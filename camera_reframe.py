"""
camera_reframe.py — 攝影機或床移動了之後，重新框床鋪範圍（2026-11-21 使用者 grill 定案 Q16、Q17）。

流程（Q16-D）：
  1. 從最近一晚的熱區圖推一個框（tapo_derive_roi 的做法），畫在那晚的畫面上
  2. 你看：按 Enter 用這個；按 D 自己用滑鼠拖一個；按 Esc 不改
  3. 存的時候**同時換比對用的基準畫面**（Q17），舊的框與基準備份到 reference/backup-<時間>/

⚠️ **不會自己存**：熱區圖分不出動的是誰、是什麼（室友、窗簾、你坐在床邊滑手機都會帶偏），
   上次直接用推出來的框，有室友那晚整個選錯（TAPO_HANDOFF）。所以一定要人看過、按了才存。
⚠️ 新的框**下一晚**開始用（camera_auto 每次開錄才讀設定）。
⚠️ 動作門檻 0.75% 是在舊框底下校準的，換框之後準確度沒有重新驗證過，只能先沿用。
   「跟你平常比」本來就只拿同一個框的夜晚比（camera_usual.py），換框之後自動重新累積 5 晚。

用法
────
  python camera_reframe.py                          # 用最近一晚
  python camera_reframe.py tapo_metrics/xxx.csv     # 指定一晚
"""
import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

import camera_alignment
import camera_auto

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

WIDTH, HEIGHT = 640, 360
HEAT_PERCENTILE = 80
# 床應該佔畫面 10%~60%，推出來的超出就不建議（同 tapo_derive_roi）
SANITY_MIN, SANITY_MAX = 0.10, 0.60


def suggest_roi(heat):
    """熱區圖 → 建議的框 (x, y, w, h)，不合理（太小、太大、沒有熱區）回 None。"""
    if heat is None:
        return None
    import tapo_derive_roi
    region = tapo_derive_roi.largest_region(heat, HEAT_PERCENTILE)
    if not region:
        return None
    x, y, w, h, _area = region
    frac = (w * h) / (WIDTH * HEIGHT)
    if not (SANITY_MIN <= frac <= SANITY_MAX):
        return None
    return (x, y, w, h)


def apply_new_roi(roi, frame, metrics_dir=camera_auto.METRICS_DIR, now=None):
    """
    存新的框＋把 frame 存成新的基準。舊的設定與基準先備份（Q17：不覆蓋）。
    回傳備份資料夾。
    """
    metrics_dir = Path(metrics_dir)
    stamp = (now or datetime.now()).strftime("%Y%m%d_%H%M%S")
    ref_dir = camera_alignment.reference_dir(metrics_dir)
    backup = ref_dir / f"backup-{stamp}"
    backup.mkdir(parents=True, exist_ok=True)
    cfg_path = metrics_dir / camera_auto.CONFIG_NAME
    cfg = camera_auto.load_config(metrics_dir)
    # 舊的設定：有檔案就備份檔案，沒有就把當時用的預設值寫一份，之後才知道換掉的是什麼
    if cfg_path.exists():
        shutil.copy2(cfg_path, backup / camera_auto.CONFIG_NAME)
    else:
        (backup / camera_auto.CONFIG_NAME).write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    for name in (camera_alignment.REFERENCE_FRAME_NAME, camera_alignment.REFERENCE_ROI_NAME):
        if (ref_dir / name).exists():
            shutil.copy2(ref_dir / name, backup / name)
    cfg["roi"] = [int(v) for v in roi]
    camera_auto.save_config(cfg, metrics_dir)
    camera_alignment.save_reference(frame, roi, metrics_dir)
    return backup


def latest_recording(metrics_dir):
    import migrate_camera_to_db
    nights = [p for p in migrate_camera_to_db.nights(metrics_dir, None)
              if p.with_name(p.stem + "_heat.npy").exists()]
    return nights[-1] if nights else None


def night_frame(csv_path):
    """那一晚拿來框的畫面：優先第 60 分鐘那張，再來任何一張，最後從影片取。"""
    frames = camera_alignment.snapshot_frames(csv_path)
    preferred = [p for p in frames if p.name.endswith("_frame_060.png")]
    for p in preferred + frames:
        img = cv2.imread(str(p), cv2.IMREAD_GRAYSCALE)
        if img is not None:
            return img
    video = Path(csv_path).with_suffix(".mp4")
    if video.exists():
        return camera_alignment.frame_from_video(video)
    return None


def _draw(frame, roi, title):
    shown = cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)
    if roi:
        x, y, w, h = roi
        cv2.rectangle(shown, (x, y), (x + w, y + h), (0, 200, 255), 2)
    cv2.putText(shown, title, (8, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 0), 2)
    return shown


def main():
    ap = argparse.ArgumentParser(description="重新框床鋪範圍")
    ap.add_argument("csv", nargs="?", help="用哪一晚（預設最近一晚）")
    args = ap.parse_args()
    metrics_dir = camera_auto.METRICS_DIR
    csv_path = Path(args.csv) if args.csv else latest_recording(metrics_dir)
    if not csv_path:
        sys.exit("✗ 找不到有熱區圖的錄影（要先錄過一晚）")
    frame = night_frame(csv_path)
    if frame is None:
        sys.exit(f"✗ {csv_path.name} 沒有畫面可以框（沒有 _frame_*.png 也沒有影片）")

    import tapo_derive_roi
    suggested = suggest_roi(tapo_derive_roi.load_mask_heat(csv_path))
    current = tuple(camera_auto.load_config(metrics_dir)["roi"])
    print(f"● 用 {csv_path.name}")
    print(f"  現在的框   {current}")
    print(f"  建議的框   {suggested or '推不出來（熱區不合理）——請自己框'}")

    win = "Sonnap - bed area"
    roi = suggested
    if roi:
        cv2.imshow(win, _draw(frame, roi, "Enter = use this   D = draw my own   Esc = cancel"))
        key = cv2.waitKey(0) & 0xFF
        if key == 27:
            cv2.destroyAllWindows()
            print("● 沒有改")
            return
        if key in (ord("d"), ord("D")):
            roi = None
    if not roi:
        picked = cv2.selectROI(win, _draw(frame, None, "Drag the bed, then Enter"), showCrosshair=False)
        if not picked or picked[2] <= 0 or picked[3] <= 0:
            cv2.destroyAllWindows()
            print("● 沒有改")
            return
        roi = tuple(int(v) for v in picked)
    cv2.destroyAllWindows()

    backup = apply_new_roi(roi, frame, metrics_dir)
    print(f"✓ 新的框 {roi}，下一晚開始用；比對用的基準也換成這晚的畫面")
    print(f"  舊的框與基準備份在 {backup}")
    print("  ⚠ 動作門檻 0.75% 是在舊框底下校準的，新框沒有重新驗證過。")


if __name__ == "__main__":
    main()
