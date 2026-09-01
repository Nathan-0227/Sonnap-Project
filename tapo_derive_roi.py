"""
tapo_derive_roi.py — 從整夜的 bbox 推出「床在哪裡」，不用使用者框、不用重錄。

═══════════════════════════════════════════════════════════════════
為什麼需要 ROI
═══════════════════════════════════════════════════════════════════
現在的門檻是「佔**整個畫面**幾 %」，而畫面裡大半不是床。這有兩個後果：

1. **分母沒有意義** —— 相機離床近，身體佔畫面 40%；離得遠佔 5%。
   所以絕對像素數（350000、250000…）換一個房間就完全失效，
   這正是 TAPO_HANDOFF #1 那個「門檻逐晚漂移」的深層原因。
2. **床以外的動作照算** —— 窗簾、門口經過的人、寵物。

換成「佔**床**幾 %」之後，門檻才能跨房間、跨擺放位置通用。

═══════════════════════════════════════════════════════════════════
做法（TAPO_HANDOFF「ROI 怎麼定」的方案 B）
═══════════════════════════════════════════════════════════════════
整晚下來，真正持續有動作的地方就是床。所以：

    把每一幀「最大連通區塊」的 bbox 疊成熱區圖
      → 取熱度前段
      → 最大的連通區塊的外接矩形 = 床

⚠️ 只累加**夠大的**區塊（預設 ≥1% 畫面）。雜訊是均勻散布的，
   不濾掉的話熱區圖會是平的，選不出東西。

⚠️ 這支**不評分、不寫任何檔案**，只讀 CSV 印結果。

用法
────
  python tapo_derive_roi.py                       # 用最新一份 CSV
  python tapo_derive_roi.py tapo_metrics/xxx.csv
"""
import csv
import sys
from pathlib import Path

import cv2
import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "tapo_metrics"

WIDTH, HEIGHT = 640, 360
FRAME_AREA = WIDTH * HEIGHT

MIN_FRAC_FOR_HEAT = 0.01   # 只有 ≥1% 畫面的區塊才進熱區圖（雜訊不算）
HEAT_PERCENTILE = 80       # 熱區圖取前 20% 熱的區域
SANITY_MIN, SANITY_MAX = 0.10, 0.60   # 床應該佔畫面 10%~60%，超出就是選錯了


def load_boxes(path):
    """回傳 [(x, y, w, h, frac)]，只留夠大的區塊。"""
    with path.open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(l for l in fh if not l.startswith("#")))
    boxes = []
    for r in rows:
        if r["warmup"] == "1" or r["illum_skip"] == "1" or not r["max_px"]:
            continue
        frac = int(r["max_px"]) / FRAME_AREA
        if frac < MIN_FRAC_FOR_HEAT:
            continue
        boxes.append((int(r["max_x"]), int(r["max_y"]),
                      int(r["max_w"]), int(r["max_h"]), frac))
    return boxes, len(rows)


def load_mask_heat(csv_path):
    """
    優先用 tapo_metric_logger 累積的**真遮罩**熱區圖。

    bbox 版（下面的 build_heat）把每個區塊當矩形疊，形狀會糊掉——
    實測那樣熱區沒有自然邊界，百分位一動 ROI 就從 19% 跳到 72%。
    真遮罩版沒有這個問題。舊的 CSV 沒有 .npy，就退回 bbox 版。
    """
    npy = csv_path.with_name(csv_path.stem + "_heat.npy")
    if not npy.exists():
        return None
    heat = np.load(npy)
    return heat if heat.shape == (HEIGHT, WIDTH) else None


def build_heat(boxes):
    heat = np.zeros((HEIGHT, WIDTH), dtype=np.float32)
    for x, y, w, h, _ in boxes:
        if w <= 0 or h <= 0:
            continue
        heat[y:y + h, x:x + w] += 1.0
    return heat


def largest_region(heat, percentile):
    """取熱度前段，回傳最大連通區塊的 bbox 與它的實際像素數。"""
    if heat.max() <= 0:
        return None
    cutoff = np.percentile(heat[heat > 0], percentile)
    mask = (heat >= max(cutoff, 1.0)).astype(np.uint8) * 255
    mask = cv2.morphologyEx(
        mask, cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
    n, _, stats, _ = cv2.connectedComponentsWithStats(mask)
    if n <= 1:
        return None
    i = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (int(stats[i, cv2.CC_STAT_LEFT]), int(stats[i, cv2.CC_STAT_TOP]),
            int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT]),
            int(stats[i, cv2.CC_STAT_AREA]))


def ascii_heat(heat, rows=14, cols=56):
    """把熱區圖畫成文字，方便隔著終端機看它選得對不對。"""
    small = cv2.resize(heat, (cols, rows), interpolation=cv2.INTER_AREA)
    peak = small.max() or 1.0
    ramp = " .:-=+*#%@"
    print("    +" + "-" * cols + "+")
    for r in range(rows):
        line = "".join(ramp[min(int(small[r, c] / peak * (len(ramp) - 1)), len(ramp) - 1)]
                       for c in range(cols))
        print(f"    |{line}|")
    print("    +" + "-" * cols + "+")
    print(f"     熱度 0 ── {peak:.0f} 幀（' ' 最冷、'@' 最熱）")


def main():
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    else:
        files = sorted(OUT_DIR.glob("*.csv"), key=lambda p: p.stat().st_mtime)
        files = [f for f in files if "selftest" not in f.name] or files
        if not files:
            sys.exit("✗ tapo_metrics/ 裡沒有 CSV。先跑 tapo_metric_logger.py。")
        path = files[-1]

    boxes, total_rows = load_boxes(path)
    print("=" * 84)
    print(f"ROI 推導：{path.name}")
    print(f"總列數 {total_rows}，其中最大區塊 ≥{MIN_FRAC_FOR_HEAT * 100:.0f}% 畫面的有 "
          f"{len(boxes)} 幀 —— 熱區圖只用這些")
    print("=" * 84)

    if len(boxes) < 50:
        sys.exit("✗ 夠大的區塊太少，推不出 ROI。可能這一晚幾乎沒動，或門檻要放寬。")

    heat = load_mask_heat(path)
    if heat is not None:
        print("熱區圖來源：**真遮罩**累積（_heat.npy）")
    else:
        heat = build_heat(boxes)
        print("熱區圖來源：bbox 累積 ⚠️ 矩形會把形狀糊掉，邊界會偏軟。")
        print("            下一晚用新版 logger 錄就會有 _heat.npy。")
    print()
    ascii_heat(heat)

    print()
    print("【百分位掃描】ROI 對取多熱有多敏感 —— 邊界夠不夠銳利")
    print("-" * 84)
    print(f"{'百分位':>8}{'ROI(x,y,w,h)':>26}{'佔畫面':>9}{'中心在外':>10}  ")
    sweep = []
    for q in (40, 50, 60, 70, 80, 90):
        r = largest_region(heat, q)
        if not r:
            continue
        qx, qy, qw, qh, _ = r
        f = (qw * qh) / FRAME_AREA
        o = sum(1 for bx, by, bw, bh, _ in boxes
                if not (qx <= bx + bw / 2 <= qx + qw and qy <= by + bh / 2 <= qy + qh))
        sweep.append((q, f, o / len(boxes)))
        print(f"{q:>8}{f'({qx},{qy},{qw},{qh})':>26}{f * 100:>8.1f}%"
              f"{o / len(boxes) * 100:>9.1f}%")
    if len(sweep) >= 2:
        spread = max(f for _, f, _ in sweep) / min(f for _, f, _ in sweep)
        print()
        print(f"  百分位 40→90，ROI 面積差 {spread:.1f} 倍。")
        if spread > 2.5:
            print("  ⚠️ **邊界很軟** —— 熱區是連續漸層，沒有「床在這裡結束」的轉折。")
            print("     這種情況不要硬選一個百分位當定案，先看下面的熱區圖確認"
                  "亮的那塊是不是床。")
        else:
            print("  ✓ 邊界夠銳利，ROI 對百分位不敏感，可以放心用。")

    result = largest_region(heat, HEAT_PERCENTILE)
    if not result:
        sys.exit("✗ 熱區圖選不出連通區塊。")
    x, y, w, h, area = result
    bbox_frac = (w * h) / FRAME_AREA

    print(f"\n推得的 ROI：x={x} y={y} w={w} h={h}")
    print(f"  外接矩形佔畫面 {bbox_frac * 100:.1f}%"
          f"（實際熱區 {area / FRAME_AREA * 100:.1f}%）")

    if SANITY_MIN <= bbox_frac <= SANITY_MAX:
        print(f"  ✓ 落在合理範圍 {SANITY_MIN * 100:.0f}–{SANITY_MAX * 100:.0f}%")
    else:
        print(f"  ⚠️ **超出合理範圍 {SANITY_MIN * 100:.0f}–{SANITY_MAX * 100:.0f}%**，"
              "很可能選錯了")
        if bbox_frac > SANITY_MAX:
            print("     太大 → 可能整晚都有東西在動（窗簾？時鐘？），"
                  "或相機視野裡床本來就佔滿")
        else:
            print("     太小 → 可能只抓到身體的一小塊，或這一晚幾乎沒翻身")

    # ── 換算：同一個門檻，分母從畫面換成 ROI ──
    print(f"\n【換算】同一個門檻，分母從整個畫面換成 ROI")
    print("-" * 84)
    ratio = bbox_frac
    print(f"ROI 佔畫面 {ratio * 100:.1f}%，所以「佔畫面 X%」≈「佔 ROI {1 / ratio:.1f}X%」")
    print(f"\n{'佔畫面':>10}{'≈佔 ROI':>12}")
    for pct in (1, 2, 3, 4, 5, 7.5, 10):
        print(f"{pct:>9.1f}%{pct / ratio:>11.1f}%")
    print(f"""
  → tapo_scan_threshold.py 掃出來落在 Montini IQR 的門檻，用 ROI 表示大概是
    上表右欄那個數量級。**那個數字才是可以跨房間帶著走的**。

  ⚠️ 這只是等比例換算，不是真的用 ROI 重跑。要真的用 ROI，得讓
     tapo_metric_logger.py 在錄的時候就套遮罩（`--roi x,y,w,h`），
     因為「床外的大動作」在 CSV 裡已經被記成最大區塊了，事後除不掉。""")

    # ── 有多少動作發生在 ROI 外 ──
    outside = sum(1 for bx, by, bw, bh, _ in boxes
                  if bx + bw / 2 < x or bx + bw / 2 > x + w
                  or by + bh / 2 < y or by + bh / 2 > y + h)
    print(f"\n【檢查】{outside} / {len(boxes)} 幀的最大區塊中心落在 ROI **之外**"
          f"（{outside / len(boxes) * 100:.1f}%）")
    if outside / len(boxes) > 0.2:
        print("  ⚠️ 比例偏高——不是 ROI 選錯，就是床以外真的有東西在動。"
              "\n     這正是 ROI 要擋掉的東西，但也要確認不是把床的一半切掉了。")
    else:
        print("  ✓ 絕大多數動作都在 ROI 內，這個框看起來是對的。")

    print("\n" + "=" * 84)
    print("""下一步

  1. 上面的 ASCII 熱區圖對照一下實際擺設 —— 亮的那塊真的是床嗎？
  2. 是的話，把 ROI 加進 tapo_metric_logger.py 錄下一晚，
     門檻就能改用「佔 ROI 幾 %」表示
  3. 不是的話（例如亮的是窗簾），先調相機角度再錄一晚，
     比改演算法有效得多""")
    print("=" * 84)


if __name__ == "__main__":
    main()
