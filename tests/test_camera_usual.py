"""
tests/test_camera_usual.py — 攝影機「跟你平常比」那段話。

這支守的是五個**壞掉時不會報錯**的地方：

1. **基線混用不同分母。** motion_threshold_basis 是 'roi'（分母＝床鋪範圍）
   或 'frame'（分母＝整個畫面），同一個 0.75% 在兩者下差一個數量級，
   而數字看起來都正常。09-01、09-03 錄於 ROI 之前就是 'frame'。
2. **基線不足時給了一個會被誤讀的數字。** 回 0% 會被讀成「跟平常一模一樣」，
   回 None 會讓畫面空白、看起來像壞了。必須講「還需要幾晚」。
3. **28 天窗格失效。** 不夾窗的話，三個月前的夜晚也會進基線，而
   「平常」應該代表現在的你。
4. **門檻邊界。** 24.9% 要講「差不多」、25.1% 才講數字。寫成 <= 或四捨五入
   之後比較，都會讓門檻悄悄位移。
5. **同一天的夜晚算進自己的基線。** 一晚兩份錄影時（10-28 21:37 與
   10-29 05:11 的起床日都是 10-29）會拿自己比自己。

執行：python tests/test_camera_usual.py
"""
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import camera_usual as cu  # noqa: E402

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


def night(date, rate, basis="roi", roi="34,129,288,231"):
    return {"date": date, "events_per_hour": rate,
            "motion_threshold_basis": basis, "roi": roi}


def days(n, start=1, rate=20.0, **kw):
    """n 晚，日期從 2026-10-start 起連續，事件率都一樣。"""
    return [night(f"2026-10-{start + i:02d}", rate, **kw) for i in range(n)]


# ═══════════════════════════════════════════════════════════════════
print("\n【1】基線只取「同一把尺」量出來的夜晚")
hist = days(6, start=1, rate=20.0, basis="frame", roi=None)
r = cu.compare_to_usual(night("2026-10-10", 40.0), hist)
ok("分母不同（frame vs roi）→ 一晚都不取", r["baseline_nights"] == 0,
   f"取到 {r['baseline_nights']} 晚")
ok("  所以講的是「還需要幾晚」不是「多了 100%」", "Needs" in r["label"], r["label"])

hist = days(6, start=1, rate=20.0, roi="0,0,640,360")
r = cu.compare_to_usual(night("2026-10-10", 40.0), hist)
ok("框不同（ROI 換過）→ 一晚都不取", r["baseline_nights"] == 0)

hist = days(6, start=1, rate=20.0)
r = cu.compare_to_usual(night("2026-10-10", 40.0), hist)
ok("同一把尺 → 取得到，而且算出偏離", r["baseline_nights"] == 6 and r["delta_pct"] == 100.0,
   f"{r['baseline_nights']} 晚 / {r['delta_pct']}%")

# ═══════════════════════════════════════════════════════════════════
print("\n【2】基線不足時不得給會被誤讀的數字")
for have in range(0, cu.BASELINE_MIN_NIGHTS):
    r = cu.compare_to_usual(night("2026-10-20", 20.0), days(have, start=10))
    short = cu.BASELINE_MIN_NIGHTS - have
    ok(f"只有 {have} 晚 → 算不出偏離",
       r["delta_pct"] is None and r["usual_events_per_hour"] is None,
       f"baseline_nights={r['baseline_nights']}")
    ok(f"  label 寫出 {short}", f"Needs {short} more recorded" in r["label"], r["label"])
    ok("  delta_pct 是 None，不是 0", r["delta_pct"] is None, str(r["delta_pct"]))

r = cu.compare_to_usual(night("2026-10-20", 20.0), days(cu.BASELINE_MIN_NIGHTS, start=10))
ok(f"剛好 {cu.BASELINE_MIN_NIGHTS} 晚 → 算得出來", r["delta_pct"] is not None)
ok("單數時 night 不加 s", "1 more recorded night " in
   cu.compare_to_usual(night("2026-10-20", 20.0), days(cu.BASELINE_MIN_NIGHTS - 1, start=10))["label"])

# ═══════════════════════════════════════════════════════════════════
print("\n【3】28 天窗格：太舊的夜晚不算")
old = [night(f"2026-08-{1 + i:02d}", 20.0) for i in range(6)]
r = cu.compare_to_usual(night("2026-10-20", 40.0), old)
ok("兩個月前的 6 晚 → 一晚都不取", r["baseline_nights"] == 0, f"取到 {r['baseline_nights']} 晚")

edge = [night("2026-09-22", 20.0)] + days(4, start=14, rate=20.0)
r = cu.compare_to_usual(night("2026-10-20", 20.0), edge)
ok("正好 28 天前那晚要算進去（09-22 → 10-20）", r["baseline_nights"] == 5,
   f"取到 {r['baseline_nights']} 晚")

# ═══════════════════════════════════════════════════════════════════
print("\n【4】門檻邊界：24.9% 講「差不多」、25.1% 才講數字")
base = days(6, start=1, rate=20.0)
for rate, expect_same, lab in [(24.98, True, "24.9%"), (25.02, False, "25.1%"),
                               (15.02, True, "−24.9% 的反向"), (15.0, False, "−25%")]:
    r = cu.compare_to_usual(night("2026-10-10", rate), base)
    same = r["label"] == cu.SAME_AS_USUAL
    ok(f"{lab}（偏離 {r['delta_pct']:+.1f}%）→ {'差不多' if expect_same else '講數字'}",
       same == expect_same, r["label"])

r = cu.compare_to_usual(night("2026-10-10", 30.0), base)
ok("高於平常 → 說 more", "more movement than usual" in r["label"], r["label"])
r = cu.compare_to_usual(night("2026-10-10", 10.0), base)
ok("低於平常 → 說 less", "less movement than usual" in r["label"], r["label"])
ok("  百分比是正數（方向靠 more/less 講，不靠負號）", "-" not in r["label"], r["label"])

# ═══════════════════════════════════════════════════════════════════
print("\n【5】同一天的夜晚不得算進自己的基線")
twin = days(6, start=1, rate=20.0) + [night("2026-10-10", 99.0)]
r = cu.compare_to_usual(night("2026-10-10", 40.0), twin)
ok("同一個起床日的另一份錄影 → 不取", r["baseline_nights"] == 6,
   f"取到 {r['baseline_nights']} 晚")

# ═══════════════════════════════════════════════════════════════════
print("\n【6】沒有事件率的夜晚、以及 annotate 的順序")
ok("events_per_hour 是 None → 回 None（沒得比）",
   cu.compare_to_usual(night("2026-10-10", None), days(6, start=1)) is None)

rows = days(8, start=1, rate=20.0)
rows[-1]["events_per_hour"] = 40.0
cu.annotate(rows)
ok("annotate 每一列都掛上 usual", all(r.get("usual") for r in rows))
ok("  最舊那晚沒有基線 → 說還需要幾晚", "Needs" in rows[0]["usual"]["label"])
ok("  最新那晚算得出偏離", rows[-1]["usual"]["delta_pct"] == 100.0,
   str(rows[-1]["usual"]["delta_pct"]))
ok("  basis 標籤有帶出來", rows[-1]["usual"]["basis"] == cu.BASIS)

# ═══════════════════════════════════════════════════════════════════
print("\n【7】給人讀的那幾句話只在這裡定義")
ok("NOTE 說了「不進分數」", "never enters any score" in cu.NOTE)
ok("NOTE 說了「動得多不等於睡得差」", "NOT read as worse sleep" in cu.NOTE)
ok("NOTE 說了跟自己比不是跟別人比", "your own recent nights" in cu.NOTE)
ok("NOTE 說了常模不是切點", "norm, not a cut-point" in cu.NOTE)
ok("NOTE 說了跨夜變動大", "3.1x" in cu.NOTE)

print()
print("=" * 78)
print("結果：全部通過" if not fails else f"結果：{len(fails)} 項失敗 → {fails}")
print("=" * 78)
sys.exit(1 if fails else 0)
