"""
tests/test_camera_clips.py —— 攝影機動作片段（camera_clips.py）

全部用**合成的錄影與 CSV**，不碰 tapo_metrics/ 裡的真實畫面；
資料庫與片段資料夾都是暫存的。

  【1】「哪裡算在動」讀的是 tapo_sleep_onset.MOTION_THRESHOLD，**呼叫時才讀**
       （把門檻換掉，挑出來的結果要跟著變——抄一份常數的話這條會紅）
  【2】挑片段：依動作大小排序、跳過影片之外的、重疊的不給兩段
  【3】標籤只講量得到的事（時刻 + 動了多久），不出現「翻身」之類的分類
  【4】做一晚：GIF 真的寫出來、幀數對、資料庫有列；重跑同一晚會取代、舊檔刪掉
  【5】沒有片段的三種原因各有自己的說明（沒錄影片／沒動／動作在影片之後）
  【6】只留最近 14 個有片段的夜晚，更舊的檔案刪掉、那晚標成 expired
  【7】API：/insights 帶片段、網址不含 user_id、檔案端點 200/404、
       刪帳號連檔案一起刪
  【8】沒有 camera_nightly 的夜晚不做片段，已有的也清掉（App 看不到、卻佔保留名額）
  【9】框畫在哪：畫面比對框住真的在動的東西；噪點與沒變化不畫；CSV 外框只在合理時才用

執行：python tests/test_camera_clips.py
"""
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# ⚠️ 一定要在 import main 之前換掉 DB_PATH 與片段資料夾
import db                                                   # noqa: E402
TMP = Path(tempfile.mkdtemp())
db.DB_PATH = TMP / "test.db"
db.init_db(db.DB_PATH)

import camera_clips as cc                                   # noqa: E402
cc.CLIPS_DIR = TMP / "clips"

import cv2                                                  # noqa: E402
import numpy as np                                          # noqa: E402
from PIL import Image                                       # noqa: E402

import main                                                 # noqa: E402
import tapo_sleep_onset as onset                            # noqa: E402
from fastapi.testclient import TestClient                   # noqa: E402

client = TestClient(main.app)
fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<52} {extra}")
    if not cond:
        fails.append(label)


# ─── 合成一晚 ────────────────────────────────────────────────────
FPS = 5
ROI = (34, 129, 288, 231)                      # 與真實錄影同一個 ROI
ROI_AREA = ROI[2] * ROI[3]                     # 66528；門檻 0.75% ≈ 499 px
START = datetime(2026, 9, 13, 1, 0, 0)


def write_night(folder, name, motions, minutes=125, video_seconds=180):
    """
    motions：[(開始秒數, 持續秒數, roi_px)]。回傳 CSV 路徑。
    video_seconds=0 表示沒存影片（只有 CSV）。前 90 秒是暖機。
    """
    folder.mkdir(parents=True, exist_ok=True)
    csv_path = folder / f"{name}.csv"
    video_frames = video_seconds * FPS
    lines = [
        f"# tapo_metric_logger  started={START.isoformat()}",
        "# size=640x360 fps=5.0 blur=7",
        f"# roi={','.join(map(str, ROI))} roi_area={ROI_AREA}",
        "t,mean,raw_px,fg_px,blobs,max_px,max_x,max_y,max_w,max_h,illum_skip,warmup,vf,"
        "roi_px,roi_x,roi_y,roi_w,roi_h",
    ]
    for i in range(minutes * 60 * FPS):
        sec = i / FPS
        px = next((p for s, d, p in motions if s <= sec < s + d), 0)
        box = (60, 160, 120, 90) if px else (0, 0, 0, 0)
        t = (START + timedelta(seconds=sec)).isoformat(timespec="milliseconds")
        vf = i if i < video_frames else ""
        warm = 1 if sec < 90 else 0
        lines.append(f"{t},100,{px},{px},{1 if px else 0},{px},{box[0]},{box[1]},{box[2]},{box[3]},"
                     f"0,{warm},{vf},{px},{box[0]},{box[1]},{box[2]},{box[3]}")
    csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if video_frames:
        vw = cv2.VideoWriter(str(csv_path.with_suffix(".mp4")),
                             cv2.VideoWriter_fourcc(*"mp4v"), FPS, (640, 360))
        for i in range(video_frames):
            frame = np.full((360, 640, 3), 40, np.uint8)
            cv2.putText(frame, str(i), (20, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (220, 220, 220), 2)
            vw.write(frame)
        vw.release()
    return csv_path


# 影片 3 分鐘；A/B/C 在影片內（大→小），E 最大但在 30 分鐘、影片之外
NIGHT = write_night(TMP / "metrics", "20260913_010000", [
    (100, 5, 3000),     # A  4.5%
    (125, 5, 1500),     # B  2.3%
    (150, 5, 800),      # C  1.2%
    (1800, 5, 5000),    # E  7.5%，影片之外
])

ANALYSED = onset.analyse(NIGHT)


def cam(user_id, date):
    """先有攝影機那一列（make_night 的前提）。內容不重要，用同一份分析結果。"""
    db.upsert_camera_nightly(user_id, date, ANALYSED)


print("【1】門檻讀的是 tapo_sleep_onset.MOTION_THRESHOLD，而且是呼叫時才讀")
plan = cc.plan_night(NIGHT)
starts = [m["start_at"] - START for m in plan["moments"]]
ok("預設門檻：挑出影片內的 A、B、C 三段", len(plan["moments"]) == 3, str(starts))
saved = onset.MOTION_THRESHOLD
try:
    onset.MOTION_THRESHOLD = 0.03                  # 只有 A（4.5%）過得了
    plan_hi = cc.plan_night(NIGHT)
finally:
    onset.MOTION_THRESHOLD = saved
ok("把門檻提高到 3% → 只剩 A（若抄了一份常數，這條會紅）",
   len(plan_hi["moments"]) == 1, str(len(plan_hi["moments"])))
ok("plan 回報的門檻就是那個常數", plan["threshold"] == onset.MOTION_THRESHOLD)

print("【2】挑片段的規則")
order = [round(m["peak"], 4) for m in plan["moments"]]
ok("依動作大小排序（最大的排第一）", order == sorted(order, reverse=True), str(order))
ok("影片之外那段（最大的 E）沒被挑進來",
   all((m["start_at"] - START).total_seconds() < 180 for m in plan["moments"]))
t0 = START
eps = [(t0 + timedelta(seconds=10), 3.0, 0.05),
       (t0 + timedelta(seconds=13), 9.0, 0.04),     # 跟第一段重疊
       (t0 + timedelta(seconds=40), 2.0, 0.03),
       (t0 + timedelta(seconds=60), 8.0, 0.03)]     # 跟上一段一樣大、動得比較久
vf_at = {s: round((s - t0).total_seconds() * FPS) for s, _, _ in eps}
picked = cc.pick_moments(eps, vf_at, video_frames=10_000, fps=FPS, n=3)
got = [round((m["start_at"] - t0).total_seconds()) for m in picked]
ok("重疊的那段跳過；一樣大時取動得久的", got == [10, 60, 40], str(got))
ok("片段從動作前 2 秒開始、長 10 秒",
   picked[0]["first_vf"] == 50 - 2 * FPS and picked[0]["last_vf"] - picked[0]["first_vf"] + 1 == 10 * FPS,
   f"{picked[0]['first_vf']}–{picked[0]['last_vf']}")

print("【3】標籤")
ok("6 秒", cc.label_for(datetime(2026, 9, 13, 2, 41), 6.2) == "02:41 · moved for 6 s",
   cc.label_for(datetime(2026, 9, 13, 2, 41), 6.2))
ok("75 秒 → 1 min 15 s", cc.duration_text(75) == "1 min 15 s", cc.duration_text(75))
ok("不到 1 秒 → 1 s（不寫 0 s）", cc.duration_text(0.2) == "1 s")
ok("標籤裡沒有「翻身」類的分類字",
   not any(w in cc.label_for(datetime(2026, 9, 13, 2, 41), 6).lower() for w in ("turn", "roll", "toss")))

print("【4】做一晚：GIF、資料庫、重跑")
uid = db.create_user("clips tester")
DATE = "2026-09-13"
cam(uid, DATE)
res = cc.make_night(NIGHT, uid, DATE)
nights = db.get_camera_clip_nights(uid)
clips = nights[DATE]["clips"]
ok("狀態 ok、三段", res["status"] == cc.STATUS_OK and len(clips) == 3, f"{res['status']} {len(clips)}")
files = sorted(cc.CLIPS_DIR.glob("*.gif"))
ok("磁碟上正好三個 GIF，檔名就是 clip_id",
   sorted(p.stem for p in files) == sorted(c["clip_id"] for c in clips), str(len(files)))
im = Image.open(files[0])
ok("每段 50 幀（10 秒 × 5 fps）、寬 480", im.n_frames == 50 and im.size[0] == 480,
   f"{im.n_frames} 幀 {im.size}")
im.close()
ok("資料庫的標籤與 label_for 一致",
   clips[0]["label"] == cc.label_for(START + timedelta(seconds=100), clips[0]["duration_seconds"]),
   clips[0]["label"])
first_ids = {c["clip_id"] for c in clips}
cc.make_night(NIGHT, uid, DATE)                          # 重跑同一晚
again = db.get_camera_clip_nights(uid)[DATE]["clips"]
ok("重跑 → 仍是三段，而且是新的 clip_id", len(again) == 3 and not first_ids & {c["clip_id"] for c in again})
ok("  舊檔都刪掉了（磁碟上還是三個）", len(list(cc.CLIPS_DIR.glob("*.gif"))) == 3)
ok("  沒有留下 .tmp", not list(cc.CLIPS_DIR.glob("*.tmp")))

print("【5】沒有片段時，各有各的原因")
u5 = db.create_user("no clips")
cases = [
    ("沒存影片", write_night(TMP / "m5", "20260920_010000", [(100, 5, 3000)], video_seconds=0),
     "2026-09-20", cc.STATUS_NO_VIDEO),
    ("整晚沒動", write_night(TMP / "m5", "20260921_010000", []), "2026-09-21", cc.STATUS_NO_MOTION),
    ("動作都在影片之後", write_night(TMP / "m5", "20260922_010000", [(1800, 5, 3000)]),
     "2026-09-22", cc.STATUS_MOTION_AFTER_VIDEO),
]
for label, path, d, want in cases:
    cam(u5, d)
    r = cc.make_night(path, u5, d)
    n = db.get_camera_clip_nights(u5)[d]
    ok(f"{label} → {want}，note 照抄 NOTES", r["status"] == want and n["note"] == cc.NOTES[want]
       and n["clips"] == [], r["status"])
ok("三種 note 彼此不同（不是同一句籠統的話）",
   len({cc.NOTES[w] for _, _, _, w in cases}) == 3)
ok("note 對使用者說話：不出現欄位名或底線", all("_" not in cc.NOTES[w] for _, _, _, w in cases))

print("【6】只留最近 14 個有片段的夜晚")
u6 = db.create_user("retention")
dummy = []
for i in range(15):                                      # 15 晚舊片段：09-01 ~ 09-15
    cid = f"{i:032x}"
    cam(u6, f"2026-09-{i + 1:02d}")
    cc.clip_path(cid).write_bytes(b"GIF89a")
    dummy.append(cid)
    db.replace_camera_clips(u6, f"2026-09-{i + 1:02d}", cc.STATUS_OK, None,
                            [{"clip_id": cid, "clip_rank": 1, "start_at": "2026-09-01T02:00:00",
                              "duration_seconds": 5.0, "label": "x"}])
cam(u6, "2026-09-16")
cc.make_night(NIGHT, u6, "2026-09-16")                   # 第 16 晚（新的，有三段）
n6 = db.get_camera_clip_nights(u6)
with_clips = sorted(d for d, v in n6.items() if v["clips"])
ok("剩 14 晚有片段，而且是最新的那 14 晚",
   with_clips == [f"2026-09-{d:02d}" for d in range(3, 17)], f"{with_clips[:2]}…{with_clips[-1:]}")
ok("最舊兩晚的檔案刪掉了", not cc.clip_path(dummy[0]).exists() and not cc.clip_path(dummy[1]).exists())
ok("  第三晚的檔案還在（只刪該刪的）", cc.clip_path(dummy[2]).exists())
ok("最舊那晚標成 expired、note 講保留規則",
   n6["2026-09-01"]["status"] == cc.STATUS_EXPIRED and n6["2026-09-01"]["note"] == cc.NOTES[cc.STATUS_EXPIRED])

print("【7】API")
u7 = client.post("/users", json={"display_name": "api clips", "study_cohort": "L1"}).json()["user_id"]
cam(u7, DATE)
cc.make_night(NIGHT, u7, DATE)
# 另一晚有攝影機資料、但從沒做過片段
cam(u7, "2026-09-12")
ins = client.get("/insights", params={"user_id": u7, "days": 30}).json()
hist = {h["date"]: h for h in ins["camera"]["history"]}
cl = hist[DATE]["clips"]
ok("/insights 那晚帶三段片段、clips_note 是 None", len(cl) == 3 and hist[DATE]["clips_note"] is None)
ok("網址格式 /camera/clips/<32 碼>.gif",
   all(c["url"].startswith("/camera/clips/") and len(c["url"]) == len("/camera/clips/") + 36 for c in cl),
   cl[0]["url"])
ok("🔴 網址不含 user_id", all(u7 not in c["url"] for c in cl))
ok("依 rank 排序、標籤照抄", [c["rank"] for c in cl] == [1, 2, 3] and "moved for" in cl[0]["label"])
ok("沒做過片段的那晚 → clips 空、note 是 NOT_MADE_NOTE",
   hist["2026-09-12"]["clips"] == [] and hist["2026-09-12"]["clips_note"] == cc.NOT_MADE_NOTE)
r = client.get(cl[0]["url"])
ok("片段端點 → 200、image/gif、內容是 GIF",
   r.status_code == 200 and r.headers["content-type"] == "image/gif" and r.content[:6] == b"GIF89a",
   str(r.status_code))
ok("查無此片段 → 404", client.get("/camera/clips/" + "0" * 31 + "f.gif").status_code == 404)
ok("格式不對（大寫、非 .gif）→ 404",
   client.get("/camera/clips/" + "A" * 32 + ".gif").status_code == 404
   and client.get(cl[0]["url"][:-4] + ".png").status_code == 404)
ok("路徑穿越 → 404", client.get("/camera/clips/..%2F..%2Fmain.py").status_code == 404)
mine = [cc.clip_path(c["url"].split("/")[-1][:-4]) for c in cl]
ok("刪帳號前：檔案在", all(p.exists() for p in mine))
client.delete(f"/users/{u7}")
ok("🔴 刪帳號後：這個人的片段檔全部刪掉（原始畫面不得留在磁碟上）", not any(p.exists() for p in mine))
ok("  別人的片段沒被誤刪", any(cc.clip_path(c["clip_id"]).exists()
                          for c in db.get_camera_clip_nights(uid)[DATE]["clips"]))

print("【8】沒有 camera_nightly 的夜晚：不做片段，已有的清掉")
u8 = db.create_user("no camera row")
r8 = cc.make_night(NIGHT, u8, "2026-09-13")
ok("沒有攝影機那一列 → 不做（狀態 no_camera_night）",
   r8["status"] == cc.STATUS_NO_CAMERA_NIGHT and db.get_camera_clip_nights(u8) == {}, r8["status"])
# 反向對照：補上那一列就做得出來——少了這條，把整個功能關掉這組也會綠
cam(u8, "2026-09-13")
made = cc.make_night(NIGHT, u8, "2026-09-13")
files8 = [cc.clip_path(c["clip_id"]) for c in db.get_camera_clip_nights(u8)["2026-09-13"]["clips"]]
ok("反向：有那一列就照做", made["status"] == cc.STATUS_OK and len(files8) == 3)
# 那一列後來不見了（例如重新匯入時被檢查擋掉）→ 重跑要把看不到的片段清掉
conn = db.connect()
conn.execute("DELETE FROM camera_nightly WHERE user_id = ?", (u8,))
conn.commit()
conn.close()
r8b = cc.make_night(NIGHT, u8, "2026-09-13")
ok("那一列不見之後重跑 → 片段列清掉", db.get_camera_clip_nights(u8) == {}
   and r8b.get("removed_clips") == 3, str(r8b))
ok("  檔案也刪掉了", not any(f.exists() for f in files8))

print("【9】框畫在哪（2026-11-09：原本被床鋪區域切成固定方框）")
blank = np.full((360, 640), 40, np.uint8)
moved = blank.copy(); moved[100:200, 300:420] = 220          # 一塊 120×100 的東西出現
box = cc.motion_box(blank, moved)
ok("畫面比對：框住那一塊（容許邊緣膨脹）",
   box is not None and abs(box[0] - 300) <= 12 and abs(box[1] - 100) <= 12
   and abs(box[2] - 120) <= 24 and abs(box[3] - 100) <= 24, str(box))
ok("反向：框不能是整個畫面", box is not None and box[2] < 640 and box[3] < 360)
ok("沒有變化 → 不畫框", cc.motion_box(blank, blank.copy()) is None)
speck = blank.copy(); speck[50:53, 50:53] = 220                 # 3×3 的噪點
ok("小噪點 → 不畫框", cc.motion_box(blank, speck) is None)
roi_b = (34, 129, 288, 231)
ok("CSV 外框：整個畫面那麼大的不採用（照明誤判／連成一片）",
   cc.highlight_box(roi_b, (0, 0, 640, 360)) == roi_b)
ok("CSV 外框：跟床鋪區域沒重疊的不採用（別處的雜訊）",
   cc.highlight_box(roi_b, (500, 10, 80, 60)) == roi_b)
ok("CSV 外框：合理又有重疊 → 用整個畫面那一塊",
   cc.highlight_box(roi_b, (200, 100, 200, 150)) == (200, 100, 200, 150))

print()
if fails:
    print(f"✗ {len(fails)} 項失敗 → {fails}")
    sys.exit(1)
print("✓ 全部通過")
