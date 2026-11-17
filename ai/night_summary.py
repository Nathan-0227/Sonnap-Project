"""
寵物 notes（2026-11-17 起，取代夢境日記與報告上的「From your buddy」）。

設計（使用者 2026-11-17 grill 後定，取代 11-12 的「AI 不寫建議、不准說因果」）：
- AI 寫**總結（≤2 句）＋從清單挑 0–3 條建議**，寵物第一人稱。全部 ≤120 個英文字。
- 整晚資料都交給 AI，但每一項附**後端算好的判讀**（評分器的級距、心率比平常高或低）。
  AI 只能照判讀說，不能自己從原始數字決定「45 分鐘的深睡算少」。
- **行動只能來自清單**（behavior/morning_tips.TIPS）：AI 回傳它挑的 id，驗證檢查 id 在清單裡、
  換了口吻的句子還留著那條的重點字（KEYWORDS）、總結裡沒有偷塞行動。
- 可以說**可能的原因**，但一律 might／can——「because／due to」這類斷定仍然擋。
  原因的來源限三個：使用者勾的標籤、量到的行為、研究文件替那個狀況列的原因。
- **不交給 AI**：攝影機（11-09 驗證過跟任何結果都沒有相關）、Garmin 壓力分數。
  昨天的步數要給，但**不准當成任何一晚的原因**（Atoui 2021，逐日研究不支持）。
- 「AI 不准說」那張表（研究文件）裡能用字串抓的，在 FORBIDDEN_CLAIMS 擋。
- 驗證沿用睡眠助理那一套（ai/chat.validate_answer：數字要在事實裡、禁用字、中文、拼字數值）。
  兩次都沒過 → SummaryUnavailable，呼叫端改顯示 applicable_tips() 的原句、不顯示總結。

⚠️ 時長一律給「2h 49m」這種寫好的字串，要求照抄。讓模型自己把 169 分鐘換算成小時，
   換錯了也看起來很合理——而數字檢查會因為換出來的數字不在事實裡而整句擋掉。
⚠️ 判讀常數直接讀評分器（garmin/evaluate_sleep_quality.py）與心情判斷（build_app_payload），
   不在這裡另訂門檻——另訂就是一個沒有出處的新門檻。
"""
import hashlib
import json
import re
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
for _p in (_HERE, _ROOT, _ROOT / "garmin"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import chat  # noqa: E402  共用驗證與 Claude 呼叫
import llm_client  # noqa: E402
import evaluate_sleep_quality as esq  # noqa: E402  評分器的門檻（唯一定義處）
from behavior import morning_tips as mt  # noqa: E402

# ── 測試替換點（測試換成假的，永遠不打真的 API）──────────────────
complete = llm_client.complete_json
key_available = llm_client.api_key_available

# 改 prompt、事實的形狀、或建議清單時要升版：舊的那一份會因為 facts_hash 不同而重生。
PROMPT_VERSION = "notes-v1"

MAX_ATTEMPTS = 2
MAX_WORDS = 120
MAX_SUMMARY_SENTENCES = 2
MAX_TIP_SENTENCES = 2

# 斷定的因果說法：可以說 might／can，不能說「因為」。
CAUSAL_PATTERN = re.compile(
    r"\b(because|due to|caused|causes|cause|since you|as a result|that's why|so you slept)\b",
    re.IGNORECASE,
)

# 總結裡不准出現行動——行動只能在挑出來的建議裡（那才查得到出處）。
SUMMARY_ACTION_PATTERN = re.compile(
    r"\b(try|should|avoid|make sure|consider|remember to|let's|lets)\b", re.IGNORECASE)

# 「AI 不准說」（研究文件「生理狀況」一節）裡能用字串抓的。逐句比對。
# (說明, 同一句裡必須同時出現的 pattern 們[, 出現就放行的 pattern])
FORBIDDEN_CLAIMS = [
    ("alcohol does not reduce deep sleep (it increases it in the first half of the night)",
     [r"\b(alcohol|drink|drinks|drinking)\b", r"\bdeep\b", r"\b(less|lower|reduc\w*|fewer|cut|shorter)\b"]),
    ("yesterday's steps must not be given as a reason for a night's sleep",
     [r"\b(steps?|walk\w*)\b", r"\b(sleep\w*|slept|deep|REM|awake|woke)\b",
      r"\b(might|may|could|can|linked|why|so|led|reason)\b"]),
    ("late dinner is not a supported reason",
     [r"\b(dinner|meal|ate|eating|food)\b"]),
    ("a to-do list only helps falling asleep, not sleeping longer or deeper",
     [r"\b(to-?do|list)\b", r"\b(longer|deeper|more deep|more REM|less awake)\b"]),
    # P2 的限定說法（高強度、睡前不久結束）是允許的，所以有放行條件
    ("evening exercise in general does not hurt sleep; only hard workouts close to bedtime",
     [r"\b(exercise|workouts?|work out)\b", r"\b(evening|night|late)\b",
      r"\b(hurt|harm|bad|worse|disturb\w*|ruin\w*)\b"],
     r"\b(hard|intense|vigorous|close to bed\w*|4 hours)\b"),
    ("camera data is not part of the notes", [r"\bcamera\b"]),
    ("the watch's stress score is not part of the notes", [r"\bstress (score|level)s?\b"]),
]
_FORBIDDEN = [(c[0], [re.compile(p, re.IGNORECASE) for p in c[1]],
               re.compile(c[2], re.IGNORECASE) if len(c) > 2 else None)
              for c in FORBIDDEN_CLAIMS]

NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "tips": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"id": {"type": "string"}, "text": {"type": "string"}},
                "required": ["id", "text"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["summary", "tips"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """You are the user's pet in Sonnap, a sleep app. It is the morning after, and you are \
writing a short note to your human about LAST NIGHT, using ONLY the FACTS block and the TIP LIST.

Write in warm, simple English, speaking as the pet ("I", "we", "you"). At most 120 words in total.

"summary": 1 or 2 sentences about how last night went.
- Describe only what happened. Each item in "last_night" has a "judgment" written by the app; use it \
as given and never judge a number yourself. Items without a judgment must not be called good or bad.
- No advice in the summary (no "try", "should", "avoid", "let's").

"tips": 0 to 3 items chosen from the TIP LIST, most relevant first.
- Use the tip's "id" and rewrite its sentence in your own pet voice, 1 or 2 sentences. Keep its meaning \
and its key words; do not add any other action. Tips marked "suggested_tonight" fit the facts best.
- You may mention a possible reason, but only one that comes from "you_noted", from "phone_down", or \
from the tip's own sentence. Always hedge it with "might" or "can". Never say "because", "due to" or "caused".
- On a good night, 0 or 1 tip is fine. Never pile on.

Hard rules:
- Copy durations, times and numbers EXACTLY as written in the facts or the tip list. Never convert, \
round or invent a number.
- "yesterday_activity" is context only: never present steps or walking as a reason for how someone slept.
- Never say alcohol lowers deep sleep. Never blame late dinners. Never say evening exercise in general \
hurts sleep.
- No medical advice; do not name health conditions, medicines or treatments. No lists, no emoji. \
Always English."""


class SummaryUnavailable(Exception):
    """這次寫不出來（沒設定、連不上、或兩次都沒過驗證）。"""


def hm(minutes):
    """215 → '3h 35m'；45 → '45m'；120 → '2h'。None → None。"""
    if minutes is None:
        return None
    m = int(round(abs(minutes)))
    h, r = divmod(m, 60)
    if h and r:
        return f"{h}h {r}m"
    if h:
        return f"{h}h"
    return f"{r}m"


def _change(now, before, more="more", less="less"):
    if now is None or before is None:
        return None
    diff = round(now - before)
    if abs(diff) < 1:
        return "about the same"
    return f"{hm(diff)} {more if diff > 0 else less}"


# ═══════════════════════════════════════════════════════════════════
# 判讀：只用評分器現成的門檻
# ═══════════════════════════════════════════════════════════════════

def _band(user):
    band = (user or {}).get("age_band") or "young_adult"
    return band if band in esq.DURATION_RANGE else "young_adult"


def _range_judgment(value, low, high):
    if value is None:
        return None
    if value < low:
        return mt.BELOW
    if value > high:
        return mt.ABOVE
    return mt.WITHIN


def _duration_judgment(duration_min, band):
    if duration_min is None:
        return None
    low, high = esq.DURATION_RANGE[band]
    return _range_judgment(duration_min / 60.0, low, high)


def _share(part, whole):
    if part is None or not whole:
        return None
    return part / whole * 100.0


def _hr_judgment(wearable):
    """
    睡著心率比平常高或低：Tier3 心率修正值（rhr + avg_hr）的方向。
    修正值為負＝心率比個人基線高。門檻用心情判斷的同一個 ANXIOUS_HR_CONFIRM（1 bpm，讀數解析度）。
    兩個都沒有（冷啟動、不可信區段）→ None，不判讀。
    """
    from build_app_payload import ANXIOUS_HR_CONFIRM   # 用到才 import（那支會連帶載入很多東西）
    mods = [wearable.get(k) for k in ("rhr_modifier", "avg_hr_modifier")]
    mods = [m for m in mods if m is not None]
    if not mods:
        return None
    total = sum(mods)
    if total <= ANXIOUS_HR_CONFIRM:
        return mt.HR_HIGHER
    if total >= -ANXIOUS_HR_CONFIRM:
        return "lower than your usual"
    return "about your usual"


def judge_night(wearable, previous_wearable, user):
    """
    回傳 {項目: 判讀字串}，給 morning_tips.triggered() 與事實區塊共用（同一份，不會漂移）。
    沒有手錶資料 → 空 dict。
    """
    if not wearable or wearable.get("final_score") is None:
        return {}
    band = _band(user)
    dur = wearable.get("duration_min")
    judged = {
        "time_asleep": _duration_judgment(dur, band),
        "deep_sleep": _range_judgment(_share(wearable.get("deep_min"), dur), *esq.DEEP_RANGE),
        "sleeping_heart_rate": _hr_judgment(wearable),
    }
    if wearable.get("rem_measured"):
        judged["rem_sleep"] = _range_judgment(_share(wearable.get("rem_min"), dur), *esq.REM_RANGE[band])
    waso = wearable.get("waso_min")
    if waso is not None:
        good, fair = esq.WASO_THRESHOLD[band]
        judged["awake_during_night"] = "low" if waso <= good else "moderate" if waso <= fair else "high"
    if previous_wearable:
        judged["previous_time_asleep"] = _duration_judgment(previous_wearable.get("duration_min"), band)
    return {k: v for k, v in judged.items() if v is not None}


# ═══════════════════════════════════════════════════════════════════
# 事實區塊
# ═══════════════════════════════════════════════════════════════════

def build_night_facts(date, user, wearable, previous_wearable, behavior,
                      rating=None, rating_label=None, tag_labels=(), yesterday=None):
    """
    一晚的事實區塊。**只放這個人、這一晚（和它的上一晚、前一個日曆日）的資料**，數字全部後端算好。

    wearable / previous_wearable / behavior 是資料庫的列（previous_* 是**上一個有資料的晚上**）。
    yesterday 是 garmin_daily 那一列（前一個日曆日），沒有就 None。
    ⚠️ 不放攝影機、不放壓力：見檔頭。
    """
    facts = {"date": date}

    target = (behavior or {}).get("target_bedtime") or user.get("target_bedtime")
    facts["your_target"] = {"in_bed_by": target}

    b = behavior or {}
    if b.get("lights_out_at"):
        minutes = b.get("adherence_minutes")
        facts["phone_down"] = {
            "at": b["lights_out_at"][11:16],
            "versus_target": (
                None if minutes is None else
                "on time" if minutes <= 0 else f"{hm(minutes)} after your target"
            ),
        }
    if b.get("bed_start_at"):
        facts["start_sleep_tapped_at"] = b["bed_start_at"][11:16]
        if b.get("phone_in_bed_minutes") is not None:
            facts["phone_use_after_start_sleep"] = hm(b["phone_in_bed_minutes"])

    judged = judge_night(wearable, previous_wearable, user)
    if wearable and wearable.get("final_score") is not None:
        dur = wearable.get("duration_min")

        def item(value, key, share=None):
            if value is None:
                return None
            out = {"value": value}
            if share is not None:
                out["share_of_sleep"] = f"{round(share)}%"
            if judged.get(key):
                out["judgment"] = judged[key]
            return out

        sleep = {
            "score": round(wearable["final_score"]),
            "quality": wearable.get("final_quality"),
            "time_asleep": item(hm(dur), "time_asleep"),
            "deep_sleep": item(hm(wearable.get("deep_min")), "deep_sleep",
                               _share(wearable.get("deep_min"), dur)),
            "awake_during_night": item(hm(wearable.get("waso_min")), "awake_during_night"),
        }
        if wearable.get("rem_measured"):
            sleep["rem_sleep"] = item(hm(wearable.get("rem_min")), "rem_sleep",
                                      _share(wearable.get("rem_min"), dur))
        if judged.get("sleeping_heart_rate"):
            sleep["sleeping_heart_rate"] = {"judgment": judged["sleeping_heart_rate"]}
        facts["last_night"] = {k: v for k, v in sleep.items() if v is not None}

        if previous_wearable:
            changes = {
                "time_asleep": _change(dur, previous_wearable.get("duration_min")),
                "deep_sleep": _change(wearable.get("deep_min"), previous_wearable.get("deep_min")),
                "awake_during_night": _change(wearable.get("waso_min"), previous_wearable.get("waso_min")),
            }
            facts["change_vs_previous_night"] = {k: v for k, v in changes.items() if v}
            if judged.get("previous_time_asleep"):
                facts["previous_night"] = {"time_asleep": {"judgment": judged["previous_time_asleep"]}}

    if yesterday and yesterday.get("steps"):
        act = {"steps": f"{yesterday['steps']:,}"}
        if yesterday.get("step_goal"):
            act["step_goal"] = f"{yesterday['step_goal']:,}"
        active = (yesterday.get("highly_active_sec") or 0) + (yesterday.get("active_sec") or 0)
        if active:
            act["active_time"] = hm(active / 60)
        facts["yesterday_activity"] = act

    if rating_label:
        facts["how_you_felt"] = rating_label
    if tag_labels:
        facts["you_noted"] = list(tag_labels)
    return facts


def tip_list(suggested_ids=()):
    """交給 AI 的整份清單。suggested_tonight＝後端依適用條件挑到的（給 AI 參考，不強制）。"""
    suggested = set(suggested_ids)
    return [{"id": tid, "kind": kind, "sentence": text, "when": mt.WHEN[tid],
             "suggested_tonight": tid in suggested}
            for tid, (kind, text) in mt.TIPS.items()]


def facts_hash(facts, tips):
    payload = PROMPT_VERSION + json.dumps([facts, tips], sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


# ═══════════════════════════════════════════════════════════════════
# 驗證
# ═══════════════════════════════════════════════════════════════════

def _sentences(text):
    return [s for s in re.split(r"[.!?]+(?:\s|$)", text.strip()) if s.strip()]


def validate_notes(notes, facts_text):
    """回傳問題清單；空清單代表通過。notes = {"summary", "tips": [{"id", "text"}]}。"""
    problems = []
    summary = (notes.get("summary") or "").strip()
    tips = notes.get("tips") or []

    if not summary:
        problems.append("empty summary")
    if len(_sentences(summary)) > MAX_SUMMARY_SENTENCES:
        problems.append(f"summary has more than {MAX_SUMMARY_SENTENCES} sentences")
    if SUMMARY_ACTION_PATTERN.search(summary):
        problems.append("the summary gives advice (advice belongs in the tips)")

    if len(tips) > mt.MAX_TIPS:
        problems.append(f"more than {mt.MAX_TIPS} tips")
    seen = set()
    for t in tips:
        tid, text = t.get("id"), (t.get("text") or "").strip()
        if tid not in mt.TIPS:
            problems.append(f"tip id {tid!r} is not in the tip list (no actions outside the list)")
            continue
        if tid in seen:
            problems.append(f"tip {tid} used twice")
        seen.add(tid)
        if not text:
            problems.append(f"tip {tid} is empty")
        if len(_sentences(text)) > MAX_TIP_SENTENCES:
            problems.append(f"tip {tid} has more than {MAX_TIP_SENTENCES} sentences")
        if not re.search(mt.KEYWORDS[tid], text, re.IGNORECASE):
            problems.append(f"tip {tid} lost its key point (expected a word like: {mt.KEYWORDS[tid]})")

    texts = [summary] + [(t.get("text") or "") for t in tips]
    whole = " ".join(texts)
    words = re.findall(r"[A-Za-z0-9']+", whole)
    if len(words) > MAX_WORDS:
        problems.append(f"too long ({len(words)} words, max {MAX_WORDS})")
    # 數字從哪裡來：總結只能用事實裡的；每條建議只能用事實裡的或**它自己那一句**的。
    # ⚠️ 不能放寬成「整份清單裡有的都行」：P1 寫了 7–9 hours，總結寫「睡了 9h」就會被放行。
    if summary:
        problems.extend(chat.validate_answer(summary, facts_text))
    for t in tips:
        text = (t.get("text") or "").strip()
        if text and t.get("id") in mt.TIPS:
            problems.extend(chat.validate_answer(text, facts_text + "\n" + mt.TIPS[t["id"]][1]))
    if CAUSAL_PATTERN.search(whole):
        problems.append("states a cause as certain (use 'might' / 'can', never 'because' / 'due to')")
    for sentence in _sentences(whole):
        for why, pats, unless in _FORBIDDEN:
            if all(p.search(sentence) for p in pats) and not (unless and unless.search(sentence)):
                problems.append(why)
    return problems


def summarize_night(facts, tips):
    """
    寫一次。回傳 {"summary", "tips": [{"id", "text"}], "model", "attempts"}；
    寫不出來丟 SummaryUnavailable。
    """
    facts_text = json.dumps(facts, ensure_ascii=False, indent=2)
    tips_text = json.dumps(tips, ensure_ascii=False, indent=2)
    feedback = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        user_prompt = f"FACTS:\n{facts_text}\n\nTIP LIST:\n{tips_text}\n{feedback}"
        try:
            data, model = complete(SYSTEM_PROMPT, user_prompt, NOTES_SCHEMA, max_tokens=1200)
        except llm_client.LLMError as exc:
            print(f"night_summary: LLM call failed - {exc}", file=sys.stderr)
            raise SummaryUnavailable("could not reach the model")
        notes = {"summary": (data.get("summary") or "").strip(),
                 "tips": [{"id": t.get("id"), "text": (t.get("text") or "").strip()}
                          for t in (data.get("tips") or [])]}
        problems = validate_notes(notes, facts_text)
        if not problems:
            return {**notes, "model": model, "attempts": attempt}
        feedback = (
            "\nYOUR PREVIOUS ANSWER WAS REJECTED because: " + "; ".join(problems)
            + ". Write it again following every rule."
        )
    raise SummaryUnavailable("no answer passed the checks")
