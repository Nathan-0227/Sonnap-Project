"""
tapo_roi_experiment.py — ROI 到底有沒有用？用人工標註驗，不是用眼睛猜。

═══════════════════════════════════════════════════════════════════
要回答的問題
═══════════════════════════════════════════════════════════════════
第 4 晚的精確率只有 65%（第 3 晚是 86%），而使用者指出畫面裡**還有室友**。
假設是：誤報大多來自床以外的動作，只看床就能擋掉。

但「加了 ROI 感覺乾淨多了」不是證據。這支把它變成可否證的：

  1. 只用**人工標記的那些幀**累積熱區圖 → 這是「我的動作發生在哪裡」
  2. 只用**沒被標記的幀**累積另一張   → 這是「誤報發生在哪裡」
  3. 兩張疊起來看，室友如果存在，會是空間上分得開的另一團
  4. 從第 1 張推出 ROI，套回整晚重跑，看召回/精確/F1 有沒有真的變好

第 3 步就足以否證整個假設：**兩張圖如果重疊，ROI 就救不了**，
因為誤報跟真動作在同一個地方，任何框都會同時擋掉兩者。

═══════════════════════════════════════════════════════════════════
⚠️ 這裡有一個循環論證的風險，必須靠交叉驗證解掉
═══════════════════════════════════════════════════════════════════
用第 4 晚的標註推 ROI、再用第 4 晚的標註驗 ROI，等於拿答案去對答案，
F1 一定會變好，那個數字沒有意義。

所以真正的判準是 `--apply-roi`：**用另一晚推出來的 ROI**。
兩晚的相機沒動過，如果 ROI 真的在框床，A 晚的框套到 B 晚也該有效。
只有跨晚仍然改善，才算 ROI 有用。

⚠️ 這支**不評分、不寫任何分數**，只讀影片與標註、印表。
   ROI 是**偵測門檻**那一側的東西，靠人工標註校準，不受設計紅線 2 約束。
   → 見 docs/TAPO_HANDOFF.md「偵測門檻 ≠ 計分門檻」。

⚠️ 它讀的是**影片**不是 CSV。CSV 只記了最大區塊，床外的動作事後除不掉；
   要換分母就必須從影片重跑整條管線。管線常數與 tapo_metric_logger.py
   逐項對齊，改了那邊這裡要跟著改。

用法
────
  python tapo_roi_experiment.py tapo_metrics/20260904_020202.csv
      → 推 ROI + 自我驗證（會過度樂觀，只當參考）

  python tapo_roi_experiment.py <csv> --apply-roi 152,37,391,323
      → 拿外來的 ROI 驗（這個才算數）

  加 --cache 會把熱區圖存成 .npz，之後重跑用得到。
"""
import argparse
import sys
from pathlib import Path

import os
os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")

import cv2
import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from tapo_annotate_continuous import (
    load_truth, truth_path_for, video_path_for,
    detect_episodes, match,
    TOLERANCE_SECONDS,
    MONTINI_MI_MEDIAN, MONTINI_MI_IQR,
)

# ── 必須與 tapo_metric_logger.py 逐項一致，否則重跑出來的不是同一個東西 ──
WIDTH, HEIGHT = 640, 360
FRAME_AREA = WIDTH * HEIGHT
FPS = 5.0
BLUR_KERNEL = (7, 7)
MOG2_HISTORY = 500
MOG2_VAR_THRESHOLD = 16
LEARNING_RATE = 1.0 / MOG2_HISTORY
OPEN_KERNEL_SIZE = 5
PIXEL_DELTA = 3
ILLUM_DOMINANT_FRAC = 0.5
RELEARN_FRAMES = 5
MIN_BLOB_PX = 4
WARMUP_SECONDS = 90
HEAT_MIN_FRAC = 0.01

WARMUP_FRAMES = int(WARMUP_SECONDS * FPS)

# 門檻格點用「佔 ROI 的百分比」。ROI 越小，同一個動作佔比越大，
# 所以格點要比整畫面版往上延伸，否則最佳值會卡在端點。
GRID = [0.2, 0.3, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0,
        5.0, 7.5, 10.0, 15.0, 20.0, 30.0, 40.0]

HEAT_PERCENTILES = (50, 60, 70, 80)


def rule(ch="-", n=96):
    print(ch * n)


def rect_mask(box):
    """(x, y, w, h) → uint8 遮罩。None 代表整個畫面。"""
    if box is None:
        return None
    x, y, w, h = box
    m = np.zeros((HEIGHT, WIDTH), np.uint8)
    m[max(y, 0):y + h, max(x, 0):x + w] = 255
    return m


def analyze(video_path, rois, mark_window=None, reviewed=None, want_heat=False):
    """
    解碼影片一次，重跑與 logger 完全相同的管線。

    rois       : [(名稱, (x,y,w,h) 或 None)]
    mark_window: set[int]，人工標記 ±容許誤差 涵蓋到的幀（要熱區分流時才給）

    回傳 (fracs, heat_in, heat_out, n_in, n_out)。
    fracs[i][f] = 第 i 個 ROI 在第 f 幀的「最大區塊佔 ROI 面積」比例；
    照明否決與暖機的幀是 nan（與 CSV 的語意一致）。
    """
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        sys.exit(f"✗ 打不開 {video_path}")

    masks = [rect_mask(b) for _, b in rois]
    areas = [FRAME_AREA if m is None else int(cv2.countNonZero(m)) for m in masks]

    fgbg = cv2.createBackgroundSubtractorMOG2(
        history=MOG2_HISTORY, varThreshold=MOG2_VAR_THRESHOLD, detectShadows=False)
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (OPEN_KERNEL_SIZE, OPEN_KERNEL_SIZE))

    fracs = [[] for _ in rois]
    heat_in = np.zeros((HEIGHT, WIDTH), np.float32)
    heat_out = np.zeros((HEIGHT, WIDTH), np.float32)
    n_in = n_out = 0

    prev_blur = None
    relearn = 0
    f = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        else:
            gray = frame
        if gray.shape != (HEIGHT, WIDTH):
            gray = cv2.resize(gray, (WIDTH, HEIGHT))
        blur = cv2.GaussianBlur(gray, BLUR_KERNEL, 0)

        illum = False
        if prev_blur is not None:
            diff = blur.astype(np.int16) - prev_blur
            dominant = max(float((diff > PIXEL_DELTA).mean()),
                           float((diff < -PIXEL_DELTA).mean()))
            if dominant > ILLUM_DOMINANT_FRAC:
                fgbg.apply(blur, learningRate=0.2)
                relearn = RELEARN_FRAMES
                illum = True
        prev_blur = blur

        if illum or relearn > 0 or f < WARMUP_FRAMES:
            if relearn > 0 and not illum:
                relearn -= 1
                fgbg.apply(blur, learningRate=0.2)
            elif f < WARMUP_FRAMES and not illum:
                fgbg.apply(blur, learningRate=LEARNING_RATE)
            for a in fracs:
                a.append(np.nan)
            f += 1
            continue

        mask = fgbg.apply(blur, learningRate=LEARNING_RATE)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

        for i, m in enumerate(masks):
            mm = mask if m is None else cv2.bitwise_and(mask, m)
            n, labels, stats, _ = cv2.connectedComponentsWithStats(mm)
            best = 0
            best_label = -1
            for k in range(1, n):
                a = int(stats[k, cv2.CC_STAT_AREA])
                if a < MIN_BLOB_PX:
                    continue
                if a > best:
                    best, best_label = a, k
            fracs[i].append(best / areas[i])

            # 熱區圖只由第一個（整畫面）ROI 累積，而且只收夠大的區塊
            if want_heat and i == 0 and best / FRAME_AREA >= HEAT_MIN_FRAC:
                in_reviewed = reviewed is None or any(s <= f <= e for s, e in reviewed)
                if in_reviewed:
                    if mark_window is not None and f in mark_window:
                        heat_in[labels == best_label] += 1.0
                        n_in += 1
                    else:
                        heat_out[labels == best_label] += 1.0
                        n_out += 1
        f += 1
        if f % 4000 == 0:
            print(f"  … {f} 幀", flush=True)

    cap.release()
    return ([np.asarray(a, dtype=np.float32) for a in fracs],
            heat_in, heat_out, n_in, n_out)


def ascii_heat(heat, rows=14, cols=56, label=""):
    small = cv2.resize(heat, (cols, rows), interpolation=cv2.INTER_AREA)
    peak = float(small.max()) or 1.0
    ramp = " .:-=+*#%@"
    if label:
        print(f"  {label}")
    print("    +" + "-" * cols + "+")
    for r in range(rows):
        line = "".join(
            ramp[min(int(small[r, c] / peak * (len(ramp) - 1)), len(ramp) - 1)]
            for c in range(cols))
        print(f"    |{line}|")
    print("    +" + "-" * cols + "+")
    print(f"     0 ── {peak:.2f}")


def overlap_iou(a, b, percentile=70):
    """
    兩張熱區圖「前段熱區」的交集比。這是 ROI 假設成立與否的關鍵數字：
    真動作與誤報如果落在同一塊，IoU 會很高，任何框都同時擋掉兩者。
    """
    ha, hb = a[a > 0], b[b > 0]
    if ha.size == 0 or hb.size == 0:
        return None
    ma = a >= np.percentile(ha, percentile)
    mb = b >= np.percentile(hb, percentile)
    inter = int(np.count_nonzero(ma & mb))
    union = int(np.count_nonzero(ma | mb))
    return inter / union if union else None


def box_from_heat(heat, percentile):
    """取熱度前段、閉運算補洞，回傳最大連通區塊的外接矩形。"""
    hot = heat[heat > 0]
    if hot.size == 0:
        return None
    cutoff = float(np.percentile(hot, percentile))
    m = (heat >= cutoff).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE,
                         cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
    n, _, stats, _ = cv2.connectedComponentsWithStats(m)
    if n <= 1:
        return None
    i = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (int(stats[i, cv2.CC_STAT_LEFT]), int(stats[i, cv2.CC_STAT_TOP]),
            int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT]))


def score(frac, marks, reviewed, hours):
    """掃門檻，回傳 [(門檻%, 事件數, 召回, 精確, F1, 誤報/小時)]。"""
    tol = int(TOLERANCE_SECONDS * FPS)
    out = []
    for p in GRID:
        eps = []
        for s, e in reviewed:
            hi = min(e, len(frac) - 1)
            pairs = [(vf, (None if np.isnan(frac[vf]) else float(frac[vf])))
                     for vf in range(max(s, 0), hi + 1)]
            eps.extend(detect_episodes(pairs, p / 100))
        tp_marks, tp_eps = match(eps, marks, tol)
        recall = tp_marks / len(marks) if marks else 0.0
        precision = tp_eps / len(eps) if eps else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
        fp_h = (len(eps) - tp_eps) / hours if hours else 0.0
        out.append((p, len(eps), recall, precision, f1, fp_h))
    return out


def print_table(name, rows, roi_area):
    ratio = roi_area / FRAME_AREA
    print(f"\n【{name}】ROI {roi_area} px（佔畫面 {ratio * 100:.1f}%）")
    print(f"{'門檻(佔ROI)':>13}{'≈佔畫面':>10}{'事件':>7}{'召回':>8}{'精確':>8}"
          f"{'F1':>7}{'誤報/時':>9}")
    rule()
    for p, n, rc, pr, f1, fph in rows:
        print(f"{p:>12.2f}%{p * ratio:>9.2f}%{n:>7}{rc * 100:>7.0f}%"
              f"{pr * 100:>7.0f}%{f1:>7.2f}{fph:>9.1f}")
    best = max(rows, key=lambda r: r[4])
    edge = best[0] in (GRID[0], GRID[-1])
    flag = "  ⚠️ 端點，最佳值可能在格點外" if edge else ""
    print(f"  → 最佳 F1 {best[4]:.2f} @ {best[0]}% ROI"
          f"（召回 {best[2] * 100:.0f}%、精確 {best[3] * 100:.0f}%）{flag}")
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", type=Path)
    ap.add_argument("--apply-roi", action="append", default=[],
                    metavar="X,Y,W,H",
                    help="外來的 ROI（跨晚驗證用，這個才算數）。可重複給多個。")
    ap.add_argument("--cache", action="store_true", help="把熱區圖存成 npz")
    args = ap.parse_args()

    video = video_path_for(args.csv)
    if not video.exists():
        sys.exit(f"✗ 找不到影片 {video}")
    marks, reviewed = load_truth(truth_path_for(args.csv))
    if not marks or not reviewed:
        sys.exit("✗ 沒有人工標註，這支沒東西可以驗。")

    tol = int(TOLERANCE_SECONDS * FPS)
    mark_window = set()
    for m in marks:
        mark_window.update(range(m - tol, m + tol + 1))
    reviewed_frames = sum(e - s + 1 for s, e in reviewed)
    hours = reviewed_frames / FPS / 3600

    print("=" * 96)
    print(f"ROI 實驗：{args.csv.name}")
    print(f"已審視 {reviewed_frames} 幀（{hours * 60:.1f} 分鐘）、"
          f"人工標記 {len(marks)} 次、容許誤差 ±{TOLERANCE_SECONDS:.0f} 秒")
    print(f"人工事件率 {len(marks) / hours:.1f} 次/小時"
          f"（Montini 2024：{MONTINI_MI_MEDIAN}，"
          f"IQR {MONTINI_MI_IQR[0]}–{MONTINI_MI_IQR[1]}）")
    print("=" * 96)

    # ── 第一趟：整畫面 + 熱區分流 ──
    print("\n第一趟解碼（整畫面，同時把熱區依人工標記分流）…")
    _, heat_in, heat_out, n_in, n_out = analyze(
        video, [("整畫面", None)], mark_window=mark_window,
        reviewed=reviewed, want_heat=True)

    print(f"\n熱區分流：標記涵蓋 {n_in} 幀、其餘 {n_out} 幀"
          f"（都只算最大區塊 ≥{HEAT_MIN_FRAC * 100:.0f}% 畫面的幀）")
    if n_in < 20:
        print("⚠️ 標記涵蓋的幀太少，推出來的 ROI 不可靠。")

    print()
    ascii_heat(heat_in, label="① 人工標記期間 —— 這是「我」在動的地方")
    print()
    ascii_heat(heat_out, label="② 其餘時間 —— 誤報來源（室友？窗簾？雜訊？）")

    # 判別圖：兩張各自正規化後相減，只留「我這裡比較熱」的地方。
    a = heat_in / max(n_in, 1)
    b = heat_out / max(n_out, 1)
    disc = np.clip(a - b, 0, None)
    print()
    ascii_heat(disc, label="③ ①−②（各自正規化）—— 只屬於我、不屬於誤報的區域")

    iou = overlap_iou(heat_in, heat_out)
    if iou is not None:
        print(f"\n①②前 30% 熱區的 IoU = {iou:.2f}")
        if iou > 0.5:
            print("  ⚠️ **重疊很高 —— ROI 在原理上救不了這一晚。**")
            print("     誤報跟真動作發生在同一塊區域，任何框都會同時擋掉兩者。")
            print("     這代表誤報的來源不是「床以外的人事物」，"
                  "而是床上沒被標記的小動作或雜訊。")
        else:
            print("  ✓ 分得開 —— 空間上確實有兩個來源，ROI 有機會擋掉其中一個。")

    # ── 候選 ROI ──
    cands = [("整畫面", None)]
    seen = set()
    for spec in args.apply_roi:
        box = tuple(int(v) for v in spec.split(","))
        if box not in seen:
            seen.add(box)
            cands.append((f"外來 ROI {box}", box))
    for p in HEAT_PERCENTILES:
        box = box_from_heat(heat_in, p)
        if box and box not in seen:
            seen.add(box)
            cands.append((f"標記熱區 p{p} {box}", box))
    box = box_from_heat(disc, 70)
    if box and box not in seen:
        cands.append((f"判別圖 p70 {box}", box))

    print("\n候選 ROI：")
    for name, b in cands:
        if b is None:
            print("  - 整畫面（基準）")
        else:
            print(f"  - {name}  佔畫面 {b[2] * b[3] / FRAME_AREA * 100:.1f}%")

    # ── 第二趟：所有候選一起跑，只解碼一次 ──
    print("\n第二趟解碼（所有候選 ROI 同時算）…")
    fracs2, _, _, _, _ = analyze(video, cands)

    print("\n" + "=" * 96)
    print("結果")
    print("=" * 96)
    summary = []
    for (name, b), fr in zip(cands, fracs2):
        area = FRAME_AREA if b is None else b[2] * b[3]
        best = print_table(name, score(fr, marks, reviewed, hours), area)
        summary.append((name, b, best))

    print("\n" + "=" * 96)
    print("對照")
    rule()
    base = summary[0][2]
    print(f"{'ROI':<36}{'最佳門檻':>10}{'召回':>8}{'精確':>8}{'F1':>7}{'vs 整畫面':>12}")
    for name, b, best in summary:
        mark = "—" if b is None else f"{best[4] - base[4]:+.2f}"
        print(f"{name[:35]:<36}{best[0]:>9.2f}%{best[2] * 100:>7.0f}%"
              f"{best[3] * 100:>7.0f}%{best[4]:>7.2f}{mark:>12}")

    print("""
判讀
  · 精確率上升而召回率沒掉 → ROI 真的擋掉了床以外的誤報
  · 兩個都掉                → ROI 把床切掉了一部分，框太小
  · 幾乎沒變                → 誤報不是空間問題（是雜訊或門檻），ROI 幫不上忙

⚠️ 「標記熱區 pXX」那幾列是**拿同一晚的答案推、再用同一晚驗**，一定偏樂觀。
   要當結論，必須看 --apply-roi 那一列（用另一晚推出來的框）。""")

    if args.cache:
        out = args.csv.with_name(args.csv.stem + "_roi.npz")
        np.savez_compressed(out, heat_in=heat_in, heat_out=heat_out,
                            disc=disc, n_in=n_in, n_out=n_out)
        print(f"\n● 已存 {out.name}")
    print("=" * 96)


if __name__ == "__main__":
    main()
