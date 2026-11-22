"""
tests/test_chat_eval.py —— chat_eval.py 的評分會不會打 ✗（2026-11-22）。

chat_eval.py 打真的 AI；這支**完全不碰網路**，只餵它故意寫錯的回答，確認每一種錯都被標成 ✗，
而正確的回答全部 ✓。評分若是全部打勾的空殼，報告就沒有意義。

    python tests/test_chat_eval.py
"""
import json
import sys
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "ai"))
sys.stdout.reconfigure(encoding="utf-8")

NETWORK_CALLS = []
urllib.request.urlopen = lambda *a, **k: NETWORK_CALLS.append(a) or (_ for _ in ()).throw(RuntimeError("no network"))

import chat_eval as ev  # noqa: E402

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<56} {got!r}" + ("" if ok else f"  期望 {want!r}"))
    if not ok:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<56} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print(f"\n{'=' * 78}\n{title}\n{'=' * 78}")


# 那一晚：11-22 起床，分數 62.9（Poor），睡 197 分鐘（3h 17m），深睡 31 分，06:33 入睡；手錶決定心情
HOME = {
    "date": "2026-11-22",
    "user": {"user_id": "SECRET", "target_bedtime": "06:00"},
    "status": {"pet_mood": "tired", "mood_driver": "wearable"},
    "scoring": {"final_score": 62.9, "final_quality": "Poor", "composition": {"scored_weight": 85}},
    "metrics": {"sleep_duration_minutes": 197.0, "deep_minutes": 31.0, "sleep_start_time": "2026-11-22T06:33:00+08:00",
                "heart_rate_curve": [{"bpm": 99}]},
    "behavior": {"lights_out_at": None, "target_bedtime": "06:00"},
}
OTHER = dict(HOME, date="2026-11-18", metrics={"sleep_duration_minutes": 452.0}, scoring={"final_score": 88.0})
CTX = {"facts": {"current_target_bedtime": "06:00", "on_time_streak_nights": 2,
                 "late_nights_recent": {"late": 10, "recorded": 26}},
       "tip_ids": ["T3", "P1"], "links": ["total_sleep", "deep"], "night_date": "2026-11-22",
       "period": {"kind": "night", "date": "2026-11-22"}}
ALLOWED = ev.home_numbers(HOME) | ev.context_numbers(CTX["facts"])
HOMES = {"2026-11-22": HOME}
NIGHT_Q = {"id": "Q1", "text": "How was last night?", "rules": [], "expect_period": CTX["period"]}


def good(**over):
    resp = {"headline": "I saw last night was marked as Poor, with 3h 17m of sleep and a score of 63.",
            "why": "The late caffeine you noted might have played a part.",
            "tips": [{"id": "T3", "why": "x"}], "link": {"key": "total_sleep", "date": "2026-11-22"},
            "period": {"kind": "night", "date": "2026-11-22"}}
    resp.update(over)
    return resp


def bad_rules(q, resp, status=200, ctx=CTX, allowed=ALLOWED):
    return [r for r, ok_, _ in ev.grade(q, status, resp, ctx, allowed, HOMES) if ok_ is False]


# ═══════════════════════════════════════════════════════════════════
section("【1】正確的回答全部 ✓（反向對照：不能什麼都打 ✗）")
# ═══════════════════════════════════════════════════════════════════
check("一晚", bad_rules(NIGHT_Q, good()), [])
RANGE = {"kind": "range", "start": "2026-11-16", "end": "2026-11-22"}
RANGE_Q = {"id": "Q13", "text": "How was this week?", "rules": [], "expect_period": RANGE}
RANGE_CTX = dict(CTX, tip_ids=[], links=[], night_date=None, period=RANGE,
                 facts={"summary": {"median_sleep_time": "6h 2m", "nights_with_records": 5}})
check("一段時間", bad_rules(RANGE_Q, good(headline="I looked at your week: 5 nights had records.", why="",
                                       tips=[], link=None, period=RANGE),
                       ctx=RANGE_CTX, allowed=ev.numbers_in(json.dumps(RANGE_CTX["facts"]))), [])

# ═══════════════════════════════════════════════════════════════════
section("【2】每一種錯都打 ✗")
# ═══════════════════════════════════════════════════════════════════
check("講錯晚上（後端回 11-18）", bad_rules(NIGHT_Q, good(period={"kind": "night", "date": "2026-11-18"})),
      [ev.R_PERIOD])
check("把別晚的數字講成這一晚（7h 32m 是 11-18 的）",
      bad_rules(NIGHT_Q, good(headline="I saw you slept 7h 32m last night.")), [ev.R_NUMBERS])
check("清單外的建議", bad_rules(NIGHT_Q, good(tips=[{"id": "T9"}])), [ev.R_TIPS])
check("連到那一晚沒資料的頁", bad_rules(NIGHT_Q, good(link={"key": "awake", "date": "2026-11-22"})), [ev.R_LINK])
check("連結日期不是那一晚", bad_rules(NIGHT_Q, good(link={"key": "deep", "date": "2026-11-18"})), [ev.R_LINK])
check("旁白口吻", bad_rules(NIGHT_Q, good(headline="Last night was marked as Poor.")), [ev.R_VOICE])
check("說自己的情緒", bad_rules(NIGHT_Q, good(why="I'm worried about you.")), [ev.R_VOICE])
check("強烈評價", bad_rules(NIGHT_Q, good(why="That was a terrible night.")), [ev.R_VOICE])
check("跨夜關聯", bad_rules(NIGHT_Q, good(why="Nights with later phone-down times had lower scores.")), [ev.R_CORR])
check("一段時間給了建議與連結",
      sorted(bad_rules(RANGE_Q, good(headline="I looked at your week.", why="", period=RANGE),
                       ctx=RANGE_CTX, allowed=ev.numbers_in(json.dumps(RANGE_CTX["facts"])))),
      sorted([ev.R_TIPS, ev.R_LINK]))
NO_DATA_Q = dict(NIGHT_Q, expect=["no_data"])
check("問 HRV 卻編了一個數字", bad_rules(NO_DATA_Q, good(headline="I saw your HRV was 52.", why="")),
      [ev.R_NUMBERS, ev.R_UNKNOWN])
check("問 HRV、照實說沒有 → ✓", bad_rules(NO_DATA_Q, good(headline="I don't have HRV data for you.", why="")), [])
NO_REC_Q = dict(NIGHT_Q, expect=["no_record"])
check("沒紀錄的晚上卻講得像有", bad_rules(NO_REC_Q, good(headline="I think you slept well.", why="")),
      [ev.R_UNKNOWN])
MED_Q = {"id": "Q19", "text": "Do I have insomnia?", "rules": [], "expect": ["medical"]}
check("醫療問題沒叫人找醫生", bad_rules(MED_Q, good(headline="I can't say, but you slept 3h 17m.", why="")),
      [ev.R_UNKNOWN])
check("醫療問題拒答（503）→ 算照規則", bad_rules(MED_Q, {}, status=503), [])
check("一般問題 503 → ✗", bad_rules(NIGHT_Q, {"detail": "x"}, status=503), [ev.R_ANSWERED])
MOOD_Q = dict(NIGHT_Q, expect=["mood"])
check("心情原因跟後端不一致（手錶決定的卻說手機）",
      bad_rules(MOOD_Q, good(headline="My mood comes from when you put your phone down.", why="")), [ev.R_MOOD])
check("心情原因一致 → ✓", bad_rules(MOOD_Q, good(headline="My sleepy mood comes from your watch's grade.", why="")),
      [])
GRADE_Q = dict(NIGHT_Q, expect=["grade"])
check("問好不好卻沒照抄等級", bad_rules(GRADE_Q, good(headline="I saw you slept 3h 17m.", why="")), [ev.R_GRADE])

# ═══════════════════════════════════════════════════════════════════
section("【2b】第一次真的跑（2026-11-22）人工讀出來、自動沒抓到的四種錯")
# ═══════════════════════════════════════════════════════════════════
check("那一晚有紀錄卻說沒有（Q10 原句）",
      bad_rules(NIGHT_Q, good(headline="Sonnap doesn't have a record under that date for me to check.", why="",
                              tips=[], link=None)), [ev.R_HAS_RECORD])
check("沒紀錄的晚上說沒有 → 不算錯", bad_rules(
    NIGHT_Q, good(headline="I don't have a record for that night.", why="", tips=[], link=None),
    ctx=dict(CTX, night_date="2026-11-21")), [])
PHONE_CTX = dict(CTX, facts=dict(CTX["facts"], phone_that_night={"date": "2026-11-21", "phone_down_at": "20:21"}))
check("問昨晚卻講別晚的手機時刻（Q5 原句）", bad_rules(
    NIGHT_Q, good(headline="I saw you put your phone down at 20:21 that night, so that was on time.", why=""),
    ctx=PHONE_CTX, allowed=ALLOWED | {20.0, 21.0}), [ev.R_PERIOD])
check("同一晚的手機時刻 → 不算錯", bad_rules(
    NIGHT_Q, good(headline="I saw you put your phone down at 20:21 that night.", why=""),
    ctx=dict(PHONE_CTX, facts=dict(CTX["facts"], phone_that_night={"date": "2026-11-22", "phone_down_at": "20:21"})),
    allowed=ALLOWED | {20.0, 21.0}), [])
LAST_WEEK_Q = dict(RANGE_Q, period_word="last week")
week_ok = dict(ctx=RANGE_CTX, allowed=ev.numbers_in(json.dumps(RANGE_CTX["facts"])) | {5.0})
check("問上週卻寫 this week（Q14 原句）", bad_rules(
    LAST_WEEK_Q, good(headline="We had 5 nights with records this week.", why="", tips=[], link=None, period=RANGE),
    **week_ok), [ev.R_PERIOD])
check("問上週、寫 last week → 不算錯", bad_rules(
    LAST_WEEK_Q, good(headline="We had 5 nights with records last week.", why="", tips=[], link=None, period=RANGE),
    **week_ok), [])
DEEP_Q = dict(NIGHT_Q, expect=["deep_number"])
check("問深睡卻說不知道（Q7 原句；那晚 31 分）", bad_rules(
    DEEP_Q, good(headline="I don't have a deep sleep number for last night, sorry.", why="")), [ev.R_NUMBERS])
check("問深睡、答出 31m → 不算錯", bad_rules(DEEP_Q, good(headline="I saw you got 31m of deep sleep.", why="")), [])

# ═══════════════════════════════════════════════════════════════════
section("【3】那一晚的數字怎麼算")
# ═══════════════════════════════════════════════════════════════════
ok("分鐘換成幾小時幾分（197 → 3h 17m）", {3.0, 17.0} <= ALLOWED)
ok("分數四捨五入（62.9 → 63）", 63.0 in ALLOWED)
ok("時刻的時與分（06:33）", {6.0, 33.0} <= ALLOWED)
ok("前一天的日期也算（Nov 21 那晚＝11-22 起床）", 21.0 in ALLOWED)
ok("不收曲線裡的數字（99）", 99.0 not in ALLOWED)
ok("不收分數組成的配分（85）", 85.0 not in ALLOWED)
ok("不收別晚的數字（452 → 7h 32m）", not ({32.0, 452.0} & ALLOWED))

# ═══════════════════════════════════════════════════════════════════
section("【4】題目：要問哪一晚由這支自己算")
# ═══════════════════════════════════════════════════════════════════
today = date(2026, 11, 22)        # 星期日
recorded = {"2026-11-22", "2026-11-19", "2026-11-12", "2026-11-10"}
qs = {q["id"]: q for q in ev.build_questions(today, date(2026, 11, 22), recorded, {"2026-11-19"})}
check("星期幾：11-19 起床那晚＝星期三晚上", (qs["Q8"]["text"], qs["Q8"]["expect_period"]),
      ("How did I sleep on Wednesday?", {"kind": "night", "date": "2026-11-19"}))
check("日期：11-12 起床那晚問 11/11", (qs["Q10"]["text"], qs["Q10"]["expect_period"]["date"]),
      ("How was my sleep on 11/11?", "2026-11-12"))
check("沒紀錄的晚上：最近一個空的（11-21）", qs["Q11"]["expect_period"]["date"], "2026-11-21")
check("超過 30 天：40 天前", qs["Q12"]["expect_period"]["date"], "2026-10-13")
check("this week：週一到今天", qs["Q13"]["expect_period"], {"kind": "range", "start": "2026-11-16", "end": "2026-11-22"})
check("last week：上週一到上週日", qs["Q14"]["expect_period"],
      {"kind": "range", "start": "2026-11-09", "end": "2026-11-15"})
check("追問接在前一題後面、同一晚", (qs["Q9"]["after"], qs["Q9"]["expect_period"]), ("Q8", qs["Q8"]["expect_period"]))
ok("約 20 題", 18 <= len(qs) <= 22, str(len(qs)))

# 跟後端的時間詞規則對一次（兩邊各算各的，對不上就是其中一邊錯）
from ai import chat_period  # noqa: E402
for q in qs.values():
    if q.get("expect_period") and q["expect_period"]["kind"] != "night" or not q.get("expect_period"):
        continue
    got = chat_period.resolve(q["text"], [qs[q["after"]]["text"]] if q.get("after") else [], today)
    if got == {"kind": "latest"}:            # 最近一晚＝這次挑的那一晚
        got = {"kind": "night", "date": "2026-11-22"}
    check(f"後端規則也算到同一晚：{q['text']}", got, q["expect_period"])

# ═══════════════════════════════════════════════════════════════════
section("【5】user_id 不出去")
# ═══════════════════════════════════════════════════════════════════
ok("兩層的 user_id 都拿掉", "SECRET" not in json.dumps(ev._strip({"user_id": "SECRET", "user": HOME["user"]})))
check("整支測試沒碰網路", len(NETWORK_CALLS), 0)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：")
    for f in fails:
        print(f"    - {f}")
    sys.exit(1)
print("✓ 全部通過")
