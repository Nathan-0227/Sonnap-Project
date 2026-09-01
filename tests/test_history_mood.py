"""
tests/test_history_mood.py

history 每晚的 pet_mood 的回歸防護（2026-09-01 隨 B1 一起加）。

這一支守的同樣是**壞掉時不會報錯**的東西——三條檢查失敗時，程式都照跑、
payload 照產、API 照回 200，只是使用者在畫面上看到錯的寵物：

  【1】history[-1] 的心情必須與 status 的心情逐字相同
       （同一晚在首頁與 Insights 顯示不同的寵物，是最難查的那種 bug）
  【2】history 每晚都要有 pet_mood，且值落在 README 定義的四個合法值內
       （少一晚 → Insights 點下去寵物消失；多一個值 → Dart 端拿不到動畫）
  【3】/insights（讀 SQLite）與 asset（讀 CSV/JSON）對同一晚必須給出相同的心情
       （兩條路徑各自算心情，是 CLAUDE.md 記的「以為三處、實際五處」同型的坑）

⚠️ 【3】用**暫存資料庫**，不會碰到 data/sonnap.db（裡面是受測者個資）。

執行：python tests/test_history_mood.py
"""
import json
import sys
import tempfile
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# ⚠️ 一定要在 import main 之前換掉 DB_PATH，否則測試會寫到真的資料庫
import db
TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import build_app_payload as bap

fails = []


def check(label, got, want):
    ok_ = got == want
    print(f"  {'✓' if ok_ else '✗'} {label:<48} {got!r}" + ("" if ok_ else f"  期望 {want!r}"))
    if not ok_:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<48} {extra}")
    if not cond:
        fails.append(label)


PAYLOAD = ROOT / "app" / "assets" / "data" / "app_payload.json"
QUALITY = ROOT / "garmin" / "data" / "garmin_sleep_quality_final.json"

# README 定義的合法值只有這四個。多一個都會讓 Dart 端的 petMoodVisual() 拿不到動畫。
LEGAL_MOODS = {"happy", "tired", "bored", "anxious"}


print("=" * 78)
print("【1】history[-1] 的心情與 status 的心情逐字相同")
print("=" * 78)

payload = json.loads(PAYLOAD.read_text(encoding="utf-8"))
history = payload["history"]
status = payload["status"]

# ⚠️ 用 .get() 不用 []：欄位整個沒產出來時，這裡要報「得到 None」而不是
#    丟 KeyError——後者一樣是紅的，但看的人得先讀 traceback 才知道發生什麼事。
check("history[-1].pet_mood == status.pet_mood",
      history[-1].get("pet_mood"), status.get("pet_mood"))
check("history[-1].mood_reason == status.mood_reason",
      history[-1].get("mood_reason"), status.get("mood_reason"))
# 心情相同但講的是不同夜晚的話，上面兩條會假性通過（例如兩晚剛好都是 Good）。
# session_id 是 "20260823_001"，代表 status 講的是哪一晚。
_sid = payload["session_id"][:8]
check("history[-1] 講的就是 status 那一晚",
      history[-1]["date"], f"{_sid[:4]}-{_sid[4:6]}-{_sid[6:8]}")

print()
print("=" * 78)
print("【2】history 每晚都有 pet_mood，且值合法")
print("=" * 78)

missing = [e["date"] for e in history if not e.get("pet_mood")]
ok("沒有任何一晚缺 pet_mood", not missing, f"缺 {len(missing)} 晚")
illegal = sorted({e["pet_mood"] for e in history} - LEGAL_MOODS)
ok("history 的心情值全部合法", not illegal, f"非法值 {illegal}" if illegal else "")
no_reason = [e["date"] for e in history if not e.get("mood_reason")]
ok("沒有任何一晚缺 mood_reason", not no_reason, f"缺 {len(no_reason)} 晚")

# 全量資料（51 晚，不只 history 帶的 30 晚）：每一列都要算得出合法的心情。
# history 只是最後 N 晚的切片，所以只驗它會漏掉窗格外的夜晚。
quality_rows = json.loads(QUALITY.read_text(encoding="utf-8"))
all_moods = [bap.map_pet_mood(r)[0] for r in quality_rows]
bad = sorted(set(all_moods) - LEGAL_MOODS)
ok(f"全量 {len(quality_rows)} 晚的心情值全部合法", not bad, f"非法值 {bad}" if bad else "")
ok("全量每一晚都算得出心情", all(all_moods), "")

print()
print("=" * 78)
print("【3】/insights（SQLite）與 asset（JSON）對同一晚給出相同的心情")
print("=" * 78)

# ⚠️ 這一條是這支測試存在的主要理由。兩條路徑讀**不同的資料來源**、
#    走**不同的函式**（asset 用 map_pet_mood、API 用 resolve_mood），
#    任何一邊改了規則而另一邊沒改，都不會有錯誤訊息。
import main
from fastapi.testclient import TestClient

client = TestClient(main.app)
db.init_db(TMP)

user_id = client.post(
    "/users", json={"display_name": "history-mood-guard", "target_bedtime": "23:30"}
).json()["user_id"]

by_date_quality = {r["date"]: r for r in quality_rows}
for entry in history:
    row = by_date_quality[entry["date"]]
    db.upsert_wearable_nightly(
        user_id, entry["date"], "garmin",
        {
            "final_score": row.get("final_score"),
            "final_quality": row.get("final_quality"),
            # 自律神經三分項：anxious 覆寫要用，少了就永遠不會判成 anxious
            "rhr_modifier": row.get("rhr_modifier"),
            "avg_hr_modifier": row.get("avg_hr_modifier"),
            "stress_modifier": row.get("stress_modifier"),
        },
        db_path=TMP,
    )

api = client.get(f"/insights?user_id={user_id}&days=365").json()
api_hist = {e["date"]: e for e in api["wearable"]["history"]}

ok("兩條路徑覆蓋的夜晚數相同", len(api_hist) == len(history),
   f"API {len(api_hist)} 晚 vs asset {len(history)} 晚")

mismatch = [
    (e["date"], e["pet_mood"], api_hist[e["date"]]["pet_mood"])
    for e in history
    if e["date"] in api_hist and api_hist[e["date"]]["pet_mood"] != e["pet_mood"]
]
ok("每一晚的 pet_mood 都相同", not mismatch,
   f"{len(mismatch)} 晚不一致" + (f" 例：{mismatch[:3]}" if mismatch else ""))

reason_mismatch = [
    e["date"] for e in history
    if e["date"] in api_hist and api_hist[e["date"]]["mood_reason"] != e["mood_reason"]
]
ok("每一晚的 mood_reason 都相同", not reason_mismatch,
   f"{len(reason_mismatch)} 晚不一致")

# 反向對照：確認上面那兩條不是因為「兩邊都沒有 anxious」而假性通過。
# 沒有這一條的話，把 anxious 覆寫整個拿掉，測試仍然全綠。
anxious_nights = [e["date"] for e in history if e["pet_mood"] == "anxious"]
ok("樣本裡真的有 anxious 的夜晚（否則上面兩條無效）",
   bool(anxious_nights), f"{len(anxious_nights)} 晚：{anxious_nights[:3]}")
distinct = {e["pet_mood"] for e in history}
ok("樣本涵蓋 2 種以上的心情", len(distinct) >= 2, f"{sorted(distinct)}")

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
