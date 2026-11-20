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
from env_utils import load_env_file  # noqa: E402
from text_guards import (  # noqa: E402
    BANNED_WORDS,
    CJK_LEAK_PATTERN,
    NUMBER_PATTERN,
    SPELLED_NUMERAL_PATTERN,
)

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
- PET MOOD (when present) was decided by the app. To explain it, use only its "decided_by" text; do not
  invent other reasons and do not say whether a sleep measure is high or low.
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
    "behavior": "when the phone was put down compared with the target bedtime",
    "wearable": "the watch's sleep quality grade for that night",
    "wearable_override": "the watch showed the body was less settled than usual that night",
}


def build_facts(user, latest_behavior, latest_wearable, streak, late, pet=None):
    """
    事實區塊。**只放這個人自己的資料**。

    late 是 adherence.late_night_ratio() 的回傳值 (ratio, late_nights, recorded)。
    pet 是 (date, mood, driver)：首頁那隻寵物的心情（2026-11-21 加，讓「寵物心情跟睡眠
    有什麼關係」答得出來）。心情由後端判好，這裡只轉述，不給 AI 任何判斷的材料。

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
    if pet and pet[1] and pet[2] in PET_MOOD_DECIDED_BY:
        facts["pet_mood"] = {"date": pet[0], "mood": pet[1],
                             "decided_by": PET_MOOD_DECIDED_BY[pet[2]]}
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


def answer_question(question, facts, history=()):
    """
    問一次。回傳 {"answer", "attempts", "model"}，答不出來丟 ChatUnavailable。

    ⚠️ 失敗訊息不帶 API 的錯誤細節——那可能包含「金鑰無效」之類的伺服器資訊，
       不該傳到手機上。細節留在後端的 log。
    """
    facts_text = json.dumps(facts, ensure_ascii=False, indent=2)
    convo = _conversation_block(history)
    feedback = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        user_prompt = f"FACTS:\n{facts_text}\n\n{convo}QUESTION:\n{question}\n{feedback}"
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
