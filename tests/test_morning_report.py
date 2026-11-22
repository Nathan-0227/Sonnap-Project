"""
tests/test_morning_report.py —— 早晨報告的後端（2026-11-12）

守的東西（都是壞掉時不會報錯的）：
   【1】小建議：觸發條件、優先順序、T1/T2 不重疊、運動只在沒有別的觸發時出現；
        生理判讀（P1–P8）的適用條件；最多 3 條
   【2】程式裡的 20 句與 Research-Background/起床小建議與自評.md **逐字一致**
   【3】POST /rested：只收清單裡的標籤、分數 1–5、真的日期；同一晚覆蓋
   【4】⚠️ 自評**不進分數、不給 XP**：存了自評前後，分數與 XP 一模一樣；評分層與遊戲層不讀這張表
   【5】刪帳號時自評與 AI 分析一起刪
   【6】寵物 notes（2026-11-17）：沒有手錶資料不呼叫、只給行為原句；沒有金鑰只給原句、不給總結、不存；
        每晚只呼叫一次；事實變了才重生、version 跟著換；兩次沒過退回並存起來、一小時內不再試
   【6c】驗證：清單外的行動、換掉重點、總結塞建議、斷定因果、「不准說」那幾種話、太長都擋；好的不誤擋
   【6d】⚠️ 攝影機與壓力不進 prompt；判讀用評分器的門檻、不是另訂的
   【7】每一晚的曲線：Garmin 來源有、Health Connect 沒有
   【8】整支測試一次都沒碰到網路

⚠️ **絕對不能打到真的 Claude API。** 三道保險同 tests/test_chat.py：
   1. import 前把 ANTHROPIC_API_KEY 設成空字串
   2. urllib.request.urlopen 換成一被呼叫就失敗
   3. ai.night_summary.complete 換成假的

執行：python tests/test_morning_report.py
"""
import contextlib
import io
import json
import os
import re
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
check("優先順序涵蓋全部句子、沒有重複", sorted(mt.PRIORITY), sorted(mt.TIPS))
check("每一句都有適用說明與重點字", (set(mt.WHEN), set(mt.KEYWORDS)), (set(mt.TIPS), set(mt.TIPS)))
for tid, (_, text) in mt.TIPS.items():
    ok(f"{tid} 的原句本身就含重點字（不然原句也過不了驗證）",
       bool(re.search(mt.KEYWORDS[tid], text, re.I)), text[:40])


def ptips(tags=(), minutes=None, **judged):
    return [t["id"] for t in mt.applicable_tips(tags, minutes, judged, limit=99)]


B, W, A, H = mt.BELOW, mt.WITHIN, mt.ABOVE, mt.HR_HIGHER
check("睡太短 → P1", ptips(time_asleep=B), ["P1"])
check("時長在範圍內 → 不給", ptips(time_asleep=W), [])
check("勾運動＋睡太短 → P2 優先於 P1、T7 拿掉（紅線 5）", ptips(["exercise"], time_asleep=B), ["P2", "P1"])
check("勾運動但睡得好 → 只有 T7", ptips(["exercise"], time_asleep=W), ["T7"])
check("REM 少＋手機晚放 → P3", "P3" in ptips(minutes=10, rem_sleep=B), True)
check("REM 少但準時 → 沒有 P3", "P3" in ptips(minutes=-5, rem_sleep=B), False)
check("REM 少＋睡太短 → P4", "P4" in ptips(time_asleep=B, rem_sleep=B), True)
check("深睡少、前一晚睡夠 → P5（不是問題）", ptips(deep_sleep=B, previous_time_asleep=W), ["P5"])
check("深睡少、前一晚也短 → 沒有 P5", ptips(deep_sleep=B, previous_time_asleep=B), [])
check("深睡少＋午睡 → T5 之後接 P6", ptips(["napped"], deep_sleep=B), ["T5", "P6"])
check("心率高＋酒精 → P7 緊接 T4", ptips(["alcohol"], sleeping_heart_rate=H), ["T4", "P7"])
check("心率高＋生病 → P8 緊接 T9", ptips(["unwell"], sleeping_heart_rate=H), ["T9", "P8"])
check("心率高但沒勾任何東西 → 不硬塞原因", ptips(sleeping_heart_rate=H), [])
check("最多 3 條（紅線 5）", len(mt.applicable_tips(["unwell", "alcohol", "late_caffeine", "noise"], 90,
                                               {"time_asleep": B, "sleeping_heart_rate": H})), 3)

# ═══════════════════════════════════════════════════════════════════
section("【2】程式裡的句子與文件逐字一致（措辭由使用者審過）")
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
    # 2026-11-15 使用者定（好友分享 grill）：自評可以**自己選擇**給好友看——只准 sharing.py 讀，
    # 而且**預設關**。評分、遊戲照舊一個字都不准讀。
    allowed = ["sharing.py"] if folder == "social" else []
    check(f"{folder}/ 讀自評的只有 {allowed or '（沒有）'}", hits, allowed)
import social.sharing as _sharing  # noqa: E402
check("自評預設不給好友看", _sharing.defaults()["morning_rating"], False)
for name in ("score_claim.py", "build_app_payload.py"):
    check(f"{name} 不讀自評", "morning_rating" in (ROOT / name).read_text(encoding="utf-8"), False)
check("上一晚的睡眠長度給「跟上一晚比」用", h2["previous_night"]["sleep_duration_minutes"], 420)

# ═══════════════════════════════════════════════════════════════════
section("【6】寵物 notes")
CALLS = []
REPLIES = []


def fake_complete(system, user_prompt, schema, max_tokens=0):     # 保險 3
    CALLS.append(user_prompt)
    return REPLIES.pop(0), "fake-model"


def notes(summary, *tips):
    return {"summary": summary, "tips": [{"id": i, "text": t} for i, t in tips]}


ns.complete = fake_complete
ns.key_available = lambda: False

# 前一個日曆日的白天資料：步數要進 prompt，壓力不准進
db.upsert_garmin_daily(u, PREV, {"steps": 4321, "step_goal": 8000, "active_sec": 1800,
                                 "stress_high_sec": 7777, "stress_medium_sec": 6666}, db_path=TMP)

w = client.get(f"/night-summary?user_id={u}&date=2026-11-01").json()
check("沒有手錶資料 → waiting，不呼叫 AI", (w["status"], len(CALLS)), ("waiting", 0))
check("waiting 沒有總結", w["summary"], None)

# 這一晚：睡 3h35m（低於 7–9h）、REM 19.5%（低於 20–25%）、深睡 20%（範圍內）、
# 放下手機晚 20 分、勾了運動、前一晚 7h（範圍內）
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("沒有金鑰 → fallback", r["source"], "fallback")
check("⚠️ fallback 不給總結（不拿模板假裝是 AI 寫的）", r["summary"], None)
check("fallback 給原句：運動＋睡太短 → P2、REM 少＋手機晚 → P3、睡太短 → P1",
      [t["id"] for t in r["tips"]], ["P2", "P3", "P1"])
check("原句逐字", r["tips"][0]["text"], mt.TIPS["P2"][1])
check("沒有金鑰 → 不存（設定好之後要能生成）", db.get_night_summary(u, D, db_path=TMP), None)
check("舊版 App 的 tip 欄位＝第一條原句", r["tip"]["id"], "P2")
v_fallback = r["version"]

ns.key_available = lambda: True
r = client.get(f"/night-summary?user_id={u}&date={D}&generate=false").json()
check("⚠️ generate=false（首頁）→ 有金鑰也不呼叫 AI、不存", (len(CALLS), r["source"], r["summary"],
      db.get_night_summary(u, D, db_path=TMP)), (0, "fallback", None, None))
GOOD = notes("We slept 3h 35m together, 3h 25m less than the night before.",
             ("P2", "Hard workouts that end near bedtime might make our nights shorter, "
                    "so let's wrap them up at least 4 hours before."))
REPLIES[:] = [GOOD]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("有金鑰 → AI 寫的那段", (r["source"], r["summary"]), ("llm", GOOD["summary"]))
check("建議用寵物口吻，原句另外附上", (r["tips"][0]["text"], r["tips"][0]["original"]),
      (GOOD["tips"][0]["text"], mt.TIPS["P2"][1]))
check("呼叫了一次", len(CALLS), 1)
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("⚠️ 再打開一次 → 讀存好的，不再花額度", (len(CALLS), r["summary"]), (1, GOOD["summary"]))
r = client.get(f"/night-summary?user_id={u}&date={D}&generate=false").json()
check("generate=false 讀得到已經存好的那一份", (len(CALLS), r["source"], r["summary"]), (1, "llm", GOOD["summary"]))
ok("事實區塊有寫好的時長（照抄用，不讓 AI 換算）", "3h 25m less" in CALLS[0], "")
ok("事實區塊有使用者的目標", '"in_bed_by": "23:30"' in CALLS[0], "")
ok("事實區塊附判讀（AI 不自己判）", f'"judgment": "{mt.BELOW}"' in CALLS[0], "")
TIPS_SENT = CALLS[0].split("\n\nTIP LIST:")[1]
ok("今晚推薦的（P2、P3、P1）都交給 AI", all(f'"id": "{tid}"' in TIPS_SENT for tid in ("P2", "P3", "P1")), "")
# ⚠️ 2026-11-18：原本整份 20 條都交給 AI、推薦只是標記；11-17 AI 自己挑了沒觸發的 P4 還把意思寫反
check("⚠️ 沒被推薦的一條都不交給 AI", [tid for tid in mt.TIPS if f'"id": "{tid}"' in TIPS_SENT
                                    and tid not in ("P2", "P3", "P1")], [])
v_llm = r["version"]

kept = json.loads(db.get_night_summary(u, D, db_path=TMP)["text"])
check("存 notes 時連同當時的事實一起存（之後比得出哪一項變了）",
      (kept.get("facts", {}).get("date"), kept.get("tip_ids")), (D, ["P2", "P3", "P1"]))
client.post("/rested", json={"user_id": u, "date": D, "rested": 3, "tags": ["late_caffeine"]})
REPLIES[:] = [notes("We slept 3h 35m together.",
                    ("T3", "Caffeine even 6 hours before bed can cut sleep short, so maybe keep coffee early."))]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    r = client.get(f"/night-summary?user_id={u}&date={D}").json()
log = buf.getvalue()
check("補了自評（事實變了）→ 重生一次", len(CALLS), 2)
ok("重寫前印出變了哪幾項：自評那一項、建議清單", "how_you_felt" in log and "tip_list" in log, log)
ok("⚠️ 紀錄裡沒有 user_id（它是憑證）", u not in log, log)
ok("⚠️ 紀錄裡只有項目名稱、沒有數值（changed: 後面只准是 a.b 這種名稱）",
   re.fullmatch(r"[a-z_.]+(, [a-z_.]+)*", log.split("changed: ")[-1].strip()) is not None, log)
check("比對函式：巢狀的寫成 a.b、一樣的不列、新增與拿掉都算",
      ns.changed_fact_keys({"x": 1, "p": {"at": "01:00", "v": 2}, "gone": 1},
                           {"x": 1, "p": {"at": "02:00", "v": 2}, "new": 1}),
      ["gone", "new", "p.at"])
ok("⚠️ 內容變了 → version 跟著換（App 靠它讓紅點再亮）", len({v_fallback, v_llm, r["version"]}) == 3,
   str((v_fallback, v_llm, r["version"])))

BAD_NUMBER = notes("We slept 9h together.")
REPLIES[:] = [BAD_NUMBER, notes("We slept 3h 35m together.")]
client.post("/rested", json={"user_id": u, "date": D, "rested": 3, "tags": ["late_caffeine", "stress"]})
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("第一次沒過 → 帶著原因重問，第二次過了", (r["source"], len(CALLS)), ("llm", 4))
ok("重問時有說哪裡不行", "REJECTED" in CALLS[-1], "")
check("好晚上可以 0 條建議", r["tips"], [])

client.post("/rested", json={"user_id": u, "date": D, "rested": 4, "tags": []})
REPLIES[:] = [BAD_NUMBER, BAD_NUMBER]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("兩次都沒過 → fallback", (r["source"], r["summary"]), ("fallback", None))
check("退回也存起來", db.get_night_summary(u, D, db_path=TMP)["source"], "fallback")
n = len(CALLS)
client.get(f"/night-summary?user_id={u}&date={D}")
check("⚠️ 一小時內再打開 → 不再花額度", len(CALLS), n)
old = (datetime.now() - timedelta(minutes=main.SUMMARY_RETRY_MINUTES + 5)).astimezone().isoformat()
conn = db.connect(TMP)
conn.execute("UPDATE night_summaries SET created_at = ? WHERE user_id = ?", (old, u))
conn.commit()
conn.close()
REPLIES[:] = [notes("We slept 3h 35m together.")]
r = client.get(f"/night-summary?user_id={u}&date={D}").json()
check("超過一小時 → 再試一次", (r["source"], len(CALLS)), ("llm", n + 1))

# ═══════════════════════════════════════════════════════════════════
section("【6c】驗證")
FACTS_TEXT = CALLS[0].split("\n\nTIP LIST:")[0]   # 只取事實那段（清單裡的數字不算數）
ok("反向對照：真的切掉了清單", "TIP LIST" not in FACTS_TEXT and '"last_night"' in FACTS_TEXT, "")


def problems(n, allowed=tuple(mt.TIPS)):
    """內容規則的檢查不管今晚推薦哪幾條（全部都准），「只准推薦的」另外測。"""
    return ns.validate_notes(n, FACTS_TEXT, allowed)


check("好的不誤擋", problems(GOOD), [])
P4_INVERTED = notes("We slept 3h 35m.", ("P4", "A short night can mean REM takes a bigger share — "
                                              "most REM comes late in the night."))
ok("⚠️ 不是今晚推薦的那條（11-17 的 P4）→ 擋", any("does not fit tonight" in p for p in
   problems(P4_INVERTED, allowed=("P1",))), str(problems(P4_INVERTED, allowed=("P1",))))
ok("反向對照：同一條被推薦時不擋", not problems(P4_INVERTED, allowed=("P4",)), "")
ok("今晚沒有推薦 → 任何一條都擋", any("does not fit tonight" in p for p in problems(GOOD, allowed=())), "")
FACTS = json.loads(FACTS_TEXT[len("FACTS:\n"):])
REPLIES[:] = [P4_INVERTED, notes("We slept 3h 35m.", ("P1", "Most adults are recommended 7–9 hours, "
                                                             "so give yourself enough time in bed."))]
out = ns.summarize_night(FACTS, ns.tip_list(["P1"]))
check("AI 挑了沒推薦的 → 帶著原因重寫，第二次過了", (out["attempts"], [t["id"] for t in out["tips"]]), (2, ["P1"]))
ok("重寫時說了是哪條不適用", "P4 does not fit tonight" in CALLS[-1], "")
check("數字不在事實裡 → 擋", bool(problems(BAD_NUMBER)), True)
ok("⚠️ 清單外的行動 → 擋", any("not in the tip list" in p for p in
   problems(notes("We slept 3h 35m.", ("X1", "Try melatonin gummies tonight.")))), "")
ok("挑了 T3 卻沒講咖啡（換掉重點）→ 擋", any("lost its key point" in p for p in
   problems(notes("We slept 3h 35m.", ("T3", "Let's go to bed earlier tonight.")))), "")
# 2026-11-22：重點字要從字首比。原本 "nap" 命中 "Sonnap"、"hot" 命中 "photo"，換掉建議的改寫照樣過關
ok("⚠️ 挑了 P6 只寫到 Sonnap（不是 nap）→ 擋", any("lost its key point" in p for p in
   problems(notes("We slept 3h 35m.", ("P6", "Sonnap says rest well and sleep early tonight.")))), "")
ok("⚠️ 挑了 T6 只寫到 photo（不是 hot）→ 擋", any("lost its key point" in p for p in
   problems(notes("We slept 3h 35m.", ("T6", "Put the photo away and sleep early tonight.")))), "")
ok("反向對照：真的講到 nap 時不擋", not any("lost its key point" in p for p in
   problems(notes("We slept 3h 35m.", ("P6", "A short, early nap helps keep deep sleep steady.")))), "")
ok("總結裡塞建議 → 擋", any("advice" in p for p in
   problems(notes("We slept 3h 35m, so try to sleep earlier."))), "")
ok("斷定因果（because）→ 擋", any("cause" in p for p in
   problems(notes("We slept 3h 35m because of the coffee."))), "")
ok("可能原因用 might → 不擋", not problems(notes("We slept 3h 35m; the late coffee might be part of it.")), "")
ok("同一條用兩次 → 擋", any("twice" in p for p in problems(
    notes("We slept 3h 35m.", ("T3", "Keep caffeine early."), ("T3", "Coffee early.")))), "")
ok("超過 3 條 → 擋", any("more than 3" in p for p in problems(notes(
    "We slept 3h 35m.", ("T3", "Keep caffeine early."), ("T4", "Alcohol breaks up sleep."),
    ("T6", "A cool room helps."), ("T12", "A quiet room helps.")))), "")
ok("太長 → 擋", any("too long" in p for p in problems(notes(" ".join(["We slept 3h 35m."] * 2),
   ("T6", " ".join(["A cool room helps a lot."] * 20))))), "")
for label, bad in [
    ("酒精讓深睡變少", notes("We slept 3h 35m.", ("T4", "Alcohol might leave you with less deep sleep."))),
    ("步數當原因", notes("We slept 3h 35m, and fewer steps might be why we slept less.")),
    ("晚餐吃太晚", notes("We slept 3h 35m; a late dinner might be part of it.")),
    ("待辦清單讓人睡更久", notes("We slept 3h 35m.", ("T8", "A to-do list can help you sleep longer."))),
    ("晚上運動傷睡眠", notes("We slept 3h 35m.", ("T7", "Exercise in the evening is bad for sleep."))),
    ("提到攝影機", notes("We slept 3h 35m and the camera saw lots of tossing.")),
    ("提到壓力分數", notes("We slept 3h 35m with a high stress score.")),
]:
    ok(f"⚠️ 不准說：{label} → 擋", bool(problems(bad)), str(problems(bad)[:1]))
ok("P2 的限定說法（高強度、睡前不久）→ 不擋", not problems(notes(
    "We slept 3h 35m.", ("P2", "Hard workouts late in the evening might disturb sleep, "
                               "so let's finish them 4 hours before bed."))), "")
ok("步數只當背景、不當原因 → 不擋", not problems(notes("We slept 3h 35m after a day of 4,321 steps.")), "")

# ═══════════════════════════════════════════════════════════════════
section("【6d】⚠️ 攝影機與壓力不進 prompt；判讀用評分器的門檻")
ok("步數有進 prompt（要給 AI 當背景）", '"steps": "4,321"' in FACTS_TEXT, "")
ok("壓力沒有進 prompt（資料庫裡明明有）", "7777" not in FACTS_TEXT and "stress_" not in FACTS_TEXT, "")
src = (ROOT / "ai" / "night_summary.py").read_text(encoding="utf-8")
code = "\n".join(line.split("#")[0] for line in src.splitlines())
for name in ("get_camera", "camera_nightly", "events_per_hour", "motion_", "stress_"):
    check(f"night_summary.py 的程式碼不讀 {name}", name in code, False)
import evaluate_sleep_quality as esq   # noqa: E402  ai/night_summary 已把 garmin/ 加進 sys.path
facts = ns.build_night_facts(D, {"target_bedtime": "23:30"},
                             {"final_score": 69.9, "duration_min": 215, "deep_min": 43,
                              "waso_min": 8, "rem_min": 42, "rem_measured": 0},
                             {"duration_min": 215, "deep_min": 60, "waso_min": 8}, None)
check("分數只放整數（App 上顯示的那個）", facts["last_night"]["score"], 70)
check("沒量到 REM → 不放 REM", "rem_sleep" in facts["last_night"], False)
check("一樣長 → about the same", facts["change_vs_previous_night"]["time_asleep"], "about the same")
check("時長格式", (ns.hm(215), ns.hm(45), ns.hm(120), ns.hm(-169)), ("3h 35m", "45m", "2h", "2h 49m"))
lo, hi = esq.DURATION_RANGE["young_adult"]
check("時長判讀邊界就是評分器的常數（下限剛好＝範圍內）",
      (ns.judge_night({"final_score": 1, "duration_min": lo * 60}, None, {})["time_asleep"],
       ns.judge_night({"final_score": 1, "duration_min": lo * 60 - 1}, None, {})["time_asleep"]),
      (mt.WITHIN, mt.BELOW))
good, fair = esq.WASO_THRESHOLD["young_adult"]
check("WASO 判讀用評分器的分齡門檻", [ns.judge_night({"final_score": 1, "waso_min": m}, None, {})
                                 ["awake_during_night"] for m in (good, fair, fair + 1)],
      ["low", "moderate", "high"])
check("年長者用自己的時長範圍（7–8h，9h 算 above）",
      ns.judge_night({"final_score": 1, "duration_min": 540}, None, {"age_band": "older_adult"})["time_asleep"],
      mt.ABOVE)
check("心率修正值為負（心率比平常高）→ higher",
      ns.judge_night({"final_score": 1, "rhr_modifier": -1.0, "avg_hr_modifier": -0.5}, None, {})
      ["sleeping_heart_rate"], mt.HR_HIGHER)
check("沒有心率修正值（冷啟動）→ 不判讀",
      "sleeping_heart_rate" in ns.judge_night({"final_score": 1}, None, {}), False)
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
