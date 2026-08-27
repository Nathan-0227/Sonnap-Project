"""
tests/test_scoring_guards.py

三個「安靜失效」的機制的回歸防護。這一支測的不是「算得對不對」，
而是**保護那些壞掉時不會報錯的東西**——2026-08-28 那一輪修的三個問題，
每一個在修之前都是「程式照跑、沒有錯誤訊息、結果安靜地錯」。

  【1】summary 的有效性判準不得在兩支腳本之間漂移
  【2】沒量到睡眠的夜晚，睡眠衍生的量不得進 baseline
  【3】baseline 窗格是「日曆天」不是「筆數」
  【4】MOTIF_FAMILIES 必須與夢境調色盤的選項一對一

執行：python tests/test_scoring_guards.py
"""
import copy
import csv
import importlib.util
import io
import re
import sys
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def load_script(path):
    """
    以模組方式載入 pipeline 腳本。

    garmin/ 底下五支是**各自獨立的行程**（run_pipeline.py 分別呼叫），
    刻意不是 package、也不互相 import。測試要同時看兩支，
    所以用 importlib 直接載檔，而不是把它們變成可 import 的結構——
    測試的需求不應該回過頭改變被測程式的架構。
    """
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


arm = load_script(ROOT / "garmin" / "apply_recovery_modifier.py")
esf = load_script(ROOT / "garmin" / "extract_sleep_features.py")
gad = load_script(ROOT / "ai" / "generate_advice.py")

SUMMARY = ROOT / "garmin" / "data" / "garmin_sleep_summary.csv"

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<44} 得到 {got!r:<10} 期望 {want!r}")
    if not ok:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<44} {extra}")
    if not cond:
        fails.append(label)


def read_summary():
    # utf-8-sig：這些 CSV 帶 BOM（專案規定輸出一律 UTF-8）
    with io.open(SUMMARY, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


rows = read_summary()

print("=" * 78)
print("【1】兩支腳本的有效性判準不得漂移")
print("=" * 78)
# apply_recovery_modifier 讀未過濾的 summary，所以自己有一份 has_measured_sleep()；
# extract_sleep_features 有 is_valid_night()。兩份判準必須對同一份資料給相同答案。
# 它們刻意沒有互相 import（見 has_measured_sleep 的 docstring），
# 所以漂移不會有任何錯誤訊息——只會有兩套不一致的「哪些夜晚算數」。
disagree = []
for r in rows:
    a = arm.has_measured_sleep(r)
    b, _ = esf.is_valid_night(r)
    if a != b:
        disagree.append((r.get("date"), a, b))

print(f"  summary 列數：{len(rows)}")
check("兩邊判斷不一致的列數", len(disagree), 0)
if disagree:
    for d in disagree[:5]:
        print(f"      {d}")
n_valid = sum(1 for r in rows if arm.has_measured_sleep(r))
ok("有效夜晚數 > 0 且 < 總列數（判準真的有在濾）",
   0 < n_valid < len(rows), f"{n_valid} / {len(rows)}")

print()
print("=" * 78)
print("【2】沒量到睡眠的夜晚，睡眠衍生的量不得進 baseline")
print("=" * 78)
# 做法：把「無效列上的睡眠衍生欄位」整個拿掉，再算一次。
# 如果 compute_modifiers 真的有擋，兩次結果必須**完全相同**——
# 因為那些值本來就不該被用到。
SLEEP_DERIVED = ("avg_heart_rate", "awake_count",
                 "sleep_segment_count", "presleep_stress_score")

stripped = copy.deepcopy(rows)
n_stripped = 0
for r in stripped:
    if not arm.has_measured_sleep(r):
        for col in SLEEP_DERIVED:
            if r.get(col):
                n_stripped += 1
            r[col] = ""

base = arm.compute_modifiers(rows)
without = arm.compute_modifiers(stripped)
ok("無效列上確實有睡眠衍生的值（否則這項測不到東西）",
   n_stripped > 0, f"清掉 {n_stripped} 個值")
check("拿掉之後結果完全相同", without == base, True)

# 反向對照：同樣的欄位改動**有效**夜晚，結果就必須改變。
# 沒有這一條，上面那條在「compute_modifiers 根本沒讀這些欄位」時也會通過。
mangled = copy.deepcopy(rows)
for r in mangled:
    if arm.has_measured_sleep(r):
        r["avg_heart_rate"] = ""
ok("反向對照：清掉有效夜晚的 avg_hr 會改變結果",
   arm.compute_modifiers(mangled) != base, "（確認這些欄位真的有被讀）")

print()
print("=" * 78)
print("【3】baseline 窗格是「日曆天」不是「筆數」")
print("=" * 78)
# MIN_BASELINE_NIGHTS 筆資料，但全部落在 MAX_BASELINE_DAYS 之外 → 必須回 None。
# 舊版寫 history[-28:] 時這個情境會回一個數字，而那正是 bug：
# 配戴稀疏時 baseline 會橫跨數月，違背這個常數自己的目的。
old = [(f"2026-01-{d:02d}", 60.0) for d in range(1, arm.MIN_BASELINE_NIGHTS + 1)]
check(f"{arm.MIN_BASELINE_NIGHTS} 筆但全在窗外 → None",
      arm.rolling_baseline(old, "2026-06-01"), None)

recent = [(f"2026-06-{d:02d}", 60.0) for d in range(1, arm.MIN_BASELINE_NIGHTS + 1)]
check(f"{arm.MIN_BASELINE_NIGHTS} 筆且都在窗內 → 有值",
      arm.rolling_baseline(recent, "2026-06-20"), 60.0)

# 混合：窗內筆數不足，就算加上窗外的湊得到 14 筆也不行
mixed = old + [(f"2026-06-{d:02d}", 60.0) for d in range(1, 5)]
check("窗外湊數不算（窗內只有 4 筆）",
      arm.rolling_baseline(mixed, "2026-06-20"), None)

ok("常數已改名，舊名稱不該還在",
   hasattr(arm, "MAX_BASELINE_DAYS") and not hasattr(arm, "MAX_BASELINE_NIGHTS"),
   f"MAX_BASELINE_DAYS={getattr(arm, 'MAX_BASELINE_DAYS', None)}")

print()
print("=" * 78)
print("【4】MOTIF_FAMILIES 必須與夢境調色盤一對一")
print("=" * 78)
# 家族一合併，去重就會把「沒用過的選項」連坐排除，把模型逼向剩下那一個
# ——那正是「棉被與雪佔 37%」的成因。新增調色盤選項卻忘了加家族，
# 不會有任何錯誤訊息，只會讓意象重新開始集中。
palette_options = re.findall(r"^  [a-f]\. ", gad.SYSTEM_PROMPT_HEAD, re.M)
check("調色盤選項數 == 家族數",
      len(gad.MOTIF_FAMILIES), len(palette_options))

# 關鍵字不得重複：兩個家族共用同一個關鍵字，等於它們仍然是連坐的
seen = {}
dupes = []
for fam, kws in gad.MOTIF_FAMILIES.items():
    for k in kws:
        if k in seen:
            dupes.append((k, seen[k], fam))
        seen[k] = fam
check("沒有兩個家族共用同一個關鍵字", len(dupes), 0)
if dupes:
    for d in dupes[:5]:
        print(f"      {d}")

# 真實資料回歸：既有夢境對不到任何家族的比例。對不到 = 去重對那晚完全失效。
advice = ROOT / "ai" / "data" / "ai_advice.json"
if advice.exists():
    import json
    raw = json.load(io.open(advice, encoding="utf-8"))
    ent = raw.get("entries", raw)
    entries = list(ent.values()) if isinstance(ent, dict) else ent
    dreams = [e["dream_summary"].lower() for e in entries
              if e.get("source") == "llm" and e.get("dream_summary")]
    unmatched = [d for d in dreams
                 if not any(any(k in d for k in kw)
                            for kw in gad.MOTIF_FAMILIES.values())]
    # 2026-08-28 修正後是 1/51。留一點餘裕給往後新增的夜晚，但守住量級——
    # 修正前是 10/51，所以這個門檻擋得住那個回歸。
    ratio = len(unmatched) / len(dreams) if dreams else 0
    ok("既有夢境對不到家族的比例 < 10%",
       ratio < 0.10, f"{len(unmatched)} / {len(dreams)} = {ratio*100:.1f}%")
else:
    print("  - 跳過真實資料回歸（ai/data/ai_advice.json 不存在）")

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
