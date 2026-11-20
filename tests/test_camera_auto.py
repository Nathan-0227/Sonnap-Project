"""
tests/test_camera_auto.py —— 按 Start Sleep 自動開攝影機（2026-11-21 grill 定案）

  【1】誰能觸發：只有私有網段／本機；外面來的、認不得的一律不算
  【2】要做什麼（純函式）：不是手機帳號或不是區網一律不動；在錄不開第二個；沒在錄不停
  【3】handle()：開錄的參數（框、14 小時、整晚影片、防待機）、已經在錄、停錄只放旗標、
       Cancel 收尾後把檔案搬去 cancelled/（不刪）、錄影程式結束前不搬
  【4】鎖檔：程式死了就當沒在錄（不然之後永遠開不了）、超過 15 小時當作沒清掉
  【5】錄影程式：看到停止旗標自己收尾（CSV 寫完）、錄滿時數自己停、到點存畫面、
       接上攝影機才回報 recording、檔名與後端一致
  【6】攝影機有沒有移動：平移 40 像素判移動、只改亮度不算、床上的人動不算、
       沒有畫面／沒有基準不擋、多張取中間值
  【7】早上匯入：移動了 → 那晚攝影機不匯入（手錶照常）；--camera-ok 照樣匯；沒移動照常
  【8】重新框：舊的框與基準備份、新框寫進設定、基準換成這晚的畫面
  【9】API：外面來的請求不開錄、不是手機帳號不開錄、手機帳號從區網來才開；任何錯誤都不讓端點失敗

⚠️ 不接真的攝影機、不開真的錄影程式：開錄用假的 launcher，錄影程式用假的串流。
執行：python tests/test_camera_auto.py
"""
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import numpy as np
import cv2

import camera_auto as ca
import camera_alignment as al

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<62} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<62} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print(f"\n{'=' * 78}\n{title}\n{'=' * 78}")


def tmpdir():
    return Path(tempfile.mkdtemp())


# ═══════════════════════════════════════════════════════════════════
section("【1】誰能觸發")
# ═══════════════════════════════════════════════════════════════════
for ip, want in [("192.168.1.75", True), ("10.202.54.92", True), ("172.20.1.3", True),
                 ("127.0.0.1", True), ("::1", True), ("::ffff:192.168.1.5", True),
                 ("8.8.8.8", False), ("100.101.102.103", False),   # Tailscale：從外面連進來
                 ("testclient", False), (None, False), ("", False)]:
    check(f"{ip!r}", ca.is_local_network(ip), want)

# ═══════════════════════════════════════════════════════════════════
section("【2】要做什麼（純函式）")
# ═══════════════════════════════════════════════════════════════════
d = ca.decide
check("手機帳號＋區網＋沒在錄 → 開", d("start", is_owner=True, from_local=True, running=False), "start")
check("已經在錄 → 不開第二個", d("start", is_owner=True, from_local=True, running=True), "already")
check("Out of bed＋在錄 → 停", d("end", is_owner=True, from_local=True, running=True), "stop")
check("Out of bed＋沒在錄 → 不動", d("end", is_owner=True, from_local=True, running=False), "ignore")
check("Cancel＋在錄 → 取消", d("cancel", is_owner=True, from_local=True, running=True), "cancel")
for ev in ("start", "end", "cancel"):
    check(f"不是手機帳號（{ev}）→ 不動", d(ev, is_owner=False, from_local=True, running=True), "ignore")
    check(f"不是區網（{ev}）→ 不動", d(ev, is_owner=True, from_local=False, running=True), "ignore")
check("認不得的事件 → 不動", d("nap", is_owner=True, from_local=True, running=False), "ignore")


# ═══════════════════════════════════════════════════════════════════
section("【3】handle()")
# ═══════════════════════════════════════════════════════════════════
class FakeProc:
    def __init__(self, alive=True):
        self.alive = alive

    def poll(self):
        return None if self.alive else 1


launched = []


def fake_launcher(argv, metrics_dir):
    launched.append(argv)
    return FakeProc()


def no_lock(_d):
    return None


def run_handle(event, *, user="me", ip="192.168.1.5", lock=no_lock, wait_state="recording",
               metrics=None, **kw):
    return ca.handle(event, user, ip, phone_account="me", metrics_dir=metrics or tmpdir(),
                     launcher=fake_launcher, lock_reader=lock, battery=lambda: False,
                     wait=lambda alive, d: wait_state, cancel_async=False, **kw)


launched.clear()
check("不是手機帳號 → None（跟攝影機無關）", run_handle("start", user="friend"), None)
check("外面來的 → None", run_handle("start", ip="8.8.8.8"), None)
check("上面兩個都沒開錄", launched, [])

r = run_handle("start")
check("開錄 → recording", r, {"state": "recording", "on_battery": False})
argv = launched[-1]
ok("用 tapo_metric_logger.py", argv[1].endswith("tapo_metric_logger.py"), argv[1])
check("框是 34,129,288,231", argv[argv.index("--roi") + 1], "34,129,288,231")
check("影片錄滿 840 分鐘", argv[argv.index("--save-video") + 1], "840")
check("最多 14 小時", argv[argv.index("--max-hours") + 1], "14")
ok("錄影期間不待機", "--keep-awake" in argv)
check("錄影程式一開就結束 → not_started", run_handle("start", wait_state="failed")["state"], "not_started")
check("還在接攝影機 → starting（手機什麼都不寫）", run_handle("start", wait_state="starting")["state"],
      "starting")


def raising_launcher(argv, metrics_dir):
    raise OSError("no python")


check("開不起來（OSError）→ not_started",
      ca.handle("start", "me", "192.168.1.5", phone_account="me", metrics_dir=tmpdir(),
                launcher=raising_launcher, lock_reader=no_lock, battery=lambda: True)["state"],
      "not_started")

launched.clear()
running = lambda _d: {"pid": 1, "csv": "x.csv", "phase": "recording"}  # noqa: E731
check("已經在錄 → already_recording", run_handle("start", lock=running)["state"], "already_recording")
check("而且沒有開第二個", launched, [])

m = tmpdir()
r = run_handle("end", lock=running, metrics=m)
check("Out of bed → stopping", r, {"state": "stopping"})
ok("只放了停止旗標（不砍程式）", (m / ca.STOP_NAME).exists())
check("沒在錄時按 Out of bed → idle", run_handle("end"), {"state": "idle"})
check("沒在錄、外面來的 → None", run_handle("end", ip="8.8.8.8"), None)

# Cancel：錄影程式收尾（鎖檔消失）之後才搬
m = tmpdir()
csv = m / "20261121_013000.csv"
for suffix in (".csv", ".mp4", "_heat.npy", "_frame_015.png", "_snapshot.png"):
    (m / f"20261121_013000{suffix}").write_bytes(b"x")
(m / "20261120_010000.csv").write_bytes(b"other night")
calls = {"n": 0}


def lock_then_gone(_d):
    calls["n"] += 1
    return {"pid": 1, "csv": str(csv), "phase": "recording"} if calls["n"] <= 2 else None


r = ca.handle("cancel", "me", "192.168.1.5", phone_account="me", metrics_dir=m,
              launcher=fake_launcher, lock_reader=lock_then_gone, battery=lambda: False,
              cancel_async=False)
check("Cancel → cancelling", r, {"state": "cancelling"})
moved = sorted(p.name for p in (m / ca.CANCELLED_DIR_NAME).iterdir())
check("那一晚的五個檔都搬去 cancelled/", len(moved), 5)
ok("一個都沒刪（cancelled/ 裡都在）", all((m / ca.CANCELLED_DIR_NAME / n).exists() for n in moved))
ok("原本的位置沒有了（早上匯入不會挑到）", not csv.exists())
ok("別晚的檔案沒被搬", (m / "20261120_010000.csv").exists())

# 錄影程式一直沒結束 → 不搬（正在寫的檔案搬了會壞）
m2 = tmpdir()
(m2 / "a.csv").write_bytes(b"x")
clock = {"t": 0.0}
moved = ca.finish_cancel(m2 / "a.csv", m2, timeout=5, sleep=lambda s: clock.__setitem__("t", clock["t"] + s),
                         clock=lambda: clock["t"], lock_reader=lambda _d: {"pid": 1})
check("錄影程式沒結束 → 不搬", moved, [])
ok("檔案還在原位", (m2 / "a.csv").exists())

# ═══════════════════════════════════════════════════════════════════
section("【4】鎖檔")
# ═══════════════════════════════════════════════════════════════════
m = tmpdir()
check("沒有鎖檔 → 沒在錄", ca.read_lock(m), None)
(m / ca.LOCK_NAME).write_text(json.dumps({"pid": 4242, "csv": "a.csv", "phase": "recording",
                                          "started": datetime.now().isoformat()}), encoding="utf-8")
check("鎖檔在但程式死了 → 沒在錄（不然永遠開不了）", ca.read_lock(m, alive=lambda p: False), None)
ok("程式活著 → 在錄", ca.read_lock(m, alive=lambda p: True) is not None)
old = (datetime.now() - timedelta(hours=16)).isoformat()
(m / ca.LOCK_NAME).write_text(json.dumps({"pid": 4242, "started": old}), encoding="utf-8")
check("16 小時前的鎖檔 → 當作沒清掉", ca.read_lock(m, alive=lambda p: True), None)
(m / ca.LOCK_NAME).write_text("{壞掉", encoding="utf-8")
check("壞掉的鎖檔 → 沒在錄", ca.read_lock(m, alive=lambda p: True), None)
ok("自己這個程式算活著", ca.pid_alive(os.getpid()))
ok("不存在的 PID 不算活著", not ca.pid_alive(999999))

# ═══════════════════════════════════════════════════════════════════
section("【5】錄影程式")
# ═══════════════════════════════════════════════════════════════════
import tapo_metric_logger as tl

check("鎖檔名兩邊一樣", tl.LOCK_NAME, ca.LOCK_NAME)
check("停止旗標名兩邊一樣", tl.STOP_NAME, ca.STOP_NAME)
ok("畫面檔名比對那邊認得", Path("x" + tl.SNAPSHOT_FRAME_PATTERN.format(15)).match("x" + al.SNAPSHOT_FRAME_GLOB))
check("給人看的那張檔名兩邊一樣", tl.SNAPSHOT_BOX_SUFFIX, al.SNAPSHOT_BOX_SUFFIX)


WATCHDOG_READS = 3000


class FakeCap:
    """假的串流：一直給畫面；第 stop_after 次讀取時放停止旗標。"""

    def __init__(self, stop_path=None, stop_after=None):
        self.n = 0
        self.stop_path = stop_path
        self.stop_after = stop_after

    def isOpened(self):
        return True

    def set(self, *a):
        return True

    def read(self):
        self.n += 1
        if self.stop_path and self.stop_after and self.n == self.stop_after:
            Path(self.stop_path).write_text("stop", encoding="utf-8")
        if self.n >= WATCHDOG_READS:      # 拿掉停止旗標的檢查時，測試要紅、不是卡死
            tl._stop = True
        time.sleep(0.005)
        frame = np.full((360, 640, 3), 60, np.uint8)
        frame[150:200, 100:200] = (self.n * 7) % 255
        return True, frame

    def release(self):
        pass


saved = (tl.open_capture, tl.SNAPSHOT_AT_MINUTES, tl.SNAPSHOT_BOX_AT_MINUTES, tl.WARMUP_SECONDS)
try:
    tl.SNAPSHOT_AT_MINUTES = (0,)
    tl.SNAPSHOT_BOX_AT_MINUTES = 0
    tl.WARMUP_SECONDS = 0
    m = tmpdir()
    out = m / "20261121_013000.csv"
    stop = m / tl.STOP_NAME
    cap = FakeCap(stop, stop_after=200)
    tl.open_capture = lambda url: cap
    connected = []
    t0 = time.time()
    tl.run("rtsp://x@cam/stream2", out, roi=(34, 129, 288, 231), stop_path=stop,
           on_connected=lambda: connected.append(True))
    ok("看到停止旗標就自己收工（沒有被砍）", cap.n < WATCHDOG_READS, f"讀了 {cap.n} 格")
    tl._stop = False
    check("接上攝影機後回報一次", connected, [True])
    lines = out.read_text(encoding="utf-8").splitlines()
    ok("CSV 有檔頭、有框", any(l.startswith("# roi=34,129,288,231") for l in lines))
    ok("CSV 有資料列（收尾有寫完）", len([l for l in lines if not l.startswith("#")]) > 2, f"{len(lines)} 行")
    ok("存了比對用的原始畫面", (m / "20261121_013000_frame_000.png").exists())
    ok("存了畫上框的那張", (m / "20261121_013000_snapshot.png").exists())

    # 錄滿時數自己停（不靠後端計時）
    m = tmpdir()
    tl.open_capture = lambda url: FakeCap()
    t0 = time.time()
    tl.run("rtsp://x@cam/stream2", m / "b.csv", max_hours=1.0 / 3600)   # 1 秒
    ok("錄滿時數自己收工", time.time() - t0 < 10, f"{time.time() - t0:.1f}s")
finally:
    tl.open_capture, tl.SNAPSHOT_AT_MINUTES, tl.SNAPSHOT_BOX_AT_MINUTES, tl.WARMUP_SECONDS = saved

m = tmpdir()
lock = m / tl.LOCK_NAME
tl.write_lock(lock, csv_path=m / "a.csv", phase="connecting")
check("鎖檔記下自己的 PID", json.loads(lock.read_text(encoding="utf-8"))["pid"], os.getpid())
ok("後端讀得到（connecting）", ca.read_lock(m)["phase"] == "connecting")
lock.write_text(json.dumps({"pid": 999999}), encoding="utf-8")
tl.remove_lock(lock)
ok("別人的鎖檔不刪", lock.exists())
tl.write_lock(lock, csv_path=m / "a.csv", phase="recording")
tl.remove_lock(lock)
ok("自己的鎖檔收工時刪掉", not lock.exists())

# ═══════════════════════════════════════════════════════════════════
section("【6】攝影機有沒有移動")
# ═══════════════════════════════════════════════════════════════════
rng = np.random.default_rng(7)
ROI = (34, 129, 288, 231)


def scene(seed_person=0):
    """上方是固定的牆與層架（有紋理），下方是床，人每晚不一樣。"""
    img = np.zeros((360, 640), np.uint8)
    wall = cv2.GaussianBlur(rng_fixed.integers(0, 255, (360, 640)).astype(np.uint8), (9, 9), 0)
    img[:] = wall
    cv2.rectangle(img, (200, 30), (420, 60), 230, -1)             # 層架
    cv2.rectangle(img, (480, 10), (600, 90), 30, -1)              # 窗
    person = np.random.default_rng(seed_person).integers(0, 255, (231, 288)).astype(np.uint8)
    img[129:360, 34:322] = cv2.GaussianBlur(person, (15, 15), 0)
    return img


rng_fixed = np.random.default_rng(3)
fixed = rng_fixed.integers(0, 255, (360, 640)).astype(np.uint8)
rng_fixed = SimpleNamespace(integers=lambda lo, hi, shape: fixed)   # 每次同一面牆
ref = scene(1)


def shifted(img, dx, dy=0):
    return cv2.warpAffine(img, np.float32([[1, 0, dx], [0, 1, dy]]), (640, 360),
                          borderMode=cv2.BORDER_REFLECT)


ok("攝影機沒動、床上的人不一樣 → 不算移動", al.frame_shift(ref, scene(99), ROI) < 5,
   f"{al.frame_shift(ref, scene(99), ROI):.1f}")
ok("平移 40 像素 → 量到約 40", abs(al.frame_shift(ref, shifted(scene(5), 40), ROI) - 40) < 3,
   f"{al.frame_shift(ref, shifted(scene(5), 40), ROI):.1f}")
bright = np.clip(scene(8).astype(np.int16) + 50, 0, 255).astype(np.uint8)
ok("整張變亮（開燈、紅外線切換）→ 不算移動", al.frame_shift(ref, bright, ROI) < 5,
   f"{al.frame_shift(ref, bright, ROI):.1f}")


def night(frames, *, ref_img=ref, roi=ROI):
    m = tmpdir()
    if ref_img is not None:
        al.save_reference(ref_img, roi, m)
    csv = m / "20261121_013000.csv"
    csv.write_text("# x\n", encoding="utf-8")
    for i, f in enumerate(frames):
        cv2.imwrite(str(m / f"20261121_013000_frame_{(i + 1) * 15:03d}.png"), f)
    return csv, m


csv, m = night([scene(2), scene(3), scene(4)])
check("三張都沒動 → ok", al.check(csv, m).status, "ok")
csv, m = night([shifted(scene(2), 40), shifted(scene(3), 42), shifted(scene(4), 38)])
check("三張都平移約 40 → moved", al.check(csv, m).status, "moved")
csv, m = night([scene(2), shifted(scene(3), 80), scene(4)])
check("只有一張怪（人擋住鏡頭）→ 中間值沒事", al.check(csv, m).status, "ok")
csv, m = night([])
check("沒有今晚的畫面 → no_snapshot（不擋）", al.check(csv, m).status, "no_snapshot")
csv, m = night([scene(2)], ref_img=None)
check("沒有基準 → no_reference（不擋）", al.check(csv, m).status, "no_reference")
check("框太靠上、上方那一條太窄 → 比整張", al.strip_height((0, 20, 100, 100)), None)
check("現在的框：上方 120 像素", al.strip_height(ROI), 120)

# ═══════════════════════════════════════════════════════════════════
section("【7】早上匯入")
# ═══════════════════════════════════════════════════════════════════
import morning_import as mi

moved_result = al.Alignment("moved", shift_px=41.0, snapshot=Path("x_snapshot.png"))
check("移動了 → 那晚攝影機不匯入", mi._alignment_gate(Path("x.csv"), Path("."), lambda c, d: moved_result, False),
      None)
check("加 --camera-ok → 照樣匯入", mi._alignment_gate(Path("x.csv"), Path("."), lambda c, d: moved_result, True),
      Path("x.csv"))
for status in ("ok", "no_snapshot", "no_reference"):
    check(f"{status} → 照常匯入",
          mi._alignment_gate(Path("x.csv"), Path("."), lambda c, d, s=status: al.Alignment(s), False),
          Path("x.csv"))
ok("--camera-ok 參數存在", mi.parse_args(["--camera-ok"]).camera_ok is True)

# ═══════════════════════════════════════════════════════════════════
section("【8】重新框")
# ═══════════════════════════════════════════════════════════════════
import camera_reframe as rf

m = tmpdir()
old_ref = scene(1)
al.save_reference(old_ref, ROI, m)
new_frame = shifted(scene(2), 40)
backup = rf.apply_new_roi((60, 140, 280, 220), new_frame, m, now=datetime(2026, 11, 21, 9, 0))
check("新框寫進設定", ca.load_config(m)["roi"], [60, 140, 280, 220])
check("其他設定不變（840 分鐘）", ca.load_config(m)["save_video_minutes"], 840)
ok("舊的設定有備份（沒有設定檔時存當時的預設）",
   json.loads((backup / ca.CONFIG_NAME).read_text(encoding="utf-8"))["roi"] == [34, 129, 288, 231])
ok("舊的基準有備份", (backup / al.REFERENCE_FRAME_NAME).exists())
new_ref, new_roi = al.load_reference(m)
check("基準的框換成新的", new_roi, (60, 140, 280, 220))
ok("基準換成這晚的畫面（跟新畫面比不會判移動）", al.frame_shift(new_ref, new_frame, new_roi) < 3)
check("熱區不合理（沒有熱區）→ 不建議", rf.suggest_roi(np.zeros((360, 640), np.float32)), None)

# ═══════════════════════════════════════════════════════════════════
section("【9】API")
# ═══════════════════════════════════════════════════════════════════
import db
db.DB_PATH = tmpdir() / "test_camera_auto.db"
db.init_db()
import main
from fastapi.testclient import TestClient

spawned = []


def recording_launcher(argv, metrics_dir):
    spawned.append(argv)
    return FakeProc()


saved_api = (ca.launch_logger, ca.wait_for_connect, ca.on_battery, ca.METRICS_DIR)
API_METRICS = tmpdir()
handle_defaults = ca.handle.__kwdefaults__.copy()
ca.handle.__kwdefaults__.update({"launcher": recording_launcher, "metrics_dir": API_METRICS,
                                 "wait": lambda alive, d: "recording", "battery": lambda: True,
                                 "lock_reader": no_lock})
try:
    outside = TestClient(main.app, raise_server_exceptions=False)
    home = TestClient(main.app, raise_server_exceptions=False, client=("192.168.1.20", 5000))

    def make_user(name):
        return outside.post("/users", json={"display_name": name, "target_bedtime": "23:30"}).json()["user_id"]

    me, friend = make_user("Phone"), make_user("Friend")
    for i in range(3):   # 手機帳號＝夜數最多的那個
        db.upsert_nightly_behavior(me, f"2026-11-1{i}", "23:30", f"2026-11-1{i}T23:40:00", 10, False)
    db.upsert_nightly_behavior(friend, "2026-11-10", "23:30", "2026-11-10T23:40:00", 10, False)
    at = "2026-11-21T01:00:00"

    r = outside.post("/sleep-status", json={"user_id": me, "event": "start", "at": at})
    check("外面來的請求：200", r.status_code, 200)
    ok("外面來的：沒有 camera、沒開錄", "camera" not in r.json() and spawned == [])
    r = home.post("/sleep-status", json={"user_id": friend, "event": "start", "at": at})
    ok("不是手機帳號：沒有 camera、沒開錄", "camera" not in r.json() and spawned == [])
    r = home.post("/sleep-status", json={"user_id": me, "event": "start", "at": at})
    check("手機帳號從區網來：開錄", r.json().get("camera"), {"state": "recording", "on_battery": True})
    check("只開了一個", len(spawned), 1)
    ok("好友即時狀態照記", db.get_live_sleep_status(me) is not None if hasattr(db, "get_live_sleep_status")
       else True)

    def boom(*a, **k):
        raise RuntimeError("camera broke")

    ca.handle.__kwdefaults__["launcher"] = boom
    r = home.post("/sleep-status", json={"user_id": me, "event": "start", "at": at})
    check("攝影機那邊出錯：端點照樣 200", r.status_code, 200)
    check("出錯時不帶 camera", "camera" in r.json(), False)
finally:
    ca.handle.__kwdefaults__.clear()
    ca.handle.__kwdefaults__.update(handle_defaults)

print()
if fails:
    print(f"✗ {len(fails)} 項沒過：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
