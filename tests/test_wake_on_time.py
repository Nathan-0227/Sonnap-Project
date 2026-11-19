"""
守睡眠計畫的「準時起床」（M3，2026-11-19）。

═══════════════════════════════════════════════════════════════════════
守什麼（每一條壞掉都不會報錯）
═══════════════════════════════════════════════════════════════════════
【1】跨午夜：目標 00:30、23:50 起床是早 40 分（準時），不是晚 23 小時
【2】按鈕優先於手錶；兩個都沒有是 None（沒量到），不是 False（沒做到）
【3】±60 的邊界；早起太多也不算準時
【4】按鈕不帶時區、手錶帶 +08:00 → 一律當牆鐘，不差 8 小時
【5】沒有目標起床時間（舊版 App）→ None
【6】PATCH /users 收 target_wake、格式錯 422；POST /nightly 存快照；改目標不改歷史
【7】/challenges 的 up_on_time 用到手錶的起床（手錶晚到也算得出來）
【8】遊戲化也走同一份併好的資料（沒併的話永遠是 insufficient_data）

    python tests/test_wake_on_time.py
"""
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import main  # noqa: E402
from behavior import wake  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app)
fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label}" + (f"  ({extra})" if extra else ""))
    if not cond:
        fails.append(label)


print("【1】跨午夜")
r = wake.evaluate_wake("2026-11-18T23:50:00", None, "00:30")
ok("目標 00:30、23:50 起床 → −40 分、準時",
   r["wake_adherence_minutes"] == -40.0 and r["up_on_time"] is True, str(r))
r = wake.evaluate_wake("2026-11-19T01:45:00", None, "23:30")
ok("目標 23:30、01:45 起床 → +135 分、沒準時",
   r["wake_adherence_minutes"] == 135.0 and r["up_on_time"] is False, str(r))

print("【2】來源")
r = wake.evaluate_wake("2026-11-19T09:10:00", "2026-11-19T08:40:00+08:00", "09:00")
ok("按鈕優先", r["wake_source"] == "button" and r["wake_adherence_minutes"] == 10.0, str(r))
r = wake.evaluate_wake(None, "2026-11-19T08:40:00+08:00", "09:00")
ok("沒按鈕用手錶", r["wake_source"] == "watch" and r["wake_adherence_minutes"] == -20.0, str(r))
r = wake.evaluate_wake(None, None, "09:00")
ok("都沒有 → None 不是 False", r["up_on_time"] is None and r["wake_source"] is None, str(r))

print("【3】±60 邊界")
ok("剛好 60 分算準時", wake.up_on_time(60.0) is True)
ok("61 分不算", wake.up_on_time(61.0) is False)
ok("早 90 分也不算（要的是同一時刻）", wake.up_on_time(-90.0) is False)

print("【4】牆鐘")
r = wake.evaluate_wake(None, "2026-11-19T09:00:00+08:00", "09:00")
ok("手錶 09:00+08:00 對目標 09:00 是 0 分（不是 ±480）",
   r["wake_adherence_minutes"] == 0.0, str(r))

print("【5】沒有目標")
r = wake.evaluate_wake("2026-11-19T09:00:00", None, None)
ok("target_wake 是 None → 不判", r["up_on_time"] is None and r["wake_at"] is not None, str(r))

print("【6】API：設定與快照")
db.init_db(TMP)
db.seed_challenges(TMP)
uid = client.post("/users", json={"display_name": "測試員", "target_bedtime": "01:00"}).json()["user_id"]
ok("新帳號沒有起床目標", db.get_user(uid)["target_wake"] is None)
ok("格式錯 → 422", client.patch(f"/users/{uid}", json={"target_wake": "9am"}).status_code == 422)
res = client.patch(f"/users/{uid}", json={"target_wake": "09:00"})
ok("PATCH 09:00", res.status_code == 200 and res.json()["target_wake"] == "09:00", res.text)

res = client.post("/nightly", json={
    "user_id": uid, "lights_out_at": "2026-11-19T01:10:00",
    "bed_start_at": "2026-11-19T00:55:00", "bed_end_at": "2026-11-19T09:20:00"})
ok("上傳一晚", res.status_code == 201, res.text)
row = db.get_nightly_behavior(uid, days=30)[-1]
ok("存了快照 09:00", row["target_wake"] == "09:00", str(row.get("target_wake")))

client.patch(f"/users/{uid}", json={"target_wake": "07:00"})
row = db.get_nightly_behavior(uid, days=30)[-1]
ok("改目標不改歷史快照", row["target_wake"] == "09:00", str(row.get("target_wake")))

ch = {c["challenge_id"]: c for c in client.get(f"/challenges?user_id={uid}").json()["challenges"]}
up = ch.get("up_on_time")
ok("/challenges 有 up_on_time", up is not None)
ok("按鈕 09:20 對 09:00 → +20、完成",
   up and up["current_value"] == 20.0 and up["status"] == "completed", str(up))

print("【7】手錶晚到也算得出來")
uid2 = client.post("/users", json={"display_name": "戴錶", "target_bedtime": "01:00"}).json()["user_id"]
client.patch(f"/users/{uid2}", json={"target_wake": "08:00"})
client.post("/nightly", json={"user_id": uid2, "lights_out_at": "2026-11-19T01:05:00"})
up = {c["challenge_id"]: c for c in client.get(f"/challenges?user_id={uid2}").json()["challenges"]}["up_on_time"]
ok("手錶還沒到 → insufficient_data", up["status"] == "insufficient_data", up["status"])
db.upsert_wearable_nightly(uid2, "2026-11-19", "garmin",
                           {"wake_time": "2026-11-19T10:30:00+08:00"}, db_path=TMP)
up = {c["challenge_id"]: c for c in client.get(f"/challenges?user_id={uid2}").json()["challenges"]}["up_on_time"]
ok("手錶到了 → +150、沒準時（讀取時才算）",
   up["current_value"] == 150.0 and up["status"] == "in_progress", str(up))

print("【8】遊戲化走同一份資料")
rows = main._game_inputs(uid)[3]
g = {c["challenge_id"]: c for c in rows}["up_on_time"]
ok("_game_inputs 的 up_on_time 也是 completed", g["status"] == "completed", g["status"])

print()
if fails:
    print(f"❌ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✅ 全部通過")
