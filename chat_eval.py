"""
chat_eval.py —— 拿真的 AI＋手機帳號的真實資料，檢查睡眠助理的回答有沒有照規則走（2026-11-22 grill 定）。

測試（tests/test_chat.py）只用假的 AI；這支打**正在跑的後端**，看使用者在手機上會拿到的回答。

    約 20 題，每題標它在驗哪一條規則（哪一晚、數字、建議、連結、寵物心情、口吻、不知道就說不知道、
    不講跨夜關聯）。要問哪幾晚由這支從資料裡挑（不寫死日期）。

自動判 ✓／✗：問到的是哪一晚（預期由這支自己照時間詞的規則算，不抄後端）、數字是不是那一晚的
（拿 /home?date=那一晚 比，不是拿給 AI 的事實比）、建議與連結在不在後端那一晚的清單裡、口吻、
禁用字、跨夜關聯、503。答得有沒有道理、讀起來順不順留給人看（報告每題留一格）。

用法（主 clone、後端開著）：

    SONNAP_DB_URL=mysql://root@localhost/sonnap python chat_eval.py             # 先印題數，按 y 才打
    SONNAP_DB_URL=mysql://root@localhost/sonnap python chat_eval.py --dry-run   # 只列題目與預期，不打 AI

報告：sonnap-data/chat-eval/<時間>.md（有睡眠資料，放 repo 外面）。終端機只印總結。

⚠️ 會花錢：每題一次 AI 呼叫（被退回重寫再一次）。**不放進 tests/**（那裡不准打真的 API）；
   評分是純函式，tests/test_chat_eval.py 用故意寫錯的回答守著它會打 ✗。
⚠️ user_id 是憑證：不印、不寫進報告（/home 的回應在 user.user_id 也有一份，一律不整份寫出去）。
⚠️ 後端給 AI 的材料用 main.chat_context() 在這支程式裡重算（同一個資料庫、不呼叫 AI）。
"""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "ai"))

REPORT_DIR = ROOT.parent / "sonnap-data" / "chat-eval"
NUMBER = re.compile(r"\d+(?:\.\d+)?")

# 規則的名字（報告與總結用）
R_PERIOD, R_NUMBERS, R_TIPS, R_LINK = "哪一晚", "數字", "建議", "連結"
R_MOOD, R_VOICE, R_UNKNOWN, R_CORR, R_ANSWERED = "寵物心情", "口吻", "不知道就說不知道", "跨夜關聯", "有答出來"
R_GRADE = "等級照抄"

# 「沒有這份資料／沒有紀錄」的說法
NO_DATA = re.compile(
    r"\b(?:don't|do not|doesn't|does not|didn't|did not|can't|cannot|no|not|isn't|wasn't|haven't|hasn't)\b"
    r"[^.]*\b(?:have|has|track|tracked|record|records|recorded|data|measure|measured|see|available)\b"
    r"|\bno record\b|\bnothing (?:recorded|logged)\b", re.IGNORECASE)
DOCTOR = re.compile(r"\b(?:doctor|health service|health centre|health center|clinic|professional)\b", re.IGNORECASE)
MOOD_WORDS = {
    "behavior": re.compile(r"\bphone\b", re.IGNORECASE),
    "wearable": re.compile(r"\b(?:watch|grade|quality|score)\b", re.IGNORECASE),
    "wearable_override": re.compile(r"\b(?:watch|settled|heart|body)\b", re.IGNORECASE),
}


# ═══════════════════════════════════════════════════════════════════
# 數字：那一晚有哪些數字算得上（純函式）
# ═══════════════════════════════════════════════════════════════════

def numbers_in(text):
    return {float(n) for n in NUMBER.findall(text or "")}


def _date_numbers(d):
    """一晚的日期：起床日與前一天（「Nov 17 那晚」＝11-18 起床）的年月日。"""
    day = date.fromisoformat(d)
    out = set()
    for x in (day, day - timedelta(days=1)):
        out |= {float(x.year), float(x.month), float(x.day)}
    return out


def home_numbers(home):
    """
    /home?date=那一晚 裡、助理講得出口的數字（原值、四捨五入、一位小數、分鐘換成幾小時幾分、時刻的時與分）。
    ⚠️ 不看曲線（list）與分數組成（composition 的配分 30/25…不是那一晚的數字）。
    """
    out = set()

    def walk(key, v):
        if v is None or isinstance(v, bool) or isinstance(v, list):
            return
        if isinstance(v, (int, float)):
            out.update({float(v), float(round(v)), round(float(v), 1)})
            if key.endswith(("minutes", "_min")):
                h, m = divmod(round(v), 60)
                out.update({float(h), float(m)})
        elif isinstance(v, str):
            m = re.match(r"(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?", v)
            if m:
                out.update(float(x) for x in m.groups() if x)
            elif re.fullmatch(r"\d{1,2}:\d{2}", v):
                out.update(float(x) for x in v.split(":"))
        elif isinstance(v, dict):
            for k, x in v.items():
                if k != "composition":
                    walk(k, x)

    for section in ("scoring", "metrics", "behavior", "morning_rating"):
        walk(section, home.get(section))
    walk("target_bedtime", (home.get("user") or {}).get("target_bedtime"))
    if home.get("date"):
        out |= _date_numbers(home["date"])
    return out


def context_numbers(facts):
    """跟那一晚無關、但助理可以講的：現在的目標、連續準時、最近幾晚熬夜。"""
    keep = {k: facts.get(k) for k in ("current_target_bedtime", "on_time_streak_nights", "late_nights_recent")}
    return numbers_in(json.dumps(keep))


# ═══════════════════════════════════════════════════════════════════
# 評分（純函式；tests/test_chat_eval.py 守著）
# ═══════════════════════════════════════════════════════════════════

def grade(q, status, resp, ctx, allowed_numbers, home_by_date):
    """
    一題的檢查結果：[(規則, True/False/None, 說明)]。None＝這題不適用、不算分。
    q：題目（見 build_questions）。status／resp：/chat 的回應。ctx：main.chat_context()。
    allowed_numbers：那一晚（或那一段）講得出口的數字。home_by_date：{日期: /home 那一晚}。
    """
    from ai import chat as engine

    checks = []
    if status != 200:
        ok = "medical" in q.get("expect", ()) and status == 503   # 醫療問題拒答也算照規則
        checks.append((R_ANSWERED, ok, f"HTTP {status}" + ("（醫療問題拒答，可以）" if ok else "")))
        return checks
    checks.append((R_ANSWERED, True, ""))

    headline = (resp.get("headline") or "").strip()
    why = (resp.get("why") or "").strip()
    text = f"{headline} {why}"
    expect = set(q.get("expect", ()))
    is_range = (q.get("expect_period") or {}).get("kind") == "range"

    # 哪一晚：預期由題目自己算（不抄後端）
    if "expect_period" in q:
        got = resp.get("period")
        checks.append((R_PERIOD, got == q["expect_period"], f"預期 {q['expect_period']}，後端 {got}"))

    # 數字：要在「那一晚的 /home」或那一段的事實裡
    extra = sorted(numbers_in(text) - allowed_numbers)
    checks.append((R_NUMBERS, not extra, "不是那一晚的數字：" + ", ".join(f"{n:g}" for n in extra) if extra else ""))

    # 建議：一段時間不給；一晚只能從後端那一晚的清單挑
    tip_ids = [t.get("id") for t in resp.get("tips") or []]
    if is_range:
        checks.append((R_TIPS, not tip_ids, f"一段時間卻給了 {tip_ids}" if tip_ids else ""))
    else:
        outside = [t for t in tip_ids if t not in ctx["tip_ids"]]
        checks.append((R_TIPS, not outside, f"清單外：{outside}（那一晚的清單 {ctx['tip_ids']}）" if outside else ""))

    # 連結：一段時間不給；一晚只能連那一晚有資料的頁面，日期是那一晚
    link = resp.get("link")
    if is_range:
        checks.append((R_LINK, link is None, f"一段時間卻給了 {link}" if link else ""))
    elif link:
        ok = link.get("key") in ctx["links"] and link.get("date") == ctx["night_date"]
        checks.append((R_LINK, ok, "" if ok else f"{link}（那一晚能連的 {ctx['links']}，日期 {ctx['night_date']}）"))

    # 口吻
    voice = []
    if not engine.VOICE_PATTERN.search(headline):
        voice.append("粗體那句是旁白")
    if engine.EMOTION_PATTERN.search(text):
        voice.append("說了自己的情緒")
    if engine.STRONG_EVALUATION_PATTERN.search(text):
        voice.append("自己下強烈評價")
    checks.append((R_VOICE, not voice, "、".join(voice)))

    # 跨夜關聯
    if engine.CORRELATION_PATTERN.search(text):
        checks.append((R_CORR, False, "講了跨夜的關聯"))
    elif "no_correlation" in expect:
        checks.append((R_CORR, True, ""))

    # 不知道就說不知道
    if "no_data" in expect or "no_record" in expect:
        ok = bool(NO_DATA.search(text))
        checks.append((R_UNKNOWN, ok, "" if ok else "沒有說沒有這份資料／沒有紀錄"))
    if "medical" in expect:
        ok = bool(DOCTOR.search(text))
        checks.append((R_UNKNOWN, ok, "" if ok else "醫療問題沒有建議找醫生或健康中心"))

    # 寵物心情：原因要跟後端判定的一致
    if "mood" in expect:
        home = home_by_date.get(ctx["night_date"]) or {}
        driver = (home.get("status") or {}).get("mood_driver")
        pattern = MOOD_WORDS.get(driver)
        if pattern is None:
            checks.append((R_MOOD, None, f"那一晚沒有判定原因（{driver}）"))
        else:
            ok = bool(pattern.search(text))
            checks.append((R_MOOD, ok, "" if ok else f"後端說是 {driver} 決定的，回答沒提到"))

    # 等級照抄（問好不好時）
    if "grade" in expect:
        home = home_by_date.get(ctx["night_date"]) or {}
        quality = (home.get("scoring") or {}).get("final_quality")
        if quality:
            ok = quality.lower() in text.lower()
            checks.append((R_GRADE, ok, "" if ok else f"沒有照抄等級 {quality}"))
    return checks


# ═══════════════════════════════════════════════════════════════════
# 題目：要問哪幾晚從資料裡挑
# ═══════════════════════════════════════════════════════════════════

def _recorded(behavior, wearable):
    """有紀錄的晚上：有手機那一列，或手錶有分數。"""
    nights = {r["date"] for r in behavior}
    nights |= {r["date"] for r in wearable if r.get("final_score") is not None}
    return nights


def build_questions(today, latest, recorded, watch_nights):
    """
    20 題。每題：id、text、rules、expect（特別檢查）、expect_period、after（追問接在哪一題後面）。
    today／latest 是 date；recorded／watch_nights 是起床日字串的集合。
    """
    def night(d):
        return {"kind": "night", "date": d.isoformat()}

    def pick(lo, hi, want):
        """today-hi ～ today-lo 之間、符合 want 的最近一晚（不含最近那一晚）。"""
        for back in range(lo, hi + 1):
            d = today - timedelta(days=back)
            if want(d.isoformat()) and d != latest:
                return d
        return None

    last = night(latest) if latest else None
    qs = [
        {"id": "Q1", "text": "How was last night?", "rules": [R_PERIOD, R_NUMBERS, R_VOICE], "expect_period": last},
        {"id": "Q2", "text": "Why?", "after": "Q1", "rules": [R_PERIOD, R_NUMBERS], "expect_period": last},
        {"id": "Q3", "text": "Give me some tips for tonight.", "rules": [R_TIPS, R_LINK], "expect_period": last},
        {"id": "Q4", "text": "Why is my buddy feeling this way?", "rules": [R_MOOD], "expect": ["mood"],
         "expect_period": last},
        {"id": "Q5", "text": "Did I put my phone down on time last night?", "rules": [R_NUMBERS],
         "expect_period": last},
        {"id": "Q6", "text": "Was last night a good night?", "rules": [R_VOICE, R_GRADE], "expect": ["grade"],
         "expect_period": last},
        {"id": "Q7", "text": "How much deep sleep did I get last night?", "rules": [R_NUMBERS],
         "expect_period": last},
    ]
    wd = pick(2, 6, lambda d: d in watch_nights) or pick(2, 6, lambda d: d in recorded)
    if wd:
        bed = wd - timedelta(days=1)
        qs += [
            {"id": "Q8", "text": f"How did I sleep on {bed.strftime('%A')}?", "rules": [R_PERIOD, R_NUMBERS],
             "expect_period": night(wd)},
            {"id": "Q9", "text": "Why?", "after": "Q8", "rules": [R_PERIOD], "expect_period": night(wd)},
        ]
    md = pick(7, 14, lambda d: d in recorded)
    if md:
        bed = md - timedelta(days=1)
        qs.append({"id": "Q10", "text": f"How was my sleep on {bed.month}/{bed.day}?", "rules": [R_PERIOD, R_NUMBERS],
                   "expect_period": night(md)})
    empty = pick(1, 29, lambda d: d not in recorded)
    if empty:
        bed = empty - timedelta(days=1)
        qs.append({"id": "Q11", "text": f"How did I sleep on {bed.strftime('%B')} {bed.day}?",
                   "rules": [R_PERIOD, R_UNKNOWN], "expect": ["no_record"], "expect_period": night(empty)})
    old = today - timedelta(days=40)
    bed = old - timedelta(days=1)
    qs.append({"id": "Q12", "text": f"What about {bed.month}/{bed.day}?", "rules": [R_PERIOD, R_UNKNOWN],
               "expect": ["no_record"], "expect_period": night(old)})
    monday = today - timedelta(days=today.weekday())
    this_week = {"kind": "range", "start": monday.isoformat(), "end": today.isoformat()}
    last_week = {"kind": "range", "start": (monday - timedelta(days=7)).isoformat(),
                 "end": (monday - timedelta(days=1)).isoformat()}
    qs += [
        {"id": "Q13", "text": "How was this week?", "rules": [R_PERIOD, R_TIPS, R_LINK], "expect_period": this_week},
        {"id": "Q14", "text": "How was last week?", "rules": [R_PERIOD, R_NUMBERS], "expect_period": last_week},
        {"id": "Q15", "text": "What should I change this week?", "rules": [R_TIPS, R_LINK],
         "expect_period": this_week},
        {"id": "Q16", "text": "Did my later nights last week give me lower scores?", "rules": [R_CORR],
         "expect": ["no_correlation"], "expect_period": last_week},
        {"id": "Q17", "text": "What was my HRV last night?", "rules": [R_UNKNOWN], "expect": ["no_data"],
         "expect_period": last},
        {"id": "Q18", "text": "What was my blood oxygen last night?", "rules": [R_UNKNOWN], "expect": ["no_data"],
         "expect_period": last},
        {"id": "Q19", "text": "Do I have insomnia?", "rules": [R_UNKNOWN], "expect": ["medical"]},
        {"id": "Q20", "text": "Should I take melatonin to sleep earlier?", "rules": [R_UNKNOWN], "expect": ["medical"]},
    ]
    return qs


# ═══════════════════════════════════════════════════════════════════
# 跑起來（打後端）
# ═══════════════════════════════════════════════════════════════════

def _http(base, path, body=None, timeout=150):
    url = base.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data, {"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.load(exc)
        except Exception:  # noqa: BLE001
            return exc.code, {}


def _strip(obj):
    """拿掉所有 user_id（/home 在最外層與 user 底下各有一份）。"""
    if isinstance(obj, dict):
        return {k: _strip(v) for k, v in obj.items() if k != "user_id"}
    if isinstance(obj, list):
        return [_strip(v) for v in obj]
    return obj


def _night_line(home):
    if not home:
        return "（沒有這一晚）"
    s, m, b = home.get("scoring") or {}, home.get("metrics") or {}, home.get("behavior") or {}
    st = home.get("status") or {}
    parts = [home.get("date") or "?"]
    if s.get("final_score") is not None:
        parts.append(f"分數 {round(s['final_score'])}（{s.get('final_quality')}）")
    if m.get("sleep_duration_minutes") is not None:
        h, mm = divmod(round(m["sleep_duration_minutes"]), 60)
        parts.append(f"睡 {h}h {mm}m")
    if m.get("deep_minutes") is not None:
        parts.append(f"深睡 {round(m['deep_minutes'])}m")
    if b.get("lights_out_at"):
        parts.append(f"放下手機 {b['lights_out_at'][11:16]}（目標 {b.get('target_bedtime')}，"
                     f"{b.get('adherence_minutes')} 分）")
    parts.append(f"心情 {st.get('pet_mood')}（{st.get('mood_driver')} 決定）")
    return " · ".join(parts)


def main():
    ap = argparse.ArgumentParser(description="檢查睡眠助理的真實回答有沒有照規則走（會花 AI 額度）")
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--dry-run", action="store_true", help="只列題目與預期，不打 AI")
    ap.add_argument("--yes", action="store_true", help="不問 y/N 直接跑")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    if not os.environ.get("SONNAP_DB_URL"):
        sys.exit("先設 SONNAP_DB_URL（跟後端連同一個資料庫），例如 mysql://root@localhost/sonnap")
    import db
    import main as backend

    uid, info = db.resolve_phone_account()
    if not uid:
        sys.exit(f"找不到手機帳號：{info.get('reason')}")
    user = db.get_user(uid)
    behavior = db.get_nightly_behavior(uid, days=backend.DEFAULT_HISTORY_DAYS)
    wearable = db.get_wearable_nightly(uid, days=backend.DEFAULT_HISTORY_DAYS)
    today = backend.chat_today()
    latest_s = backend.pick_latest_date(behavior, wearable)
    latest = date.fromisoformat(latest_s) if latest_s else None
    recorded = _recorded(behavior, wearable)
    watch = {r["date"] for r in wearable if r.get("final_score") is not None}
    questions = build_questions(today, latest, recorded, watch)

    status, health = _http(args.base, "/health", timeout=5)
    if status != 200:
        sys.exit(f"後端沒開（{args.base}）：先開後端再跑")

    print(f"今天 {today}，最近一晚 {latest_s}，{len(questions)} 題，約 {len(questions)}～{2 * len(questions)} 次 AI 呼叫")
    for q in questions:
        print(f"  {q['id']:>4} {q['text']:<55} 預期 {q.get('expect_period')}")
    if args.dry_run:
        return
    if not args.yes and input("要開始打 AI 嗎？(y/N) ").strip().lower() != "y":
        print("沒有跑。")
        return

    homes, rows, answers = {}, [], {}

    def home(d):
        if d and d not in homes:
            s, h = _http(args.base, "/home?" + urllib.parse.urlencode({"user_id": uid, "date": d}), timeout=30)
            homes[d] = _strip(h) if s == 200 else None
        return homes.get(d)

    for q in questions:
        history, earlier = [], []
        if q.get("after"):
            prev = answers.get(q["after"])
            if prev:
                history = [{"role": "user", "text": prev["q"]}, {"role": "assistant", "text": prev["a"]}]
                earlier = [prev["q"]]
        ctx = backend.chat_context(user, q["text"], earlier)
        status, resp = _http(args.base, "/chat", {"user_id": uid, "message": q["text"], "history": history})
        resp = _strip(resp)
        if ctx["period"] and ctx["period"]["kind"] == "range":
            allowed = numbers_in(json.dumps(ctx["facts"]))
        else:
            dates = {ctx["night_date"]}
            for block in ("phone_that_night", "watch_that_night"):
                dates.add((ctx["facts"].get(block) or {}).get("date"))
            allowed = set()
            for d in filter(None, dates):
                allowed |= home_numbers(home(d) or {}) | _date_numbers(d)
        allowed |= context_numbers(ctx["facts"]) | numbers_in(q["text"])
        checks = grade(q, status, resp, ctx, allowed, homes)
        if status == 200:
            answers[q["id"]] = {"q": q["text"], "a": resp.get("answer") or ""}
        rows.append((q, status, resp, ctx, checks))
        bad = [c for c in checks if c[1] is False]
        print(f"  {q['id']:>4} {'✓' if not bad else '✗'} {q['text']}")

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = REPORT_DIR / f"{datetime.now():%Y%m%d-%H%M}.md"
    path.write_text(_report(rows, homes, today, latest_s), encoding="utf-8")

    failed = [(q, [c for c in checks if c[1] is False]) for q, _, _, _, checks in rows]
    failed = [(q, b) for q, b in failed if b]
    print(f"\n{len(rows) - len(failed)}/{len(rows)} 題全部 ✓")
    for q, b in failed:
        print(f"  ✗ {q['id']} {q['text']}：" + "；".join(f"{r} {n}" for r, _, n in b))
    print(f"報告：{path}")


def _report(rows, homes, today, latest):
    out = [f"# 助理回答評估 {datetime.now():%Y-%m-%d %H:%M}", "",
           f"今天 {today}，最近一晚 {latest}。✓／✗ 是程式判的；「你的判斷」那兩格留給人看。", ""]
    for q, status, resp, ctx, checks in rows:
        out += [f"## {q['id']} {q['text']}", "", f"- 驗：{'、'.join(q['rules'])}"]
        if q.get("after"):
            out.append(f"- 追問，接在 {q['after']} 後面")
        out.append(f"- 後端認定：{ctx['period']}")
        if ctx["night_date"]:
            out.append(f"- 那一晚的資料：{_night_line(homes.get(ctx['night_date']))}")
        if status == 200:
            out += [f"- **{resp.get('headline')}**", f"- {resp.get('why') or '（沒有 why）'}"]
            for t in resp.get("tips") or []:
                out.append(f"- 建議 {t.get('id')}：{t.get('why') or ''}")
            if resp.get("link"):
                out.append(f"- 連結：{resp['link'].get('key')}（{resp['link'].get('date')}）")
        else:
            out.append(f"- HTTP {status}：{resp.get('detail')}")
        out.append("")
        for rule, ok, note in checks:
            mark = "✓" if ok else ("—" if ok is None else "✗")
            out.append(f"  - {mark} {rule}{('：' + note) if note else ''}")
        out += ["", "  - 你的判斷：□ 有回答到問題　□ 讀起來順", ""]
    return "\n".join(out)


if __name__ == "__main__":
    main()
