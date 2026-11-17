"""
ai/text_guards.py —— AI 輸出的共用驗證規則（2026-11-18 從 generate_advice.py 搬出來）。

用的人：睡眠助理（ai/chat.py）與寵物 notes（ai/night_summary.py，經 chat.validate_answer）。
夢境日記退場（2026-11-17 改成寵物 notes）之後，這幾條規則是唯一還在用的部分，所以單獨留下。

⚠️ 只能有這一份。兩份禁詞清單漂移時，一邊擋得住的詞另一邊擋不住，而且不會有任何錯誤訊息。
⚠️ 驗證寫寬很省事，但誤判的代價是使用者拿不到答案（CLAUDE.md 方法論第 5 點）。
   這裡每一條都**收窄過**，改之前先讀那一條的說明。
"""
import re

# 禁詞：針對「本來就睡不好的學生」這個目標族群，避免醫療宣稱與罪惡感。
# ⚠️ 2026-08-26 語言改英文之後，這份清單是重寫的不是翻譯的。英文要考慮詞形變化與子字串誤傷，
#    所以呼叫端一律用「完整單詞」比對（\b...\b），不是 `word in text`——
#    否則 "ill" 會命中 "still"、"treat" 會命中 "retreat"。
BANNED_WORDS = [
    "diagnose", "diagnosis", "diagnostic", "treat", "treatment", "cure",
    "insomnia", "depression", "depressive", "anxiety disorder", "apnea",
    "medication", "medicine", "drug", "drugs", "pill", "pills",
    "disease", "disorder", "syndrome", "patient", "patients",
    "prescribe", "prescription", "therapy", "clinical diagnosis",
]

# 語言洩漏：輸出固定英文，模型可能漂回中文、或在英文句子裡夾一個中文詞。
# 原本（輸出是中文的時候）擋的是「混進簡體字形」——2026-08-12 真的發生過「門边」。
# 改英文之後同一類失敗換成「出現任何 CJK 字元」。
# 涵蓋：CJK 統一漢字、平假名／片假名、CJK 標點與全形字元。
# 保留「擋下來重試」而不是自動清掉的原則：偷偷改會蓋掉問題。
CJK_LEAK_PATTERN = re.compile(
    r"[　-〿぀-ヿ㐀-䶿一-鿿豈-﫿＀-￯]"
)

# 「數字要在事實裡」比對用：抓出文字裡的每一個數。
NUMBER_PATTERN = re.compile(r"\d+(?:\.\d+)?")

# 拼字小數："you slept ten point three hours" 這種。
# 起因：舊的夢境日記 46 晚裡有 4 晚寫成「十點三小時」，同一個 App 裡兩種寫法看起來很怪。
#
# ⚠️ **必須有 point 才擋**，這條收窄過、不要改回去：
#    第一版寫成「數字詞＋單位」就擋，結果「十分安穩」（＝非常安穩）被誤判。
#    實際出問題的全都是**小數**；整數的數字詞（"give it one more try"、"half an hour earlier"、
#    "a couple of nights"）是自然英文，不是在報數值。英文的數字詞也是常用字，更要守住這個條件。
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
