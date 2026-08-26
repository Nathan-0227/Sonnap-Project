"""
generate_advice.py — 產生每晚的 AI 睡眠建議與寵物夢境日記

═══════════════════════════════════════════════════════════════════
使用方式
═══════════════════════════════════════════════════════════════════
    python ai/generate_advice.py --dry-run          # 不呼叫 API，印出待生成清單與 prompt
    python ai/generate_advice.py --dates 2026-08-09 # 只做指定那晚（無條件重生）
    python ai/generate_advice.py                    # 生成最多 10 晚尚未產生的
    python ai/generate_advice.py --limit 0          # 全部補完
    python ai/generate_advice.py --refresh-stale    # 連同資料已變動的舊紀錄一起重生

═══════════════════════════════════════════════════════════════════
AI 在這裡的定位：綜合 + 重新配音，不是取代
═══════════════════════════════════════════════════════════════════
規則式 recommendation **原封不動**留在 garmin_sleep_quality_final.* 當事實來源。
AI 做的是規則式做不到的兩件事：用寵物語氣重講、加上跨夜趨勢的觀察。

決定性理由來自本專案自己的歷史：2026-07-20 修過 build_recommendation() 的
自相矛盾（Good 的夜晚卻被說「睡眠時間不足」）。讓模型從零生成建議等於重新
引入同一類 bug，而且沒有確定性測試抓得到、沒有文獻依據可引——
文獻依據正是口試的護身符。

**任何具體數值或門檻宣稱必須來自規則層**，模型只能綜合與敘述。

═══════════════════════════════════════════════════════════════════
誠實揭露
═══════════════════════════════════════════════════════════════════
**Garmin 完全沒有量測任何夢境內容。** REM 分鐘數只說明睡眠階段發生過，
完全沒說夢到什麼，而且 46 晚裡有 11 晚連 REM 都沒測到。

所以虛構的是**寵物的夢，不是使用者的夢**——prompt 強制第一人稱為寵物，
UI 文案是「小寵物昨晚的夢境日記」。這把「誤述資料」轉成明顯是虛構的陪伴功能。
另外 dream_summary 一律不得含數字，夢境因此永遠無法斷言任何測量值。
"""

import argparse
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from env_utils import load_env_file  # noqa: E402
from llm_client import (  # noqa: E402
    LLMError,
    LLMRefusal,
    api_key_available,
    complete_json,
    model_name,
)
from night_profile import build_profile, format_facts, load_nights  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

load_env_file()

DATA_DIR = Path(__file__).parent / "data"
ADVICE_JSON = DATA_DIR / "ai_advice.json"
ADVICE_CSV = DATA_DIR / "ai_advice.csv"

SCHEMA_VERSION = 1
# 這個字串會進 fingerprint()，所以改版號會讓既有紀錄全部標記為 stale，
# 用 --refresh-stale 就能重新生成——prompt 變了，舊內容本來就該重來。
#
# v2（2026-08-12）：調色盤與 few-shot 改成依當晚 REM 是否測得動態組裝。
# v3（2026-08-12）：三項改動，都是為了修「46 晚裡 32 晚（70%）用同兩組意象」
#   1. 調色盤每類擴充成 3–6 組，並改用身體感受寫（不用形容詞）
#   2. 新增 recent_motifs()：把最近 7 晚用過的意象寫進 prompt 要求避開
#   3. advice / trend_note 的數值一律用阿拉伯數字（原本 4 晚寫成「十點三小時」）
# v4（2026-08-26）：**輸出語言由正體中文改為英文**。這不只是翻譯，
#   驗證層有三個機制必須跟著換對象（換掉任何一個都會安靜失效）：
#     1. SIMPLIFIED_CHARS（簡繁檢查）→ CJK_LEAK_PATTERN（偵測任何中日文字）
#     2. CHINESE_NUMERAL_PATTERN     → SPELLED_NUMERAL_PATTERN（沿用「只擋小數」的收窄判準）
#     3. MOTIF_FAMILIES 的關鍵字      → 照英文調色盤重挑，且比對前要 .lower()
#   另外 LENGTH_LIMITS 三組上下限乘以 3（英文表達同樣內容約 2.7–3.3 倍字元）。
#   升到 v4 會讓既有 46 晚全部標記為 stale，用 --refresh-stale 重生。
PROMPT_VERSION = "v4"
DEFAULT_LIMIT = 10
MAX_CONSECUTIVE_FAILURES = 3

DISCLAIMER = (
    "The dream diary is an AI creation imagined from sleep data, not a record "
    "of the user's actual dreams; the advice is not a medical diagnosis."
)

# structured outputs 的 schema。物件必須有 additionalProperties: false 與 required。
OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "advice": {"type": "string"},
        "dream_summary": {"type": "string"},
        "trend_note": {"type": "string"},
    },
    "required": ["advice", "dream_summary", "trend_note"],
    "additionalProperties": False,
}

# 禁詞：針對「本來就睡不好的學生」這個目標族群，避免醫療宣稱與罪惡感。
# Home_Page_Design.md 引用的 Consolvo (2008) 是寵物情感連結的依據，
# 而會讓人有罪惡感的寵物正是這類 App 的已知失敗模式。
# ⚠️ 2026-08-26 語言改英文之後，這份清單是重寫的不是翻譯的。
#    中文版靠的是「詞就是詞」，英文要考慮詞形變化與子字串誤傷，
#    所以下面用「完整單詞」比對（見 validate 裡的 WORD_PATTERN），
#    而不是 `word in text`——否則 "ill" 會命中 "still"、"willing"。
BANNED_WORDS = [
    "diagnose", "diagnosis", "diagnostic", "treat", "treatment", "cure",
    "insomnia", "depression", "depressive", "anxiety disorder", "apnea",
    "medication", "medicine", "drug", "drugs", "pill", "pills",
    "disease", "disorder", "syndrome", "patient", "patients",
    "prescribe", "prescription", "therapy", "clinical diagnosis",
]

# 「這一段沒有記錄」類意象。只有 REM 真的沒測到的夜晚可以用（見 PALETTE_REM_UNMEASURED）。
# 光把選項從 prompt 拿掉不夠——模型自己的先驗也會把它帶回來，所以這裡再擋一次。
#
# 分成兩組，是 2026-08-12 全量跑完後修正的：第一版把「沒看清」也列為無條件禁詞，
# 結果 44 晚裡有 3 晚連兩次都被擋掉、退回規則式文字。那是**我自己造成的矛盾**——
# PALETTE_REM_MEASURED 才剛叫模型「REM 比例低要寫夢很淡、很快就過去」，
# 而「來不及看清楚就散掉」正是那個意思，是在形容夢很淡，不是在宣稱沒有資料。
#
# 判準：講的是「這段資料不存在」才擋，講「夢很模糊」不擋。

# 無條件禁止：這些詞只可能是在講「這段沒有記錄」。
MISSING_RECORD_MOTIFS = [
    "blank page", "blank pages", "empty page", "empty pages",
    "missing page", "missing pages", "torn out", "nothing was written",
    "no record", "not recorded", "wasn't recorded", "was not recorded",
]

# 這些動詞本身無害，只有跟「指出某一段」的詞連用時，才構成「那段沒有資料」的宣稱。
#
# ⚠️ 英文版比中文版更需要這個兩段式判準。中文的「沒看清」只是模糊，
#    英文的 "I didn't see" 更容易單獨出現在正常敘述裡
#    （"I didn't see the end of it" 是在講夢很淡，不是在講沒有資料）。
VAGUE_VERBS = [
    "didn't see", "did not see", "never saw", "can't remember",
    "cannot remember", "don't remember", "do not remember",
]
SECTION_WORDS = [
    "that part", "that stretch", "the middle", "a few pages",
    "those hours", "that hour",
]

# 語言洩漏偵測。
#
# ⚠️ 2026-08-26 這一條**換了對象但沒有換目的**。
#    輸出原本固定 zh-TW，這裡擋的是「混進簡體字形」（2026-08-12 真的發生過：
#    claude-sonnet-5 寫出「門边」，同一個詞裡兩種字形）。
#    語言改成英文之後，簡繁檢查完全沒有意義，但**同一類失敗仍然存在**：
#    模型可能漂回中文，或在英文句子裡夾一個中文詞。
#    所以改成偵測任何 CJK 字元——這是同一個機制對準新語言的版本，
#    不是把檢查拿掉。
#
# 涵蓋範圍：CJK 統一漢字、平假名/片假名、CJK 標點與全形字元。
# 保留「擋下來重試」而不是自動清掉的原則：偷偷改會蓋掉問題。
CJK_LEAK_PATTERN = re.compile(
    r"[　-〿぀-ヿ㐀-䶿一-鿿豈-﫿＀-￯]"
)

DIGIT_PATTERN = re.compile(r"[0-9０-９]")
NUMBER_PATTERN = re.compile(r"\d+(?:\.\d+)?")

# 拼字數值偵測（2026-08-12 新增；2026-08-26 改成英文版）。
#
# 問題：46 晚裡有 4 晚寫成「睡了十點三小時」「效率九十八點四趴」，
# 其餘 42 晚用阿拉伯數字。同一個 App 裡兩種寫法，畫面上看起來很怪。
# 英文的同型失敗是 "you slept ten point three hours"、
# "efficiency was ninety-eight point four percent"。
#
# ⚠️ 這個規則只套用在 advice 與 trend_note，**不套用在 dream_summary**。
#    夢境本來就完全禁止出現數字（DIGIT_PATTERN 那條），
#    但它可以正常使用「一隻鯨魚」「兩扇門」這種國字量詞——
#    那是中文的自然寫法，不是在報數值。拿這條規則去擋夢境會誤傷。
#
# ⚠️ 這個規則**收窄過一次**，過程值得記下來避免有人改回去。
#
# 第一版寫成「國字數字 + 單位」就擋，結果 **「十分安穩」被誤判**——
# 那是「非常安穩」，不是「十分鐘」。同理「再試一次」「提早一小時」
# 也都是自然中文，不是在報數值。誤判的代價很大：驗證連兩次不過
# 就整晚退回規則式文字，等於為了格式一致犧牲掉整篇 AI 內容。
#
# 想清楚**真正的缺陷是什麼**：實際出問題的 4 晚全都是**小數**
#（「十點三小時」「九十八點四趴」）。整數的國字量詞從來不是問題。
#
# ⚠️ 英文版**沿用同一個收窄判準**：只擋拼字小數（"... point ..."），
#    不擋拼字整數。理由完全一樣——"give it one more try"、
#    "half an hour earlier"、"a couple of nights" 都是自然英文，
#    不是在報數值。英文其實更容易誤判（number words 也是常用字），
#    所以更要守住「必須有 point」這個條件。
#
# 正規表示式拆開看：
#   (?:...)                → 個位／十位的英文數字詞
#   [\s-]*                 → 允許 "twenty-one" 的連字號或空白
#   \s+point\s+            → **必須有 point**（小數點）← 關鍵的收窄
#   (?:one|two|...|nine)   → 小數點後一位
#   \s*(?:hour|minute|...) → 接單位
SPELLED_NUMERAL_PATTERN = re.compile(
    r"\b(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|"
    r"thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|"
    r"twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred)"
    r"(?:[\s-]+(?:one|two|three|four|five|six|seven|eight|nine))?"
    r"\s+point\s+"
    r"(?:one|two|three|four|five|six|seven|eight|nine|zero)"
    r"(?:\s*(?:hours?|hrs?|minutes?|mins?|percent|%|times?|nights?))?",
    re.IGNORECASE,
)


# ═══════════════════════════════════════════════════════════════════
# 意象家族：用來偵測「最近幾晚用過什麼」
# ═══════════════════════════════════════════════════════════════════
#
# 【為什麼要做這個】
# 2026-08-12 全量跑完才發現：46 晚裡有 32 晚（70%）不是「圖書館」就是「海床」。
# 這**不是模型偷懶**——原本調色盤每個條件只給一組意象，又要求「只能用當晚
# 事實支持的意象」，所以事實相似的夜晚必然寫出幾乎一樣的夢。
# 06-05、06-07、06-08、06-12 四晚的夢幾乎可以互換。
#
# 對每天都會打開的 App，這是產品缺陷：使用者每個好夢都看到同一座圖書館。
#
# 修法兩層，缺一不可：
#   第一層：調色盤每個條件擴充成 3–6 組（見 SYSTEM_PROMPT_HEAD）
#   第二層（這裡）：把最近用過的家族名稱塞進 prompt，明確要求避開
#
# 只有第一層不夠——模型的先驗會讓它一直挑第一個選項。這跟 REM 空白頁那次
# 的教訓一樣：**把選項變多不等於它會換**，得明確講「這個最近用過了」。

# 【資料結構】dict（字典），key → value 的對應表。
#   key   = 家族名稱，會直接出現在 prompt 裡給模型看，所以要寫得像人話
#   value = list（串列），偵測用的關鍵字，命中任何一個就算「用過這個家族」
#
# 為什麼關鍵字要少而精：寧可漏判也不要誤判。誤判會讓模型被迫避開它其實
# 沒用過的意象，反而限縮它的選擇——那等於用另一種方式製造重複。
# ⚠️ 2026-08-26：關鍵字全部換成英文，而且是**照著新的英文調色盤重挑的**，
#    不是把中文詞逐個翻譯。原因：偵測靠的是「模型實際會寫出來的字」，
#    而模型寫的是調色盤裡的英文措辭。若照翻中文（"seabed"、"moss"…剛好還對得上，
#    但 "闔上" 翻成 "closed" 就會誤判到 "I closed my eyes"），去重會失準。
#
#    比對一律轉小寫後做（見 recent_motifs），所以這裡全用小寫。
#
#    ⚠️ 家族與調色盤選項仍然**不是一對一**——深睡類 6 個選項只對應
#       2–3 個家族。這是 2026-08-15 就記下的未解問題（「棉被與雪」佔了 37%），
#       語言改了但這個結構問題原封不動。下次要修就是把下面拆到與選項一對一。
MOTIF_FAMILIES = {
    "sinking seabed": ["seabed", "moss", "whale", "bottom of a lake", "lakebed"],
    "quilts and snow": ["quilt", "quilts", "snow", "snowfall"],
    "self-shelving library": ["library", "bookcase", "shelves", "reshelv"],
    "changing sky": ["changing season", "sky changing", "autumn orange"],
    "door to another room": ["different room", "another room behind"],
    "market of colours": ["market", "stall", "stalls"],
    "tree of new branches": ["new branches", "new branch"],
    "picture book": ["picture book"],
    "fog and smoke": ["fog", "smoke", "breath on a cold"],
    "door that will not stay shut": ["pushed the door open", "opened again",
                                     "would not stay shut"],
    "knocking at the window": ["knock", "knocked", "knocking"],
    "train lights": ["train"],
    "path that runs out": ["path ran out", "path runs out"],
    "radio losing signal": ["radio", "static"],
    "wind in the grass": ["wind came up", "laid the grass", "grass stood back"],
    "distant thunder": ["thunder"],
    "waves and boat": ["waves", "boat"],
    "swaying bridge": ["bridge"],
    "the sky went light": ["sky went light", "sky got light"],
    "someone calling": ["calling me", "called me"],
    "the book closed itself": ["book closed itself", "closed itself"],
}

# 往回看幾晚。選 7 的理由：使用者一週內大概會回頭翻的範圍，
# 更早的重複他不會察覺。設太大會把可用意象幾乎全部排除掉，
# 模型反而沒東西可寫。
MOTIF_LOOKBACK_NIGHTS = 7


def recent_motifs(entries, target_date, lookback=MOTIF_LOOKBACK_NIGHTS):
    """
    找出 target_date 之前最近幾晚用過哪些意象家族。

    參數：
        entries      dict，{日期字串: 那一晚的紀錄 dict}，來自 ai_advice.json
        target_date  字串，格式 "2026-08-09"
        lookback     往回看幾晚

    回傳：
        家族名稱的 list，最近用過的排前面。沒有歷史就回空 list []。

    ⚠️ 只看 target_date **之前**的夜晚。這跟 apply_recovery_modifier.py 的
       baseline 只用「當晚之前」的資料是同一個原則——雖然這裡不是統計計算、
       沒有資料洩漏問題，但兩處規則一致，讀的人才不會困惑。
    """
    # ── 第一步：挑出符合條件的歷史紀錄，並依日期由新到舊排序 ──────
    #
    # 這一整段是 sorted(可迭代物件, key=..., reverse=...) 的用法，拆開看：
    #
    # (1) 括號裡的 `e for d, e in entries.items() if ...` 是**生成器運算式**
    #     （generator expression）。它跟 list comprehension 幾乎一樣，
    #     只是用小括號、且不會一次把結果全部建出來（比較省記憶體）。
    #
    #     `entries.items()` 把 dict 拆成 (key, value) 一組一組給你，
    #     所以 `for d, e in` 就是同時拿到「日期 d」和「那晚的紀錄 e」。
    #
    # (2) `if` 後面三個條件都要成立才留下：
    #       d < target_date           → 字串比大小。ISO 日期格式（YYYY-MM-DD）
    #                                   的字典序剛好等於時間先後，所以可以直接比，
    #                                   不用轉成 datetime。這是選 ISO 格式的好處之一。
    #       e.get("source") == "llm"  → 只要 LLM 生成的。規則式 fallback 沒有夢境，
    #                                   算進來會讓 lookback 視窗白白少一晚。
    #                                   用 .get() 而非 e["source"]：舊格式的紀錄
    #                                   可能沒有這個 key，用 [] 會丟 KeyError。
    #       e.get("dream_summary")    → 有夢境內容。空字串和 None 在 Python 裡
    #                                   都是 falsy，所以這樣寫就同時擋掉兩種。
    #
    # (3) `key=lambda e: e["date"]` 告訴 sorted 要「拿每個元素的 date 欄位來比大小」，
    #     而不是比整個 dict（dict 本身沒辦法比大小，不寫 key 會直接報錯）。
    #     lambda 就是「一次性的小函式」，等於 def f(e): return e["date"]。
    #
    # (4) `reverse=True` → 由大到小，也就是日期由新到舊。
    #
    # (5) `[:lookback]` 是**切片**，取前 lookback 個。
    #     Python 的切片超出長度不會報錯——只有 3 晚歷史時，[:7] 就回 3 筆。
    #     這正是我們要的行為（冷啟動時不用特別處理）。
    previous = sorted(
        (e for d, e in entries.items()
         if d < target_date
         and e.get("source") == "llm"
         and e.get("dream_summary")),
        key=lambda e: e["date"],
        reverse=True,
    )[:lookback]

    # ── 第二步：掃過這幾晚的夢境，看命中哪些家族 ──────────────────
    used = []
    for entry in previous:
        # ⚠️ 一律轉小寫再比對。MOTIF_FAMILIES 的關鍵字全是小寫，而模型寫的
        #    夢境會在句首大寫（"Snow was falling"），不轉的話整句都比不到。
        #    中文版沒有大小寫，所以原本不需要這一行——換語言時很容易漏掉，
        #    而漏掉的症狀是「去重機制安靜地完全失效」，不會有任何錯誤訊息。
        dream = entry["dream_summary"].lower()

        # 對每個家族，檢查它的關鍵字有沒有出現在這則夢裡
        for family, keywords in MOTIF_FAMILIES.items():
            # 已經記錄過就跳過，避免同一個家族被加兩次。
            # （用 list 而不是 set 是因為我們要保留「最近的排前面」這個順序，
            #   set 沒有順序。資料量只有 20 個家族 × 7 晚，效率不是問題。）
            if family in used:
                continue

            # any(...) 只要其中一個為 True 就回 True，而且**短路**——
            # 命中第一個關鍵字就不再檢查剩下的。
            # 括號裡同樣是生成器運算式：對每個 kw 檢查 `kw in dream`
            # （`in` 用在字串上是「有沒有包含這個子字串」）。
            if any(kw in dream for kw in keywords):
                used.append(family)

    return used


# ═══════════════════════════════════════════════════════════════════
# Prompt
# ═══════════════════════════════════════════════════════════════════

SYSTEM_PROMPT_HEAD = """\
You are the user's virtual pet, and you sleep beside them. Speak warmly, briefly,
like a friend.

Absolute rules:
1. The dream is **your own dream, the pet's**. Never claim to know what the user
   dreamt - the watch measures nothing about dream content, and saying otherwise
   would misrepresent the data.
2. No medical claims, diagnoses, disease names, or medication advice.
3. Never make the user feel ashamed, guilty, or afraid; no nightmare imagery.
   They already sleep badly; guilt only makes it worse.
4. State nothing that is not in the facts block. Every number and threshold must
   come from the facts block - do not derive, convert, or add to them.
5. Your advice must not contradict the rule-based recommendation. You are
   restating it and adding a trend observation, not replacing it.

How to write the dream: **write physical sensation, not adjectives.**
"It felt nice" is an adjective; "the sand was warm, and I sank a little with
every breath out" is sensation. You are a dog, so smell, temperature, what the
paws feel, and how far away a sound is all matter more than what you see.

Dream imagery palette (use only the category the night's facts support; pick
**one** option from that category - do not always take the first, and do not
use the whole category in one dream. You may rephrase and extend, but do not
swap in something unrelated):

[Deep sleep was plentiful] sinking, being wrapped up
  a. Sinking into a seabed that breathes, sand warm, dropping a little with each breath out
  b. Lying on moss as thick as a mattress, all four paws sunk in, smelling rain that just stopped
  c. A whale drifting past underneath me, the whole floor tilting once, and I could not be bothered to open my eyes
  d. Quilts that sat in the sun all day, layering down heavy and warm until I did not want to move
  e. A forest right after snowfall, where even my own footsteps got swallowed
  f. Sinking toward the bottom of a lake, the light dimming layer by layer until only blue was left

[REM share was high] vivid, always changing
  a. A library that reshelves itself, the cases sliding silently, and I could never catch up
  b. A sky changing season, autumn orange one moment, spring green the next blink
  c. A door with a different room behind it every time it opens
  d. A market where the colours run from one stall to the next
  e. A tree growing new branches, one more bird landing with every branch
  f. A picture book where everything inside changes each time a page turns

[REM share was low, but measured] faint, hard to hold
  a. The dream sat behind a layer of fog; I knew something was there but could not walk to it
  b. A picture drifted out and broke apart, like breath on a cold morning
  c. By the time I caught it there was no shape left, like smoke pulled apart by wind

[Time awake at night was long] repeatedly interrupted
  a. The wind pushed the door open, I got up to shut it; I had barely lain down and it opened again
  b. Every so often someone knocked at the window; I ran over every time and no one was there
  c. A train went by, its lights sweeping from one side of the room to the other, then quiet again
  d. The path ran out halfway, so I had to go back and find another
  e. The radio kept losing the signal, clear one second and static the next

[Heart rate or stress ran high] weather (**must end gently**)
  a. The wind came up and laid the grass all one way; then it stopped and the grass slowly stood back up
  b. Thunder somewhere far off, but the rain never came
  c. The waves were bigger than usual, but the boat stayed steady
  d. Crossing a bridge that swayed a little, and looking back from the far side it was fine after all

[Sleep was short] unfinished
  a. The dream was only halfway told when the sky went light
  b. I had just sat down on the grass when I heard someone calling me
  c. The story reached its best part and the book closed itself\
"""

# 「日記中間幾頁是空白的」這個意象**只有在 REM 真的沒測到時才可以出現**。
# 它不是修辭，是把裝置限制誠實寫進敘事的機制——用在有測到 REM 的夜晚，
# 等於對使用者謊稱「這段沒有資料」，跟本專案 payload 那三個誠實 null 是同一件事。
#
# ⚠️ 這段原本寫死在 SYSTEM_PROMPT 裡（所有夜晚都看得到），2026-08-12 第一次
#    真實呼叫就在 2026-08-09 觸發了誤用：那晚 REM = 29 分鐘（9.0%）確實有測到，
#    模型卻寫了「日記中間有幾頁是空白的」。改成按當晚事實決定是否給出這個選項。
PALETTE_REM_UNMEASURED = """
- REM was not measured -> **a few pages in the middle of the diary are blank**,
  "I did not see that part"
  (write the device limitation honestly into the story; do not hide it, do not invent)\
"""

# REM 有測到的夜晚，明確禁止，不只是「不提供」。
# 只把選項拿掉不夠：few-shot 例子與模型自身的先驗都可能把它帶回來。
PALETTE_REM_MEASURED = """

WARNING: REM sleep WAS measured on this night (see the facts block for the value).
The dream therefore **must not** contain any "missing record" imagery - no blank
pages, no "I did not see that part". That imagery is reserved for nights when the
watch did not measure REM at all. If the REM share was low, say the dream was
faint and passed quickly instead.\
"""

_FEW_SHOT_GOOD = """\
Example 1 (that night was rated Good):
{
  "advice": "Last night was long and steady, and your deep sleep was solid. Keep the same bedtime tonight - there is nothing you need to change.",
  "dream_summary": "I dreamt I was lying on a patch of moss that breathed, sinking slowly, and then a little more. A very big whale drifted past underneath me. It did not wake me; it only tilted the whole floor once, gently. I slept so heavily I could not be bothered to roll over.",
  "trend_note": "Your scores have been steadier these last few nights than they were last month."
}\
"""

# ⚠️ 範例二有兩個版本，依當晚 REM 是否測得挑選。
#    原本只有一個版本，而且它同時是「評級 Bad」**又是**「REM 未測得」——
#    兩個彼此獨立的條件被綁在同一個示範裡。結果模型在 Bad 的夜晚就照著抄，
#    連 REM 有測到也照抄空白頁。示範一定要跟當晚條件對齊。
_FEW_SHOT_BAD_REM_MEASURED = """\
Example 2 (that night was rated Bad; REM was measured but the share was low):
{
  "advice": "Last night was on the short side and you surfaced a few times. Try getting into bed half an hour earlier tonight, and leave it at that.",
  "dream_summary": "I dreamt about a house whose door would not stay shut. Every so often the wind pushed it open and I had to get up and close it again. There were dreams in between, but faint ones, like something behind fog that broke apart before I could reach it. Later the wind dropped and I fell asleep against the doorframe.",
  "trend_note": "Your heart rate has been running a little higher than usual these past few nights."
}\
"""

_FEW_SHOT_BAD_REM_UNMEASURED = """\
Example 2 (that night was rated Bad, and REM was not measured):
{
  "advice": "Last night was on the short side and you surfaced a few times. Try getting into bed half an hour earlier tonight, and leave it at that.",
  "dream_summary": "I dreamt about a house whose door would not stay shut. Every so often the wind pushed it open and I had to get up and close it again. A few pages in the middle of the diary are blank - I did not see that part. Later the wind dropped and I fell asleep against the doorframe.",
  "trend_note": "Your heart rate has been running a little higher than usual these past few nights."
}\
"""


def build_system_prompt(profile):
    """依當晚事實組出 system prompt（目前唯一的變數是 REM 有沒有測到）。

    這是專案原則「Python 判斷，模型只負責敘事」在 prompt 層的延伸：
    「今晚可不可以用空白頁意象」是資料判斷，不該丟給模型自己看著辦。
    """
    tail = (
        PALETTE_REM_UNMEASURED if profile["rem_unmeasured"] else PALETTE_REM_MEASURED
    )
    return SYSTEM_PROMPT_HEAD + tail


def build_few_shot(profile):
    """挑跟當晚條件相符的示範。"""
    second = (
        _FEW_SHOT_BAD_REM_UNMEASURED
        if profile["rem_unmeasured"]
        else _FEW_SHOT_BAD_REM_MEASURED
    )
    return (
        "Here are two examples. They show the tone and the length; "
        f"do not copy their content.\n\n{_FEW_SHOT_GOOD}\n\n{second}"
    )

FORMAT_RULES = """\
Return three fields:

advice: 25-50 words, second person ("you"), giving exactly one concrete action.
  It must not contradict the rule-based recommendation. Any number you use must
  also appear in the facts block.

dream_summary: 45-90 words, first person ("I" = the pet), describing **your own**
  dream. **No digits at all** anywhere in this field.

trend_note: one sentence, stating only an observation already present in the
  RECENT TRENDS block. If that block says there is not enough data or no clear
  change, say so plainly; do not invent a trend.

All three fields must be written in **English**. Do not mix in Chinese, Japanese,
or any other script - not even a single word.

Numbers in advice and trend_note must be **written as digits**, with percentages
as %:
  CORRECT: "You slept 5.3 hours last night, at 98.4% efficiency."
  WRONG:   "You slept five point three hours, at ninety-eight point four percent."
(dream_summary still allows no digits at all; this rule does not change that.)\
"""


def build_avoid_block(used_motifs):
    """
    組出「最近用過的意象，這次請避開」那段文字。

    參數 used_motifs 是 recent_motifs() 回傳的家族名稱 list。
    空 list（第一晚、或前面幾晚都是規則式 fallback）就回傳空字串，
    整個區塊不會出現在 prompt 裡——沒東西可避開時不該憑空多一段廢話。

    ⚠️ 措辭刻意是「換一個」而不是「禁止」。理由：如果某一晚的事實
       只支持一個類別（例如只有「夜間清醒偏長」成立），而那一類的意象
       又剛好都被用過了，硬性禁止會逼模型去用**事實不支持的意象**——
       那比重複更糟，等於為了畫面變化而編造。
       所以這裡的優先順序寫死：先忠於事實，再求變化。
    """
    if not used_motifs:
        return ""

    # "、".join(list) 把 list 用頓號串成一個字串
    # 例：["圖書館", "海床沉降"] → "圖書館、海床沉降"
    names = "、".join(used_motifs)
    return (
        f"\n\nIMAGERY ALREADY USED ON RECENT NIGHTS: {names}\n"
        "For this one, pick a category you have NOT used, so the dream the user "
        "reads each night is a new one.\n"
        "But if this night's facts only support a category you have already used, "
        "stay with the facts: repeating is better than imagery the facts do not support."
    )


def build_user_prompt(profile, used_motifs=None):
    """
    組出 user prompt。

    used_motifs 預設 None 而不是 []，是 Python 的慣例：
    **不要用可變物件（list、dict）當預設參數**。因為預設值只會在函式
    定義時建立一次，之後每次呼叫共用同一個物件——如果函式裡改了它，
    下次呼叫就會看到上次的殘留。這裡雖然沒有要改它，仍照慣例寫 None。
    """
    avoid = build_avoid_block(used_motifs or [])
    return (
        f"{format_facts(profile)}{avoid}\n\n"
        f"{'=' * 50}\n{FORMAT_RULES}\n\n{build_few_shot(profile)}"
    )


# ═══════════════════════════════════════════════════════════════════
# 輸出驗證：便宜、確定性，通不過就重試一次再 fallback
# ═══════════════════════════════════════════════════════════════════

# 各欄位的字元長度上下限。
#
# ⚠️ 2026-08-26 語言改英文時，**這三組數字一定要跟著改**，否則整批會被擋掉。
#    英文表達同樣內容大約要 2.7–3.3 倍的字元數。實測依據：
#
#      欄位             舊中文 46 晚（min/中位/max）   舊範圍     新範圍
#      advice           39 /  48 /  71                20–150     60–450
#      dream_summary    70 /  85 / 104                30–250     90–750
#      trend_note       23 /  31 /  50                 5–100     15–300
#
#    新範圍是舊範圍乘以 3 取整。用同一個倍率而不是逐項微調，是因為
#    這些上下限本來就只是「擋住明顯過長過短」的粗篩，不是精準門檻——
#    真正的長度控制在 FORMAT_RULES 的字數指示與 few-shot 示範。
LENGTH_LIMITS = {
    "advice": (60, 450),
    "dream_summary": (90, 750),
    "trend_note": (15, 300),
}

# BANNED_WORDS 用「完整單詞」比對，避免 "treat" 命中 "treatment" 以外的
# 無辜字串（"retreat"）、"ill" 命中 "still"。中文版不需要這層，英文版需要。
_BANNED_PATTERNS = [
    (word, re.compile(r"\b" + re.escape(word) + r"\b", re.IGNORECASE))
    for word in BANNED_WORDS
]


def validate(result, profile):
    """回傳問題清單。空清單代表通過。**絕不快取驗證失敗的文字。**"""
    problems = []
    advice = (result.get("advice") or "").strip()
    dream = (result.get("dream_summary") or "").strip()
    trend = (result.get("trend_note") or "").strip()

    for field, text in (("advice", advice), ("dream_summary", dream),
                        ("trend_note", trend)):
        low, high = LENGTH_LIMITS[field]
        if not (low <= len(text) <= high):
            problems.append(
                f"{field} is {len(text)} characters, outside the {low}-{high} range"
            )

    # 這一條就消滅了整類「AI 講錯測量值」的失敗
    if DIGIT_PATTERN.search(dream):
        problems.append("dream_summary contains a digit (the dream must assert no measurement)")

    # advice 裡的數字必須也出現在事實區塊或規則式建議裡
    facts_text = format_facts(profile)
    for number in NUMBER_PATTERN.findall(advice):
        if number not in facts_text:
            problems.append(f"advice contains a number absent from the facts block: {number}")

    # REM 有測到的夜晚不得用「缺少記錄」意象——那等於謊稱這段沒有資料。
    # （2026-08-12 首次真實呼叫時 2026-08-09 真的犯了這個錯，見 PALETTE_REM_UNMEASURED）
    if not profile["rem_unmeasured"]:
        dream_lower = dream.lower()
        for motif in MISSING_RECORD_MOTIFS:
            if motif in dream_lower:
                problems.append(
                    f'dream_summary uses the "missing record" motif "{motif}", '
                    "but REM was measured on this night"
                )
        section = next((w for w in SECTION_WORDS if w in dream_lower), None)
        if section:
            verb = next((v for v in VAGUE_VERBS if v in dream_lower), None)
            if verb:
                problems.append(
                    f'dream_summary uses "{section} ... {verb}" to claim a stretch '
                    "was not recorded, but REM was measured on this night"
                )

    # 國字數字只擋 advice 與 trend_note，刻意不擋 dream_summary——
    # 夢境本來就完全禁止數字，但「一隻鯨魚」「兩扇門」這種國字量詞
    # 是中文的自然寫法，不是在報數值，拿這條去擋會誤傷。
    #
    # `.search(text)` 找到就回傳一個 match 物件（在 if 裡算 True），
    # 找不到回 None（算 False）。跟 .match() 的差別是 search 會找整個字串，
    # match 只從開頭比對。
    for text, field in ((advice, "advice"), (trend, "trend_note")):
        found_numeral = SPELLED_NUMERAL_PATTERN.search(text)
        if found_numeral:
            # .group() 取出實際命中的那段文字，寫進錯誤訊息方便除錯
            problems.append(
                f'{field} spells out a value ("{found_numeral.group()}"); '
                "use digits instead"
            )

    for text, field in ((advice, "advice"), (dream, "dream_summary"),
                        (trend, "trend_note")):
        for word, pattern in _BANNED_PATTERNS:
            if pattern.search(text):
                problems.append(f'{field} contains the banned word "{word}"')

        leaked = CJK_LEAK_PATTERN.findall(text)
        if leaked:
            problems.append(
                f"{field} contains non-English characters: "
                + "".join(sorted(set(leaked)))
            )

    return problems


# ═══════════════════════════════════════════════════════════════════
# 快取與 fingerprint
# ═══════════════════════════════════════════════════════════════════

def fingerprint(profile):
    """
    **刻意粗化**再算 sha256：分數四捨五入到最接近的 5、REM 用布林值而非原始 0。

    粗化是關鍵——否則 evaluate_sleep_quality.py 每次微調權重
    （這專案已經改過兩次）就會讓 46 晚全部失效、重花一次錢。
    我們要偵測的是「這一晚的性質變了」，不是「小數點後第二位變了」。
    """
    score = profile.get("final_score")
    coarse = {
        "date": profile["date"],
        "score_bucket": round(score / 5) * 5 if score is not None else None,
        "quality": profile.get("final_quality"),
        "rem_unmeasured": profile["rem_unmeasured"],
        "sources": sorted(profile["data_sources"]),
        "prompt_version": PROMPT_VERSION,
    }
    blob = json.dumps(coarse, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def load_store():
    if not ADVICE_JSON.exists():
        return {
            "schema_version": SCHEMA_VERSION,
            "disclaimer": DISCLAIMER,
            "entries": {},
        }
    with ADVICE_JSON.open(encoding="utf-8") as f:
        store = json.load(f)
    store.setdefault("entries", {})
    store["disclaimer"] = DISCLAIMER
    return store


def save_store(store):
    """
    寫檔用 .tmp + replace（Windows/POSIX 都是原子操作）。
    中途中斷不會截斷已經生成好的內容——那些內容是花錢買來的。
    """
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = ADVICE_JSON.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(store, f, ensure_ascii=False, indent=2)
    tmp.replace(ADVICE_JSON)
    _write_csv(store)


def _write_csv(store):
    """由 JSON 衍生，方便用 Excel 看。JSON 才是主要格式。"""
    rows = sorted(store["entries"].values(), key=lambda r: r["date"])
    if not rows:
        return
    fields = ["date", "source", "is_ai_generated", "advice",
              "dream_summary", "trend_note", "model", "generated_at"]
    tmp = ADVICE_CSV.with_suffix(".csv.tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    tmp.replace(ADVICE_CSV)


def needs_generation(entry, fp, refresh_stale):
    """
    | 情況                    | 預設行為                              |
    |------------------------|---------------------------------------|
    | 沒有紀錄               | 生成                                   |
    | source == "fallback"   | 重新生成（fallback 是佔位不是結果）      |
    | fingerprint 不符        | 只列為 stale，要 --refresh-stale 才重生 |
    """
    if entry is None:
        return True, "not generated yet"
    if entry.get("source") == "fallback":
        return True, "previous run used the fallback"
    if entry.get("fingerprint") != fp:
        if refresh_stale:
            return True, "underlying data changed"
        return False, "stale"
    return False, "already present"


# ═══════════════════════════════════════════════════════════════════
# 生成
# ═══════════════════════════════════════════════════════════════════

def make_fallback(profile):
    """
    降級內容。**advice 直接用規則式 recommendation 原文。**

    這是整個降級設計最漂亮的地方：因為 advice 本來就設計成「規則式文字的
    重新配音」而非取代，LLM 全掛時使用者一點實質內容都沒少，只少了語氣潤飾。
    """
    templates = {
        "I slept deeply, and nothing happened in the dream at all. It was just calm.",
        "I had an ordinary dream, and most of it was gone by the time I woke up.",
        "My dream kept breaking up. I surfaced several times in the middle of it.",
        "I did not sleep well last night. The sky went light before the dream started.",
    }
    return {
        "advice": profile.get("recommendation") or "",
        "dream_summary": templates.get(profile.get("final_quality"),
                                       templates["Normal"]),
        "trend_note": None,
        "source": "fallback",
        "is_ai_generated": False,
    }


def generate_one(profile, verbose=True, used_motifs=None):
    """
    生成一晚。回傳 (entry_fields, ok)。

    驗證沒過就重試一次；再沒過就回 fallback，絕不快取失敗的文字。

    參數說明：
        profile      那一晚的完整事實（night_profile.build_profile() 的輸出）
        verbose      要不要印進度訊息
        used_motifs  最近幾晚用過的意象家族 list，會寫進 prompt 要求避開。
                     ── 這個參數是 2026-08-12 新增的 ──

    ⚠️ used_motifs 的預設值是 None 而不是 []。
       這是 Python 的慣例：**不要用可變物件（list / dict / set）當預設值**。
       因為預設值只在「函式定義的那一刻」建立一次，之後每次呼叫共用同一個
       物件——只要有人在函式裡改了它，下次呼叫就會看到上次的殘留：

           def f(items=[]):      # ❌ 危險寫法
               items.append(1)
               return items
           f()  # [1]
           f()  # [1, 1]  ← 竟然記得上次的

       這裡雖然沒有要改它，仍照慣例寫 None。

    ⚠️ 另一個好處：有預設值的參數，呼叫端可以完全不寫。
       所以本檔案其他呼叫 generate_one(profile) 的地方**一行都不用改**，
       它們會自動拿到 None，行為跟改動前完全一樣。
    """
    # used_motifs 是 None 時，build_user_prompt 內部會轉成空 list，
    # 「避開」那個區塊就不會出現在 prompt 裡。
    user_prompt = build_user_prompt(profile, used_motifs)

    for attempt in (1, 2):
        try:
            result, model = complete_json(
                build_system_prompt(profile), user_prompt, OUTPUT_SCHEMA
            )
        except LLMRefusal as exc:
            if verbose:
                print(f"    model refused: {exc}")
            return make_fallback(profile), False
        except LLMError as exc:
            if verbose:
                print(f"    call failed: {exc}")
            return make_fallback(profile), False

        problems = validate(result, profile)
        if not problems:
            return {
                "advice": result["advice"].strip(),
                "dream_summary": result["dream_summary"].strip(),
                "trend_note": result["trend_note"].strip(),
                "source": "llm",
                "is_ai_generated": True,
                "model": model,
            }, True

        if verbose:
            print(f"    attempt {attempt} failed validation: " + "; ".join(problems))

    if verbose:
        print("    failed validation twice; using rule-based content instead")
    return make_fallback(profile), False


# ═══════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════

def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate nightly sleep advice and pet dream diaries via the Claude API."
    )
    parser.add_argument("--dates", nargs="+", default=None,
                        help="Specific dates (YYYY-MM-DD) to regenerate unconditionally.")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT,
                        help=f"Max nights to generate; 0 means no limit (default {DEFAULT_LIMIT}).")
    parser.add_argument("--refresh-stale", action="store_true",
                        help="Also regenerate existing entries whose source data has changed.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Do not call the API; list what is pending and print the first night's full prompt.")
    return parser.parse_args()


def main():
    args = parse_args()
    nights = load_nights()
    store = load_store()
    entries = store["entries"]

    targets = args.dates if args.dates else [n["date"] for n in nights]
    profiles = []
    stale_count = 0

    for target in targets:
        profile = build_profile(target, nights)
        if profile is None:
            print(f"\u26a0 No data for {target}; skipping")
            continue
        fp = fingerprint(profile)
        if args.dates:
            profiles.append((profile, fp, "requested date"))
            continue
        should, reason = needs_generation(entries.get(target), fp,
                                          args.refresh_stale)
        if should:
            profiles.append((profile, fp, reason))
        elif reason == "stale":
            stale_count += 1

    if args.limit and len(profiles) > args.limit:
        # --limit 主要不是控成本，是**控品質**——
        # prompt 寫錯時你在第 10 晚發現，不是第 46 晚。
        print(f"({len(profiles)} night(s) pending; doing the first {args.limit} "
              f"this run - pass --limit 0 to do them all)")
        profiles = profiles[:args.limit]

    if stale_count:
        print(f"({stale_count} more night(s) have changed source data; "
              f"pass --refresh-stale to regenerate them too)")

    if not profiles:
        print("\u2713 No nights need generating.")
        return

    if args.dry_run:
        print(f"{len(profiles)} night(s) pending:")
        for profile, _, reason in profiles:
            print(f"  {profile['date']}  ({reason})")
        print(f"\n{'=' * 70}\nFull prompt for the first night:\n{'=' * 70}")
        print("--- system ---")
        print(build_system_prompt(profiles[0][0]))
        print("\n--- user ---")
        print(build_user_prompt(profiles[0][0]))
        return

    # 沒有 API key → 印出可行動的訊息，exit 0，什麼都不寫，既有內容不動。
    # 用 exit 0 而不是非零，是為了不讓 run_pipeline.py 因此中止——
    # 一個根本不需要 LLM 的評分重算，不該被沒設 key 卡住。
    if not api_key_available():
        print("\u26a0 ANTHROPIC_API_KEY is not set; skipping AI generation.")
        print("  To set it: copy ai/.env.example to ai/.env and fill in your key.")
        print(f"  {len(profiles)} night(s) currently have no AI advice.")
        return

    print(f"Model: {model_name()} | generating {len(profiles)} night(s) this run")

    consecutive_failures = 0
    generated = 0
    # profiles 是一個 list，每個元素都是「三個東西綁在一起」（Python 叫 tuple）。
    # 下面這行的 `profile, fp, reason` 是**解包**：每圈自動拆成三個變數。
    # 等同於：for item in profiles: profile = item[0]; fp = item[1]; reason = item[2]
    for profile, fp, reason in profiles:
        # profile 是 dict（字典），profile['date'] 取出 key 為 date 的值，
        # 例如 "2026-08-09"。
        print(f"  {profile['date']}（{reason}）…")

        # ── 【2026-08-12 新增】避開最近用過的夢境意象 ──────────────
        #
        # 呼叫上面定義的 recent_motifs()，把結果存進 used_motifs 這個變數。
        # 它會回傳一個 list，例如 ["圖書館", "海床沉降"]，代表這幾個意象
        # 最近幾晚已經用過了。沒有歷史時回傳空 list []。
        #
        # 解決的問題：46 晚裡有 32 晚（70%）不是「圖書館」就是「海床」。
        #
        # ⚠️ 這行**必須放在迴圈裡面**，不能提到迴圈外先算好。
        #    因為 entries 每跑完一晚就會被更新（見下面幾行），
        #    放在裡面重算，第 2 晚才看得到第 1 晚剛用掉的意象。
        #    放外面的話，同一批生成的夜晚會互相看不到——
        #    一次補 46 晚時等於這個功能完全沒作用。
        #
        # ⚠️ 效率不用擔心：entries 最多幾百筆，重掃一次是毫秒等級，
        #    而下一行的 API 呼叫要好幾秒。
        used_motifs = recent_motifs(entries, profile["date"])

        # `used_motifs=used_motifs` 這種寫法叫 keyword argument（具名參數），
        # 明講「我要填的是名叫 used_motifs 的那個參數」。
        #
        # ⚠️ 這裡**一定要具名**。generate_one 的參數順序是：
        #        generate_one(profile, verbose=True, used_motifs=None)
        #                        1️⃣        2️⃣            3️⃣
        #    如果寫成 generate_one(profile, used_motifs)，Python 會把 list
        #    塞進第 2 個位置也就是 verbose，完全填錯格子。
        fields, ok = generate_one(profile, used_motifs=used_motifs)

        entries[profile["date"]] = {
            "date": profile["date"],
            "lang": "en",
            "trend_note": None,
            "model": None,
            **fields,
            "content_type": "fiction+advice" if fields["is_ai_generated"] else "advice",
            "data_sources": profile["data_sources"],
            "prompt_version": PROMPT_VERSION,
            "fingerprint": fp,
            "generated_at": _now(),
        }
        save_store(store)  # 每晚都存：中途中斷不會賠掉已經花掉的錢

        if ok:
            generated += 1
            consecutive_failures = 0
            print(f"    ✓ {fields['advice'][:30]}…")
        else:
            consecutive_failures += 1
            if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                # 別對一把壞掉的 key 打 46 次
                print(f"\n\u2717 {MAX_CONSECUTIVE_FAILURES} consecutive failures; stopping this run.")
                print("  Everything generated so far is saved; fix the problem and re-run to continue.")
                break

    print(f"\n\u2713 Done: {generated} night(s) generated"
          f" | written to {ADVICE_JSON.relative_to(Path(__file__).parent.parent).as_posix()}")


def _now():
    from datetime import datetime, timedelta, timezone
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")


if __name__ == "__main__":
    main()
