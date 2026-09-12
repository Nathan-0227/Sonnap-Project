"""
ai/chat.py —— 睡眠助理的問答（B6）。

把**這個人自己的**資料整理成事實區塊，連同問題送給 Claude，回答要通過
四道驗證才交給 App。

═══════════════════════════════════════════════════════════════════
四道驗證（跟夢境日記共用同一份定義，不在這裡另寫一份）
═══════════════════════════════════════════════════════════════════

    1. 醫療用語禁詞       generate_advice.BANNED_WORDS，**完整單詞比對**
                          （treat 不能命中 retreat）
    2. 數字必須在事實裡   回答裡的每一個數字都要出現在事實區塊
    3. 中文洩漏           generate_advice.CJK_LEAK_PATTERN（輸出固定英文）
    4. 拼字數值           generate_advice.SPELLED_NUMERAL_PATTERN——
                          **必須有 point 才擋**，"give it one more try" 要放行

⚠️ 從 generate_advice import 而不是抄一份：兩份禁詞清單漂移時，夢境擋得住的詞
   聊天擋不住，而且不會有任何錯誤訊息。
⚠️ 驗證寫寬很省事，但誤判的代價是使用者拿不到答案（方法論第 5 點）。
   tests/test_chat.py 同時驗「擋得住」與「不誤傷」。

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

import llm_client  # noqa: E402
from generate_advice import (  # noqa: E402
    BANNED_WORDS,
    CJK_LEAK_PATTERN,
    NUMBER_PATTERN,
    SPELLED_NUMERAL_PATTERN,
)

# ── 測試替換點（測試換成假的，永遠不打真的 API）──────────────────
complete = llm_client.complete_json
key_available = llm_client.api_key_available

# 第一次沒過驗證就帶著「哪裡不行」重問一次。再不行就老實說答不出來。
MAX_ATTEMPTS = 2

_BANNED = [(w, re.compile(r"\b" + re.escape(w) + r"\b", re.IGNORECASE)) for w in BANNED_WORDS]

ANSWER_SCHEMA = {
    "type": "object",
    "properties": {"answer": {"type": "string"}},
    "required": ["answer"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """You are Sonnap's sleep assistant inside a sleep app for university students.

Answer the user's question using ONLY the facts in the FACTS block. The facts describe this one user.

Rules:
- Write 2 to 4 short sentences in plain, friendly English. No lists, no headings.
- Only use digits that appear in the FACTS block. Never invent, estimate or convert numbers.
- If the question needs data that is not in the facts, say plainly that Sonnap does not have that data.
- Focus on behaviour the user can change, such as when they put the phone down and keeping a steady bedtime.
- Do not give medical advice. Do not name health conditions, medicines or treatments. If the user sounds
  worried about their health, suggest talking to a doctor or the campus health service.
- Always answer in English, even if the question is in another language."""


class ChatUnavailable(Exception):
    """答不出來（沒設定、連不上、或兩次都沒過驗證）。訊息是給使用者看的英文。"""


def build_facts(user, latest_behavior, latest_wearable, streak, late):
    """
    事實區塊。**只放這個人自己的資料**。

    late 是 adherence.late_night_ratio() 的回傳值 (ratio, late_nights, recorded)。

    ⚠️ 時刻直接切 ISO 字串的 HH:MM，不轉時區——那是記錄當下的牆鐘時間
       （與 App 端 parseWallClock() 同一個道理）。
    ⚠️ 分數只放整數，與 App 上顯示的一致；小數點後的數字放進去，模型就會
       講出 App 上看不到的「82.4 分」。
    """
    facts = {"target_bedtime": user.get("target_bedtime")}

    if latest_behavior:
        lights_out = latest_behavior.get("lights_out_at") or ""
        minutes = latest_behavior.get("adherence_minutes")
        facts["last_night_phone"] = {
            "date": latest_behavior.get("date"),
            "phone_down_at": lights_out[11:16] or None,
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
        facts["last_night_watch"] = {
            "date": latest_wearable.get("date"),
            "sleep_score": round(latest_wearable["final_score"]),
            "quality": latest_wearable.get("final_quality"),
            "sleep_minutes": round(duration) if duration is not None else None,
        }
    return facts


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


def answer_question(question, facts):
    """
    問一次。回傳 {"answer", "attempts", "model"}，答不出來丟 ChatUnavailable。

    ⚠️ 失敗訊息不帶 API 的錯誤細節——那可能包含「金鑰無效」之類的伺服器資訊，
       不該傳到手機上。細節留在後端的 log。
    """
    facts_text = json.dumps(facts, ensure_ascii=False, indent=2)
    feedback = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        user_prompt = f"FACTS:\n{facts_text}\n\nQUESTION:\n{question}\n{feedback}"
        try:
            data, model = complete(SYSTEM_PROMPT, user_prompt, ANSWER_SCHEMA, max_tokens=2000)
        except llm_client.LLMRefusal:
            raise ChatUnavailable("The assistant could not answer that question.")
        except llm_client.LLMError as exc:
            print(f"chat: LLM call failed - {exc}", file=sys.stderr)
            raise ChatUnavailable("The assistant could not be reached right now.")

        answer = (data.get("answer") or "").strip()
        problems = validate_answer(answer, facts_text)
        if not problems:
            return {"answer": answer, "attempts": attempt, "model": model}
        feedback = (
            "\nYOUR PREVIOUS ANSWER WAS REJECTED because: " + "; ".join(problems)
            + ". Write it again following every rule."
        )
    raise ChatUnavailable("The assistant could not give an answer that passed the safety checks.")
