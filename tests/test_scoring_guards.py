"""
tests/test_scoring_guards.py

三個「安靜失效」的機制的回歸防護。這一支測的不是「算得對不對」，
而是**保護那些壞掉時不會報錯的東西**——2026-08-28 那一輪修的三個問題，
每一個在修之前都是「程式照跑、沒有錯誤訊息、結果安靜地錯」。

  【1】summary 的有效性判準不得在兩支腳本之間漂移
  【2】沒量到睡眠的夜晚，睡眠衍生的量不得進 baseline
  【3】baseline 窗格是「日曆天」不是「筆數」
  【4】MOTIF_FAMILIES 必須與夢境調色盤的選項一對一
  【5】階段時長超出睡眠視窗的夜晚必須被排除
  【6】壓力修正值依個人波動換算（2026-10-22）

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
print("【5】階段時長超出睡眠視窗的夜晚必須被排除")
print("=" * 78)
# 2026-09-30 新增。Garmin 有時給出「階段時長合計 > 它自己給的入睡→起床視窗」
# 的資料（實測 2026-06-27：688 分 vs 447.9 分）。在加這條檢查之前，
# 效率算出 153.62% 後被 `min(…, 100.0)` 夾平成 100%，於是一列完全不可信的
# 資料（REM=0、深睡佔 42%）照樣拿滿睡眠效率那 25 分——**沒有任何錯誤訊息**。
#
# ⚠️ 兩支函式各有一份判準且刻意不互相 import，所以下面兩邊都要驗。


def night_row(total_sleep, period_min):
    """合成一列 summary。入睡固定 02:00，起床往後推 period_min 分鐘。"""
    from datetime import datetime, timedelta
    start = datetime.fromisoformat("2026-01-01T02:00:00+08:00")
    return {
        "date": "2026-01-01",
        "sleep_start_time": start.isoformat(),
        "wake_time": (start + timedelta(minutes=period_min)).isoformat(),
        "total_sleep_minutes": str(total_sleep),
    }


# 超出很多 → 兩邊都要擋
bad = night_row(688, 447.9)
ok("矛盾的列：is_valid_night 要擋", esf.is_valid_night(bad)[0] is False)
ok("矛盾的列：has_measured_sleep 要擋", arm.has_measured_sleep(bad) is False)

# 正常的列 → 兩邊都要放行（確認這條檢查不會過度殺傷）
good = night_row(400, 480)
ok("正常的列：is_valid_night 要放行", esf.is_valid_night(good)[0] is True)
ok("正常的列：has_measured_sleep 要放行", arm.has_measured_sleep(good) is True)

# 邊界：Garmin 階段時長量化到整分鐘，1 分鐘內的落差屬量化誤差，不可誤殺。
# 實測有 16 晚總睡眠正好等於視窗（效率真的是 100.00%），那些必須留著。
exact = night_row(480, 480)
ok("總睡眠正好等於視窗（真 100%）不可誤殺", esf.is_valid_night(exact)[0] is True)
ok("兩個常數必須相同",
   esf.MAX_SLEEP_OVER_PERIOD_MINUTES == arm.MAX_SLEEP_OVER_PERIOD_MINUTES,
   f"{esf.MAX_SLEEP_OVER_PERIOD_MINUTES} / {arm.MAX_SLEEP_OVER_PERIOD_MINUTES}")

# 真實資料回歸：summary 裡那一晚確實會被擋下來。
real_bad = [r for r in rows if r.get("date") == "2026-06-27"]
if real_bad:
    ok("真實資料 2026-06-27 被排除", esf.is_valid_night(real_bad[0])[0] is False)
else:
    print("  - 跳過真實資料回歸（summary 裡沒有 2026-06-27）")

print()
print("=" * 78)
print("【6】壓力修正值依個人波動換算（2026-10-22）")
print("=" * 78)

# 14 晚、日期連續、數值 20/30 交錯 → 中位數 25、MAD 5、波動 5×1.4826≈7.41。
hist = [(f"2026-09-{d:02d}", 20.0 if d % 2 else 30.0) for d in range(1, 15)]
spread = arm.rolling_spread(hist, "2026-09-15", arm.STRESS_SPREAD_FLOOR)
check("波動 = MAD × 1.4826", round(spread, 2), round(5 * arm.MAD_TO_SD, 2))
base = arm.rolling_baseline(hist, "2026-09-15")
f = lambda cur: arm.score_lower_is_better_vs_spread(cur, base, spread, arm.STRESS_CAP)
# 0.5 倍以內是雜訊：偏離 3（0.4 倍）不扣分。改回固定每單位 0.4 分的話會是 −1.2。
check("偏離 0.4 倍個人波動 → 0", f(base + 0.4 * spread), 0.0)
check("偏離 2 倍 → 扣滿", round(f(base + 2 * spread), 6), -arm.STRESS_CAP)
check("偏離 1.25 倍 → 扣一半", round(f(base + 1.25 * spread), 6), -arm.STRESS_CAP / 2)
check("比平常低 2 倍 → 加滿（對稱）", round(f(base - 2 * spread), 6), arm.STRESS_CAP)

# 同樣偏離 10 分：波動大的人扣得少——這正是改版的目的。舊換算兩人都扣滿 −4。
wide = [(d, v * 2 - 25) for d, v in hist]          # 中位數仍 25，波動變兩倍
s_wide = arm.rolling_spread(wide, "2026-09-15", arm.STRESS_SPREAD_FLOOR)
narrow_pts = arm.score_lower_is_better_vs_spread(35, 25, spread, arm.STRESS_CAP)
wide_pts = arm.score_lower_is_better_vs_spread(35, 25, s_wide, arm.STRESS_CAP)
ok("同樣偏離 10 分，平常起伏大的人扣得少", wide_pts > narrow_pts,
   f"起伏小 {narrow_pts:.2f}／起伏大 {wide_pts:.2f}")

# 窗格內數值全相同時 MAD = 0。沒有下限的話，偏離 1 分就會被除以 0 放大成扣滿。
flat = [(d, 25.0) for d, _ in hist]
s_flat = arm.rolling_spread(flat, "2026-09-15", arm.STRESS_SPREAD_FLOOR)
check("MAD = 0 時波動取下限（一個量測單位）", s_flat, arm.STRESS_SPREAD_FLOOR)

# 波動與 baseline 必須用同一個窗格：28 天前的值不得進入波動。
old = [("2026-07-01", 999.0)] + hist
check("太舊的夜晚不進波動", round(arm.rolling_spread(old, "2026-09-15", 1.0), 2), round(spread, 2))
check("不足 14 晚 → None（冷啟動）", arm.rolling_spread(hist[:13], "2026-09-15", 1.0), None)

# 上面只驗函式本身。主迴圈改回舊的 score_lower_is_better(stress, ...) 的話，
# 那幾條照樣全綠，而 pipeline 照跑、沒有錯誤訊息。
src = (ROOT / "garmin" / "apply_recovery_modifier.py").read_text(encoding="utf-8")
ok("主迴圈的壓力用新換算",
   "score_lower_is_better_vs_spread(stress," in src
   and "score_lower_is_better(stress," not in src)

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
