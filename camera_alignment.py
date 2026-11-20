"""
camera_alignment.py — 攝影機有沒有被移動（2026-11-21 使用者 grill 定案 Q12、Q14、Q15、Q17）。

錄影程式整晚在第 15／30／60／90／120 分鐘各存一張原始畫面（`<那一晚>_frame_NNN.png`）。
這支拿每一張跟**基準畫面**比，算平移了幾個像素，取中間值；超過門檻就判「可能移動了」，
早上匯入那一晚的攝影機資料就不匯入。

⚠️ 為什麼要擋：床鋪框（ROI）是照當初的擺放推出來的。攝影機被碰歪，框就框到別的地方，
   動作次數、片段、「跟你平常比」全部悄悄變錯，而且**沒有任何錯誤訊息**。
⚠️ **只判定、絕不自動改框**：上次讓程式自己推框，有室友的那晚整個選錯（TAPO_HANDOFF）。
   改框走 camera_reframe.py，由人確認。

⚠️ **只比床鋪框上方那一條**（牆、層架），不比整張。2026-11-21 拿 10 晚真實錄影試：
   畫面下半部是人和被子、每晚都不一樣，整張比的話攝影機沒動也會從 2 跳到 259 像素；
   只比上方那一條、5 張取中間值，9/10 晚是 1～4 像素，
   另一晚（11-09）中間值 32——看畫面那晚攝影機真的擺得不一樣（上方的牆、層架都換了位置）。
⚠️ 抓得到的是**攝影機**移動。**床移動、攝影機沒動**時上方的牆不會動，這支抓不到——
   那種情況靠存下來的那張畫上框的照片（`_snapshot.png`）給人看。

基準：tapo_metrics/reference/frame.png＋roi.json（那張基準是在哪個框底下拍的，決定「上方」到哪裡）。
第一次從當初推出框的那晚錄影 20260903_020631.mp4 第 30 分鐘取一格（人已經躺好）。
重新框的時候 camera_reframe.py 會換基準，舊的備份起來（Q17）。

用法
────
  python camera_alignment.py --make-reference tapo_metrics/20260903_020631.mp4 --roi 34,129,288,231
  python camera_alignment.py tapo_metrics/20261121_013000.csv      # 檢查一晚
"""
import argparse
import json
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
METRICS_DIR = ROOT / "tapo_metrics"
REFERENCE_DIR_NAME = "reference"
REFERENCE_FRAME_NAME = "frame.png"
REFERENCE_ROI_NAME = "roi.json"
# 與 tapo_metric_logger 的檔名相同（這支不 import 那支；tests/test_camera_auto.py 守著兩邊一致）
SNAPSHOT_FRAME_GLOB = "_frame_*.png"
SNAPSHOT_BOX_SUFFIX = "_snapshot.png"

# ⚠️ **設計決策、沒有文獻**（使用者 2026-11-21 定）：框寬 288 的約 1/10。
#    10 晚實測沒動的晚上中間值 1～4 像素、擺歪那晚 32，門檻落在中間。
MOVE_THRESHOLD_PX = 30.0
# 床鋪框上緣再往上留幾個像素才開始算「上方」（框邊緣附近常有枕頭、頭髮）
STRIP_MARGIN_PX = 9
# 上方那一條太窄（框貼著畫面頂端）就沒有東西可比，退回整張
MIN_STRIP_PX = 60
# 從基準影片取第幾秒那一格（人已經躺好）
REFERENCE_AT_SECONDS = 1800.0


@dataclass
class Alignment:
    status: str                    # ok／moved／no_snapshot／no_reference
    shift_px: float = 0.0          # 幾張的中間值
    shifts: list = field(default_factory=list)
    snapshot: Path = None          # 畫上框的那張（給人看）

    @property
    def moved(self):
        return self.status == "moved"


def _prepare(gray):
    """標準化亮度（扣平均、除標準差）再加漢寧窗——全域明暗變化不會被當成平移。"""
    img = gray.astype(np.float32)
    img = cv2.GaussianBlur(img, (5, 5), 0)
    img = (img - img.mean()) / (img.std() + 1e-6)
    window = cv2.createHanningWindow((img.shape[1], img.shape[0]), cv2.CV_32F)
    return img * window


def strip_height(roi):
    """比對用的上方那一條有多高。沒有框或太窄回 None（＝比整張）。"""
    if not roi:
        return None
    h = int(roi[1]) - STRIP_MARGIN_PX
    return h if h >= MIN_STRIP_PX else None


def frame_shift(reference, current, roi=None):
    """兩張灰階畫面之間平移了幾個像素（相位相關）。給了 roi 就只比框上方那一條。"""
    if reference.shape != current.shape:
        current = cv2.resize(current, (reference.shape[1], reference.shape[0]))
    top = strip_height(roi)
    if top:
        reference, current = reference[:top, :], current[:top, :]
    (dx, dy), _response = cv2.phaseCorrelate(_prepare(reference), _prepare(current))
    return float(np.hypot(dx, dy))


def reference_dir(metrics_dir=METRICS_DIR):
    return Path(metrics_dir) / REFERENCE_DIR_NAME


def load_reference(metrics_dir=METRICS_DIR):
    """回傳 (灰階畫面, roi) 或 (None, None)。"""
    d = reference_dir(metrics_dir)
    frame = cv2.imread(str(d / REFERENCE_FRAME_NAME), cv2.IMREAD_GRAYSCALE)
    if frame is None:
        return None, None
    roi = None
    try:
        data = json.loads((d / REFERENCE_ROI_NAME).read_text(encoding="utf-8"))
        roi = tuple(int(v) for v in data["roi"])
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return frame, roi


def save_reference(gray, roi, metrics_dir=METRICS_DIR):
    d = reference_dir(metrics_dir)
    d.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(d / REFERENCE_FRAME_NAME), gray)
    (d / REFERENCE_ROI_NAME).write_text(
        json.dumps({"roi": [int(v) for v in roi] if roi else None}), encoding="utf-8")
    return d / REFERENCE_FRAME_NAME


def snapshot_frames(csv_path):
    csv_path = Path(csv_path)
    return sorted(csv_path.parent.glob(csv_path.stem + SNAPSHOT_FRAME_GLOB))


def snapshot_box(csv_path):
    csv_path = Path(csv_path)
    p = csv_path.with_name(csv_path.stem + SNAPSHOT_BOX_SUFFIX)
    return p if p.exists() else None


def check(csv_path, metrics_dir=METRICS_DIR, threshold=MOVE_THRESHOLD_PX):
    """
    這一晚的攝影機跟基準比有沒有移動。

    沒有今晚的畫面（舊版錄影程式錄的、或錄不到 15 分鐘）→ no_snapshot；
    沒有基準 → no_reference。這兩種**不擋**，只提醒（沒有證據就不動）。
    """
    shown = snapshot_box(csv_path)
    frames = snapshot_frames(csv_path)
    if not frames:
        return Alignment("no_snapshot", snapshot=shown)
    ref, roi = load_reference(metrics_dir)
    if ref is None:
        return Alignment("no_reference", snapshot=shown)
    shifts = []
    for p in frames:
        cur = cv2.imread(str(p), cv2.IMREAD_GRAYSCALE)
        if cur is not None:
            shifts.append(frame_shift(ref, cur, roi))
    if not shifts:
        return Alignment("no_snapshot", snapshot=shown)
    mid = float(statistics.median(shifts))
    return Alignment("moved" if mid > threshold else "ok", shift_px=mid,
                     shifts=shifts, snapshot=shown)


def frame_from_video(video_path, at_seconds=REFERENCE_AT_SECONDS):
    """從錄影取一格灰階畫面。"""
    cap = cv2.VideoCapture(str(video_path))
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 5.0
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(at_seconds * fps))
        ok, frame = cap.read()
    finally:
        cap.release()
    if not ok or frame is None:
        return None
    return frame if frame.ndim == 2 else cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)


def main():
    ap = argparse.ArgumentParser(description="攝影機有沒有被移動")
    ap.add_argument("csv", nargs="?", help="要檢查的那一晚的 CSV")
    ap.add_argument("--make-reference", metavar="影片", help="從這支錄影取一格當基準")
    ap.add_argument("--roi", metavar="X,Y,W,H", help="基準是在哪個床鋪框底下拍的")
    args = ap.parse_args()
    if args.make_reference:
        gray = frame_from_video(args.make_reference)
        if gray is None:
            sys.exit(f"✗ 讀不出 {args.make_reference} 的畫面")
        roi = tuple(int(v) for v in args.roi.split(",")) if args.roi else None
        print(f"✓ 基準存在 {save_reference(gray, roi)}")
        return
    if not args.csv:
        ap.error("要給一份 CSV，或用 --make-reference")
    result = check(args.csv)
    print(f"● {Path(args.csv).name}：{result.status}，平移中間值 {result.shift_px:.1f} px"
          f"（門檻 {MOVE_THRESHOLD_PX:.0f}；各張 {[round(s, 1) for s in result.shifts]}）")
    if result.snapshot:
        print(f"  今晚的畫面：{result.snapshot}")


if __name__ == "__main__":
    main()
