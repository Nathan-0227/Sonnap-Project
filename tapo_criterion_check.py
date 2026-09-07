"""
攝影機事件率 vs 文獻常模 vs 同一晚的 Garmin —— 效標對照。

═══════════════════════════════════════════════════════════════════════
⚠️ 這支**只清點，不評分**。
═══════════════════════════════════════════════════════════════════════
它不產生任何分數、不寫進任何欄位、不被任何評分程式 import。
設計紅線 2 規定「要計分先有文獻」，而 `Research-Background/攝影機分數.md`
的結論是**現行有效的攝影機計分項目：0 項**。這支是那份文件 E 節
（效標驗證）的工具，是走到「能不能計分」那一步之前的前置作業。

輸出三欄對照：
    ① 我們量到的動作率（次/小時）
    ② 文獻常模（Montini 2024 / De Koninck 1992）
    ③ 同一晚的 Garmin（分數、WASO、清醒次數）

──────────────────────────────────────────────────────────────────────
⚠️ 分母陷阱：ROI 錄的與非 ROI 錄的**不能用同一個門檻**
──────────────────────────────────────────────────────────────────────
校準出來的 0.75% 是**佔 ROI**。ROI 只有 288×231 = 66528 px，
整張畫面是 640×360 = 230400 px，差 3.46 倍。把 0.75% 直接套到
整張畫面上，門檻會**大 3.46 倍**，事件率被系統性壓低——
而且不會拋例外、不會有空值，數字看起來完全正常。
（`tests/test_tapo_roi_csv.py` 守的就是這件事。）

→ 非 ROI 的錄影一律換算：門檻 = 0.75% × (ROI 面積 / 畫面面積)。
→ 另外用 bbox 中心是否落在 ROI 內做一次近似的空間過濾。
   ⚠️ 這是**近似**不是等價：CSV 只記最大連通域的 bbox，
   ROI 外還有別的連通域時，這個過濾攔不掉。所以兩種都印，
   差多少自己看。

用法：
    python tapo_criterion_check.py
    python tapo_criterion_check.py --min-hours 4
"""
import argparse
import csv
import sys
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

from tapo_metric_logger import read_roi, read_started          # noqa: E402
from tapo_scan_threshold import episodes                       # noqa: E402
from tapo_sleep_onset import MOTION_THRESHOLD                  # noqa: E402

OUT_DIR = ROOT / "tapo_metrics"
GARMIN_CSV = ROOT / "garmin" / "data" / "garmin_sleep_quality_final.csv"
# ⚠️ WASO（awake_minutes）與 awake_count **不在** final 那份裡，在 summary。
#    只讀 final 的話這兩欄會是空的，而且不會報錯——表格照印，只是永遠 nan。
GARMIN_SUMMARY_CSV = ROOT / "garmin" / "data" / "garmin_sleep_summary.csv"

FRAME_W, FRAME_H = 640, 360
FRAME_AREA = FRAME_W * FRAME_H

# 校準用的 ROI（三晚人工標註定案，見 docs/TAPO_HANDOFF.md）。
CALIBRATION_ROI = (34, 129, 288, 231)

# ─── 文獻常模（第一作者已核對）────────────────────────────────────
# Montini A, Loddo G, Zenesini C, Mainieri G, Baldelli L, Mignani F,
#   Mondini S, Provini F. Physiological movements during sleep in healthy
#   adults across all ages. Sleep. 2024;47(9):zsae138.
#   → 50 名健康成人 video-PSG，movement index 中位數 11 次/小時（IQR 8–15）
MONTINI_MEDIAN = 11.0
MONTINI_IQR = (8.0, 15.0)
# De Koninck J, Lorrain D, Gagnon P. Sleep positions and position shifts in
#   five age groups. Sleep. 1992;15(2):143-149.
#   → 18–24 歲體位改變 3.6 次/小時
DEKONINCK_1824 = 3.6

# ⚠️ 常模不等於門檻：文獻數的是人工判讀的動作（有起訖、有拓樸分類），
#    我們數的是像素面積過門檻的 episode。兩者不是同一個構念——
#    實測我們的一次動作是 13–19 秒，Montini 是 4 秒（已排除是參數問題）。
#    所以下面的「倍數」是**健全性檢查**，不是效度證據。


def night_of(t):
    """錄影起點屬於哪一夜（用起床日，對齊 Garmin 的 calendarDate）。"""
    return ((t - timedelta(hours=12)) + timedelta(days=1)).date().isoformat()


def load_samples(path, roi):
    """
    回傳 (plain, gated)。

    plain  = 不做空間過濾
    gated  = 最大連通域的 bbox 中心落在 ROI 內才算
    """
    plain, gated = [], []
    with path.open(encoding="utf-8") as fh:
        rows = csv.DictReader(l for l in fh if not l.startswith("#"))
        # ⚠️ tapo_metrics/ 底下不是每個 .csv 都是 logger 產的（還有人工標註、
        #    clip_measure 之類）。用**欄位**認，不要用檔名認——先前用檔案大小
        #    篩過，結果把只錄到 25 分鐘的那一晚整個漏掉了。
        if not rows.fieldnames or "t" not in rows.fieldnames:
            return [], []
        for r in rows:
            if r.get("warmup") == "1":
                continue
            t = datetime.fromisoformat(r["t"])
            if r.get("illum_skip") == "1":
                plain.append((t, 0.0, False))
                gated.append((t, 0.0, False))
                continue
            if roi:                       # 錄的時候就有 ROI：直接用 roi_px
                frac = int(r["roi_px"]) / (roi[2] * roi[3])
                plain.append((t, frac, True))
                gated.append((t, frac, True))
            else:                         # 沒有 ROI：整畫面，門檻要換算
                frac = int(r["max_px"]) / FRAME_AREA
                plain.append((t, frac, True))
                cx = int(r["max_x"]) + int(r["max_w"]) / 2
                cy = int(r["max_y"]) + int(r["max_h"]) / 2
                x, y, w, h = CALIBRATION_ROI
                inside = x <= cx < x + w and y <= cy < y + h
                gated.append((t, frac if inside else 0.0, True))
    return plain, gated


def analyse(path, min_hours):
    started = read_started(path)
    roi, _ = read_roi(path)
    scale = 1.0 if roi else (CALIBRATION_ROI[2] * CALIBRATION_ROI[3]) / FRAME_AREA
    thr = MOTION_THRESHOLD * scale

    plain, gated = load_samples(path, roi)
    if not plain:
        return None
    span = (plain[-1][0] - plain[0][0]).total_seconds() / 3600
    if span < min_hours:
        return None

    return {
        "file": path.name,
        "night": night_of(started or plain[0][0]),
        "start": (started or plain[0][0]).strftime("%H:%M"),
        "hours": span,
        "roi": roi,
        "threshold": thr,
        "rate_plain": len(episodes(plain, thr)) / span,
        "rate_gated": len(episodes(gated, thr)) / span,
        # ⚠️ 早上 5 點之後才開錄的不是睡眠，是白天的測試場次。
        #    它的事件率不可以跟睡眠夜混在一起讀。
        "daytime": (started or plain[0][0]).hour >= 5,
    }


def load_garmin():
    """把 final 與 summary 兩份合起來，用 date 對齊。"""
    out = {}
    for path in (GARMIN_CSV, GARMIN_SUMMARY_CSV):
        if not path.exists():
            continue
        with path.open(encoding="utf-8-sig", newline="") as fh:
            for r in csv.DictReader(fh):
                out.setdefault(r["date"], {}).update(r)
    return out


def num(row, *names):
    for n in names:
        v = (row or {}).get(n)
        if v not in (None, ""):
            try:
                return float(v)
            except ValueError:
                pass
    return None


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--min-hours", type=float, default=4.0,
                    help="短於這個時數的錄影不算一晚（預設 4）")
    args = ap.parse_args()

    files = [p for p in sorted(OUT_DIR.glob("*.csv"))
             if "_truth" not in p.name and "selftest" not in p.name]
    nights = [r for r in (analyse(p, args.min_hours) for p in files) if r]

    print("=" * 78)
    print("攝影機事件率 × 文獻常模 × 同一晚的 Garmin")
    print("=" * 78)
    if not nights:
        print(f"✗ {OUT_DIR} 裡沒有長度 >= {args.min_hours}h 的錄影")
        return

    print()
    print(f"【1】每一晚量到什麼（校準門檻 {MOTION_THRESHOLD:.4%} 佔 ROI）")
    print()
    print(f"{'夜':<12}{'開始':<7}{'時數':>6}{'ROI':>5}{'實際門檻':>10}"
          f"{'次/小時':>9}{'ROI過濾後':>10}")
    print("-" * 78)
    for r in nights:
        print(f"{r['night']:<12}{r['start']:<7}{r['hours']:>6.2f}"
              f"{('有' if r['roi'] else '無'):>5}{r['threshold']:>9.4%}"
              f"{r['rate_plain']:>9.1f}{r['rate_gated']:>10.1f}"
              f"{'   ← 白天場次，不是睡眠' if r['daytime'] else ''}")

    print()
    print("【2】對照文獻常模（⚠️ 常模不是門檻，見檔頭）")
    print()
    lo, hi = MONTINI_IQR
    print(f"{'夜':<12}{'次/小時':>9}{'是 Montini 中位數的幾倍':>26}{'落在 IQR 8-15?':>16}")
    print("-" * 78)
    for r in [n for n in nights if not n["daytime"]]:
        rate = r["rate_gated"]
        mark = "✓ 是" if lo <= rate <= hi else "✗ 否"
        print(f"{r['night']:<12}{rate:>9.1f}{rate / MONTINI_MEDIAN:>25.1f}x{mark:>16}")
    print()
    print(f"  Montini A 2024（video-PSG, n=50）：中位數 {MONTINI_MEDIAN} 次/小時，IQR {lo}-{hi}")
    print(f"  De Koninck J 1992（18-24 歲體位改變）：{DEKONINCK_1824} 次/小時")

    print()
    print("【3】同一晚的 Garmin")
    print()
    g = load_garmin()
    print(f"{'夜':<12}{'次/小時':>9}{'final_score':>13}{'quality':>10}"
          f"{'WASO 分':>9}{'清醒次數':>10}")
    print("-" * 78)
    matched = []
    for r in [n for n in nights if not n["daytime"]]:
        row = g.get(r["night"])
        if row is None:
            print(f"{r['night']:<12}{r['rate_gated']:>9.1f}      （那一晚沒有手錶資料）")
            continue
        score = num(row, "final_score")
        waso = num(row, "awake_minutes", "waso_minutes")
        awk = num(row, "awake_count")
        matched.append((r["rate_gated"], score, waso, awk))
        print(f"{r['night']:<12}{r['rate_gated']:>9.1f}"
              f"{score if score is not None else float('nan'):>13.1f}"
              f"{row.get('final_quality', '?'):>10}"
              f"{waso if waso is not None else float('nan'):>9.0f}"
              f"{awk if awk is not None else float('nan'):>10.0f}")

    print()
    print("【4】結論")
    print()
    print(f"  兩邊都有資料的夜晚：{len(matched)} 晚")
    if len(matched) < 10:
        print("  → **n 太小，不算相關係數。**")
        print("     `Research-Background/攝影機分數.md` E 節要求至少 10 晚；")
        print(f"     n={len(matched)} 算出來的 r 主要反映的是雜訊，印出來只會被人引用。")
    else:
        import statistics
        xs = [m[0] for m in matched]
        for i, name in ((1, "final_score"), (2, "WASO"), (3, "awake_count")):
            pairs = [(x, m[i]) for x, m in zip(xs, matched) if m[i] is not None]
            if len(pairs) >= 10:
                px, py = zip(*pairs)
                print(f"  r(次/小時, {name}) = {statistics.correlation(px, py):+.2f}  (n={len(pairs)})")
    print()
    print("  ⚠️ 不管 r 多少，攝影機都還不能計分——那需要的是")
    print("     『結果關聯』研究的門檻，不是常模，也不是內部相關。")
    print("     現行有效的攝影機計分項目仍然是 0 項。")


if __name__ == "__main__":
    main()
