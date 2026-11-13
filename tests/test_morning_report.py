"""
tests/test_morning_report.py —— 早晨報告的後端（2026-11-12）

守的東西（都是壞掉時不會報錯的）：
   【1】小建議：觸發條件、優先順序、T1/T2 不重疊、運動只在沒有別的觸發時出現
   【2】程式裡的 12 句與 Research-Background/起床小建議與自評.md **逐字一致**
   【3】POST /rested：只收清單裡的標籤、分數 1–5、真的日期；同一晚覆蓋
   【4】⚠️ 自評**不進分數、不給 XP**：存了自評前後，分數與 XP 一模一樣；評分層與遊戲層不讀這張表
   【5】刪帳號時自評與 AI 分析一起刪
   【6】AI 分析：沒有手錶資料不呼叫；沒有金鑰退回且不存；每晚只呼叫一次；事實變了才重生；
        驗證擋得住（數字、因果、太長）；兩次沒過退回並存起來、一小時內不再試；小建議逐字附上
   【7】每一晚的曲線：Garmin 來源有、Health Connect 沒有
   【8】整支測試一次都沒碰到網路

⚠️ **絕對不能打到真的 Claude API。** 三道保險同 tests/test_chat.py：
   1. import 前把 ANTHROPIC_API_KEY 設成空字串
   2. urllib.request.urlopen 換成一被呼叫就失敗
   3. ai.night_summary.complete 換成假的

執行：python tests/test_morning_report.py
"""
import os
import sys
import tempfile
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

os.environ["ANTHROPIC_API_KEY"] = ""          # 保險 1

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

NETWORK_CALLS = []


def _no_network(*args, **kwargs):              # 保險 2
    NETWORK_CALLS.append(args)
    raise AssertionError("test_morning_report tried to reach the real network")


urllib.request.urlopen = _no_network

import db
TMP = Path(tempfile.mkdtemp()) / "test_morning_report.db"
db.DB_PATH = TMP

import main
from ai import night_summary as ns
from behavior import morning_tips as mt
from fastapi.testclient import TestClient

client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<60} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<60} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print()
    print("=" * 78)
    print(title)


db.init_db(TMP)
db.seed_challenges(TMP)

# ═══════════════════════════════════════════════════════════════════
section("【1】小建議：觸發與優先順序")


def tip(tags=(), minutes=None):
    t = mt.pick_tip(tags, minutes)
    return t["id"] if t else None


check("什麼都沒觸發 → 不硬塞", tip(), None)
check("晚 29 分 → 還不算", tip(minutes=29), None)
check("晚 30 分 → T1（手機放床外）", tip(minutes=30), "T1")
check("晚 59 分 → T1", tip(minutes=59), "T1")
check("⚠️ 晚 60 分 → T2（原本 T1 會吃掉它，永遠輪不到）", tip(minutes=60), "T2")
check("早睡（負值）→ 不觸發", tip(minutes=-20), None)
check("生病優先於咖啡因", tip(["late_caffeine", "unwell"]), "T9")
check("使用者勾的優先於量到的（咖啡因 vs 晚 90 分）", tip(["late_caffeine"], 90), "T3")
check("只勾運動 → T7", tip(["exercise"]), "T7")
check("⚠️ 運動＋晚 45 分 → 不給正向那句（紅線 5）", tip(["exercise"], 45), "T1")
check("噪音與溫度分開（拆成兩個標籤）", (tip(["noise"]), tip(["temperature"])), ("T12", "T6"))
check("不認得的標籤 → 不觸發", tip(["coffee"]), None)
check("說明類的句子標成 note", mt.pick_tip(["travel"])["kind"], "note")
check("每個標籤都有對應的句子", set(mt.TAG_TIPS) == set(mt.TAGS), True)
check("優先順序涵蓋全部 12 句、沒有重複", sorted(mt.PRIORITY, key=lambda x: int(x[1:])),
      [f"T{i}" for i in range(1, 13)])

# ═══════════════════════════════════════════════════════════════════
section("【2】程式裡的 12 句與文件逐字一致（措辭由使用者審過）")
doc = (ROOT / "Research-Background" / "起床小建議與自評.md").read_text(encoding="utf-8")
for tip_id, (_, text) in mt.TIPS.items():
    ok(f"{tip_id} 在文件裡找得到原句", text in doc, text[:40])
for n, label in mt.RESTED_LABELS.items():
    ok(f"自評選項 {n} 照抄論文原文", label in doc, label)

# ═══════════════════════════════════════════════════════════════════
section("【3】POST /rested")
u = client.post("/users", json={"display_name": "Morning", "target_bedtime": "23:30"}).json()["user_id"]
D, PREV = "2026-11-12", "2026-11-11"

r = client.post("/rested", json={"user_id": u, "date": D, "rested": 4, "tags": ["exercise", "exercise", "stress"],
                                 "minutes_after_wake": 3})
check("存得進去", r.status_code, 200)
check("重複的標籤只留一個", [t["id"] for t in r.json()["morning_rating"]["tags"]], ["exercise", "stress"])
check("回的 label 照抄論文", r.json()["morning_rating"]["label"], "Well-rested")
check("不認得的標籤 → 422（不收自由文字）",
      client.post("/rested", json={"user_id": u, "date": D, "rested": 3, "tags": ["I had beer"]}).status_code, 422)
check("rested=0 → 422", client.post("/rested", json={"user_id": u, "date": D, "rested": 0}).status_code, 422)
check("rested=6 → 422", client.post("/rested", json={"user_id": u, "date": D, "rested": 6}).status_code, 422)
check("不存在的日期 → 422", client.post("/rested", json={"user_id": u, "date": "2026-02-30", "rested": 3}).status_code, 422)
check("不存在的使用者 → 404", client.post("/rested", json={"user_id": "nobody", "date": D, "rested": 3}).status_code, 404)
client.post("/rested", json={"user_id": u, "date": D, "rested": 2, "tags": []})
check("同一晚再送一次就覆蓋", db.get_morning_rating(u, D, db_path=TMP)["rested"], 2)

# ═══════════════════════════════════════════════════════════════════
section("【4】⚠️ 自評不進分數、不給 XP")
db.upsert_nightly_behavior(u, D, "23:30", f"{PREV}T23:50:00+08:00", 20.0, False, db_path=TMP)
db.upsert_wearable_nightly(u, PREV, source="garmin", metrics={
    "duration_min": 420, "deep_min": 70, "rem_min": 90, "waso_min": 20,
    "final_score": 82.0, "final_quality": "Good", "rem_measured": 1}, db_path=TMP)
db.upsert_wearable_nightly(u, D, source="garmin", metrics={
    "duration_min": 215, "deep_min": 43, "rem_min": 42, "waso_min": 8,
    "final_score": 69.9, "final_quality": "Normal", "rem_measured": 1,
    "sleep_start_time": f"{D}T05:54:00+08:00", "wake_time": f"{D}T09:29:00+08:00"}, db_path=TMP)

client.post("/rested", json={"user_id": u, "date": D, "rested": 1, "tags": []})
h1 = client.get(f"/home?user_id={u}&date={D}").json()
g1 = client.get(f"/game?user_id={u}").json()
client.post("/rested", json={"user_id": u, "date": D, "rested": 5, "tags": ["exercise"]})
h2 = client.get(f"/home?user_id={u}&date={D}").json()
g2 = client.get(f"/game?user_id={u}").json()
check("分數一模一樣（很累 vs 很有精神）", h1["scoring"]["final_score"], h2["scoring"]["final_score"])
check("心情一模一樣", h1["status"]["pet_mood"], h2["status"]["pet_mood"])
check("XP 一模一樣", g1.get("xp_total"), g2.get("xp_total"))
ok("反向對照：/home 真的讀到了自評（否則上面三條會假性通過）",
   h1["morning_rating"]["rested"] == 1 and h2["morning_rating"]["rested"] == 5)
for folder in ("garmin", "game", "social"):
    hits = [p.name for p in (ROOT / folder).rglob("*.py")
            if "morning_rating" in p.read_text(encoding="utf-8", errors="ignore")]
    check(f"{folder}/ 沒有任何地方讀自評", hits, [])
for name in ("score_claim.py", "build_app_payload.py"):
    check(f"{name} 不讀自評", "morning_rating" in (ROOT / name).read_text(encoding="utf-8"), False)
check("上一晚的睡眠長度給「跟上一晚比」用", h2["previous_night"]["sleep_duration_minutes"], 420)

# ═══════════════════════════════════════════════════════════════════
section("【6】AI 分析")
CALLS = []
REPLIES = []


def fake_complete(system, user_prompt, schema, max_tokens=0):     # 保險 3
    CALLS.append(user_prompt)
    return {"text": REPLIES.pop(0)}, "fake-model"


ns.complete = fake_complete
ns.key_available = lambda: False

w = client.get(f"/night-summary?user_id={u}&date=2026-11-01").json()
check("沒有手錶資料 → waiting，不呼叫 AI", (w["status"], len(CALLS)), ("waiting", 0))

r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("沒有金鑰 → 退回後端那兩句話", r["source"], "fallback")
# 這一晚有行為資料 → /home 的文案是行為那一套（沒有 score_message），有幾句就接幾句
check("退回的文字就是 /home 畫面上的那幾句", r["text"],
      " ".join(x for x in (h2["display"].get("score_message"), h2["display"].get("mood_description")) if x))
check("沒有金鑰 → 不存（設定好之後要能生成）", db.get_night_summary(u, D, db_path=TMP), None)
check("小建議照樣附上、逐字（勾了運動 → T7）", r["tip"]["text"], mt.TIPS["T7"][1])

ns.key_available = lambda: True
GOOD = "We slept 3h 35m together, 3h 25m less than the night before. Let's be in bed by 23:30 tonight."
REPLIES[:] = [GOOD]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("有金鑰 → AI 寫的那段", (r["source"], r["text"]), ("llm", GOOD))
check("呼叫了一次", len(CALLS), 1)
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("⚠️ 再打開一次 → 讀存好的，不再花額度", (len(CALLS), r["text"]), (1, GOOD))
ok("事實區塊有寫好的時長（照抄用，不讓 AI 換算）", "3h 25m less" in CALLS[0], "")
ok("事實區塊有使用者的目標", '"in_bed_by": "23:30"' in CALLS[0], "")

client.post("/rested", json={"user_id": u, "date": D, "rested": 3, "tags": ["late_caffeine"]})
REPLIES[:] = [GOOD]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("補了自評（事實變了）→ 重生一次", len(CALLS), 2)
check("小建議跟著換成咖啡因那句", r["tip"]["id"], "T3")

BAD_NUMBER = "We slept 9h together. Let's be in bed by 23:30 tonight."
BAD_CAUSE = "We slept 3h 35m because of the caffeine. Let's be in bed by 23:30 tonight."
LONG = " ".join(["We slept 3h 35m together."] * 14)
check("數字不在事實裡 → 擋", bool(ns.validate_summary(BAD_NUMBER, CALLS[0])), True)
check("說因果（because）→ 擋", bool(ns.validate_summary(BAD_CAUSE, CALLS[0])), True)
check("太長 → 擋", bool(ns.validate_summary(LONG, CALLS[0])), True)
check("好的那段不誤擋", ns.validate_summary(GOOD, CALLS[0]), [])

client.post("/rested", json={"user_id": u, "date": D, "rested": 3, "tags": ["late_caffeine", "stress"]})
REPLIES[:] = [BAD_NUMBER, GOOD]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("第一次沒過 → 帶著原因重問，第二次過了", (r["source"], len(CALLS)), ("llm", 4))
ok("重問時有說哪裡不行", "REJECTED" in CALLS[-1], "")

client.post("/rested", json={"user_id": u, "date": D, "rested": 4, "tags": []})
REPLIES[:] = [BAD_CAUSE, BAD_NUMBER]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("兩次都沒過 → 退回", r["source"], "fallback")
check("退回也存起來", db.get_night_summary(u, D, db_path=TMP)["source"], "fallback")
n = len(CALLS)
client.get(f"/night-summary?user_id={u}&date={D}")
check("⚠️ 一小時內再打開 → 不再花額度", len(CALLS), n)
old = (datetime.now() - timedelta(minutes=main.SUMMARY_RETRY_MINUTES + 5)).astimezone().isoformat()
conn = db.connect(TMP)
conn.execute("UPDATE night_summaries SET created_at = ? WHERE user_id = ?", (old, u))
conn.commit()
conn.close()
REPLIES[:] = [GOOD]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("超過一小時 → 再試一次", (r["source"], len(CALLS)), ("llm", n + 1))

section("【6b】事實區塊")
facts = ns.build_night_facts(D, {"target_bedtime": "23:30"},
                             {"final_score": 69.9, "duration_min": 215, "deep_min": 43,
                              "waso_min": 8, "rem_min": 42, "rem_measured": 0},
                             {"duration_min": 215, "deep_min": 60, "waso_min": 8}, None)
check("分數只放整數（App 上顯示的那個）", facts["last_night"]["score"], 70)
check("沒量到 REM → 不放 REM", "rem_sleep" in facts["last_night"], False)
check("一樣長 → about the same", facts["change_vs_previous_night"]["time_asleep"], "about the same")
check("時長格式", (ns.hm(215), ns.hm(45), ns.hm(120), ns.hm(-169)), ("3h 35m", "45m", "2h", "2h 49m"))

# ═══════════════════════════════════════════════════════════════════
section("【7】每一晚的曲線")
main._garmin_records = lambda: [
    {"metric": "sleep_stage", "timestamp": f"{D}T05:54:00+08:00", "value": "light"},
    {"metric": "sleep_stage", "timestamp": f"{D}T06:30:00+08:00", "value": "deep"},
    {"metric": "sleep_stage", "timestamp": f"{D}T07:10:00+08:00", "value": "rem"},
]
h = client.get(f"/home?user_id={u}&date={D}").json()
st = h["metrics"]["sleep_stages"]
check("Garmin 那一晚有曲線", [s["stage"] for s in st["segments"]], ["light", "deep", "rem"])
check("圖例用手錶自己的總數", st["minutes"]["deep"], 43)
check("淺睡＝總睡眠 − 深睡 − REM", st["minutes"]["light"], 130.0)
db.upsert_wearable_nightly(u, "2026-11-13", source="health_connect", metrics={
    "duration_min": 400, "final_score": 80.0, "final_quality": "Good",
    "sleep_start_time": "2026-11-13T00:00:00+08:00", "wake_time": "2026-11-13T07:00:00+08:00"}, db_path=TMP)
check("Health Connect 那一晚沒有（逐段資料沒存）",
      client.get(f"/home?user_id={u}&date=2026-11-13").json()["metrics"]["sleep_stages"], None)

# ═══════════════════════════════════════════════════════════════════
section("【5】刪帳號時一起刪")
ok("刪之前有資料", db.get_morning_rating(u, D, db_path=TMP) and db.get_night_summary(u, D, db_path=TMP))
check("DELETE /users", client.delete(f"/users/{u}").status_code, 200)
check("自評刪掉了", db.get_morning_rating(u, D, db_path=TMP), None)
check("AI 分析刪掉了", db.get_night_summary(u, D, db_path=TMP), None)

# ═══════════════════════════════════════════════════════════════════
section("【8】保險有效：整支測試一次都沒碰到網路")
check("網路呼叫次數", len(NETWORK_CALLS), 0)

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
