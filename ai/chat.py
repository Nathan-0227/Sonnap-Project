"""
ai/chat.py —— 睡眠助理的問答（B6）。

把**這個人自己的**資料整理成事實區塊，連同問題送給 Claude，回答要通過
四道驗證才交給 App。

═══════════════════════════════════════════════════════════════════
四道驗證（定義在 ai/text_guards.py，寵物 notes 也共用，不在這裡另寫一份）
═══════════════════════════════════════════════════════════════════

    1. 醫療用語禁詞       text_guards.BANNED_WORDS，**完整單詞比對**
                          （treat 不能命中 retreat）
    2. 數字必須在事實裡   回答裡的每一個數字都要出現在事實區塊
    3. 中文洩漏           text_guards.CJK_LEAK_PATTERN（輸出固定英文）
    4. 拼字數值           text_guards.SPELLED_NUMERAL_PATTERN——
                          **必須有 point 才擋**，"give it one more try" 要放行

⚠️ 從 text_guards import 而不是抄一份：兩份禁詞清單漂移時，notes 擋得住的詞
   聊天擋不住，而且不會有任何錯誤訊息。
⚠️ 驗證寫寬很省事，但誤判的代價是使用者拿不到答案（方法論第 5 點）。
   tests/test_chat.py 同時驗「擋得住」與「不誤傷」。

═══════════════════════════════════════════════════════════════════
分段回答（2026-11-22，參考 Oura／WHOOP，使用者 grill 定）
═══════════════════════════════════════════════════════════════════

    headline  一句直接回答（≤ 25 字）
    why       0–1 句為什麼（≤ 30 字，只准 might／can；不准偷塞建議）
    tips      0–2 條，**只能從後端算好的那一晚適用清單挑**（同寵物 notes 的 triggered()）；
              每條附後端固定表的 Why 那一行（WHY），不交給 AI 寫
    link      0–1 個詳細頁，只能從那一晚有資料的 LINKS 挑

合起來的 answer（headline＋why）留給舊版 App。

═══════════════════════════════════════════════════════════════════
⚠️ 會花錢
═══════════════════════════════════════════════════════════════════

每問一次就是一次 Claude API 呼叫。測試一律換掉 `complete`，並把真的網路
呼叫攔成直接失敗——一個 bug 都不能讓測試打到真的 API。
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import llm_client  # noqa: E402
from env_utils import load_env_file  # noqa: E402
from text_guards import (  # noqa: E402
    BANNED_WORDS,
    CJK_LEAK_PATTERN,
    NUMBER_PATTERN,
    SPELLED_NUMERAL_PATTERN,
)
from behavior import morning_tips as mt  # noqa: E402

# 讀 ai/.env 的金鑰。⚠️ 原本由 generate_advice.py 在 import 時讀（chat 間接沾光），
# 2026-11-18 夢境程式刪掉後搬到這裡——少了這一行，助理與寵物 notes 會悄悄變成
# 「永遠沒有金鑰」而且不會報錯。不覆寫已存在的環境變數（測試先設成空字串就擋得住）。
load_env_file()

# ── 測試替換點（測試換成假的，永遠不打真的 API）──────────────────
complete = llm_client.complete_json
key_available = llm_client.api_key_available

# 第一次沒過驗證就帶著「哪裡不行」重問一次。再不行就老實說答不出來。
MAX_ATTEMPTS = 2

_BANNED = [(w, re.compile(r"\b" + re.escape(w) + r"\b", re.IGNORECASE)) for w in BANNED_WORDS]

ANSWER_SCHEMA = {
    "type": "object",
    "properties": {
        "headline": {"type": "string"},
        "why": {"type": "string"},
        "tip_ids": {"type": "array", "items": {"type": "string"}},
        "link": {"type": "string"},
    },
    "required": ["headline", "why", "tip_ids", "link"],
    "additionalProperties": False,
}

MAX_TIPS = 2
MAX_HEADLINE_WORDS = 25
MAX_WHY_WORDS = 30

# 回答底下可以連到哪一頁（App 對到首頁同一份詳細頁 NightSheets）。後端只給**那一晚有資料**的。
# ⚠️ 只列 NightSheets 開得了的四頁：放下手機、睡著心率那兩頁在早晨報告裡、首頁開不了，
#    列進來的話 AI 挑了 App 卻沒地方開。
LINKS = {
    "total_sleep": "how long the watch says the user slept",
    "efficiency": "sleep efficiency",
    "awake": "time awake during the night",
    "deep": "deep sleep",
}

# Why 那一行：每條建議一句，**後端照抄、不交給 AI**（2026-11-22 使用者逐句審過）。
# 只有對得到睡眠計畫的那幾條（App 的 kTipToPlan）才有；鍵要跟那張表一樣（test_chat【6f】守著）。
# ⚠️ 不寫 because：只陳述觸發它的事實。
WHY = {
    "T3": "You noted late caffeine last night.",
    "T4": "You noted alcohol last night.",
    "T5": "You noted a nap yesterday.",
    "T6": "You noted the room was too hot or cold.",
    "T12": "You noted noise last night.",
    "T7": "You noted exercise yesterday.",
    "T8": "You noted feeling stressed last night.",
    "P2": "You noted exercise, and your watch showed a harder night than usual.",
    "P3": "Your watch showed less REM than Sonnap's range, and your phone went down after your target.",
    "P6": "You noted a nap, and your watch showed less deep sleep than Sonnap's range.",
    "P7": "You noted alcohol, and your sleeping heart rate was higher than your usual.",
}

# why 那句可以講這兩件（準時放下手機、固定就寢：量測那幾列，沒有按鈕），不算偷塞建議（grill Q4）。
_WHY_ALLOWED_ACTIONS = {"T1", "T2"}

SYSTEM_PROMPT = """You are Sonnap's sleep assistant inside a sleep app for university students.

Answer the user's question using ONLY the facts in the FACTS block. The facts describe this one user.

Answer in four parts:
- "headline": exactly ONE short sentence (at most 25 words) that answers the question directly.
- "why": at most ONE short sentence (at most 30 words) of context or a possible reason, or "" when there
  is nothing to add. A possible reason uses "might" or "can", never "because" or "due to". Do not give
  advice in the headline or why, except putting the phone down on time or keeping a steady bedtime.
- "tip_ids": 0 to 2 ids from the TIP LIST that fit the question. Never use an id that is not in the TIP LIST.
  The app shows each tip itself, so do not repeat its advice in the headline or why. If the TIP LIST is
  empty or nothing fits, give [] and, when the user asked for tips, say plainly that nothing from that
  night stands out.
- "link": one key from the LINKS block that matches what the headline is about, or "".

Which night:
- The NIGHT block says which night the question is about (dated by the morning the user woke up). Talk
  about that night. Only call it "last night" when "most_recent_night" is true; otherwise use its date.
  If "recorded" is false, say plainly that Sonnap has no record for that night.
- When a PERIOD block is present instead, the question is about those days. Use the "summary" numbers as
  given (medians and counts) and say how many nights had records; never work out an average or any other
  number yourself. If no night has a record, say so plainly.
- If the user asks to compare two nights or two periods, say you can look at one night or one week at a time.

Rules:
- Plain, friendly English. No lists, no headings.
- Only use digits that appear in the FACTS block. Never invent, estimate or convert numbers.
- If the question needs data that is not in the facts, say plainly that Sonnap does not have that data.
- PET MOOD (when present) was decided by the app. To explain it, use only its "decided_by" text for that
  night and "how_pet_mood_works" for the general rule; do not invent other reasons, do not say whether a
  sleep measure is high or low, and do not claim the mood never or always depends on something.
- When talking about a past night's bedtime, use that night's "target_bedtime_that_night". The user's
  "current_target_bedtime" may have changed since then.
- Focus on behaviour the user can change, such as when they put the phone down and keeping a steady bedtime.
- Do not give medical advice. Do not name health conditions, medicines or treatments. If the user sounds
  worried about their health, suggest talking to a doctor or the campus health service.
- Always answer in English, even if the question is in another language.
- CONVERSATION SO FAR (when present) is only there so you understand follow-up questions such as "why?".
  It is not a source of facts: every number you write must still come from the FACTS block."""


class ChatUnavailable(Exception):
    """答不出來（沒設定、連不上、或兩次都沒過驗證）。訊息是給使用者看的英文。"""


# 寵物心情是誰決定的（main.resolve_mood 的 driver）→ 給 AI 讀的一句話。
# ⚠️ 不給 mood_reason：那是規則標籤（final_quality=Good），而且 anxious 那條會帶出壓力，
#    壓力不交給 AI（同寵物 notes）。這裡只說「由哪一類訊號決定」。
PET_MOOD_DECIDED_BY = {
    "behavior": "this night: when the phone was put down compared with that night's target bedtime",
    "wearable": "this night: the watch's sleep quality grade (no phone-down record for that night)",
    "wearable_override": "this night: the watch showed the body was less settled than usual",
}

# 一般規則（照 main.resolve_mood 寫的一句話）。2026-11-22 加：只給「這一晚由什麼決定」的話，
# AI 會自己推成「寵物心情完全跟睡眠無關」（手機實測），所以把真正的規則也給它。
PET_MOOD_RULE = ("Usually decided by when the phone was put down compared with the target bedtime. "
                 "On nights with no phone-down record, the watch's sleep quality grade decides it. "
                 "If the watch shows the body was less settled than usual, the mood can become anxious.")


def hm(minutes):
    """分鐘數 → "6h 12m"（給 AI 照抄的字串；讓它自己換算的話，換錯了看起來也很合理）。"""
    m = round(minutes)
    return f"{m // 60}h {m % 60}m" if m >= 60 else f"{m}m"


def build_facts(user, latest_behavior, latest_wearable, streak, late, pet=None, noted=(), night=None):
    """
    事實區塊。**只放這個人自己的資料**。

    late 是 adherence.late_night_ratio() 的回傳值 (ratio, late_nights, recorded)。
    pet 是 (date, mood, driver)：首頁那隻寵物的心情（2026-11-21 加，讓「寵物心情跟睡眠
    有什麼關係」答得出來）。心情由後端判好，這裡只轉述，不給 AI 任何判斷的材料。
    noted 是起床自評勾的標籤（morning_tips.TAGS 的 id，2026-11-22 加：建議的 Why 要講得出來）。
    night 是 {"date", "most_recent_night", "recorded"}：問的是哪一晚（2026-11-22 加，見 chat_period.py）。
    問某一晚時，latest_behavior／latest_wearable 傳的就是**那一晚**的列。

    ⚠️ 時刻直接切 ISO 字串的 HH:MM，不轉時區——那是記錄當下的牆鐘時間
       （與 App 端 parseWallClock() 同一個道理）。
    ⚠️ 分數只放整數，與 App 上顯示的一致；小數點後的數字放進去，模型就會
       講出 App 上看不到的「82.4 分」。
    """
    # ⚠️ 2026-11-22：原本只有一個 target_bedtime（＝現在的目標），AI 拿它去對那一晚的放下手機時刻；
    #    目標改過的話數字就配錯（手機實測：那晚判準時用 01:25，AI 說 04:00）。現在兩個分開給。
    facts = {"current_target_bedtime": user.get("target_bedtime")}
    if night:
        facts["night"] = dict(night)

    if latest_behavior:
        lights_out = latest_behavior.get("lights_out_at") or ""
        minutes = latest_behavior.get("adherence_minutes")
        facts["phone_that_night"] = {
            "date": latest_behavior.get("date"),
            "phone_down_at": lights_out[11:16] or None,
            "target_bedtime_that_night": latest_behavior.get("target_bedtime"),
            "minutes_after_target": round(minutes) if minutes is not None else None,
            "counted_as_late": (
                bool(latest_behavior["is_late"]) if latest_behavior.get("is_late") is not None else None
            ),
        }

    _, late_nights, recorded = late
    facts["on_time_streak_nights"] = streak
    facts["late_nights_recent"] = {"late": late_nights, "recorded": recorded}

    if latest_wearable and latest_wearable.get("final_score") is not None:
        duration = latest_wearable.get("duration_min")
        facts["watch_that_night"] = {
            "date": latest_wearable.get("date"),
            "sleep_score": round(latest_wearable["final_score"]),
            "quality": latest_wearable.get("final_quality"),
            "sleep_minutes": round(duration) if duration is not None else None,
            "sleep_time": hm(duration) if duration is not None else None,
        }
    if pet and pet[1] and pet[2] in PET_MOOD_DECIDED_BY:
        facts["pet_mood"] = {"date": pet[0], "mood": pet[1],
                             "decided_by": PET_MOOD_DECIDED_BY[pet[2]],
                             "how_pet_mood_works": PET_MOOD_RULE}
    labels = [mt.TAGS[t] for t in noted if t in mt.TAGS]
    if labels:
        facts["you_noted_that_night"] = labels
    return facts


def _median(values):
    vals = sorted(v for v in values if v is not None)
    if not vals:
        return None
    mid = len(vals) // 2
    return vals[mid] if len(vals) % 2 else (vals[mid - 1] + vals[mid]) / 2


def _clock_minutes(iso):
    """放下手機的牆鐘時刻 → 從中午 12:00 起算的分鐘（跨午夜連續）。12:00–18:00 不算就寢，回 None。"""
    if not iso or len(iso) < 16:
        return None
    h, m = int(iso[11:13]), int(iso[14:16])
    if 12 <= h < 18:
        return None
    return (h - 12) % 24 * 60 + m


def _clock_text(minutes_from_noon):
    m = round(minutes_from_noon) % (24 * 60)
    return f"{(m // 60 + 12) % 24:02d}:{m % 60:02d}"


def build_range_facts(user, start, end, nights, behavior_by_date, wearable_by_date):
    """
    一段時間的事實區塊（2026-11-22）：每晚一列＋後端先算好的整段數字。

    ⚠️ 整段的數字一律**中位數**（同 Insights：平均會被一兩晚拉走）；熬夜晚數照抄每晚的 is_late
       （跨午夜只在 behavior/adherence.py 算）。只有 1 晚有值時不給中位數——那一晚的數字就在 nights 裡。
    ⚠️ AI 不准自己算：數字檢查只放行事實裡有的數字，自己算的平均會被擋下來。
    """
    rows = []
    for d in nights:
        b, w = behavior_by_date.get(d), wearable_by_date.get(d)
        if w and w.get("final_score") is None:
            w = None
        if not b and not w:
            continue
        row = {"date": d}
        if b:
            lights_out = b.get("lights_out_at") or ""
            minutes = b.get("adherence_minutes")
            row["phone_down_at"] = lights_out[11:16] or None
            row["minutes_after_target"] = round(minutes) if minutes is not None else None
            row["counted_as_late"] = bool(b["is_late"]) if b.get("is_late") is not None else None
        if w:
            duration = w.get("duration_min")
            row["sleep_time"] = hm(duration) if duration is not None else None
            row["sleep_score"] = round(w["final_score"])
            row["quality"] = w.get("final_quality")
        rows.append(row)

    beh = [behavior_by_date[d] for d in nights if behavior_by_date.get(d)]
    wear = [wearable_by_date[d] for d in nights
            if wearable_by_date.get(d) and wearable_by_date[d].get("final_score") is not None]
    summary = {"nights_with_phone_down": len(beh), "nights_with_watch": len(wear)}
    judged = [b for b in beh if b.get("is_late") is not None]
    if judged:
        summary["late_nights"] = {"late": sum(1 for b in judged if b["is_late"]), "of": len(judged)}

    def median_of(values, fmt):
        vals = [v for v in values if v is not None]
        return fmt(_median(vals)) if len(vals) >= 2 else None

    for key, values, fmt in (
        ("median_sleep_time", [w.get("duration_min") for w in wear], hm),
        ("median_sleep_score", [w.get("final_score") for w in wear], round),
        ("median_phone_down_at", [_clock_minutes(b.get("lights_out_at")) for b in beh], _clock_text),
        ("median_minutes_after_target", [b.get("adherence_minutes") for b in beh], round),
    ):
        value = median_of(values, fmt)
        if value is not None:
            summary[key] = value

    return {
        "current_target_bedtime": user.get("target_bedtime"),
        "period": {"from": start, "to": end, "nights_in_period": len(nights),
                   "nights_with_any_record": len(rows)},
        "nights": rows,
        "summary": summary,
    }


def tip_list(tip_ids):
    """交給 AI 的清單：只有後端依適用條件挑到的那幾條（同寵物 notes，不讓 AI 自己判斷適不適用）。"""
    return [{"id": tid, "sentence": mt.TIPS[tid][1], "when": mt.WHEN[tid]} for tid in tip_ids]


def _numbers(text):
    return {float(n) for n in NUMBER_PATTERN.findall(text)}


def validate_answer(answer, facts_text):
    """回傳這個回答的問題清單；空清單代表通過。"""
    problems = []
    if not answer.strip():
        problems.append("empty answer")
    if CJK_LEAK_PATTERN.search(answer):
        problems.append("not in English")
    for word, pattern in _BANNED:
        if pattern.search(answer):
            problems.append(f"medical wording '{word}'")
    if SPELLED_NUMERAL_PATTERN.search(answer):
        problems.append("a number spelled out in words")
    # ⚠️ 比數值不比字串："5" 與事實裡時刻的 "05" 是同一個數。
    extra = _numbers(answer) - _numbers(facts_text)
    for n in sorted(extra):
        problems.append(f"the number {n:g} is not in the facts")
    return problems


def _words(text):
    return re.findall(r"[A-Za-z0-9']+", text)


def validate_parts(parts, facts_text, allowed_tips, allowed_links):
    """
    分段回答的問題清單；空清單代表通過。parts = {"headline", "why", "tip_ids", "link"}。

    allowed_tips／allowed_links 刻意沒有預設值——漏傳時直接報錯，不會悄悄退回「全部都可以」。
    """
    import night_summary as ns  # 延後 import：night_summary 也 import 這一支

    headline = (parts.get("headline") or "").strip()
    why = (parts.get("why") or "").strip()
    tip_ids = parts.get("tip_ids") or []
    link = (parts.get("link") or "").strip()
    allowed_tips, allowed_links = set(allowed_tips), set(allowed_links)
    problems = []

    if not headline:
        problems.append("empty headline")
    if len(ns._sentences(headline)) > 1:
        problems.append("the headline has more than one sentence")
    if len(_words(headline)) > MAX_HEADLINE_WORDS:
        problems.append(f"the headline is longer than {MAX_HEADLINE_WORDS} words")
    if len(ns._sentences(why)) > 1:
        problems.append("why has more than one sentence")
    if len(_words(why)) > MAX_WHY_WORDS:
        problems.append(f"why is longer than {MAX_WHY_WORDS} words")

    if len(tip_ids) > MAX_TIPS:
        problems.append(f"more than {MAX_TIPS} tips")
    if len(set(tip_ids)) != len(tip_ids):
        problems.append("the same tip twice")
    for tid in tip_ids:
        if tid not in allowed_tips:
            problems.append(f"tip {tid!r} is not in the TIP LIST (no tips outside the list)")
    if link and link not in allowed_links:
        problems.append(f"link {link!r} is not in the LINKS block")

    # 建議只能從 tip_ids 出來：headline／why 講到某條建議的重點字、那條卻沒選 → 偷塞
    # （跟 notes 同一份 KEYWORDS）。只管「教你怎麼做」的那幾條；準時放手機、固定就寢可以講。
    text = f"{headline} {why}"
    for tid, (kind, _) in mt.TIPS.items():
        if kind != "tip" or tid in tip_ids or tid in _WHY_ALLOWED_ACTIONS:
            continue
        # ⚠️ 開頭要 \b：notes 那份沒有，"nap" 會命中 "Sonnap"、"hot" 命中 "photo"
        if re.search(r"\b(?:" + mt.KEYWORDS[tid] + ")", text, re.IGNORECASE):
            problems.append(f"the headline or why talks about tip {tid} without choosing it "
                            "(put it in tip_ids, or leave it out)")

    if headline:
        problems.extend(validate_answer(text, facts_text))
    if ns.CAUSAL_PATTERN.search(text):
        problems.append("states a cause as certain (use 'might' / 'can', never 'because' / 'due to')")
    for sentence in ns._sentences(text):
        for reason, pats, unless in ns._FORBIDDEN:
            if all(p.search(sentence) for p in pats) and not (unless and unless.search(sentence)):
                problems.append(reason)
    return problems


# 後端最多看幾則前文（5 輪＝10 則）；App 也只送這麼多，這裡再夾一次。
MAX_HISTORY_MESSAGES = 10


def _conversation_block(history):
    """前文寫成一段文字（2026-11-19，讓「為什麼？」接得上）。
    數字照舊只認 FACTS——驗證不看這一段，所以前文裡的數字不會被當成事實。"""
    turns = [(role, (text or "").strip()) for role, text in history][-MAX_HISTORY_MESSAGES:]
    lines = [f"{'User' if role == 'user' else 'You'}: {text}" for role, text in turns if text]
    if not lines:
        return ""
    return "CONVERSATION SO FAR (oldest first):\n" + "\n".join(lines) + "\n\n"


def answer_question(question, facts, history=(), tips=(), links=()):
    """
    問一次。tips：那一晚適用的建議 id（後端算好）；links：那一晚有資料的 LINKS 鍵。

    回傳 {"headline", "why", "tips": [{"id", "why"}], "link", "answer", "attempts", "model"}，
    答不出來丟 ChatUnavailable。tips 裡的 why 是 WHY 那張表的字（沒有的是 None），不是 AI 寫的。

    ⚠️ 失敗訊息不帶 API 的錯誤細節——那可能包含「金鑰無效」之類的伺服器資訊，
       不該傳到手機上。細節留在後端的 log。
    """
    tips = [t for t in tips if t in mt.TIPS]
    links = [k for k in links if k in LINKS]
    facts_text = json.dumps(facts, ensure_ascii=False, indent=2)
    tips_text = json.dumps(tip_list(tips), ensure_ascii=False, indent=2)
    links_text = json.dumps({k: LINKS[k] for k in links}, ensure_ascii=False, indent=2)
    convo = _conversation_block(history)
    feedback = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        user_prompt = (f"FACTS:\n{facts_text}\n\nTIP LIST:\n{tips_text}\n\nLINKS:\n{links_text}\n\n"
                       f"{convo}QUESTION:\n{question}\n{feedback}")
        try:
            data, model = complete(SYSTEM_PROMPT, user_prompt, ANSWER_SCHEMA, max_tokens=2000)
        except llm_client.LLMRefusal:
            raise ChatUnavailable("The assistant could not answer that question.")
        except llm_client.LLMError as exc:
            print(f"chat: LLM call failed - {exc}", file=sys.stderr)
            raise ChatUnavailable("The assistant could not be reached right now.")

        problems = validate_parts(data, facts_text, tips, links)
        if not problems:
            headline = data["headline"].strip()
            why = (data.get("why") or "").strip()
            return {
                "headline": headline,
                "why": why or None,
                "tips": [{"id": tid, "why": WHY.get(tid)} for tid in data.get("tip_ids") or []],
                "link": (data.get("link") or "").strip() or None,
                "answer": f"{headline} {why}".strip(),
                "attempts": attempt,
                "model": model,
            }
        feedback = (
            "\nYOUR PREVIOUS ANSWER WAS REJECTED because: " + "; ".join(problems)
            + ". Write it again following every rule."
        )
    raise ChatUnavailable("The assistant could not give an answer that passed the safety checks.")
