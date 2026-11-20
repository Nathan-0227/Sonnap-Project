"""
camera_auto.py — 手機按 Start Sleep 就自動開攝影機錄影，Out of bed／Cancel 就停（2026-11-21 使用者 grill 定案）。

═══════════════════════════════════════════════════════════════════
流程
═══════════════════════════════════════════════════════════════════
  手機 POST /sleep-status（start／end／cancel）
    → main.py 照舊記好友即時狀態
    → handle()：decide() 決定要不要動攝影機
         start  → 另外開一個**獨立的** tapo_metric_logger.py（後端重開也不會斷）
         end    → 放停止旗標檔，錄影程式看到就自己收尾
         cancel → 同上，收尾之後把那一晚的檔案搬到 cancelled/（不刪、早上匯入不會挑到）

═══════════════════════════════════════════════════════════════════
不能破的規則（每一條都是 grill 的答案）
═══════════════════════════════════════════════════════════════════
⚠️ **只認手機帳號**（db.resolve_phone_account，與手錶／攝影機匯入同一個判準），
   **而且請求要來自私有網段或本機**（Q1、Q2）。API 沒有密碼、user_id 就是鑰匙，
   不擋的話拿到 id 的人就能從外面讓臥室的攝影機開錄。
⚠️ **停錄不可以從外面砍**：Windows 上 terminate() 是 TerminateProcess，
   錄影程式的收尾（熱區圖、影片檔尾）一個都不會做，影片會壞（Q3）。
   所以只放旗標檔，讓它自己結束。
⚠️ **已經在錄就不開第二個**（Q6）；兩個程式同時接攝影機會搶串流。
   「在錄」看錄影程式自己寫的鎖檔，**手動開的也算**——Out of bed 一樣停它（Q10）。
⚠️ 最多錄 14 小時（Q4），由錄影程式自己的 --max-hours 守，不靠後端計時
   （後端半夜重開的話計時就沒了）。
⚠️ 這裡任何錯誤都**不能**讓 /sleep-status 失敗：好友狀態照記，攝影機只是附加的。
"""
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).parent
METRICS_DIR = ROOT / "tapo_metrics"
LOGGER_SCRIPT = ROOT / "tapo_metric_logger.py"

# 錄影程式與這邊共用的兩個檔名（定義在錄影程式那邊，這裡只照抄名字）
LOCK_NAME = "logger.lock"
STOP_NAME = "STOP"
CANCELLED_DIR_NAME = "cancelled"
CONFIG_NAME = "camera_auto.json"
AUTO_LOG_NAME = "auto_logger.log"

# Q8：沒有設定檔時用這組（也是 2026-09 三晚人工標註校準時用的框）
DEFAULT_CONFIG = {
    "roi": [34, 129, 288, 231],
    # 14 小時 = 840 分鐘，涵蓋整晚，隔天才剪得出動作片段
    "save_video_minutes": 840,
    # Q4：忘了按 Out of bed 的保險。與睡覺畫面、鬧鐘同一個 14 小時
    "max_hours": 14,
}

# 開錄之後等錄影程式回報「接上攝影機了」最多幾秒。手機那邊的逾時要比這個長。
CONNECT_WAIT_SECONDS = 8.0
# Cancel 時等錄影程式收尾最多幾秒（它卡在重連時可能要等一陣子）
CANCEL_WAIT_SECONDS = 180.0
# 鎖檔超過這麼久還在，一定是錄影程式被硬砍沒清掉（它自己最多錄 14 小時）
STALE_LOCK_HOURS = 15.0


# ─── 判斷（純函式）─────────────────────────────────────────────────

def is_local_network(client_ip):
    """
    請求是不是來自本機或私有網段（家裡 Wi-Fi、手機熱點、USB 轉接）。
    認不得的（測試的 'testclient'、None）一律當外面來的。
    ⚠️ Tailscale 那種 100.64.0.0/10 不算：那是從外面連進來的。
    """
    try:
        ip = ipaddress.ip_address(str(client_ip))
    except ValueError:
        return False
    if ip.is_loopback:
        return True
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    if ip in ipaddress.ip_network("100.64.0.0/10"):
        return False
    return ip.is_private


def decide(event, *, is_owner, from_local, running):
    """
    回傳要做什麼：'start'／'already'／'stop'／'cancel'／'ignore'。

    'ignore' 的情況：不是手機帳號、不是區網、要停但沒有在錄、事件不認得。
    """
    if not is_owner or not from_local:
        return "ignore"
    if event == "start":
        return "already" if running else "start"
    if event == "end":
        return "stop" if running else "ignore"
    if event == "cancel":
        return "cancel" if running else "ignore"
    return "ignore"


# ─── 設定與鎖檔 ────────────────────────────────────────────────────

def load_config(metrics_dir=METRICS_DIR):
    """讀 tapo_metrics/camera_auto.json，缺的欄位補預設值。檔案不存在就用預設（不寫檔）。"""
    cfg = dict(DEFAULT_CONFIG)
    path = Path(metrics_dir) / CONFIG_NAME
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                cfg.update({k: v for k, v in data.items() if k in DEFAULT_CONFIG})
        except (OSError, ValueError):
            pass
    return cfg


def save_config(cfg, metrics_dir=METRICS_DIR):
    path = Path(metrics_dir) / CONFIG_NAME
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def pid_alive(pid):
    """這個 PID 的程式還活著嗎。Windows 用 OpenProcess，其他系統用 kill(0)。"""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if sys.platform == "win32":
        import ctypes
        from ctypes import wintypes
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        STILL_ACTIVE = 259
        k32 = ctypes.windll.kernel32
        handle = k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        try:
            code = wintypes.DWORD()
            if not k32.GetExitCodeProcess(handle, ctypes.byref(code)):
                return False
            return code.value == STILL_ACTIVE
        finally:
            k32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_lock(metrics_dir=METRICS_DIR, *, alive=pid_alive, now=None):
    """
    錄影程式寫的鎖檔。回傳 dict（pid、csv、phase、started）或 None（沒在錄）。

    ⚠️ 鎖檔在、但程式已經死了（被硬砍、當機）→ 當成沒在錄，不然之後永遠開不了錄。
    """
    path = Path(metrics_dir) / LOCK_NAME
    try:
        info = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(info, dict) or not alive(info.get("pid")):
        return None
    started = info.get("started")
    if started:
        try:
            age_h = ((now or datetime.now()) - datetime.fromisoformat(started)).total_seconds() / 3600
            if age_h > STALE_LOCK_HOURS:
                return None
        except ValueError:
            pass
    return info


def on_battery():
    """筆電現在是不是用電池。查不到回 None（桌機、非 Windows）。"""
    if sys.platform != "win32":
        return None
    import ctypes

    class SYSTEM_POWER_STATUS(ctypes.Structure):
        _fields_ = [("ACLineStatus", ctypes.c_byte), ("BatteryFlag", ctypes.c_byte),
                    ("BatteryLifePercent", ctypes.c_byte), ("SystemStatusFlag", ctypes.c_byte),
                    ("BatteryLifeTime", ctypes.c_ulong), ("BatteryFullLifeTime", ctypes.c_ulong)]

    status = SYSTEM_POWER_STATUS()
    if not ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(status)):
        return None
    if status.ACLineStatus == 0:
        return True
    if status.ACLineStatus == 1:
        return False
    return None


# ─── 動作 ─────────────────────────────────────────────────────────

def logger_argv(cfg, python=None):
    roi = cfg["roi"]
    return [
        python or sys.executable, str(LOGGER_SCRIPT),
        "--roi", ",".join(str(int(v)) for v in roi),
        "--save-video", str(cfg["save_video_minutes"]),
        "--max-hours", str(cfg["max_hours"]),
        "--keep-awake",
    ]


def launch_logger(argv, metrics_dir=METRICS_DIR):
    """
    開一個**跟後端脫鉤**的錄影程式：後端關掉或重開，它照樣錄。
    輸出寫進 tapo_metrics/auto_logger.log（裡面不會有帳密，錄影程式本來就不印）。
    """
    metrics_dir = Path(metrics_dir)
    metrics_dir.mkdir(parents=True, exist_ok=True)
    log = (metrics_dir / AUTO_LOG_NAME).open("a", encoding="utf-8")
    log.write(f"\n===== {datetime.now().isoformat(timespec='seconds')} auto start =====\n")
    log.flush()
    kwargs = {"cwd": str(ROOT), "stdout": log, "stderr": subprocess.STDOUT,
              "stdin": subprocess.DEVNULL, "env": {**os.environ, "PYTHONIOENCODING": "utf-8"}}
    if sys.platform == "win32":
        # ⚠️ 不要加回 DETACHED_PROCESS（2026-11-21 實機：每次開錄跳出一個黑色終端機視窗，
        #    關掉它錄影就斷）。venv 的 python.exe 只是轉介，真正跑的是它叫起來的系統 Python；
        #    轉介那支「沒有主控台」時，系統 Python 會自己開一個看得見的新視窗。
        #    CREATE_NO_WINDOW 給它一個隱藏的主控台、往下繼承，就沒有視窗。
        #    一樣跟後端脫鉤：不在後端那個終端機裡，Ctrl+C／關掉後端都碰不到它。
        kwargs["creationflags"] = (subprocess.CREATE_NEW_PROCESS_GROUP
                                   | subprocess.CREATE_NO_WINDOW)
    else:
        kwargs["start_new_session"] = True
    try:
        return subprocess.Popen(argv, **kwargs)
    finally:
        log.close()


def request_stop(metrics_dir=METRICS_DIR):
    """放停止旗標檔。錄影程式每一圈都會看，看到就自己收尾結束。"""
    path = Path(metrics_dir) / STOP_NAME
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(datetime.now().isoformat(timespec="seconds"), encoding="utf-8")
    return path


def wait_for_connect(proc_alive, metrics_dir=METRICS_DIR, *, timeout=CONNECT_WAIT_SECONDS,
                     sleep=time.sleep, clock=time.monotonic, lock_reader=read_lock):
    """
    等錄影程式回報接上攝影機。回 'recording'（接上了）／'failed'（程式結束了）／'starting'（還在接）。
    """
    deadline = clock() + timeout
    while True:
        info = lock_reader(metrics_dir)
        if info and info.get("phase") == "recording":
            return "recording"
        if not proc_alive():
            return "failed"
        if clock() >= deadline:
            return "starting"
        sleep(0.25)


def cancelled_files(csv_path):
    """同一晚的所有檔案（CSV、影片、熱區圖、畫面）：檔名前綴相同的那幾個。"""
    csv_path = Path(csv_path)
    return sorted(p for p in csv_path.parent.glob(csv_path.stem + "*") if p.is_file())


def move_to_cancelled(csv_path, metrics_dir=METRICS_DIR):
    """Q5：不刪，搬到 cancelled/（早上匯入只看 tapo_metrics 第一層，不會挑到）。"""
    dest = Path(metrics_dir) / CANCELLED_DIR_NAME
    dest.mkdir(parents=True, exist_ok=True)
    moved = []
    for p in cancelled_files(csv_path):
        target = dest / p.name
        shutil.move(str(p), str(target))
        moved.append(target)
    return moved


def finish_cancel(csv_path, metrics_dir=METRICS_DIR, *, timeout=CANCEL_WAIT_SECONDS,
                  sleep=time.sleep, clock=time.monotonic, lock_reader=read_lock):
    """等錄影程式收尾（鎖檔消失）再搬檔。等不到就不搬——正在寫的檔案搬了會壞。"""
    deadline = clock() + timeout
    while lock_reader(metrics_dir) is not None:
        if clock() >= deadline:
            return []
        sleep(1.0)
    if not csv_path:
        return []
    return move_to_cancelled(csv_path, metrics_dir)


def handle(event, user_id, client_ip, *, phone_account=None, metrics_dir=METRICS_DIR,
           launcher=launch_logger, lock_reader=read_lock, battery=on_battery,
           wait=wait_for_connect, cancel_async=True, config_loader=load_config):
    """
    /sleep-status 收到一個事件之後要對攝影機做什麼。回傳給手機的那一小段（dict），
    或 None（跟攝影機無關：不是手機帳號、不是區網）。

    state：
      recording         開了、而且接上攝影機
      already_recording 本來就在錄（手動開的或前一次按的）
      starting          開了，但還沒回報接上（手機那邊什麼都不寫）
      not_started       開錄失敗
      stopping／cancelling 放了停止旗標
      idle              要停但本來就沒在錄
    """
    is_owner = phone_account is not None and user_id == phone_account
    from_local = is_local_network(client_ip)
    lock = lock_reader(metrics_dir)
    action = decide(event, is_owner=is_owner, from_local=from_local, running=lock is not None)

    if action == "ignore":
        if is_owner and from_local and event in ("end", "cancel"):
            return {"state": "idle"}
        return None
    if action == "already":
        return {"state": "already_recording", "on_battery": battery()}
    if action == "start":
        cfg = config_loader(metrics_dir)
        try:
            proc = launcher(logger_argv(cfg), metrics_dir)
        except OSError:
            return {"state": "not_started", "on_battery": battery()}
        state = wait(lambda: proc.poll() is None, metrics_dir)
        if state == "failed":
            state = "not_started"
        return {"state": state, "on_battery": battery()}
    if action == "stop":
        request_stop(metrics_dir)
        return {"state": "stopping"}
    if action == "cancel":
        request_stop(metrics_dir)
        csv_path = lock.get("csv")
        if cancel_async:
            threading.Thread(target=finish_cancel, args=(csv_path, metrics_dir),
                             kwargs={"lock_reader": lock_reader}, daemon=True).start()
        else:
            finish_cancel(csv_path, metrics_dir, lock_reader=lock_reader)
        return {"state": "cancelling"}
    return None
