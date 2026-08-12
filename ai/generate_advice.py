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
# v2（2026-08-12）：調色盤與 few-shot 改成依當晚 REM 是否測得動態組裝。
# 這個字串進 fingerprint，所以改版號會讓既有紀錄全部標記為 stale，
# 用 --refresh-stale 就能重新生成——prompt 變了，舊內容本來就該重來。
PROMPT_VERSION = "v2"
DEFAULT_LIMIT = 10
MAX_CONSECUTIVE_FAILURES = 3

DISCLAIMER = (
    "夢境日記為 AI 依睡眠數據想像的創作，非使用者實際夢境的紀錄；"
    "建議內容不構成醫療診斷。"
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
BANNED_WORDS = [
    "診斷", "治療", "失眠症", "憂鬱症", "焦慮症", "藥物", "服藥",
    "疾病", "症候群", "就醫", "病人", "患者",
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
    "空白", "留白", "沒有記錄", "沒被記下", "缺了一段", "沒看見",
]

# 這些動詞本身無害，只有跟「指出某一段」的詞連用時，才構成「那段沒有資料」的宣稱。
VAGUE_VERBS = ["沒看清", "沒記住", "想不起來", "沒印象"]
SECTION_WORDS = ["那一段", "那段", "中間", "有幾頁", "那陣子"]

# 簡體字洩漏偵測。輸出固定是 zh-TW（見下方 entries 的 "lang"），
# 但模型偶爾會混進簡體字形——2026-08-12 用 claude-sonnet-5 生成 2026-08-09
# 就寫出「門边」（門是正體、边是簡體），同一個詞裡兩種字形。
#
# 只列「簡體獨有、正體中文不可能出現」的字，所以不會誤判。
# 不做全表轉換：那需要第三方套件（opencc），違反專案「非必要不加依賴」的規範，
# 而且我們要的是**擋下來重試**，不是偷偷替換成正體——偷偷改會蓋掉問題。
#
# ⚠️ 刻意**不含** 于／后／里 這類「簡體與正體同形、正體中文本來就會用」的字
#    （皇后、公里、于姓）。誤判的代價不小：驗證連兩次不過就整晚退回規則式文字。
SIMPLIFIED_CHARS = set(
    "边门发关国爱这来时会说个们对为体现实点从样种儿头长东车马鸟"
    "书买卖问间闻开无与业丝乐产亲见觉论证识语读话该谁请谢贝页风飞"
    "汉难鸡鸭鱼鲜龙齿声学习写农军变复够条丽举义乡乌"
)

DIGIT_PATTERN = re.compile(r"[0-9０-９]")
NUMBER_PATTERN = re.compile(r"\d+(?:\.\d+)?")


# ═══════════════════════════════════════════════════════════════════
# Prompt
# ═══════════════════════════════════════════════════════════════════

SYSTEM_PROMPT_HEAD = """\
你是使用者的虛擬寵物，陪著他一起睡覺。你要用溫暖、簡短、像朋友的語氣說話。

絕對規則：
1. 夢境是**你自己（寵物）做的夢**。絕不宣稱知道使用者夢到什麼——
   手錶完全沒有量測夢境內容，那樣講就是誤述資料。
2. 不得有任何醫療宣稱、診斷、疾病名稱或藥物建議。
3. 不得讓使用者感到羞辱、愧疚或恐懼；不使用惡夢意象。
   使用者本來就睡不好，讓他有罪惡感只會讓情況更糟。
4. 不得陳述事實區塊裡沒有的資訊。所有數值與門檻都只能來自事實區塊，
   不可以自己推算、換算或補充。
5. 你的建議不得與「規則式建議原文」矛盾。你是把它重新講一遍並加上趨勢觀察，
   不是取代它。

夢境意象調色盤（只能使用當晚事實支持的意象）：
- 深層睡眠充足 → 靜止下沉的意象：溫暖的海床、厚厚的苔蘚、緩慢呼吸的鯨魚
- REM 比例高 → 鮮明流動的意象：會自己重新排列的圖書館、換季的天空
- 夜間清醒偏長 → 夢一直被打斷、門一直被推開
- 心率或壓力偏高 → 夢裡的天氣（起風、開得很快的車），但一定要溫和收尾
- 睡眠時間偏短 → 夢還沒說完就天亮了\
"""

# 「日記中間幾頁是空白的」這個意象**只有在 REM 真的沒測到時才可以出現**。
# 它不是修辭，是把裝置限制誠實寫進敘事的機制——用在有測到 REM 的夜晚，
# 等於對使用者謊稱「這段沒有資料」，跟本專案 payload 那三個誠實 null 是同一件事。
#
# ⚠️ 這段原本寫死在 SYSTEM_PROMPT 裡（所有夜晚都看得到），2026-08-12 第一次
#    真實呼叫就在 2026-08-09 觸發了誤用：那晚 REM = 29 分鐘（9.0%）確實有測到，
#    模型卻寫了「日記中間有幾頁是空白的」。改成按當晚事實決定是否給出這個選項。
PALETTE_REM_UNMEASURED = """
- REM 未測得 → **日記中間幾頁是空白的**、「那一段我沒看見」
  （把裝置限制誠實地寫進敘事，不要隱藏也不要編造）\
"""

# REM 有測到的夜晚，明確禁止，不只是「不提供」。
# 只把選項拿掉不夠：few-shot 例子與模型自身的先驗都可能把它帶回來。
PALETTE_REM_MEASURED = """

⚠️ 這一晚的 REM 睡眠**有測到**（數值見事實區塊）。因此夢境中**不得**出現
「日記有空白頁」「那一段我沒看見」這類「缺少記錄」的意象——那是專門保留給
手錶沒測到 REM 的夜晚用的。REM 比例低要用「夢很淡、很快就過去」之類的說法。\
"""

_FEW_SHOT_GOOD = """\
範例一（那晚評級 Good）：
{
  "advice": "昨晚睡得又長又穩，深層睡眠也很扎實。今晚維持一樣的就寢時間就好，不用特別做什麼。",
  "dream_summary": "我夢見自己趴在一片會呼吸的苔蘚上，慢慢地沉下去、沉下去。有一隻很大的鯨魚從我下面游過，牠沒有吵醒我，只是讓整片地面輕輕晃了一下。我睡得好沉，連翻身都懶。",
  "trend_note": "這幾晚的睡眠分數比前一個月穩定一些。"
}\
"""

# ⚠️ 範例二有兩個版本，依當晚 REM 是否測得挑選。
#    原本只有一個版本，而且它同時是「評級 Bad」**又是**「REM 未測得」——
#    兩個彼此獨立的條件被綁在同一個示範裡。結果模型在 Bad 的夜晚就照著抄，
#    連 REM 有測到也照抄空白頁。示範一定要跟當晚條件對齊。
_FEW_SHOT_BAD_REM_MEASURED = """\
範例二（那晚評級 Bad，REM 有測到但比例偏低）：
{
  "advice": "昨晚睡得比較短，中間也醒了幾次。今晚試著提早半小時上床，其他先別想太多。",
  "dream_summary": "我夢見一間門關不緊的房子，風每隔一陣子就把門推開一次，我只好爬起來再去關。中間有做夢，可是很淡，像隔著一層霧，還沒看清楚就散掉了。後來風停了，我就靠在門邊睡著了。",
  "trend_note": "最近幾晚的心率比先前偏高一些。"
}\
"""

_FEW_SHOT_BAD_REM_UNMEASURED = """\
範例二（那晚評級 Bad，且 REM 未測得）：
{
  "advice": "昨晚睡得比較短，中間也醒了幾次。今晚試著提早半小時上床，其他先別想太多。",
  "dream_summary": "我夢見一間門關不緊的房子，風每隔一陣子就把門推開一次，我只好爬起來再去關。日記中間有幾頁是空白的，那一段我沒看見。後來風停了，我就靠在門邊睡著了。",
  "trend_note": "最近幾晚的心率比先前偏高一些。"
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
    return f"以下是兩個示範，示範語氣與長度，不要照抄內容。\n\n{_FEW_SHOT_GOOD}\n\n{second}"

FORMAT_RULES = """\
輸出三個欄位：

advice：40–80 字，第二人稱（你），恰好給一個具體可執行的動作。
  不得與規則式建議原文矛盾。出現的任何數字都必須也出現在事實區塊裡。

dream_summary：60–120 字，第一人稱（我＝寵物），描述**你自己**的夢。
  **完全不得出現任何數字**（阿拉伯數字與全形數字都不行）。

trend_note：一句話，只能陳述【近期趨勢】區塊裡已經有的觀察。
  若該區塊說資料不足或沒有明顯變化，就照實說，不要編造趨勢。

三個欄位一律用**臺灣正體中文**，不得混入任何簡體字形
（例：要寫「門邊」不是「門边」、「時間」不是「时间」）。\
"""


def build_user_prompt(profile):
    return (
        f"{format_facts(profile)}\n\n"
        f"{'=' * 50}\n{FORMAT_RULES}\n\n{build_few_shot(profile)}"
    )


# ═══════════════════════════════════════════════════════════════════
# 輸出驗證：便宜、確定性，通不過就重試一次再 fallback
# ═══════════════════════════════════════════════════════════════════

def validate(result, profile):
    """回傳問題清單。空清單代表通過。**絕不快取驗證失敗的文字。**"""
    problems = []
    advice = (result.get("advice") or "").strip()
    dream = (result.get("dream_summary") or "").strip()
    trend = (result.get("trend_note") or "").strip()

    if not (20 <= len(advice) <= 150):
        problems.append(f"advice 長度 {len(advice)} 字，超出 20–150 範圍")
    if not (30 <= len(dream) <= 250):
        problems.append(f"dream_summary 長度 {len(dream)} 字，超出 30–250 範圍")
    if not (5 <= len(trend) <= 100):
        problems.append(f"trend_note 長度 {len(trend)} 字，超出 5–100 範圍")

    # 這一條就消滅了整類「AI 講錯測量值」的失敗
    if DIGIT_PATTERN.search(dream):
        problems.append("dream_summary 含有數字（夢境不得斷言任何測量值）")

    # advice 裡的數字必須也出現在事實區塊或規則式建議裡
    facts_text = format_facts(profile)
    for number in NUMBER_PATTERN.findall(advice):
        if number not in facts_text:
            problems.append(f"advice 出現事實區塊裡沒有的數字：{number}")

    # REM 有測到的夜晚不得用「缺少記錄」意象——那等於謊稱這段沒有資料。
    # （2026-08-12 首次真實呼叫時 2026-08-09 真的犯了這個錯，見 PALETTE_REM_UNMEASURED）
    if not profile["rem_unmeasured"]:
        for motif in MISSING_RECORD_MOTIFS:
            if motif in dream:
                problems.append(
                    f"dream_summary 用了「缺少記錄」意象「{motif}」，"
                    "但這晚 REM 有測到"
                )
        section = next((w for w in SECTION_WORDS if w in dream), None)
        if section:
            verb = next((v for v in VAGUE_VERBS if v in dream), None)
            if verb:
                problems.append(
                    f"dream_summary 用「{section}…{verb}」指稱某一段沒有記錄，"
                    "但這晚 REM 有測到"
                )

    for text, field in ((advice, "advice"), (dream, "dream_summary"),
                        (trend, "trend_note")):
        for word in BANNED_WORDS:
            if word in text:
                problems.append(f"{field} 含禁詞「{word}」")

        found = sorted(set(text) & SIMPLIFIED_CHARS)
        if found:
            problems.append(f"{field} 含簡體字：{'、'.join(found)}")

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
        return True, "尚未生成"
    if entry.get("source") == "fallback":
        return True, "上次是 fallback"
    if entry.get("fingerprint") != fp:
        if refresh_stale:
            return True, "資料已變動"
        return False, "stale"
    return False, "已存在"


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
        "Good": "我睡得很沉，夢裡什麼都沒發生，就是很安穩。",
        "Normal": "我做了一個普通的夢，醒來就忘了大半。",
        "Poor": "我的夢斷斷續續的，中間醒了好幾次。",
        "Bad": "昨晚我沒睡好，夢還沒開始就天亮了。",
    }
    return {
        "advice": profile.get("recommendation") or "",
        "dream_summary": templates.get(profile.get("final_quality"),
                                       templates["Normal"]),
        "trend_note": None,
        "source": "fallback",
        "is_ai_generated": False,
    }


def generate_one(profile, verbose=True):
    """
    生成一晚。回傳 (entry_fields, ok)。

    驗證沒過就重試一次；再沒過就回 fallback，絕不快取失敗的文字。
    """
    user_prompt = build_user_prompt(profile)

    for attempt in (1, 2):
        try:
            result, model = complete_json(
                build_system_prompt(profile), user_prompt, OUTPUT_SCHEMA
            )
        except LLMRefusal as exc:
            if verbose:
                print(f"    模型拒絕回應：{exc}")
            return make_fallback(profile), False
        except LLMError as exc:
            if verbose:
                print(f"    呼叫失敗：{exc}")
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
            print(f"    第 {attempt} 次輸出未通過驗證：{'；'.join(problems)}")

    if verbose:
        print("    兩次都沒通過驗證，改用規則式內容")
    return make_fallback(profile), False


# ═══════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════

def parse_args():
    parser = argparse.ArgumentParser(
        description="用 Claude API 產生每晚的睡眠建議與寵物夢境日記。"
    )
    parser.add_argument("--dates", nargs="+", default=None,
                        help="指定日期（YYYY-MM-DD），無條件重新生成。")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT,
                        help=f"最多生成幾晚，0 代表不限（預設 {DEFAULT_LIMIT}）。")
    parser.add_argument("--refresh-stale", action="store_true",
                        help="連同資料已變動的舊紀錄一併重新生成。")
    parser.add_argument("--dry-run", action="store_true",
                        help="不呼叫 API，只印出待生成清單與第一晚的完整 prompt。")
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
            print(f"⚠ 找不到 {target} 的資料，略過")
            continue
        fp = fingerprint(profile)
        if args.dates:
            profiles.append((profile, fp, "指定日期"))
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
        print(f"（待生成 {len(profiles)} 晚，本次只做前 {args.limit} 晚；"
              f"加 --limit 0 可全部補完）")
        profiles = profiles[:args.limit]

    if stale_count:
        print(f"（另有 {stale_count} 晚的來源資料已變動，"
              f"加 --refresh-stale 可一併重生）")

    if not profiles:
        print("✓ 沒有需要生成的夜晚。")
        return

    if args.dry_run:
        print(f"待生成 {len(profiles)} 晚：")
        for profile, _, reason in profiles:
            print(f"  {profile['date']}  （{reason}）")
        print(f"\n{'=' * 70}\n第一晚的完整 prompt：\n{'=' * 70}")
        print("--- system ---")
        print(build_system_prompt(profiles[0][0]))
        print("\n--- user ---")
        print(build_user_prompt(profiles[0][0]))
        return

    # 沒有 API key → 印出可行動的訊息，exit 0，什麼都不寫，既有內容不動。
    # 用 exit 0 而不是非零，是為了不讓 run_pipeline.py 因此中止——
    # 一個根本不需要 LLM 的評分重算，不該被沒設 key 卡住。
    if not api_key_available():
        print("⚠ 未設定 ANTHROPIC_API_KEY，跳過 AI 生成。")
        print("  設定方式：複製 ai/.env.example 成 ai/.env 並填入金鑰。")
        print(f"  目前有 {len(profiles)} 晚尚未生成 AI 建議。")
        return

    print(f"使用模型：{model_name()}｜本次生成 {len(profiles)} 晚")

    consecutive_failures = 0
    generated = 0
    for profile, fp, reason in profiles:
        print(f"  {profile['date']}（{reason}）…")
        fields, ok = generate_one(profile)

        entries[profile["date"]] = {
            "date": profile["date"],
            "lang": "zh-TW",
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
                print(f"\n✗ 連續失敗 {MAX_CONSECUTIVE_FAILURES} 次，停止本輪。")
                print("  已生成的內容都已存檔，修正問題後再跑一次即可續做。")
                break

    print(f"\n✓ 完成：成功 {generated} 晚"
          f"｜輸出 {ADVICE_JSON.relative_to(Path(__file__).parent.parent).as_posix()}")


def _now():
    from datetime import datetime, timedelta, timezone
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")


if __name__ == "__main__":
    main()
