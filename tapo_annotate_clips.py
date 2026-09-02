"""
tapo_annotate_clips.py — 用人工標註把偵測門檻釘下來。

═══════════════════════════════════════════════════════════════════
為什麼需要這一支
═══════════════════════════════════════════════════════════════════
前兩晚的實測暴露了一個方法上的錯：我原本說「掃門檻，找落在 Montini
IQR 的那一段」。**逐晚套用那個做法是循環論證** —— 它會強迫每一晚都讀成
「平均」，把夜與夜之間的差異（正是我們想量的東西）全部抹掉。

實測：固定 5% 門檻，第一晚 8.6 次/小時、第二晚 19.1 次/小時。
而兩晚的熱區重心（310,206 vs 302,191）與區塊大小分布
（中位數 2.57% vs 3.31%、p90 14.29% vs 14.46%）幾乎相同
—— 相機沒動、動作大小一樣，**變的是頻率**。那是真實的夜間差異，不是漂移。

所以正確的順序是：

  1. 門檻用**真值**定 —— 「什麼才算一次動作」是物理問題不是統計問題
  2. 文獻常模當**跨多晚的分布檢查**，不是逐晚的目標
  3. 門檻固定之後，每晚的數字本來就該不一樣

這一支做第 1 步。

═══════════════════════════════════════════════════════════════════
怎麼做
═══════════════════════════════════════════════════════════════════
`tapo 2.0/sleep_videos/` 有 126 個片段（1920x1080 @ 15fps，共約 35 分鐘），
是舊偵測器判定「大翻身」時錄下來的。人工看過、數出真正的動作次數，
就是標準答案。

⚠️ **標註必須是盲的** —— 標的時候不會顯示演算法的答案，否則人會被帶著走。
   所以分成三個獨立步驟，`--measure` 與標註互不相見。

⚠️ 片段是從動作觸發那一刻開始錄的，**沒有安靜的前段讓 MOG2 建背景**。
   所以 `--measure` 用兩趟：第一趟跑完整支建模型，第二趟凍結模型
   （learningRate=0）才量測。用的是跟即時管線完全相同的運算子。

⚠️ 這支**不評分**。它定的是偵測門檻，靠效標校準、不受紅線 2 約束
   （見 TAPO_HANDOFF「偵測門檻 ≠ 計分門檻」）。

用法
────
  python tapo_annotate_clips.py --measure        # ① 演算法先跑（不需要人）
  python tapo_annotate_clips.py                  # ② 人工盲標（可中斷、可續做）
  python tapo_annotate_clips.py --compare        # ③ 對照

標註時的按鍵：
  0-9  這個片段裡有幾次真正的動作（看完再按）
  r    重播      b    回上一個      s    跳過（不確定）
  q    存檔離開（下次接著標）
"""
import argparse
import csv
import random
import sys
from pathlib import Path

import os
os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")

import cv2
import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
CLIP_DIR = ROOT / "tapo 2.0" / "sleep_videos"
OUT_DIR = ROOT / "tapo_metrics"
TRUTH_CSV = OUT_DIR / "clip_truth.csv"
MEASURE_CSV = OUT_DIR / "clip_measure.csv"

# ─── 與 tapo_metric_logger 對齊的管線參數（改了兩邊都要改）─────────
WIDTH, HEIGHT = 640, 360
FRAME_AREA = WIDTH * HEIGHT
BLUR_KERNEL = (7, 7)
MOG2_HISTORY = 500
MOG2_VAR_THRESHOLD = 16
OPEN_KERNEL_SIZE = 5
MIN_BLOB_PX = 4

# 事件聚合（與 tapo_scan_threshold 對齊）
START_FRAMES = 3
END_FRAMES = 15

SAMPLE_SIZE = 30      # 預設抽這麼多支來標；--all 標全部
SAMPLE_SEED = 20260902   # 固定種子，抽樣可重現


def clips():
    return sorted(CLIP_DIR.glob("*.mp4"))


def sample(files, n, seed=SAMPLE_SEED):
    if n >= len(files):
        return files
    rng = random.Random(seed)
    return sorted(rng.sample(files, n))


# ═══════════════════════════════════════════════════════════════════
# ① --measure：演算法自己跑一遍（不需要人，也不該看到人的答案）
# ═══════════════════════════════════════════════════════════════════

def measure_clip(path):
    """
    兩趟：先建 MOG2 背景模型，再凍結模型量測。

    回傳每幀的「最大連通區塊佔畫面比例」。取不到就回 None。
    """
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (OPEN_KERNEL_SIZE, OPEN_KERNEL_SIZE))

    def frames():
        cap = cv2.VideoCapture(str(path))
        if not cap.isOpened():
            return
        try:
            while True:
                ok, fr = cap.read()
                if not ok or fr is None:
                    return
                fr = cv2.resize(fr, (WIDTH, HEIGHT))
                yield cv2.GaussianBlur(
                    cv2.cvtColor(fr, cv2.COLOR_BGR2GRAY), BLUR_KERNEL, 0)
        finally:
            cap.release()

    fgbg = cv2.createBackgroundSubtractorMOG2(
        history=MOG2_HISTORY, varThreshold=MOG2_VAR_THRESHOLD, detectShadows=False)

    # 第一趟：只建模型，不取結果
    count = 0
    for blur in frames():
        fgbg.apply(blur)                 # 用預設學習率讓模型收斂
        count += 1
    if count < 10:
        return None

    # 第二趟：凍結模型（learningRate=0），這才是量測
    fracs = []
    for blur in frames():
        mask = fgbg.apply(blur, learningRate=0.0)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        n, _, stats, _ = cv2.connectedComponentsWithStats(mask)
        biggest = 0
        for i in range(1, n):
            a = int(stats[i, cv2.CC_STAT_AREA])
            if a >= MIN_BLOB_PX and a > biggest:
                biggest = a
        fracs.append(biggest / FRAME_AREA)
    return fracs


def count_episodes(fracs, threshold,
                   start_frames=START_FRAMES, end_frames=END_FRAMES):
    """與 tapo_scan_threshold.episodes 同一套聚合規則，只回次數。"""
    n = motion_run = quiet_run = 0
    in_ep = False
    for f in fracs:
        if f >= threshold:
            quiet_run = 0
            if not in_ep:
                motion_run += 1
                if motion_run >= start_frames:
                    in_ep = True
                    n += 1
        else:
            motion_run = 0
            if in_ep:
                quiet_run += 1
                if quiet_run >= end_frames:
                    in_ep = False
    return n


GRID = [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 7.5, 10.0, 15.0]


def cmd_measure(files):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"對 {len(files)} 個片段跑管線（兩趟，會花幾分鐘）…")
    with MEASURE_CSV.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["clip", "frames", "max_frac", "p95_frac"]
                   + [f"n@{p}%" for p in GRID])
        bad = 0
        for i, p in enumerate(files, 1):
            fracs = measure_clip(p)
            if not fracs:
                bad += 1
                print(f"  [{i}/{len(files)}] {p.name} ✗ 讀不到（檔案壞了）")
                continue
            row = [p.name, len(fracs), f"{max(fracs):.5f}",
                   f"{float(np.percentile(fracs, 95)):.5f}"]
            row += [count_episodes(fracs, t / 100) for t in GRID]
            w.writerow(row)
            print(f"  [{i}/{len(files)}] {p.name}  最大 {max(fracs) * 100:5.2f}% 畫面")
    print(f"\n✓ 寫入 {MEASURE_CSV}" + (f"（{bad} 個檔壞掉，已跳過）" if bad else ""))


# ═══════════════════════════════════════════════════════════════════
# ② 人工盲標
# ═══════════════════════════════════════════════════════════════════

WIN = "TAPO clip annotation"


def load_truth():
    if not TRUTH_CSV.exists():
        return {}
    with TRUTH_CSV.open(encoding="utf-8") as fh:
        return {r["clip"]: r for r in csv.DictReader(fh)}


def save_truth(done):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with TRUTH_CSV.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["clip", "n_movements", "note"])
        for name in sorted(done):
            r = done[name]
            w.writerow([name, r["n_movements"], r.get("note", "")])


def play_once(path, speed_ms=45):
    """播一遍。回傳使用者在播放中按下的鍵（沒按就回 -1）。"""
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        return ord("s")
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    idx = 0
    key = -1
    while True:
        ok, fr = cap.read()
        if not ok or fr is None:
            break
        idx += 1
        fr = cv2.resize(fr, (960, 540))
        bar = int(960 * idx / total)
        cv2.rectangle(fr, (0, 530), (bar, 540), (0, 200, 255), -1)
        cv2.putText(fr, f"{path.name}   {idx}/{total}", (12, 28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 4)
        cv2.putText(fr, f"{path.name}   {idx}/{total}", (12, 28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
        cv2.putText(fr, "0-9 = how many movements | r replay | b back | s skip | q quit",
                    (12, 512), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 4)
        cv2.putText(fr, "0-9 = how many movements | r replay | b back | s skip | q quit",
                    (12, 512), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        cv2.imshow(WIN, fr)
        k = cv2.waitKey(speed_ms) & 0xFF
        if k != 255:
            key = k
            if k in (ord("q"), ord("b"), ord("s")) or ord("0") <= k <= ord("9"):
                break
    cap.release()
    return key


def cmd_annotate(files):
    done = load_truth()
    todo = [p for p in files if p.name not in done]
    print(f"共 {len(files)} 支，已標 {len(files) - len(todo)} 支，還剩 {len(todo)} 支。")
    if not todo:
        print("全部標完了。跑 --compare 看結果。")
        return
    print("""
規則（請一致，這是標準答案）：
  數的是「**身體的動作**」次數 —— 翻身、抬手、調整姿勢都算一次。
  中間隔一兩秒的算同一次；明顯停下來再動才算下一次。
  畫面在動但不是人（光線變化、雜訊）**不算**。
  完全沒動就按 0。看不清楚按 s 跳過，不要猜。
""")
    cv2.namedWindow(WIN, cv2.WINDOW_AUTOSIZE)
    i = 0
    order = list(todo)
    while 0 <= i < len(order):
        p = order[i]
        while True:
            k = play_once(p)
            if k == ord("r") or k == -1:
                continue
            break
        if k == ord("q"):
            break
        if k == ord("b"):
            i = max(0, i - 1)
            continue
        if k == ord("s"):
            done[p.name] = {"n_movements": "", "note": "skipped"}
        elif ord("0") <= k <= ord("9"):
            done[p.name] = {"n_movements": str(k - ord("0")), "note": ""}
        else:
            continue
        save_truth(done)
        i += 1
    cv2.destroyAllWindows()
    save_truth(done)
    n = sum(1 for r in done.values() if r["n_movements"] != "")
    print(f"\n✓ 已標 {n} 支，寫入 {TRUTH_CSV}")
    print("  隨時可以再跑一次接著標；標夠了跑 --compare。")


# ═══════════════════════════════════════════════════════════════════
# ③ 對照
# ═══════════════════════════════════════════════════════════════════

def cmd_compare():
    if not (TRUTH_CSV.exists() and MEASURE_CSV.exists()):
        sys.exit("✗ 需要先跑 --measure 與人工標註兩者。")
    with TRUTH_CSV.open(encoding="utf-8") as fh:
        truth = {r["clip"]: r for r in csv.DictReader(fh)
                 if r["n_movements"] != ""}
    with MEASURE_CSV.open(encoding="utf-8") as fh:
        meas = {r["clip"]: r for r in csv.DictReader(fh)}
    both = sorted(set(truth) & set(meas))
    if len(both) < 5:
        sys.exit(f"✗ 兩邊都有的片段只有 {len(both)} 支，太少。再標幾支。")

    human = [int(truth[c]["n_movements"]) for c in both]
    print("=" * 84)
    print(f"門檻 vs 人工標註（n={len(both)} 支片段）")
    print("=" * 84)
    print(f"人工總計 {sum(human)} 次動作，"
          f"{sum(1 for h in human if h == 0)} 支被標成完全沒動")
    print()
    print(f"{'門檻':>8}{'演算法總計':>12}{'差距':>8}{'完全吻合':>10}"
          f"{'誤報':>8}{'漏報':>8}  判讀")
    print("-" * 84)

    best = None
    for p in GRID:
        algo = [int(meas[c][f"n@{p}%"]) for c in both]
        diff = sum(algo) - sum(human)
        exact = sum(1 for a, h in zip(algo, human) if a == h)
        fp = sum(max(a - h, 0) for a, h in zip(algo, human))
        fn = sum(max(h - a, 0) for a, h in zip(algo, human))
        err = fp + fn
        if best is None or err < best[1]:
            best = (p, err)
        print(f"{p:>7.1f}%{sum(algo):>12}{diff:>+8}{exact:>9}/{len(both)}"
              f"{fp:>8}{fn:>8}")

    print("-" * 84)
    print(f"\n★ 總誤差最小的門檻：{best[0]}% 畫面（誤報+漏報 = {best[1]} 次）")
    print("""
  ⚠️ 這個數字才是可以拿去用的偵測門檻 —— 它是拿真值校準出來的，
     不是為了湊出某個每小時次數。

  ⚠️ 但它還帶著兩個限制：
     1. 這些片段是**舊偵測器判定為大翻身時**才錄的，所以樣本偏向
        「有動作」的時刻。量得到準確率，量不到漏報率
        （偵測器完全沒反應的那些時刻沒有影片）。
     2. 片段是 stream1（1920x1080），即時記錄是 stream2。
        兩者都降到 640x360 才處理，但壓縮假影可能不同。

  → 門檻定下來之後，回去用 tapo_scan_threshold.py 對整夜資料跑一次，
    看每晚的事件率**分布**有沒有落在 Montini 的 8-15 附近。
    注意是看分布，不是逐晚硬套 —— 逐晚硬套就是循環論證。""")
    print("=" * 84)


def main():
    ap = argparse.ArgumentParser(description="用人工標註校準偵測門檻（不評分）")
    ap.add_argument("--measure", action="store_true", help="① 演算法先跑一遍")
    ap.add_argument("--compare", action="store_true", help="③ 對照真值與演算法")
    ap.add_argument("--all", action="store_true",
                    help=f"用全部片段，不只抽樣的 {SAMPLE_SIZE} 支")
    ap.add_argument("-n", type=int, default=SAMPLE_SIZE, help="抽樣支數")
    args = ap.parse_args()

    files = clips()
    if not files:
        sys.exit(f"✗ {CLIP_DIR} 底下沒有 .mp4")
    picked = files if args.all else sample(files, args.n)

    if args.compare:
        cmd_compare()
    elif args.measure:
        cmd_measure(picked)
    else:
        cmd_annotate(picked)


if __name__ == "__main__":
    main()
