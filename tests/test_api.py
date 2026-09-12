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
print("【額外】sleep_start_time / wake_time 是「睡著」不是「上床」")
print("=" * 78)
# session 是 23:00 上床 → 07:30 離床，但第一段睡眠 23:20 才開始、
# 最後一段睡眠 07:00 結束（07:00–07:30 是 AWAKE_IN_BED）。
# 這兩欄必須拿 sleep_onset / final_wake，拿 session 起訖就是把
# 「臥床」寫成「睡著」——那個值已經在 time_in_bed_min 裡了。
check("metrics.sleep_start_time = 第一段睡眠的起點",
      h5["metrics"]["sleep_start_time"], f"{D}T23:20:00+08:00")
check("metrics.wake_time = 最後一段睡眠的終點",
      h5["metrics"]["wake_time"], f"{E}T07:00:00+08:00")
ok("不等於 session 起點（那是上床，不是睡著）",
   h5["metrics"]["sleep_start_time"] != session["startTime"],
   f'session={session["startTime"]} vs onset={h5["metrics"]["sleep_start_time"]}')
ok("不等於 session 終點（那是離床，不是醒來）",
   h5["metrics"]["wake_time"] != session["endTime"],
   f'session={session["endTime"]} vs wake={h5["metrics"]["wake_time"]}')
ok("也不等於 lights_out_at（行為層是第三個構念）",
   h5["metrics"]["sleep_start_time"] != h5["behavior"]["lights_out_at"],
   f'lights_out={h5["behavior"]["lights_out_at"]}')

ins5 = client.get(f"/insights?user_id={u5}").json()
hist5 = ins5["wearable"]["history"]
ok("/insights 的 history 帶得出這兩欄",
   all("sleep_start_time" in r and "wake_time" in r for r in hist5),
   f"{len(hist5)} 晚")
check("/insights 與 /home 同一個值",
      (hist5[0]["sleep_start_time"], hist5[0]["wake_time"]),
      (h5["metrics"]["sleep_start_time"], h5["metrics"]["wake_time"]))

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
print("【額外】行為版睡眠效率：兩個 sleep_efficiency 不可混淆")
print("=" * 78)
# ⚠️ 這一組守的是一個**壞掉時不會報錯**的情況：behavior.sleep_efficiency
#    與 metrics.sleep_efficiency（Garmin）是不同的量，卻同時出現在同一個
#    回應裡。少了 basis／note，前端拿到數字無從分辨是哪一種。
u7 = client.post("/users", json={"display_name": "效率", "study_cohort": "L1"}).json()["user_id"]
r7 = client.post("/nightly", json={
    "user_id": u7,
    "lights_out_at": "2026-09-06T23:30:00+08:00",
    "bed_start_at": "2026-09-06T23:00:00+08:00",
    "bed_end_at": "2026-09-07T07:00:00+08:00",
}).json()
check("POST 回應的效率（臥床 480 分、滑 30 分）", r7["sleep_efficiency"], 93.8)
check("臥床時間", r7["time_in_bed_minutes"], 480.0)
check("上床後滑手機", r7["phone_in_bed_minutes"], 30.0)

ins7 = client.get(f"/insights?user_id={u7}").json()["behavior"]
n7 = ins7["history"][-1]
check("/insights 讀得回同一個值（DB 欄位有真的存進去）",
      n7["sleep_efficiency"], r7["sleep_efficiency"])
ok("逐夜都帶 efficiency_basis", bool(n7["efficiency_basis"]), n7["efficiency_basis"])
ok("behavior 層帶 efficiency_note（這是它唯一隨身的限制說明）",
   bool(ins7["efficiency_note"]))
ok("note 明說它不是穿戴的那個效率、不可比臨床門檻",
   "NOT the same quantity" in ins7["efficiency_note"]
   and "clinical" in ins7["efficiency_note"])
ok("basis 說得出兩個假設",
   "lights_out" in n7["efficiency_basis"] and "waso" in n7["efficiency_basis"])

# 沒按按鈕的一晚：必須是 null，不是 0
u8 = client.post("/users", json={"display_name": "沒按", "study_cohort": "L1"}).json()["user_id"]
r8 = client.post("/nightly", json={
    "user_id": u8, "lights_out_at": "2026-09-06T23:30:00+08:00"}).json()
check("沒按開始／結束睡覺 → 效率是 null 不是 0", r8["sleep_efficiency"], None)
check("臥床時間也是 null", r8["time_in_bed_minutes"], None)
ins8 = client.get(f"/insights?user_id={u8}").json()["behavior"]
check("/insights 也是 null", ins8["history"][-1]["sleep_efficiency"], None)

# ── 挑戰讀「滑手機分鐘數」，不讀「效率」 ──
# 同一份資料的兩種寫法，但回饋迴圈只能掛在使用者控制得了的那一端。
# 反向對照：兩者數值本來就不同（30.0 vs 93.8），所以讀錯就會被抓到。
ch7 = [x for x in client.get(f"/challenges?user_id={u7}").json()["challenges"]
       if x["challenge_id"] == "phone_in_bed_tonight"][0]
check("挑戰的 current_value 是滑手機分鐘數", ch7["current_value"], 30.0)
ok("**不是**效率（30.0 ≠ 93.8，讀錯就會被這條抓到）",
   ch7["current_value"] != r7["sleep_efficiency"])
check("越小越好", ch7["lower_is_better"], True)
check("30 分鐘剛好達標（target=30）", ch7["completed"], True)

# 沒按按鈕 → 是「資料不足」不是「沒達成」。兩者混在一起，
# 使用者會因為沒按按鈕而被判定失敗。
ch8 = [x for x in client.get(f"/challenges?user_id={u8}").json()["challenges"]
       if x["challenge_id"] == "phone_in_bed_tonight"][0]
check("沒按按鈕 → insufficient_data", ch8["status"], "insufficient_data")
check("沒按按鈕 → current_value 是 null 不是 0", ch8["current_value"], None)
ok("detail 要說得出「去按開始睡覺」", "Start sleep" in ch8["detail"], ch8["detail"])

# 反向對照：這個效率**不得**進 final_score / energy_level。
# 沒有這一條，把它加進評分也不會有任何測試變紅。
h7 = client.get(f"/home?user_id={u7}").json()
ok("沒有穿戴資料時 energy_level 仍是 null（行為效率不得冒充分數）",
   h7["status"]["energy_level"] is None, repr(h7["status"]["energy_level"]))

print()
print("=" * 78)
print("【額外】SONNAP_DB 環境變數")
print("=" * 78)
# 2026-09-07 加的。預設路徑跟著 db.py 的目錄走，所以每個 worktree
# 各有一份 DB——手機建的帳號只存在於其中一個裡，換個目錄啟動後端
# 就 404。這一條守的是「設了環境變數就要真的跟著走」。
import importlib  # noqa: E402
import os as _os  # noqa: E402

_saved = _os.environ.get("SONNAP_DB")
try:
    _os.environ["SONNAP_DB"] = str(Path(tempfile.mkdtemp()) / "env.db")
    _fresh = importlib.reload(db)
    check("設了 SONNAP_DB 就跟著走",
          str(_fresh.DB_PATH), _os.environ["SONNAP_DB"].replace("/", _os.sep))
    # 反向對照：沒設的時候必須退回預設。少了這一條，
    # 把預設寫死成某個固定路徑也會讓上面那條通過。
    _os.environ.pop("SONNAP_DB")
    _fresh = importlib.reload(db)
    check("沒設就退回 db.py 旁邊的 data/sonnap.db",
          _fresh.DB_PATH, _fresh.ROOT / "data" / "sonnap.db")
finally:
    if _saved is not None:
        _os.environ["SONNAP_DB"] = _saved
    else:
        _os.environ.pop("SONNAP_DB", None)
    importlib.reload(db)
    db.DB_PATH = TMP          # 後面還有測試要用暑存 DB

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
print("【額外】同一晚重傳，不得抹掉已經存下的上床／下床標記")
print("=" * 78)
# ⚠️ 2026-09-11 實測：MySQL 裡每一晚的 bed_start_at 都是 NULL，連補登時後端
#    親口回過 84.6% 的 09-09 也是。upsert 整列覆寫，而 App 每次回到前景都重傳
#    同一晚——第一次收下後本機就清掉，之後的重傳不帶標記，就把它抹成 NULL。
#    每一次都回 201：**成功了，但把資料弄丟**。
u8 = client.post("/users", json={"display_name": "重傳", "study_cohort": "L0"}).json()["user_id"]
NIGHT8 = {"user_id": u8, "lights_out_at": "2026-09-06T23:30:00+08:00"}
MARKS8 = {"bed_start_at": "2026-09-06T23:00:00+08:00",
          "bed_end_at": "2026-09-07T07:00:00+08:00"}


def stored8():
    return client.get(f"/insights?user_id={u8}").json()["behavior"]["history"][-1]


a8 = client.post("/nightly", json={**NIGHT8, **MARKS8}).json()
check("① 帶標記：效率", a8["sleep_efficiency"], 93.8)
check("① 標記來自這次請求", a8["bed_marks_source"], "request")
ok("① 回應帶回 bed_start_at（App 靠它決定清本機）", a8["bed_start_at"] is not None)

b8 = client.post("/nightly", json=NIGHT8).json()
check("② 不帶標記重傳：DB 的效率仍在", stored8()["sleep_efficiency"], 93.8)
ok("② DB 的 bed_start_at 仍在", stored8()["bed_start_at"] is not None,
   str(stored8()["bed_start_at"]))
check("② 回應的效率照實（沿用已存的標記算）", b8["sleep_efficiency"], 93.8)
check("② bed_marks_source 是 stored", b8["bed_marks_source"], "stored")
# ⚠️ 這一條最要緊：回應若帶回舊標記，App 會以為「我送的被收下了」而清本機。
check("② 回應的 bed_start_at 必須是 None", b8["bed_start_at"], None)

c8 = client.post("/nightly", json={**NIGHT8,
                                   "bed_start_at": "2026-09-07T23:10:00+08:00"}).json()
check("③ 帶的是下一晚的開始（拒收）：DB 效率仍在", stored8()["sleep_efficiency"], 93.8)
check("③ 回應 bed_start_at 是 None（否則今晚的會被清）", c8["bed_start_at"], None)

client.post("/nightly", json={**NIGHT8, "bed_start_at": "2026-09-06T23:00:00+08:00"})
check("④ 只帶同一個上床：沿用已存的下床", stored8()["sleep_efficiency"], 93.8)

client.post("/nightly", json={**NIGHT8, "bed_start_at": "2026-09-06T23:15:00+08:00",
                              "bed_end_at": "2026-09-07T07:00:00+08:00"})
check("⑤ 帶新的一組：照新的覆寫（更正仍有效）", stored8()["sleep_efficiency"], 96.8)

# 反向對照：從來沒按過的夜晚，重傳不可以憑空生出效率
u9 = client.post("/users", json={"display_name": "沒按", "study_cohort": "L0"}).json()["user_id"]
f9 = client.post("/nightly", json={"user_id": u9,
                                   "lights_out_at": "2026-09-06T23:30:00+08:00"}).json()
check("反向：沒有標記的夜晚效率是 None", f9["sleep_efficiency"], None)
check("反向：bed_marks_source 是 None", f9["bed_marks_source"], None)

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
