#!/usr/bin/env python
"""
錄影期間的網路狀態記錄器 —— 回答「斷線時是哪一邊先走的」。

⚠️ 為什麼需要這支（2026-09-09 那晚）：
   錄影掛了 233 分鐘只拿到 17.9 分鐘資料，事後**查不出**是
   「手機熱點自己關掉」還是「筆電漫遊去接別的 Wi-Fi」——
   兩者的解法完全相反（前者改手機設定，後者關掉自動連線），
   但錄影的 CSV 裡只有「串流中斷」，沒有任何網路面的證據。

   這台機器只有一張 Wi-Fi，而且存了 41 個已知網路；相機只連得上
   手機熱點（校園的 eduroam / TANetRoaming 是 WPA2-Enterprise，
   IoT 相機在規格上就加入不了）。所以這兩種情境都完全可能。

   每 30 秒記一列：SSID、本機 IPv4、相機 554 埠通不通。
   隔天與錄影 CSV 對時間戳就知道答案。

⚠️ **它不碰錄影，也不寫錄影的 CSV。** 刻意分開：錄影 CSV 的欄位有測試守著
   （`tests/test_tapo_roi_csv.py` 守 ROI 分母），為了診斷去改它的 schema
   風險不對等——診斷是暫時的，那個分母是永久的。

⚠️ 相機網址從 `tapo 2.0/.env` 讀，**只取 host，永遠不印帳密**。

用法（與錄影同時，另開一個終端機）：

  .venv/Scripts/python.exe tapo_netwatch.py

隔天：

  .venv/Scripts/python.exe tapo_netwatch.py --report tapo_metrics/<檔名>_netwatch.csv
"""

import argparse
import csv
import re
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

from tapo_metric_logger import OUT_DIR, read_rtsp_url

INTERVAL_SECONDS = 30
PORT_TIMEOUT = 3.0
RTSP_PORT = 554

# ⚠️ netsh 的輸出會跟著系統語言變。用「冒號前的欄位名」比對而不是固定行號，
#    並且**排除 BSSID**——它也以 SSID 結尾，抓錯會記到 AP 的 MAC。
_SSID_RE = re.compile(r"^\s*SSID\s*:\s*(.+?)\s*$")
_STATE_RE = re.compile(r"^\s*(?:State|狀態)\s*:\s*(.+?)\s*$")


def current_wifi():
    """回 (ssid, state)。拿不到就回 ("", "")，不要讓記錄器因此死掉。"""
    try:
        out = subprocess.run(
            ["netsh", "wlan", "show", "interfaces"],
            capture_output=True, text=True, timeout=10,
            encoding="utf-8", errors="replace",
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return "", ""
    ssid = state = ""
    for line in out.splitlines():
        if "BSSID" in line:
            continue
        m = _SSID_RE.match(line)
        if m and not ssid:
            ssid = m.group(1)
        m = _STATE_RE.match(line)
        if m and not state:
            state = m.group(1)
    return ssid, state


def local_ipv4():
    """本機**預設路由**那張介面的 IPv4。UDP connect 不會真的送封包。"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return ""
    finally:
        sock.close()


def port_open(host, port=RTSP_PORT, timeout=PORT_TIMEOUT):
    """相機的 RTSP 埠通不通。這比 ping 準——有些相機不回 ICMP。"""
    sock = socket.socket()
    sock.settimeout(timeout)
    try:
        sock.connect((host, port))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def camera_host(env_file=None):
    """從 .env 的網址只取 host。⚠️ 回傳值不含帳密，可以印。"""
    url = read_rtsp_url(env_file)
    return url.rsplit("@", 1)[-1].split(":")[0].split("/")[0]


def watch(host, out_path, interval=INTERVAL_SECONDS):
    print(f"● 監看 {host}:{RTSP_PORT}，每 {interval} 秒一列")
    print(f"● 寫入 {out_path}")
    print("● Ctrl+C 結束")
    with out_path.open("w", newline="", encoding="utf-8") as fh:
        fh.write(f"# tapo_netwatch  started={datetime.now().isoformat()}\n")
        fh.write(f"# camera_host={host} interval_s={interval}\n")
        w = csv.writer(fh)
        w.writerow(["t", "ssid", "wifi_state", "local_ip", "camera_reachable"])
        prev = None
        try:
            while True:
                ssid, state = current_wifi()
                ip = local_ipv4()
                ok = port_open(host)
                w.writerow([datetime.now().isoformat(timespec="seconds"),
                            ssid, state, ip, int(ok)])
                fh.flush()
                # 只在**狀態改變**時印，否則整夜洗版看不出重點
                now = (ssid, ip, ok)
                if now != prev:
                    mark = "✅" if ok else "❌"
                    print(f"  {datetime.now():%H:%M:%S}  {mark} "
                          f"SSID={ssid or '(無)'}  本機={ip or '(無)'}")
                    prev = now
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\n● 收工")
    report(out_path)


def report(path):
    """把整夜壓成「發生了什麼」——這才是隔天真正要看的東西。"""
    rows = [r for r in csv.DictReader(
        l for l in path.open(encoding="utf-8") if not l.startswith("#"))]
    if not rows:
        print("⚠ 沒有資料")
        return
    t0 = datetime.fromisoformat(rows[0]["t"])
    t1 = datetime.fromisoformat(rows[-1]["t"])
    up = sum(1 for r in rows if r["camera_reachable"] == "1")
    print(f"\n  {t0:%m-%d %H:%M} ~ {t1:%m-%d %H:%M}"
          f"（{(t1-t0).total_seconds()/3600:.1f} 小時、{len(rows)} 列）")
    print(f"  相機可達 {up}/{len(rows)} 列（{up/len(rows)*100:.0f}%）")

    print("\n  狀態變化（這一欄就是答案）：")
    prev = None
    for r in rows:
        cur = (r["ssid"], r["local_ip"], r["camera_reachable"])
        if cur != prev:
            t = datetime.fromisoformat(r["t"])
            mark = "✅可達" if r["camera_reachable"] == "1" else "❌不可達"
            print(f"    {t:%H:%M:%S}  {mark}  "
                  f"SSID={r['ssid'] or '(無)'}  本機={r['local_ip'] or '(無)'}")
            prev = cur

    print("\n  怎麼判讀：")
    print("    SSID 換掉了      → 筆電漫遊去別的 Wi-Fi。關掉那些網路的自動連線")
    print("    SSID 變成 (無)   → 熱點消失了。改手機的『無裝置時自動關閉』＋插電")
    print("    SSID 沒變但不可達 → 相機自己掉線或手機把它踢了")


def main():
    ap = argparse.ArgumentParser(description="錄影期間的網路狀態記錄器")
    ap.add_argument("--report", type=Path, help="不監看，只重讀既有的 netwatch CSV")
    ap.add_argument("--env-file", help="含 CAMERA_RTSP_URL 的 .env（worktree 要指到主 clone）")
    ap.add_argument("--interval", type=int, default=INTERVAL_SECONDS, metavar="秒")
    ap.add_argument("--host", help="直接指定相機 IP，不讀 .env")
    args = ap.parse_args()

    if args.report:
        report(args.report)
        return

    host = args.host or camera_host(args.env_file)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{datetime.now():%Y%m%d_%H%M%S}_netwatch.csv"
    watch(host, out, args.interval)


if __name__ == "__main__":
    main()
