"""
早晨報告的 AI 分析（2026-11-12）：寵物口吻、2–3 句，只講這一晚。

設計（使用者 2026-11-12 定）：
- 每晚只生成一次，存進 night_summaries；事實變了（手錶晚到、補了自評）才重生。
- 只重述**後端已經算好的事實**：分數、等級、睡多久、跟上一晚比的差值、放下手機比目標晚多少、
  使用者自己的目標。**不准自己下結論、不准說因果、不給醫療建議。**
- 從「跟上一晚比」裡挑變化最大的一件講，最後一句提醒使用者自己設的目標。
- **小建議不歸這裡管**：後端用 behavior/morning_tips.pick_tip() 挑好，畫面另起一列顯示。
  AI 碰不到建議，也就改不壞它。
- 驗證沿用睡眠助理那一套（ai/chat.validate_answer：數字要在事實裡、禁用字、中文、拼字數值），
  再加上這裡才有的：長度、句數、因果說法。兩次都沒過 → SummaryUnavailable，
  呼叫端退回後端現成的兩句話。

⚠️ 時長一律給「2h 49m」這種寫好的字串，要求照抄。讓模型自己把 169 分鐘換算成小時，
   換錯了也看起來很合理——而數字檢查會因為換出來的數字不在事實裡而整句擋掉。
"""
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import chat  # noqa: E402  共用驗證與 Claude 呼叫
import llm_client  # noqa: E402

# ── 測試替換點（測試換成假的，永遠不打真的 API）──────────────────
complete = llm_client.complete_json
key_available = llm_client.api_key_available

# 改 prompt 或事實的形狀時要升版：舊的那一份會因為 facts_hash 不同而重生。
PROMPT_VERSION = "night-v1"

MAX_ATTEMPTS = 2
MAX_WORDS = 60
MAX_SENTENCES = 3

# 因果說法：我們只能說「這兩件事同一晚發生」，不能說「因為」。
CAUSAL_PATTERN = re.compile(
    r"\b(because|due to|caused|causes|cause|since you|as a result|that's why|so you slept)\b",
    re.IGNORECASE,
)

SUMMARY_SCHEMA = {
    "type": "object",
    "properties": {"text": {"type": "string"}},
    "required": ["text"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """You are the user's pet dog in Sonnap, a sleep app. It is the morning after, and you are \
talking to your human about LAST NIGHT, using ONLY the FACTS block.

Write 2 or 3 short sentences, at most 50 words, in warm, simple English, speaking as the pet ("we", "I", "you").
- Pick the ONE biggest change in "change_vs_previous_night" and mention it. If there is none, mention last \
night's sleep time.
- Mention at most 2 numbers. Copy durations and times EXACTLY as written in the facts (for example "2h 49m", \
"03:00"). Never convert, round or invent a number.
- End with one sentence reminding them of THEIR OWN target from "your_target" (for example being in bed by \
that time). Do not give any other advice or tips.
- Never say why something happened: no "because", "due to", "caused". Only say what happened.
- If "how_you_felt" or "you_noted" is present you may mention it, without judging it.
- No medical advice; do not name health conditions, medicines or treatments. No lists, no emoji except \
at most one at the end. Always English."""


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


def build_night_facts(date, user, wearable, previous_wearable, behavior,
                      rating=None, rating_label=None, tag_labels=()):
    """
    一晚的事實區塊。**只放這個人、這一晚（和它的上一晚）的資料**，數字全部後端算好。

    wearable / previous_wearable / behavior 是資料庫的列（previous_* 是**上一個有資料的晚上**）。
    """
    facts = {"date": date}

    target = (behavior or {}).get("target_bedtime") or user.get("target_bedtime")
    facts["your_target"] = {"in_bed_by": target}

    if behavior and behavior.get("lights_out_at"):
        minutes = behavior.get("adherence_minutes")
        facts["phone_down"] = {
            "at": behavior["lights_out_at"][11:16],
            "versus_target": (
                None if minutes is None else
                "on time" if minutes <= 0 else f"{hm(minutes)} after your target"
            ),
        }

    if wearable and wearable.get("final_score") is not None:
        sleep = {
            "score": round(wearable["final_score"]),
            "quality": wearable.get("final_quality"),
            "time_asleep": hm(wearable.get("duration_min")),
            "deep_sleep": hm(wearable.get("deep_min")),
            "awake_during_night": hm(wearable.get("waso_min")),
        }
        if wearable.get("rem_measured"):
            sleep["rem_sleep"] = hm(wearable.get("rem_min"))
        facts["last_night"] = {k: v for k, v in sleep.items() if v is not None}

        if previous_wearable:
            changes = {
                "time_asleep": _change(wearable.get("duration_min"), previous_wearable.get("duration_min")),
                "deep_sleep": _change(wearable.get("deep_min"), previous_wearable.get("deep_min")),
                "awake_during_night": _change(wearable.get("waso_min"), previous_wearable.get("waso_min")),
            }
            facts["change_vs_previous_night"] = {k: v for k, v in changes.items() if v}

    if rating_label:
        facts["how_you_felt"] = rating_label
    if tag_labels:
        facts["you_noted"] = list(tag_labels)
    return facts


def facts_hash(facts):
    payload = PROMPT_VERSION + json.dumps(facts, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def validate_summary(text, facts_text):
    """回傳問題清單；空清單代表通過。"""
    problems = chat.validate_answer(text, facts_text)
    words = re.findall(r"[A-Za-z0-9']+", text)
    if len(words) > MAX_WORDS:
        problems.append(f"too long ({len(words)} words, max {MAX_WORDS})")
    sentences = [s for s in re.split(r"[.!?]+(?:\s|$)", text.strip()) if s.strip()]
    if len(sentences) > MAX_SENTENCES:
        problems.append(f"too many sentences ({len(sentences)}, max {MAX_SENTENCES})")
    if CAUSAL_PATTERN.search(text):
        problems.append("says why something happened (no 'because' / 'due to')")
    return problems


def summarize_night(facts):
    """寫一次。回傳 {"text", "model", "attempts"}；寫不出來丟 SummaryUnavailable。"""
    facts_text = json.dumps(facts, ensure_ascii=False, indent=2)
    feedback = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        user_prompt = f"FACTS:\n{facts_text}\n{feedback}"
        try:
            data, model = complete(SYSTEM_PROMPT, user_prompt, SUMMARY_SCHEMA, max_tokens=800)
        except llm_client.LLMError as exc:
            print(f"night_summary: LLM call failed - {exc}", file=sys.stderr)
            raise SummaryUnavailable("could not reach the model")
        text = (data.get("text") or "").strip()
        problems = validate_summary(text, facts_text)
        if not problems:
            return {"text": text, "model": model, "attempts": attempt}
        feedback = (
            "\nYOUR PREVIOUS ANSWER WAS REJECTED because: " + "; ".join(problems)
            + ". Write it again following every rule."
        )
    raise SummaryUnavailable("no answer passed the checks")
