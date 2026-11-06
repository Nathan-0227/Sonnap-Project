"""
camera_clips.py —— 攝影機動作片段：一晚挑出動作最大的幾段，做成 GIF 給 App 看。

    python camera_clips.py --csv tapo_metrics/20260913_045549.csv   # 一晚
    python camera_clips.py --all                                    # tapo_metrics 裡全部
    python camera_clips.py --all --dry-run                          # 只列出會挑哪幾段

要寫進 MariaDB 就先設 SONNAP_DB_URL（跟啟動後端同一個），否則寫進 SQLite。
每天早上 morning_import.py 會在攝影機入庫之後自動跑一次 --csv。

═══════════════════════════════════════════════════════════════════
設計（2026-11-07 與使用者逐條確認過）
═══════════════════════════════════════════════════════════════════
- 一晚最多 CLIPS_PER_NIGHT 段，每段約 CLIP_SECONDS 秒，動作前 LEAD_SECONDS 秒開始播
- **原始畫面**（使用者決定；畫面裡只會有本人），在動的區域疊半透明暖色
- 標籤只寫量得到的事：「02:41 · moved for 6 s」。**不寫「翻身」「小動作」**——
  那種分類來自舊偵測器，門檻沒有依據（設計紅線 2 的精神：沒驗證過就不宣稱）
- 「動作最大」= 那段動作裡，在動面積佔床鋪區域（ROI）的最大比例。只用來挑片段、
  不計分，所以不受計分門檻那條紅線約束
- 保留最近 KEEP_NIGHTS 個**有片段的夜晚**，不是日曆天
- 呈現用，不進任何分數

═══════════════════════════════════════════════════════════════════
⚠️ 不能破的幾件事
═══════════════════════════════════════════════════════════════════
1. **「哪裡算在動」只有一個定義處**：門檻是 tapo_sleep_onset.MOTION_THRESHOLD
   （三晚人工標註定案、F1 0.84–0.88），分段是它 import 的 episodes()，
   比例是 tapo_metric_logger.row_frac()。這裡**呼叫時才讀**、不抄一份——
   抄了的話，那邊重新校準之後這裡會安靜地用舊門檻挑片段。
   tests/test_camera_clips.py【1】把門檻換掉，確認挑出來的結果跟著變。
2. **網址不含 user_id**：片段用隨機 clip_id 命名，網址是 /camera/clips/<id>.gif。
   uvicorn 的 access log 會印出完整網址，而 user_id 是憑證。
3. **檔案在所有 worktree 之外**（CLIPS_DIR）：放在 worktree 裡的話
   `git worktree remove` 會把它一起帶走（2026-09-06 的錄影檔就是這樣沒的）。
4. **刪帳號要連檔案一起刪**：資料庫的 CASCADE 只清得到資料列，GIF 是原始畫面，
   留著就違反「退出即刪除」。main.py 的 DELETE /users 呼叫 delete_user_clips()。
5. 不印任何 user_id。

⚠️ 影片只錄前 N 分鐘（tapo_metric_logger --save-video N），之後只有 CSV。
   影片第 N 幀 == CSV 裡 vf==N 那一列；落在影片之外的動作沒有畫面可剪。
"""
import argparse
import os
import re
import secrets
import sys
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import db
from behavior import adherence

ROOT = Path(__file__).parent

# ⚠️ 預設放在 repo 的**上一層**（…/Projects/sonnap-data/camera_clips），
#    主 clone 與每個 worktree 都會指到同一個地方，而且不在任何 worktree 裡。
CLIPS_DIR = Path(os.environ.get("SONNAP_CLIPS_DIR")
                 or ROOT.parent / "sonnap-data" / "camera_clips")

CLIPS_PER_NIGHT = 3
LEAD_SECONDS = 2           # 動作開始前先播幾秒，看得出「本來是靜的」
CLIP_SECONDS = 10          # 一段的總長（含 LEAD）
KEEP_NIGHTS = 14
OUTPUT_WIDTH = 480         # 640×360 → 480×270：一段 10 秒約 1–2 MB
HIGHLIGHT_RGB = (255, 170, 60)     # 寵物的暖色
HIGHLIGHT_ALPHA = 0.35
GIF_COLORS = 64            # 夜視是灰階＋一個疊色，64 色看不出差別；128 色時一段 2.8 MB

CLIP_ID = re.compile(r"^[0-9a-f]{32}$")

STATUS_OK = "ok"
STATUS_NO_VIDEO = "no_video"
STATUS_NO_MOTION = "no_motion"
STATUS_MOTION_AFTER_VIDEO = "motion_after_video"
STATUS_EXPIRED = "expired"
# 不寫進資料庫的狀態：那晚沒有 camera_nightly（錄影沒被算成一晚），見 make_night()
STATUS_NO_CAMERA_NIGHT = "no_camera_night"

# ⚠️ 這些句子**原封不動顯示在手機上**（Insights 頁的攝影機卡），Dart 不改寫。
#    寫法比照 behavior/sleep_efficiency.py：第二人稱、不出現欄位名、
#    做得到的事要講出來。
NOTES = {
    STATUS_NO_VIDEO: (
        "This night was recorded without video, so there are no clips to show. "
        "Record with video turned on to see your movements here."
    ),
    STATUS_NO_MOTION: (
        "The camera saw no movement big enough to make a clip this night."
    ),
    STATUS_MOTION_AFTER_VIDEO: (
        "The video for this night stopped before your biggest movements, "
        "so there is nothing to clip. Record a longer video to see them."
    ),
    STATUS_EXPIRED: (
        f"Clips are kept for your latest {KEEP_NIGHTS} recorded nights only."
    ),
}
# 有攝影機那一晚、卻從來沒做過片段（例如這個功能上線前、或做的時候失敗）。
NOT_MADE_NOTE = "No clips have been made for this night yet."


# ═══════════════════════════════════════════════════════════════════
# 檔案
# ═══════════════════════════════════════════════════════════════════

def clip_path(clip_id, clips_dir=None):
    """clip_id → 檔案路徑。不合格式的 id 回 None（擋掉 ../ 之類的路徑）。"""
    if not isinstance(clip_id, str) or not CLIP_ID.match(clip_id):
        return None
    return Path(clips_dir or CLIPS_DIR) / f"{clip_id}.gif"


def clip_url(clip_id):
    """App 用的相對網址。⚠️ 不含 user_id，理由見檔頭第 2 點。"""
    return f"/camera/clips/{clip_id}.gif"


def delete_files(clip_ids, clips_dir=None):
    n = 0
    for cid in clip_ids:
        p = clip_path(cid, clips_dir)
        if p is not None and p.exists():
            p.unlink()
            n += 1
    return n


def delete_user_clips(user_id, db_path=None, clips_dir=None):
    """刪掉這個帳號所有片段的**檔案**。資料列由 db.delete_user 的 CASCADE 清。"""
    return delete_files(db.camera_clip_ids_for_user(user_id, db_path=db_path), clips_dir)


# ═══════════════════════════════════════════════════════════════════
# 挑片段（純邏輯，不碰影片）
# ═══════════════════════════════════════════════════════════════════

def duration_text(seconds):
    s = max(1, round(seconds))
    if s < 60:
        return f"{s} s"
    m, s = divmod(s, 60)
    return f"{m} min {s} s" if s else f"{m} min"


def label_for(start_at, duration_seconds):
    """畫面上的字。只講量得到的：幾點、動了多久。"""
    return f"{start_at:%H:%M} · moved for {duration_text(duration_seconds)}"


def read_frame_meta(csv_path):
    """
    回傳 ({時刻: vf}, {vf: (bbox, frac)})。

    bbox 是那一幀最大動作區塊的外框（有 ROI 用 ROI 內的那一塊），frac 用
    tapo_metric_logger.row_frac() 算——與偵測走同一個函式。
    """
    import csv
    from tapo_metric_logger import read_roi, row_frac

    roi, _ = read_roi(csv_path)
    vf_at, meta = {}, {}
    with Path(csv_path).open(encoding="utf-8") as fh:
        for r in csv.DictReader(l for l in fh if not l.startswith("#")):
            if r.get("vf", "") == "":
                continue
            vf = int(r["vf"])
            vf_at[datetime.fromisoformat(r["t"])] = vf
            keys = ("roi_x", "roi_y", "roi_w", "roi_h") if roi else ("max_x", "max_y", "max_w", "max_h")
            try:
                bbox = tuple(int(r[k]) for k in keys)
            except (KeyError, ValueError):
                bbox = None
            meta[vf] = (bbox, row_frac(r, roi))
    return vf_at, meta


def find_episodes(csv_path):
    """整夜的動作段落 [(開始時刻, 持續秒數, 最大比例)]，與入睡偵測同一套定義。"""
    import tapo_sleep_onset as onset
    samples, _roi = onset.load(Path(csv_path))
    # ⚠️ 呼叫時才讀門檻，不抄一份（檔頭第 1 點）
    return onset.episodes(samples, onset.MOTION_THRESHOLD)


def pick_moments(episodes, vf_at, video_frames, fps, n=CLIPS_PER_NIGHT):
    """
    挑出動作最大的 n 段，回傳 [{start_at, duration_seconds, peak, first_vf, last_vf}]，
    依「動作大小」排序（第一個最大）。

    - 最大 = 峰值比例最高；一樣大時取動得比較久的
    - 落在影片之外的段落跳過（只有 CSV、沒有畫面）
    - 與已挑中的片段在時間上重疊就跳過——同一次翻身不給兩段
    """
    lead = round(LEAD_SECONDS * fps)
    length = round(CLIP_SECONDS * fps)
    chosen = []
    for start, dur, peak in sorted(episodes, key=lambda e: (-e[2], -e[1])):
        vf = vf_at.get(start)
        if vf is None or vf >= video_frames:
            continue
        first = max(0, vf - lead)
        last = min(video_frames - 1, first + length - 1)
        if any(first <= c["last_vf"] and c["first_vf"] <= last for c in chosen):
            continue
        chosen.append({"start_at": start, "duration_seconds": dur, "peak": peak,
                       "first_vf": first, "last_vf": last})
        if len(chosen) >= n:
            break
    return chosen


# ═══════════════════════════════════════════════════════════════════
# 做 GIF
# ═══════════════════════════════════════════════════════════════════

def _font(size):
    from PIL import ImageFont
    for name in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def render_clip(video_path, moment, meta, threshold, label, out_path, fps):
    """把一段畫面存成 GIF。在動（frac ≥ 門檻）的幀把那個區塊疊上暖色。"""
    import cv2
    import numpy as np
    from PIL import Image, ImageDraw

    cap = cv2.VideoCapture(str(video_path))
    try:
        cap.set(cv2.CAP_PROP_POS_FRAMES, moment["first_vf"])
        frames = []
        font = _font(15)
        for vf in range(moment["first_vf"], moment["last_vf"] + 1):
            ok, frame = cap.read()
            if not ok:
                break
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB).astype(np.float32)
            bbox, frac = meta.get(vf, (None, None))
            if bbox and frac is not None and frac >= threshold and bbox[2] > 0 and bbox[3] > 0:
                x, y, w, h = bbox
                region = rgb[y:y + h, x:x + w]
                region[:] = region * (1 - HIGHLIGHT_ALPHA) + np.array(HIGHLIGHT_RGB) * HIGHLIGHT_ALPHA
            img = Image.fromarray(rgb.clip(0, 255).astype(np.uint8))
            img = img.resize((OUTPUT_WIDTH, round(img.height * OUTPUT_WIDTH / img.width)))
            # ⚠️ 標籤放右下角：左上角是攝影機自己的時間戳記、左下角是 Tapo 浮水印，
            #    蓋住前者等於把唯一能拿來核對時刻的東西遮掉。
            draw = ImageDraw.Draw(img)
            w, h = draw.textbbox((0, 0), label, font=font)[2:]
            x, y = img.width - w - 12, img.height - h - 10
            draw.rectangle((x - 6, y - 4, x + w + 6, y + h + 4), fill=(16, 22, 44))
            draw.text((x, y), label, font=font, fill=(255, 225, 180))
            frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=GIF_COLORS))
    finally:
        cap.release()
    if not frames:
        return False
    tmp = out_path.with_suffix(".tmp")
    frames[0].save(tmp, format="GIF", save_all=True, append_images=frames[1:],
                   duration=round(1000 / fps), loop=0, optimize=True)
    tmp.replace(out_path)
    return True


def _video_info(video_path):
    import cv2
    cap = cv2.VideoCapture(str(video_path))
    try:
        if not cap.isOpened():
            return 0, 0.0
        return int(cap.get(cv2.CAP_PROP_FRAME_COUNT)), float(cap.get(cv2.CAP_PROP_FPS) or 0)
    finally:
        cap.release()


# ═══════════════════════════════════════════════════════════════════
# 一晚
# ═══════════════════════════════════════════════════════════════════

def night_of(csv_path):
    """
    這份錄影屬於哪一晚（起床日），以及它算不算一晚。回 (date 或 None, 原因)。

    ⚠️ 判準與 migrate_camera_to_db.py 相同（同一個 analyse、同一個下限、
       同一個 night_date）：不算一晚的錄影不會有 camera_nightly 那一列，
       做了片段也沒有地方顯示。
    """
    import migrate_camera_to_db as mig
    import tapo_sleep_onset as onset
    r = onset.analyse(Path(csv_path))
    if r.get("error"):
        return None, r["error"]
    tib = r.get("time_in_bed_minutes")
    if tib is None or tib < mig.MIN_NIGHT_MINUTES:
        return None, f"recorded {tib or 0:.0f} min, under {mig.MIN_NIGHT_MINUTES} min"
    return adherence.night_date(datetime.fromisoformat(r["bed_start_at"])).isoformat(), None


def plan_night(csv_path):
    """不寫任何東西，回傳這晚會怎麼處理：{status, moments, video, fps}。"""
    import tapo_sleep_onset as onset
    video = Path(csv_path).with_suffix(".mp4")
    frames, fps = _video_info(video) if video.exists() else (0, 0.0)
    if frames <= 0 or fps <= 0:
        return {"status": STATUS_NO_VIDEO, "moments": [], "video": None, "fps": 0.0,
                "threshold": onset.MOTION_THRESHOLD}
    episodes = find_episodes(csv_path)
    if not episodes:
        return {"status": STATUS_NO_MOTION, "moments": [], "video": video, "fps": fps,
                "threshold": onset.MOTION_THRESHOLD}
    vf_at, _meta = read_frame_meta(csv_path)
    moments = pick_moments(episodes, vf_at, frames, fps)
    return {"status": STATUS_OK if moments else STATUS_MOTION_AFTER_VIDEO,
            "moments": moments, "video": video, "fps": fps,
            "threshold": onset.MOTION_THRESHOLD}


def make_night(csv_path, user_id, date, db_path=None, clips_dir=None):
    """
    做一晚的片段並寫入資料庫。回傳 {status, labels}。

    順序：先把新的 GIF 全部寫好 → 寫資料庫 → 才刪舊檔。中途失敗時把這次
    新寫的檔刪掉，舊的片段原樣保留（不會出現「資料庫指著不存在的檔」）。

    ⚠️ **那一晚要先有 camera_nightly 那一列**，否則不做、並清掉已有的片段
       （2026-11-07 補做時發現）：App 只顯示 camera_nightly 裡的夜晚，
       沒有那一列的片段**永遠看不到**，卻會佔掉「保留 14 晚」的名額。
       實例：09-13 那份錄影半夜斷線，早上匯入的檢查刻意擋掉它
       （沒有 camera_nightly），片段卻照做了。判準不在這裡重寫一份——
       「這晚算不算數」由攝影機入庫那一步決定，這裡只看結果。
    """
    clips_dir = Path(clips_dir or CLIPS_DIR)
    if not db.has_camera_nightly(user_id, date, db_path=db_path):
        removed = db.delete_camera_clip_night(user_id, date, db_path=db_path)
        delete_files(removed, clips_dir)
        return {"status": STATUS_NO_CAMERA_NIGHT, "labels": [], "expired_clips": 0,
                "removed_clips": len(removed)}
    clips_dir.mkdir(parents=True, exist_ok=True)
    plan = plan_night(csv_path)
    rows, written = [], []
    try:
        if plan["moments"]:
            _vf_at, meta = read_frame_meta(csv_path)
            for rank, m in enumerate(plan["moments"], start=1):
                cid = secrets.token_hex(16)
                label = label_for(m["start_at"], m["duration_seconds"])
                if render_clip(plan["video"], m, meta, plan["threshold"], label,
                               clip_path(cid, clips_dir), plan["fps"]):
                    written.append(cid)
                    rows.append({"clip_id": cid, "clip_rank": rank,
                                 "start_at": m["start_at"].isoformat(timespec="seconds"),
                                 "duration_seconds": round(m["duration_seconds"], 1),
                                 "label": label})
        status = plan["status"]
        if status == STATUS_OK and not rows:      # 影片讀得到長度、卻讀不出畫面
            status = STATUS_MOTION_AFTER_VIDEO
        old = db.replace_camera_clips(user_id, date, status, NOTES.get(status),
                                      rows, db_path=db_path)
    except BaseException:
        delete_files(written, clips_dir)
        raise
    delete_files(old, clips_dir)
    expired = db.expire_camera_clip_nights(user_id, KEEP_NIGHTS, STATUS_EXPIRED,
                                           NOTES[STATUS_EXPIRED], db_path=db_path)
    delete_files(expired, clips_dir)
    return {"status": status, "labels": [r["label"] for r in rows],
            "expired_clips": len(expired)}


# ═══════════════════════════════════════════════════════════════════
# 命令列
# ═══════════════════════════════════════════════════════════════════

def main(argv=None):
    import migrate_camera_to_db as mig

    ap = argparse.ArgumentParser(description="錄影 → 動作片段 GIF（呈現用，不計分）")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--csv", action="append", help="只處理這些錄影的 CSV（可重複）")
    g.add_argument("--all", action="store_true", help="處理 tapo_metrics 裡全部的錄影")
    ap.add_argument("--metrics-dir", default=str(ROOT / "tapo_metrics"))
    ap.add_argument("--dry-run", action="store_true", help="只列出會挑哪幾段，不寫任何東西")
    args = ap.parse_args(argv)

    if os.environ.get("SONNAP_DB_URL"):
        print("● 資料庫   MySQL/MariaDB（由 SONNAP_DB_URL 指定，內容不印）")
    else:
        print(f"● 資料庫   {db.DB_PATH}（SQLite）")
    print(f"● 片段存放 {CLIPS_DIR}")
    user_id, who = mig.resolve_user()          # 與攝影機入庫同一個判準；不印完整 id
    print(f"● 寫入帳號 {who}")
    if args.dry_run:
        print("● --dry-run：不會寫入任何東西")
    print()

    # ⚠️ 由舊到新：保留規則看的是「最近 KEEP_NIGHTS 個有片段的夜晚」，
    #    倒過來跑的話，最新的幾晚反而會被當成舊的清掉。
    csvs = sorted(mig.nights(args.metrics_dir, None)) if args.all else [Path(p) for p in args.csv]
    done = skipped = 0
    for path in csvs:
        try:
            date, why = night_of(path)
        except Exception as exc:                   # noqa: BLE001  一份壞掉不擋整批
            print(f"  —           {path.name}  ⚠ 讀不下去：{type(exc).__name__}")
            skipped += 1
            continue
        if date is None:
            print(f"  —           {path.name}  （不算一晚：{why}）")
            skipped += 1
            continue
        if args.dry_run and not db.has_camera_nightly(user_id, date):
            plan, labels = {"status": STATUS_NO_CAMERA_NIGHT}, []
        elif args.dry_run:
            plan = plan_night(path)
            labels = [label_for(m["start_at"], m["duration_seconds"]) for m in plan["moments"]]
        else:
            result = make_night(path, user_id, date)
            plan, labels = result, result["labels"]
        if plan["status"] == STATUS_NO_CAMERA_NIGHT:
            shown = ("攝影機紀錄裡沒有這一晚（沒匯入，或早上匯入的檢查擋掉了），不做片段"
                     + (f"；清掉 {plan['removed_clips']} 段看不到的舊片段"
                        if plan.get("removed_clips") else ""))
        else:
            shown = "；".join(labels) if labels else NOTES.get(plan["status"], "")
        print(f"  {date}  {path.name}  [{plan['status']}]  {shown}")
        done += 1

    print()
    print(f"處理 {done} 晚，跳過 {skipped} 份。")
    print("⚠️ 片段是原始畫面，只存在這台電腦；呈現用，不進任何分數。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
