"""
tests/test_demo_accounts.py —— 成果展示範帳號不得污染真實資料

  【1】示範帳號的夜數比本人多時，resolve_phone_account() 仍然認得本人
       （含反向對照：確認示範帳號真的比較多，否則這條會假性通過）
  【2】compare_night_sources 不帶暱稱時不讀示範帳號
  【3】示範帳號都加成本人的好友，好友頁看得到，且暱稱都帶 (demo)
  【4】重跑 --create 不會越長越多；--remove 清乾淨，本人的資料一筆不少
  【5】每晚的達成度跟手機上傳走同一個函式（adherence.evaluate_night）
  【6】手錶資料（2026-11-16 起也產生）：source 一律 "demo"、分數由既有評分器算、
       API 重排的睡眠階段跟評分時同一份（demo_sleep 是決定性的）、白天資料有寫
  【7】動態牆：每張卡帶自己選的場景與寵物；只寫準時與否的人階梯圖沒有時刻；
       只開預設的人沒有階梯圖；回應裡沒有任何 user_id
  【8】Garmin 原始檔是本人的：示範帳號（沒有 garmin 來源）的「昨天」一次都不讀它，
       整天心率／壓力線／醒著心率是 null；有 garmin 來源的帳號照讀（反向對照）

⚠️ 全程使用暫存資料庫。執行：python tests/test_demo_accounts.py
"""
import sys
import tempfile
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
TMP = Path(tempfile.mkdtemp()) / "test_demo_accounts.db"
db.DB_PATH = TMP

import compare_night_sources
import demo_accounts
from behavior import adherence

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label}" + ("" if good else f"：得到 {got!r}，應為 {want!r}"))
    if not good:
        fails.append(label)


db.init_db(TMP)

# 本人：5 晚真實資料（比任何一個示範帳號都少）
me = db.create_user("Nathan", db_path=TMP)
for d in range(1, 6):
    night = adherence.evaluate_night(f"2026-11-0{d}T23:40:00+08:00", "23:30")
    db.upsert_nightly_behavior(me, night["date"], night["target_bedtime"],
                               night["lights_out_at"], night["adherence_minutes"],
                               night["is_late"], db_path=TMP)

from datetime import date
rows = demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)

print("【1】示範帳號不會被當成手機帳號")
conn = db.connect(TMP)
counts = {r["display_name"]: r["n"] for r in conn.execute(
    "SELECT u.display_name, COUNT(n.date) AS n FROM users u "
    "LEFT JOIN nightly_behavior n ON n.user_id = u.user_id GROUP BY u.user_id")}
conn.close()
check("反向對照：至少一個示範帳號的夜數比本人多",
      max(v for k, v in counts.items() if k != "Nathan") > counts["Nathan"], True)
picked, info = db.resolve_phone_account(TMP)
check("resolve_phone_account 選中本人", picked == me, True)
check("理由是 ok", info["reason"], "ok")

print("【2】compare_night_sources 不讀示範帳號")
loaded = compare_night_sources.load_behavior(TMP)
check("只讀到本人那 5 晚", len(loaded), 5)

print("【3】好友與暱稱")
friends = set(db.list_friend_ids(me, TMP))
demo_ids = {uid for uid, _ in demo_accounts.demo_users(TMP)}
check("4 個示範帳號", len(demo_ids), 4)
check("全部是本人的好友", friends == demo_ids, True)
check("暱稱都帶 (demo)", all(n.endswith("(demo)") for _, n in demo_accounts.demo_users(TMP)), True)
check("每個都有邀請碼", all(r["code"] for r in rows), True)

print("【4】重建不累積、刪除不傷本人")
demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)
check("重建後仍是 4 個", len(demo_accounts.demo_users(TMP)), 4)
check("本人的好友仍是 4 個（舊的那批已被清掉）", len(db.list_friend_ids(me, TMP)), 4)
check("刪除回報 4 個", demo_accounts.remove_all(TMP), 4)
check("本人的 5 晚還在", len(db.get_nightly_behavior(me, days=3650, db_path=TMP)), 5)
check("本人沒有好友殘留", db.list_friend_ids(me, TMP), [])
conn = db.connect(TMP)
orphans = conn.execute(
    "SELECT COUNT(*) AS n FROM nightly_behavior WHERE user_id NOT IN (SELECT user_id FROM users)"
).fetchone()["n"]
conn.close()
check("沒有孤兒的每晚資料", orphans, 0)

print("【5】達成度與 evaluate_night 一致")
demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)
uid = demo_accounts.demo_users(TMP)[0][0]
mismatch = 0
for r in db.get_nightly_behavior(uid, days=3650, db_path=TMP):
    again = adherence.evaluate_night(r["lights_out_at"], r["target_bedtime"])
    mismatch += (again["adherence_minutes"], again["is_late"], again["date"]) != \
                (r["adherence_minutes"], bool(r["is_late"]), r["date"])
check("每一晚都對得上", mismatch, 0)

print("【6】手錶資料是示範來源、分數走既有評分器")
import demo_sleep  # noqa: E402
conn = db.connect(TMP)
sources = {r["source"] for r in conn.execute(
    "SELECT DISTINCT source FROM wearable_nightly WHERE user_id IN "
    "(SELECT user_id FROM users WHERE study_cohort = ?)", (db.DEMO_COHORT,)).fetchall()}
daily = conn.execute(
    "SELECT COUNT(*) AS n FROM garmin_daily WHERE user_id IN "
    "(SELECT user_id FROM users WHERE study_cohort = ?)", (db.DEMO_COHORT,)).fetchone()["n"]
conn.close()
check("示範帳號的手錶資料 source 只有 demo", sources, {"demo"})
check("白天資料每人 21 天", daily, 4 * 21)
rows_w = db.get_wearable_nightly(uid, days=3650, db_path=TMP)
check("每晚都有手錶資料", len(rows_w), 21)
check("每晚都有分數與等級", all(r["final_score"] is not None and r["final_quality"] for r in rows_w), True)
bad = 0
for r in rows_w:
    blk = demo_sleep.stages_block(r)
    segs = blk["segments"] if blk else []
    asleep = sum((datetime.fromisoformat(x["end"]) - datetime.fromisoformat(x["start"])).total_seconds() / 60
                 for x in segs if x["stage"] != "awake")
    bad += (not segs or round(asleep) != round(r["duration_min"])
            or segs[0]["start"] != r["sleep_start_time"]
            or demo_sleep.awake_count(segs) != r["awake_count"])
check("重排的階梯跟存下來的睡眠分鐘、入睡時刻、醒來次數一致", bad, 0)
check("同一晚重排兩次一模一樣", demo_sleep.stages_block(rows_w[-1]) == demo_sleep.stages_block(rows_w[-1]), True)

print("【7】動態牆")
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
# 動態牆只看最近 7 天 → 這裡重建到今天為止
demo_accounts.create_all(nights=21, db_path=TMP)
client = TestClient(main.app, raise_server_exceptions=False)
r = client.get("/friends/feed", params={"user_id": me})
check("200", r.status_code, 200)
cards = r.json()["cards"]
latest = {}
for c in cards:
    if not c["mine"]:
        latest.setdefault(c["display_name"], c)
check("4 位朋友都有卡", len(latest), 4)
check("各自的場景", {n: c["scene"] for n, c in latest.items()},
      {"Mia (demo)": "lake", "Leo (demo)": "campfire", "Yuki (demo)": "rooftop", "Ken (demo)": "treehouse"})
mia = latest["Mia (demo)"]["items"]
check("Mia（只寫準時與否）：有階梯", bool(mia.get("stages", {}).get("segments")), True)
check("Mia：階梯沒有兩端時刻", sorted(set(mia["stages"]) & {"start", "end"}), [])
check("Mia：沒有放下手機的時刻", "phone_down_time" in mia, False)
leo = latest["Leo (demo)"]["items"]
check("Leo（準確時刻）：階梯兩端有時刻", all(leo["stages"].get(k) for k in ("start", "end")), True)
check("Ken（只開預設）：沒有階梯", "stages" in latest["Ken (demo)"]["items"], False)
all_ids = {me} | {u for u, _ in demo_accounts.demo_users(TMP)}
check("回應裡沒有任何 user_id", any(u in r.text for u in all_ids), False)
seg_iso = any("T" in str(s.get("from", "")) for c in cards for s in (c["items"].get("stages") or {}).get("segments", []))
check("每一段只給第幾分鐘，不給 ISO 時刻", seg_iso, False)

print("【8】Garmin 原始檔只給本人讀")
calls = []
real_records = main._garmin_records
main._garmin_records = lambda: calls.append(1) or []
try:
    demo_uid = demo_accounts.demo_users(TMP)[0][0]
    y = main.yesterday_block(demo_uid, date.today().isoformat())
    check("示範帳號有白天資料（步數）", y is not None and y["steps"] is not None, True)
    check("示範帳號的昨天一次都沒讀原始檔", len(calls), 0)
    check("整天心率／壓力線／醒著心率都是 null",
          [y["heart_rate"], y["stress_curve"], y["awake_heart_rate"]], [None, None, None])
    # 反向對照：本人有一晚 garmin 來源 → 會去讀
    db.upsert_wearable_nightly(me, "2026-11-01", "garmin", {"duration_min": 400}, db_path=TMP)
    db.upsert_garmin_daily(me, "2026-10-31", {"steps": 5000}, db_path=TMP)
    main.yesterday_block(me, "2026-11-01")
    check("有 garmin 來源的帳號照讀原始檔", len(calls) > 0, True)
finally:
    main._garmin_records = real_records

print()
if fails:
    print(f"✗ {len(fails)} 項失敗")
    sys.exit(1)
print("✓ 全部通過")
