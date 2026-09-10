"""
tests/test_chat.py —— 睡眠助理（POST /chat）

⚠️ **這支測試絕對不能打到真的 Claude API。** 三道保險：
   1. 在 import 任何東西之前把 ANTHROPIC_API_KEY 設成空字串——
      ai/env_utils.load_env_file() 不覆寫已存在的環境變數，所以 ai/.env
      裡真的金鑰載不進來。
   2. 把 urllib.request.urlopen 換成「一被呼叫就讓測試失敗」。
   3. 把 ai.chat.complete 換成假的。

守的東西：
   - 四道驗證擋得住：醫療用語、數字不在事實裡、中文、拼字數值
   - 四道驗證不誤傷：retreat、one more try、half an hour earlier
   - 第一次沒過會帶著原因重問，兩次都沒過就老實說答不出來
   - 事實區塊只有這個人自己的資料
   - 沒設定金鑰時直接 503，一個請求都不發

執行：python tests/test_chat.py
"""
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

os.environ["ANTHROPIC_API_KEY"] = ""          # 保險 1：一定要在 import 之前

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

NETWORK_CALLS = []


def _no_network(*args, **kwargs):              # 保險 2
    NETWORK_CALLS.append(args)
    raise AssertionError("test_chat tried to reach the real network")


urllib.request.urlopen = _no_network

import db
TMP = Path(tempfile.mkdtemp()) / "test_chat.db"
db.DB_PATH = TMP

import main
from ai import chat
from fastapi.testclient import TestClient

client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<52} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<52} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


class FakeLLM:
    """依序回預先寫好的答案，並記下每一次的 prompt。"""

    def __init__(self, *answers):
        self.answers = list(answers)
        self.prompts = []

    def __call__(self, system_prompt, user_prompt, schema, **kwargs):
        self.prompts.append(user_prompt)
        return {"answer": self.answers.pop(0)}, "fake-model"


def use(fake, key=True):
    chat.complete = fake                                 # 保險 3
    chat.key_available = (lambda: True) if key else (lambda: False)


FACTS = {"target_bedtime": "23:30", "last_night_phone": {"date": "2026-09-03", "phone_down_at": "02:39",
         "minutes_after_target": 189, "counted_as_late": True},
         "on_time_streak_nights": 0, "late_nights_recent": {"late": 3, "recorded": 5}}
FACTS_TEXT = chat.json.dumps(FACTS)


def safe_validate(text, facts_text=FACTS_TEXT):
    """
    ⚠️ 驗證本身出錯時記成失敗，不讓整支測試崩掉。崩掉會遮住後面所有檢查——
       變異測試跑「數字當字串比」時就是這樣：抓到了，但抓法是整支中斷。
       而且在正式環境裡，驗證出錯會變成 500，那本身就是 bug。
    """
    try:
        return chat.validate_answer(text, facts_text)
    except Exception as exc:  # noqa: BLE001
        return [f"validate_answer crashed: {type(exc).__name__}: {exc}"]

# ═══════════════════════════════════════════════════════════════════
section("【1】驗證擋得住")
# ═══════════════════════════════════════════════════════════════════
check("數字不在事實裡", safe_validate("You slept 7 hours.", FACTS_TEXT),
      ["the number 7 is not in the facts"])
ok("醫療用語", any("insomnia" in p for p in safe_validate("This looks like insomnia.", FACTS_TEXT)))
ok("中文", "not in English" in safe_validate("你昨晚 02:39 才放下手機。", FACTS_TEXT))
ok("拼字數值（有 point）", "a number spelled out in words" in safe_validate(
    "You slept ten point three hours.", FACTS_TEXT))
ok("空白回答", "empty answer" in safe_validate("   ", FACTS_TEXT))

# ═══════════════════════════════════════════════════════════════════
section("【2】驗證不誤傷（誤判的代價是使用者拿不到答案）")
# ═══════════════════════════════════════════════════════════════════
for text in (
    "You put the phone down at 02:39, which was 189 minutes after your 23:30 target.",
    "Try to retreat to bed a little earlier tonight.",             # retreat 含 treat
    "Give it one more try tonight.",                                # 拼字數字但沒有 point
    "Putting the phone down half an hour earlier would help.",
    "You were late on 3 of the 5 recorded nights.",
    "Your phone went down at 2:39.",                                # 05 與 5 是同一個數
):
    check(f"放行：{text[:44]}", safe_validate(text, FACTS_TEXT), [])

# ═══════════════════════════════════════════════════════════════════
section("【3】端點：沒設定金鑰 → 503，一個請求都不發")
# ═══════════════════════════════════════════════════════════════════
db.init_db(TMP)
db.seed_challenges(TMP)


def make_user(name, lights_out):
    uid = client.post("/users", json={"display_name": name, "target_bedtime": "23:30"}).json()["user_id"]
    r = client.post("/nightly", json={"user_id": uid, "lights_out_at": lights_out})
    assert r.status_code == 201, r.text
    return uid


alice = make_user("Alice", "2026-09-03T02:39:00+08:00")
bob = make_user("Bob", "2026-09-03T22:47:00+08:00")

unused = FakeLLM("should not be used")
use(unused, key=False)
r = client.post("/chat", json={"user_id": alice, "message": "How late was I?"})
check("沒金鑰 → 503", r.status_code, 503)
check("一個 prompt 都沒送", unused.prompts, [])

# ═══════════════════════════════════════════════════════════════════
section("【4】端點：通過驗證的回答原樣回來")
# ═══════════════════════════════════════════════════════════════════
fake = FakeLLM("You put the phone down at 02:39, which counted as a late night.")
use(fake)
r = client.post("/chat", json={"user_id": alice, "message": "How late was I last night?"})
check("200", r.status_code, 200)
check("回答照抄", r.json().get("answer"), "You put the phone down at 02:39, which counted as a late night.")
check("標明來源是 LLM", r.json().get("source"), "llm")
ok("事實區塊有 Alice 自己的時刻", "02:39" in fake.prompts[0])
ok("事實區塊沒有 Bob 的資料", "22:47" not in fake.prompts[0] and "Bob" not in fake.prompts[0])
ok("問題本身有送出去", "How late was I last night?" in fake.prompts[0])

# ═══════════════════════════════════════════════════════════════════
section("【5】第一次沒過 → 帶著原因重問；兩次都沒過 → 老實說答不出來")
# ═══════════════════════════════════════════════════════════════════
fake = FakeLLM("You slept 7 hours.", "You put the phone down at 02:39.")
use(fake)
r = client.post("/chat", json={"user_id": alice, "message": "How long did I sleep?"})
check("第二次過了 → 200", r.status_code, 200)
check("問了兩次", len(fake.prompts), 2)
second = fake.prompts[1] if len(fake.prompts) > 1 else ""   # 不直接索引：沒重問時清單只有一筆
ok("第二次的 prompt 講了第一次為什麼被退", "the number 7 is not in the facts" in second)

fake = FakeLLM("This looks like insomnia.", "Take a pill.")
use(fake)
r = client.post("/chat", json={"user_id": alice, "message": "Am I sick?"})
check("兩次都沒過 → 503", r.status_code, 503)
ok("不把沒過驗證的回答交出去", "insomnia" not in r.text and "pill" not in r.text)

# ═══════════════════════════════════════════════════════════════════
section("【6】輸入檢查")
# ═══════════════════════════════════════════════════════════════════
use(FakeLLM("unused"))
check("空問題 → 422", client.post("/chat", json={"user_id": alice, "message": ""}).status_code, 422)
check("太長 → 422", client.post("/chat", json={"user_id": alice, "message": "x" * 501}).status_code, 422)
check("沒有這個人 → 404", client.post("/chat", json={"user_id": "nobody", "message": "hi"}).status_code, 404)

# ═══════════════════════════════════════════════════════════════════
section("【7】保險有效：整支測試一次都沒碰到網路")
# ═══════════════════════════════════════════════════════════════════
check("urlopen 被呼叫的次數", len(NETWORK_CALLS), 0)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：")
    for f in fails:
        print(f"    - {f}")
    sys.exit(1)
print("✓ 全部通過")
