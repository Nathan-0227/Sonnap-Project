"""
tapo_metric_logger.py — 只記錄原始度量，不判事件、不設門檻、不評分。

═══════════════════════════════════════════════════════════════════
這支要解決什麼
═══════════════════════════════════════════════════════════════════
現行偵測器把「門檻」寫死在錄製階段：每一幀當場判成 micro / large / none，
只存分類不存數值。所以門檻一改就得重錄，而且不同夜晚的門檻不一樣、
又沒有記在任何欄位裡 —— 這就是 TAPO_HANDOFF #1 那個「跨夜不可比較」的根因。

這支反過來做：**把每一幀的連續度量寫進 CSV，一個門檻都不設。**
事件、分級、每小時事件率全部留到事後離線算，想換門檻就重跑 CSV，
**永遠不必再重錄一晚**。

跟現行偵測器的關係：
  - 完全獨立，不 import、不修改 tapo/ 或 tapo 2.0/ 的任何檔案
  - 可以同時跑（預設連 stream2，與現行偵測器的 stream1 分開，不搶頻寬）
  - 不寫資料庫、不存影片、不刪任何東西

═══════════════════════════════════════════════════════════════════
管線（TAPO_HANDOFF「建議的管線」那一節的實作）
═══════════════════════════════════════════════════════════════════
  降取樣 → 灰階 → 模糊 → 照明變化否決 → MOG2 背景相減
         → 開運算 → 連通域分析 → 記錄最大區塊

⚠️ 這裡**沒有 ROI**，是刻意的：ROI 可以事後從 CSV 裡的 bbox 累加推出來
   （TAPO_HANDOFF 的方案 B），現在框反而是猜。

用法
────
  python tapo_metric_logger.py --selftest 60      # 先跑 60 秒確認接得上
  python tapo_metric_logger.py                    # 整晚跑，Ctrl+C 結束

⚠️ RTSP 網址從 `tapo 2.0/.env` 的 CAMERA_RTSP_URL 讀，**永遠不印出來**
   （那是帳密，這個 repo 為此外洩過兩次）。
"""
import argparse
import csv
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
ENV_PATH = ROOT / "tapo 2.0" / ".env"
OUT_DIR = ROOT / "tapo_metrics"

# ─── 管線參數 ────────────────────────────────────────────────────
# ⚠️ 這些是**偵測參數**不是計分門檻，可以自由調（TAPO_HANDOFF
#    「偵測門檻 ≠ 計分門檻」那一節）。但改了要記進 CSV 的檔頭。
WIDTH, HEIGHT = 640, 360     # 降取樣：省算力，而且縮圖本身就在平均雜訊
TARGET_FPS = 5.0             # 動作中位數 4 秒（Montini 2024）→ 20 幀，夠了
BLUR_KERNEL = (7, 7)         # 21x21 是給 1080p 的，360p 要跟著縮
MOG2_HISTORY = 500
MOG2_VAR_THRESHOLD = 16
LEARNING_RATE = 1.0 / MOG2_HISTORY   # 明確寫出來，不用預設的 -1
OPEN_KERNEL_SIZE = 5         # 開運算：孤立雜訊點消失、大區塊保留
ILLUM_JUMP = 4.0             # 平均亮度跳這麼多 = 紅外燈切換／自動曝光，不是動作
RELEARN_FRAMES = 10          # 照明變化後讓背景重學幾幀
MIN_BLOB_PX = 4              # 小於這個不算一「塊」（純粹避免數到單點）
# MOG2 一開始沒有背景模型，整幀都會被判成前景（實測第 0 幀 = 100% 畫面）。
# 這段時間照樣記錄，但標成 warmup，事後一律排除。
WARMUP_SECONDS = 90

FLUSH_EVERY = 100            # 每幾列 flush 一次，斷電時損失有限

_stop = False


def _handle_stop(signum, frame):
    global _stop
    _stop = True


def read_rtsp_url():
    """從 .env 取 CAMERA_RTSP_URL。⚠️ 呼叫端不得印出回傳值。"""
    if not ENV_PATH.exists():
        sys.exit(f"✗ 找不到 {ENV_PATH}（那份不在版控裡，要自己放）")
    for line in ENV_PATH.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("CAMERA_RTSP_URL"):
            _, _, value = line.partition("=")
            url = value.strip().strip('"').strip("'")
            if url:
                return url
    sys.exit("✗ .env 裡沒有 CAMERA_RTSP_URL")


def to_substream(url):
    """
    改連 stream2（子碼流，約 640x360）。

    兩個好處：不與現行偵測器搶 stream1、頻寬與解碼成本低很多。
    而且它的原生解析度正好就是我們要降到的尺寸。
    """
    return url.replace("/stream1", "/stream2")


def describe(url):
    """能安全印出來的描述——只留 host 之後的路徑，帳密整段丟掉。"""
    tail = url.rsplit("@", 1)[-1]
    return f"rtsp://…@{tail}"


def open_capture(url):
    cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
    try:
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)     # 只要最新一幀，不要積壓
    except cv2.error:
        pass
    return cap


def run(url, out_path, selftest_seconds=None):
    fgbg = cv2.createBackgroundSubtractorMOG2(
        history=MOG2_HISTORY, varThreshold=MOG2_VAR_THRESHOLD, detectShadows=False
    )
    kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (OPEN_KERNEL_SIZE, OPEN_KERNEL_SIZE)
    )

    cap = open_capture(url)
    if not cap.isOpened():
        sys.exit(f"✗ 連不上 {describe(url)}\n"
                 "   檢查：相機開著嗎？在同一個網段嗎？.env 的密碼是換過之後的嗎？")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    started = datetime.now()
    deadline = time.time() + selftest_seconds if selftest_seconds else None
    interval = 1.0 / TARGET_FPS

    mean_prev = None
    relearn = 0
    rows = 0
    skipped_illum = 0
    reconnects = 0
    next_due = time.time()
    warm_from = time.time()      # 重連之後背景模型要重建，這個會跟著重設

    with out_path.open("w", newline="", encoding="utf-8") as fh:
        # 檔頭把參數寫進去——這樣這份 CSV 自己就說得出它是怎麼產生的，
        # 不必回頭查程式是哪一版（就是 TAPO_HANDOFF #1 要求的那件事）。
        fh.write(f"# tapo_metric_logger  started={started.isoformat()}\n")
        fh.write(f"# size={WIDTH}x{HEIGHT} fps={TARGET_FPS} blur={BLUR_KERNEL[0]} "
                 f"mog2_history={MOG2_HISTORY} var={MOG2_VAR_THRESHOLD} "
                 f"lr={LEARNING_RATE:.6f} open={OPEN_KERNEL_SIZE} "
                 f"illum_jump={ILLUM_JUMP} min_blob_px={MIN_BLOB_PX} warmup_s={WARMUP_SECONDS}\n")
        fh.write(f"# source={describe(url)}\n")
        writer = csv.writer(fh)
        writer.writerow([
            "t",          # ISO 時刻
            "mean",       # 整幀平均亮度（照明變化的證據）
            "raw_px",     # 開運算**前**的前景像素數 ← 舊程式的 countNonZero 等價物
            "fg_px",      # 開運算**後**的前景像素數
            "blobs",      # 連通區塊數（≥ MIN_BLOB_PX）
            "max_px",     # 最大區塊的面積 ← 這才是動作幅度
            "max_x", "max_y", "max_w", "max_h",   # 最大區塊的 bbox（事後推 ROI 用）
            "illum_skip", # 這一幀是否因照明變化被否決
            "warmup",     # 背景模型還沒建好，這一幀不可用
        ])

        print(f"● 連上 {describe(url)}")
        print(f"● 寫入 {out_path}")
        print(f"● {WIDTH}x{HEIGHT} @ {TARGET_FPS}fps，Ctrl+C 結束"
              + (f"（自測 {selftest_seconds} 秒）" if selftest_seconds else ""))

        while not _stop:
            if deadline and time.time() >= deadline:
                break

            ok, frame = cap.read()
            if not ok or frame is None:
                reconnects += 1
                print(f"⚠ 串流中斷，第 {reconnects} 次重連…")
                cap.release()
                time.sleep(min(2 * reconnects, 30))
                cap = open_capture(url)
                if not cap.isOpened():
                    continue
                mean_prev, relearn = None, RELEARN_FRAMES
                warm_from = time.time()
                continue

            now = time.time()
            if now < next_due:          # 依牆鐘節流，不依幀數（RTSP 幀率會浮動）
                continue
            next_due = now + interval

            if frame.shape[1] != WIDTH or frame.shape[0] != HEIGHT:
                frame = cv2.resize(frame, (WIDTH, HEIGHT))
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            blur = cv2.GaussianBlur(gray, BLUR_KERNEL, 0)
            mean_now = float(blur.mean())

            warming = 1 if (now - warm_from) < WARMUP_SECONDS else 0

            # ── 照明變化否決 ──
            illum_skip = 0
            if mean_prev is not None and abs(mean_now - mean_prev) > ILLUM_JUMP:
                fgbg.apply(blur, learningRate=0.2)     # 讓背景快速重學
                relearn = RELEARN_FRAMES
                illum_skip = 1
            mean_prev = mean_now

            if illum_skip or relearn > 0:
                if relearn > 0 and not illum_skip:
                    relearn -= 1
                    fgbg.apply(blur, learningRate=0.2)
                skipped_illum += 1
                writer.writerow([datetime.now().isoformat(timespec="milliseconds"),
                                 f"{mean_now:.2f}", "", "", "", "", "", "", "", "", 1, warming])
                rows += 1
                continue

            mask = fgbg.apply(blur, learningRate=LEARNING_RATE)
            raw_px = int(cv2.countNonZero(mask))
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
            fg_px = int(cv2.countNonZero(mask))

            n, _, stats, _ = cv2.connectedComponentsWithStats(mask)
            blobs = 0
            max_px = max_x = max_y = max_w = max_h = 0
            for i in range(1, n):                       # 第 0 個是背景
                area = int(stats[i, cv2.CC_STAT_AREA])
                if area < MIN_BLOB_PX:
                    continue
                blobs += 1
                if area > max_px:
                    max_px = area
                    max_x = int(stats[i, cv2.CC_STAT_LEFT])
                    max_y = int(stats[i, cv2.CC_STAT_TOP])
                    max_w = int(stats[i, cv2.CC_STAT_WIDTH])
                    max_h = int(stats[i, cv2.CC_STAT_HEIGHT])

            writer.writerow([datetime.now().isoformat(timespec="milliseconds"),
                             f"{mean_now:.2f}", raw_px, fg_px, blobs,
                             max_px, max_x, max_y, max_w, max_h, 0, warming])
            rows += 1
            if rows % FLUSH_EVERY == 0:
                fh.flush()

    cap.release()
    elapsed = (datetime.now() - started).total_seconds()
    print(f"\n● 結束：{rows} 列 / {elapsed / 3600:.2f} 小時"
          f"（照明否決 {skipped_illum} 列、重連 {reconnects} 次）")
    print(f"● {out_path}")
    return out_path


def preview(csv_path):
    """
    收工時的快速預覽。⚠️ 這**不是判定**，只是讓你當場知道資料有沒有錄壞。
    真正的門檻掃描是隔天的事。
    """
    frames, spans = [], []
    with csv_path.open(encoding="utf-8") as fh:
        rows = [r for r in csv.DictReader(l for l in fh if not l.startswith("#"))]
    usable = [r for r in rows
              if r["illum_skip"] == "0" and r.get("warmup") == "0" and r["max_px"]]
    if len(usable) < 10:
        print("⚠ 有效幀太少，先確認相機畫面是不是黑的。")
        return

    frame_area = WIDTH * HEIGHT
    fracs = sorted(int(r["max_px"]) / frame_area for r in usable)
    t0 = datetime.fromisoformat(usable[0]["t"])
    t1 = datetime.fromisoformat(usable[-1]["t"])
    hours = (t1 - t0).total_seconds() / 3600 or 1e-9
    warm = sum(1 for r in rows if r.get("warmup") == "1")

    print(f"\n  有效幀 {len(usable)} / 全部 {len(rows)}（暖機排除 {warm}），跨度 {hours:.2f} 小時")
    print(f"  最大區塊佔畫面比例：中位數 {fracs[len(fracs) // 2] * 100:.2f}%、"
          f"p95 {fracs[int(len(fracs) * 0.95)] * 100:.2f}%、最大 {fracs[-1] * 100:.2f}%")

    noise = [int(r["raw_px"]) - int(r["fg_px"]) for r in usable if r["raw_px"]]
    if noise:
        raw = [int(r["raw_px"]) for r in usable if r["raw_px"]]
        killed = sum(noise) / max(sum(raw), 1) * 100
        print(f"  開運算清掉了 {killed:.1f}% 的前景像素 ← 那些就是散布的雜訊")

    print("\n  門檻預覽（**不是判定**，隔天才做正式掃描）：")
    print(f"  {'門檻(佔畫面)':<14}{'有動作的幀':>10}{'佔比':>8}")
    for pct in (1, 2, 5, 10, 15, 20):
        hit = sum(1 for f in fracs if f * 100 >= pct)
        print(f"  {pct:>3}%{'':<10}{hit:>10}{hit / len(fracs) * 100:>7.1f}%")
    print("\n  → 隔天用這份 CSV 掃「門檻 vs 每小時事件數」，"
          "找落在 Montini 8–15 次/小時的那一段。")


def main():
    ap = argparse.ArgumentParser(description="TAPO 原始度量記錄器（不評分）")
    ap.add_argument("--selftest", type=int, metavar="秒",
                    help="只跑這麼多秒，用來確認接得上（建議睡前先跑 60）")
    ap.add_argument("--stream1", action="store_true",
                    help="用主碼流。預設走 stream2，才不會跟現行偵測器搶")
    ap.add_argument("--out", type=Path, help="輸出 CSV 路徑")
    args = ap.parse_args()

    signal.signal(signal.SIGINT, _handle_stop)
    signal.signal(signal.SIGTERM, _handle_stop)

    url = read_rtsp_url()
    if not args.stream1:
        url = to_substream(url)

    out = args.out or OUT_DIR / (
        datetime.now().strftime("%Y%m%d_%H%M%S")
        + ("_selftest" if args.selftest else "") + ".csv"
    )
    path = run(url, out, args.selftest)
    preview(path)


if __name__ == "__main__":
    main()
