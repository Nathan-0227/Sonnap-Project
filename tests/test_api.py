"""
tests/test_api.py — 多使用者 API 的驗收

⚠️ 全程使用**暫存資料庫**，不會碰到 data/sonnap.db（裡面是受測者個資）。

執行：python tests/test_api.py
"""
import json
import re
import sys
import tempfile
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# ⚠️ 一定要在 import main 之前換掉 DB_PATH，否則端點會寫到真的資料庫
import db
TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import main
from fastapi.testclient import TestClient

client = TestClient(main.app)

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<44} {got!r}" + ("" if ok else f"  期望 {want!r}"))
    if not ok:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<44} {extra}")
    if not cond:
        fails.append(label)


print("=" * 78)
print("【驗收 2】空目錄建表；重跑第二次不報錯")
print("=" * 78)
db.init_db(TMP)
import sqlite3
conn = sqlite3.connect(TMP)
tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
expect_tables = {"users", "nightly_behavior", "app_usage_daily", "block_events",
                 "wearable_nightly", "challenges", "challenge_progress"}
ok("七張表全部建出來", expect_tables <= tables, f"{sorted(expect_tables & tables)}")
conn.close()
db.init_db(TMP)          # 第二次
db.init_db(TMP)          # 第三次
print("  ✓ 重複執行 init_db 三次沒有報錯")
db.seed_challenges(TMP)
db.seed_challenges(TMP)
print(f"  ✓ seed 兩次後挑戰數 = {len(db.get_challenges(TMP))}（不會重複）")

print()
print("=" * 78)
print("【驗收 3】兩個使用者拿到不同的 user_id，且 /home 回傳不同內容")
print("=" * 78)
r1 = client.post("/users", json={"display_name": "小明", "target_bedtime": "23:30"})
r2 = client.post("/users", json={"display_name": "小華", "target_bedtime": "01:00"})
check("POST /users 狀態碼", r1.status_code, 201)
u1, u2 = r1.json()["user_id"], r2.json()["user_id"]
ok("兩個 user_id 不同", u1 != u2, f"{u1[:8]}… vs {u2[:8]}…")

# 小明準時（23:20 < 23:30），小華熬夜（03:00 vs 01:00 → 遲 120 分）
client.post("/nightly", json={"user_id": u1, "lights_out_at": "2026-08-25T23:20:00+08:00"})
client.post("/nightly", json={"user_id": u2, "lights_out_at": "2026-08-26T03:00:00+08:00"})

h1 = client.get(f"/home?user_id={u1}").json()
h2 = client.get(f"/home?user_id={u2}").json()
check("小明的心情", h1["status"]["pet_mood"], "happy")
check("小華的心情", h2["status"]["pet_mood"], "tired")
check("小明 adherence", h1["behavior"]["adherence_minutes"], -10.0)
check("小華 adherence", h2["behavior"]["adherence_minutes"], 120.0)
ok("兩人的 /home 內容不同", h1 != h2)
check("沒有穿戴資料 → energy_level 為 null", h1["status"]["energy_level"], None)
check("沒有穿戴資料 → scoring 為 null", h1["scoring"], None)

print()
print("=" * 78)
print("【驗收 6・紅線 5】遲三小時的夜晚，回饋必須明顯少於準時的夜晚")
print("=" * 78)
u3 = client.post("/users", json={"display_name": "對照組", "target_bedtime": "23:30"}).json()["user_id"]

# 同一個人，兩晚：一晚準時、一晚遲三小時
client.post("/nightly", json={"user_id": u3, "lights_out_at": "2026-08-20T23:15:00+08:00"})
on_time = client.get(f"/home?user_id={u3}&date=2026-08-21").json()
c_on = client.get(f"/challenges?user_id={u3}&as_of=2026-08-21").json()["challenges"]

client.post("/nightly", json={"user_id": u3, "lights_out_at": "2026-08-22T02:30:00+08:00"})
late = client.get(f"/home?user_id={u3}&date=2026-08-22").json()
c_late = client.get(f"/challenges?user_id={u3}&as_of=2026-08-22").json()["challenges"]

by_id_on = {c["challenge_id"]: c for c in c_on}
by_id_late = {c["challenge_id"]: c for c in c_late}

print(f"  準時那晚：mood={on_time['status']['pet_mood']:<8} "
      f"adherence={on_time['behavior']['adherence_minutes']:+.0f} 分")
print(f"  遲三小時：mood={late['status']['pet_mood']:<8} "
      f"adherence={late['behavior']['adherence_minutes']:+.0f} 分")
ok("心情不同（happy vs tired）",
   on_time["status"]["pet_mood"] == "happy" and late["status"]["pet_mood"] == "tired")

t_on = by_id_on["on_time_tonight"]
t_late = by_id_late["on_time_tonight"]
print(f"  「準時放下手機」進度：準時 {t_on['progress']} / 遲到 {t_late['progress']}")
ok("挑戰進度：準時 > 遲到", t_on["progress"] > t_late["progress"])
ok("挑戰完成狀態不同", t_on["completed"] and not t_late["completed"])

s_on = by_id_on["streak_nights"]
s_late = by_id_late["streak_nights"]
print(f"  「連續 3 晚」進度：準時 {s_on['current_value']} 晚 / 遲到 {s_late['current_value']} 晚")
ok("連續紀錄：遲到那晚歸零", s_on["current_value"] > s_late["current_value"])

print()
print("=" * 78)
print("【額外】缺資料的夜晚必須中斷連續紀錄（否則可以靠選擇性記錄刷連續）")
print("=" * 78)
u4 = client.post("/users", json={"display_name": "跳日", "target_bedtime": "23:30"}).json()["user_id"]

# ⚠️ night_date() 會把時間往後推 6 小時再取日期（「18:00 之後算隔天那一晚」）。
#    所以 08-10 晚上 23:00 放下手機 → 歸屬 **08-11** 那一晚。
#    存進去的日期會是 08-11 / 08-12 / 08-14，缺口在 08-13。
for d in ("2026-08-10", "2026-08-11", "2026-08-13"):
    client.post("/nightly", json={"user_id": u4, "lights_out_at": f"{d}T23:00:00+08:00"})
stored = sorted(r["date"] for r in db.get_nightly_behavior(u4, days=99, db_path=TMP))
check("歸屬日期（驗證 6 小時位移）", stored, ["2026-08-11", "2026-08-12", "2026-08-14"])


def streak_at(user, as_of):
    cs = client.get(f"/challenges?user_id={user}&as_of={as_of}").json()["challenges"]
    return {c["challenge_id"]: c for c in cs}["streak_nights"]["current_value"]


check("as_of=08-12（08-11+08-12 連續）→ 2", streak_at(u4, "2026-08-12"), 2.0)
check("as_of=08-13（當晚無資料）→ 0", streak_at(u4, "2026-08-13"), 0.0)
check("as_of=08-14（前一晚 08-13 缺）→ 1 不是 3", streak_at(u4, "2026-08-14"), 1.0)

print()
print("=" * 78)
print("【驗收 3b】上傳 Health Connect → 分數走既有評分器 → 出現在 /home")
print("=" * 78)
u5 = client.post("/users", json={
    "display_name": "有錶的同學", "target_bedtime": "23:30",
    "study_cohort": "L1", "wearable_brand": "Fitbit"}).json()["user_id"]

D, E = "2026-08-25", "2026-08-26"
session = {
    "startTime": f"{D}T23:00:00+08:00", "endTime": f"{E}T07:30:00+08:00",
    "stages": [
        {"startTime": f"{D}T23:00:00+08:00", "endTime": f"{D}T23:20:00+08:00", "stage": "AWAKE"},
        {"startTime": f"{D}T23:20:00+08:00", "endTime": f"{E}T00:20:00+08:00", "stage": "LIGHT"},
        {"startTime": f"{E}T00:20:00+08:00", "endTime": f"{E}T01:20:00+08:00", "stage": "DEEP"},
        {"startTime": f"{E}T01:20:00+08:00", "endTime": f"{E}T01:35:00+08:00", "stage": "AWAKE"},
        {"startTime": f"{E}T01:35:00+08:00", "endTime": f"{E}T03:05:00+08:00", "stage": "LIGHT"},
        {"startTime": f"{E}T03:05:00+08:00", "endTime": f"{E}T04:05:00+08:00", "stage": "REM"},
        {"startTime": f"{E}T04:05:00+08:00", "endTime": f"{E}T05:35:00+08:00", "stage": "LIGHT"},
        {"startTime": f"{E}T05:35:00+08:00", "endTime": f"{E}T06:35:00+08:00", "stage": "REM"},
        {"startTime": f"{E}T06:35:00+08:00", "endTime": f"{E}T07:00:00+08:00", "stage": "LIGHT"},
        {"startTime": f"{E}T07:00:00+08:00", "endTime": f"{E}T07:30:00+08:00", "stage": "AWAKE_IN_BED"},
    ],
    "avgHeartRate": 58.2, "restingHeartRate": 52,
}
rw = client.post("/wearable", json={"user_id": u5, "session": session})
check("POST /wearable 狀態碼", rw.status_code, 201)
w = rw.json()
check("分數（與手算相符）", w["final_score"], 98.8)
check("臥床時間（Garmin 給不出來）", w["time_in_bed_min"], 510.0)
check("入睡潛伏期", w["sleep_latency_min"], 20.0)

client.post("/nightly", json={"user_id": u5, "lights_out_at": f"{D}T23:05:00+08:00"})
h5 = client.get(f"/home?user_id={u5}").json()
check("有穿戴資料 → energy_level 有值", h5["status"]["energy_level"], 99)
check("mood 由行為驅動（不是由分數）", h5["status"]["mood_driver"], "behavior")
check("Tier B 的臥床時間出現在 metrics",
      h5["metrics"]["time_in_bed_minutes"], 510.0)
ok("data_sources 兩層都有", set(h5["data_sources"]) == {"behavior", "health_connect"},
   str(h5["data_sources"]))

print()
print("=" * 78)
print("【額外】沒有行為資料時，心情要與舊路徑（build_app_payload）完全一致")
print("=" * 78)
u6 = client.post("/users", json={"display_name": "只有錶", "study_cohort": "L1"}).json()["user_id"]
client.post("/wearable", json={"user_id": u6, "session": session, "device_brand": "Garmin"})
h6 = client.get(f"/home?user_id={u6}").json()
w6 = db.get_wearable_nightly(u6, days=5, db_path=TMP)[0]
expect_mood, expect_reason = main.map_pet_mood(w6)
check("mood 與 map_pet_mood 一致", h6["status"]["pet_mood"], expect_mood)
check("mood_driver", h6["status"]["mood_driver"], "wearable")

print()
print("=" * 78)
print("【驗收 5】舊端點 /get-sleep-data 行為完全不變")
print("=" * 78)
old = client.get("/get-sleep-data")
check("狀態碼", old.status_code, 200)
disk = json.load((ROOT / "app/assets/data/app_payload.json").open(encoding="utf-8"))
ok("回傳內容與磁碟上的 app_payload.json 逐位元組相同", old.json() == disk)
hh = client.get("/health").json()
check("/health status", hh["status"], "ok")
ok("/health 有 payload_available", "payload_available" in hh)

print()
print("=" * 78)
print("【額外】錯誤處理：不存在的使用者、壞掉的輸入")
print("=" * 78)
check("不存在的 user_id → 404", client.get("/home?user_id=nope").status_code, 404)
check("壞掉的 target_bedtime → 422",
      client.post("/users", json={"display_name": "x", "target_bedtime": "25 點"}).status_code, 422)
check("壞掉的 Health Connect session → 422",
      client.post("/wearable", json={"user_id": u5, "session": {"startTime": "x"}}).status_code, 422)
check("as_of 格式錯 → 422",
      client.get(f"/challenges?user_id={u5}&as_of=8/26").status_code, 422)
check("正常改名 → 200",
      client.patch(f"/users/{u5}", json={"display_name": "改名"}).status_code, 200)
check("只送未知欄位（會被 pydantic 濾掉）→ 422",
      client.patch(f"/users/{u5}", json={"user_id": "想改主鍵"}).status_code, 422)
check("空的更新 → 422", client.patch(f"/users/{u5}", json={}).status_code, 422)

print()
print("=" * 78)
print("【額外・知情同意】DELETE /users 必須連帶清掉所有資料")
print("=" * 78)
before = len(db.get_wearable_nightly(u5, days=99, db_path=TMP))
check("刪除前有穿戴資料", before > 0, True)
check("DELETE 狀態碼", client.delete(f"/users/{u5}").status_code, 200)
conn = sqlite3.connect(TMP)
leftovers = {}
for t in ("nightly_behavior", "wearable_nightly", "challenge_progress"):
    leftovers[t] = conn.execute(f"SELECT COUNT(*) FROM {t} WHERE user_id=?", (u5,)).fetchone()[0]
conn.close()
check("CASCADE 後沒有孤兒資料", leftovers, {"nightly_behavior": 0, "wearable_nightly": 0,
                                             "challenge_progress": 0})

print()
print("=" * 78)
print("【驗收 7・紅線 4】behavior/ 不得 import 評分層")
print("=" * 78)
# ⚠️ 用純 Python 而不是 subprocess 呼叫 grep：PowerShell 沒有 grep，
#    而本專案已經踩過「同一台機器兩種終端機兩種結果」的坑
#    （run_pipeline.py 的 cp1252 那次）。測試本身不該有這種相依。
#
# ⚠️ 只比對 **import 行**，不能單純搜關鍵字——那樣會抓到規則自己的
#    說明文字（behavior/__init__.py 就寫著這條規則）。實際踩過。
IMPORT_RE = re.compile(
    r"^\s*(?:import|from)\s+.*"
    r"(evaluate_sleep_quality|apply_recovery_modifier|garmin)"
)
hits = []
for py in sorted((ROOT / "behavior").rglob("*.py")):
    for lineno, line in enumerate(py.read_text(encoding="utf-8").splitlines(), 1):
        if IMPORT_RE.search(line):
            hits.append(f"{py.relative_to(ROOT).as_posix()}:{lineno}: {line.strip()}")
ok("import 行零結果", not hits, "\n      ".join(hits) or "(無)")

# 另一半：behavior/ 也不該讀 Tier B 的表
TIER_B_RE = re.compile(r"^\s*(?:import|from)\s+.*(wearable|healthconnect)")
hits_b = []
for py in sorted((ROOT / "behavior").rglob("*.py")):
    for lineno, line in enumerate(py.read_text(encoding="utf-8").splitlines(), 1):
        if TIER_B_RE.search(line):
            hits_b.append(f"{py.relative_to(ROOT).as_posix()}:{lineno}: {line.strip()}")
ok("也沒有 import Tier B（wearable/）", not hits_b,
   "\n      ".join(hits_b) or "(無)")

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
