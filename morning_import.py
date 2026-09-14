"""
morning_import.py — 每天早上一條指令：把昨晚的手錶與攝影機資料寫進資料庫。

    ① 資料庫連得上嗎                                   ← 沒過就停，什麼都沒動
    ② 昨晚的錄影：還在錄？太短？後半夜斷線？             ← 沒過就停，什麼都沒動
    ③ 手錶：備份 → 抓 Garmin（完整區間）→ 評分 → 晚數檢查 ← 沒過就還原檔案再停
    ④ 全部過了才寫：手錶 → DB、攝影機 → DB、補夢境、重建 App 資料檔

═══════════════════════════════════════════════════════════════════
為什麼要包成一支
═══════════════════════════════════════════════════════════════════
早上那一串原本是九條要照順序打的指令，其中兩個錯**不會報錯**：

1. **抓資料是覆寫。** 少給日期範圍（或用 `run_pipeline.py --fetch`——
   `garmin_connect_fetch.py` 的 `--days` 預設是 1）會把整份歷史換成
   最近一天，之後的評分、匯入全部照常成功。
2. **攝影機半夜斷線時，臥床時間會被算短，而且短得很合理。**
   09-13 那晚錄了 304 分鐘，後半段串流沒回來，算出 124 分鐘——
   剛好過了「不到 120 分鐘不算一晚」的門檻，會被當成正常的一晚寫進去。

兩個都得靠人看數字才擋得住，而早上剛起床正是最不會仔細看的時候。

═══════════════════════════════════════════════════════════════════
停下來的規則
═══════════════════════════════════════════════════════════════════
| 檢查 | 什麼時候停 | 停下來時的狀態 |
|---|---|---|
| 資料庫 | 沒設 `SONNAP_DB_URL`，或 5 秒內連不上 | 什麼都還沒動 |
| 攝影機 | 還在錄、不到 120 分鐘、臥床 ÷ 錄影時長 < 0.8 | 什麼都還沒動（排在抓手錶**之前**） |
| 手錶 | 抓取或評分失敗、原本有的夜晚不見了 | 還原成跑之前的檔案 |

**任何一項沒過，資料庫一筆都不寫。**
攝影機排在前面，是因為它只讀本機檔案、幾秒就查完；
手錶要連 Garmin 伺服器好幾分鐘，沒必要先抓完才發現今天整批都不能寫。

⚠️ 「寫入」那一段本身沒有交易保護：手錶寫完、攝影機寫到一半失敗的話，
   手錶那份會留著。兩支匯入腳本都可以重複執行（upsert），修好再跑一次就好。

═══════════════════════════════════════════════════════════════════
用法（PowerShell，在主 clone 跑——.env 只在那裡）
═══════════════════════════════════════════════════════════════════
    $env:SONNAP_DB_URL="mysql://root@localhost/sonnap"
    .venv\\Scripts\\python.exe morning_import.py

    --skip-camera          昨晚沒錄、或錄壞了，只匯手錶
    --camera-csv <路徑>    指定要匯入哪一份錄影（預設挑昨晚最長的那份）
    --no-ai                不補夢境（夢境要花 Claude API 額度）
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "garmin"))

import db_backend                                   # noqa: E402
import migrate_camera_to_db                         # noqa: E402
import tapo_sleep_onset as onset                    # noqa: E402
from apply_recovery_modifier import WEARER_SEGMENTS  # noqa: E402
from behavior import adherence                      # noqa: E402
from tapo_metric_logger import read_started         # noqa: E402

# 從第一個戴錶者分段的起日抓起。不另外寫一個日期：分段表是唯一定義處，
# 哪天往前補資料時兩邊才不會各說各話。
FETCH_START = WEARER_SEGMENTS[0][0]

# 臥床時間 ÷ 錄影時長低於這個比例，就當成「後半段沒有資料」。
#
# 校準（2026-09-15，tapo_metrics/ 裡全部的整夜錄影）：
#   正常的夜晚（09-01、03、06、10、11、14）      0.99–1.00
#   09-12（起床後串流斷了一小時才按停）            0.91   ← 不能擋
#   09-13（後半夜斷線，錄 304 分算出 124 分）       0.41   ← 要擋
#   09-09（熱點掉了，錄 233 分算出 54 分）          0.23   ← 要擋
# 0.8 落在 0.41 與 0.91 中間，兩邊都有餘裕。
#
# ⚠️ 「錄影時長」算到**最後一列**，包含斷線期間的標記列——logger 斷線時
#    每十次重試寫一列空值標記，所以最後一列離按下 Ctrl+C 不會超過幾分鐘。
#    臥床時間則只算到最後一筆**可用**資料（tapo_sleep_onset.analyse）。
#    兩者的差就是「錄了但沒有資料」的那一段。
MIN_BED_COVERAGE = 0.8

# CSV 在這麼多秒內還被寫過，就當成錄影還開著。
# logger 每 100 列 flush 一次，約 4 幀/秒 → 25 秒一次，120 秒夠寬。
RECORDING_ACTIVE_SECONDS = 120

# 09-15 資料庫壞掉時，連線是「接得通但永遠不回應」——沒有逾時的話
# 腳本會一直卡住，看起來像在跑。
DB_TIMEOUT_SECONDS = 5

# 每次備份整個 garmin/data（約 16 MB），留最近幾份。
KEEP_BACKUPS = 7
BACKUP_STAMP = re.compile(r"^\d{8}_\d{6}$")


class Stop(Exception):
    """某一項檢查沒過。訊息是給人看的，要說清楚下一步怎麼做。"""


@dataclass
class Paths:
    root: Path
    backup_root: Path

    @property
    def garmin_data(self):
        return self.root / "garmin" / "data"

    @property
    def final_json(self):
        return self.garmin_data / "garmin_sleep_quality_final.json"

    @property
    def payload(self):
        return self.root / "app" / "assets" / "data" / "app_payload.json"

    @property
    def metrics_dir(self):
        return self.root / "tapo_metrics"


# ═══════════════════════════════════════════════════════════════════
# ① 資料庫
# ═══════════════════════════════════════════════════════════════════

def check_database(env):
    """回 (ok, 訊息)。⚠️ 訊息裡不得出現 URL——它可能帶密碼。"""
    url = env.get("SONNAP_DB_URL", "")
    try:
        cfg = db_backend.mysql_config(url) if url else None
    except ValueError:
        # mysql_config 的例外訊息會把整個 URL 印出來，所以不轉述它
        return False, "SONNAP_DB_URL 的格式不對（少了資料庫名稱）。"
    if not cfg:
        return False, "\n".join([
            "沒有設 SONNAP_DB_URL。少了它，資料會寫進另一個空的 SQLite 檔。",
            "  先在這個視窗設好再跑：",
            '    $env:SONNAP_DB_URL="mysql://root@localhost/sonnap"',
        ])
    try:
        import mysql.connector  # noqa: PLC0415  只有真的要連才需要
        conn = mysql.connector.connect(**cfg, connection_timeout=DB_TIMEOUT_SECONDS,
                                       use_pure=True)
        conn.close()
    except Exception as exc:  # noqa: BLE001  連不上的原因很多，一律當成連不上
        return False, "\n".join([
            f"{DB_TIMEOUT_SECONDS} 秒內連不上資料庫（{type(exc).__name__}）。",
            "  打開 XAMPP 控制台看 MySQL 有沒有開。Start 只按一次，等 15 秒；",
            "  起不來就不要連按——兩個資料庫程式同時啟動會把檔案越弄越壞。",
        ])
    return True, ""


# ═══════════════════════════════════════════════════════════════════
# ② 攝影機
# ═══════════════════════════════════════════════════════════════════

def recording_started(csv_path):
    """檔頭的開始時刻；舊檔沒有就退回檔名上的時刻。"""
    return read_started(csv_path) or datetime.strptime(csv_path.name[:15], "%Y%m%d_%H%M%S")


def recording_last_row(csv_path):
    """最後一列的時刻，**包含斷線標記列**。一列都沒有回 None。"""
    last = None
    with csv_path.open(encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#") or line.startswith("t,") or not line.strip():
                continue
            last = line
    if last is None:
        return None
    return datetime.fromisoformat(last.split(",", 1)[0])


def recording_minutes(csv_path):
    last = recording_last_row(csv_path)
    if last is None:
        return 0.0
    return (last - recording_started(csv_path)).total_seconds() / 60


def last_night_recording(metrics_dir, now):
    """
    回 (那一晚的起床日, 要匯入的那份, 同一晚被略過的其他份)。找不到回 (None, None, [])。

    「昨晚」= 起床日是今天或昨天的最新一晚（沿用 adherence.night_date 的約定）。
    再早的就不算：那代表昨晚沒錄，不該把前幾天的拿出來重匯。

    同一晚可能不只一份（開錄失敗重開、斷線後重開），挑**錄得最久**的那份。
    09-14 就有一份 10 秒的誤開檔排在正式那份前面。
    """
    wake_today = adherence.night_date(now)
    wanted = {wake_today, wake_today - timedelta(days=1)}
    by_night = {}
    for path in migrate_camera_to_db.nights(metrics_dir, None):
        night = adherence.night_date(recording_started(path))
        if night in wanted:
            by_night.setdefault(night, []).append(path)
    if not by_night:
        return None, None, []
    night = max(by_night)
    ranked = sorted(by_night[night], key=recording_minutes, reverse=True)
    return night, ranked[0], ranked[1:]


@dataclass
class CameraVerdict:
    ok: bool
    reason: str
    recorded_minutes: float = 0.0
    time_in_bed_minutes: float = 0.0


def check_camera(csv_path, analyse=onset.analyse):
    # ⚠️ 用真的時鐘，不用呼叫端給的 now：「還在寫入嗎」問的是這一刻的檔案，
    #    跟要匯入哪一天無關。
    age = time.time() - csv_path.stat().st_mtime
    if age < RECORDING_ACTIVE_SECONDS:
        return CameraVerdict(False, f"{csv_path.name} {age:.0f} 秒前還在寫入——"
                                    "錄影還開著嗎？先在錄影視窗按 Ctrl+C。")

    result = analyse(csv_path)
    if result.get("error"):
        return CameraVerdict(False, f"{csv_path.name} 讀不出資料（{result['error']}）。")

    tib = result["time_in_bed_minutes"] or 0.0
    recorded = recording_minutes(csv_path)
    if tib < migrate_camera_to_db.MIN_NIGHT_MINUTES:
        return CameraVerdict(False, f"{csv_path.name} 的臥床時間只有 {tib:.0f} 分鐘，"
                                    f"不到 {migrate_camera_to_db.MIN_NIGHT_MINUTES} 分鐘不算一晚。",
                             recorded, tib)
    if recorded > 0 and tib / recorded < MIN_BED_COVERAGE:
        return CameraVerdict(False, f"{csv_path.name} 錄了 {recorded:.0f} 分鐘，臥床時間卻只算出 "
                                    f"{tib:.0f} 分鐘（{tib / recorded:.0%}）——"
                                    "多半是半夜斷線、後段沒有資料，寫進去會是一個偏短的臥床時間。",
                             recorded, tib)
    return CameraVerdict(True, "", recorded, tib)


# ═══════════════════════════════════════════════════════════════════
# ③ 手錶
# ═══════════════════════════════════════════════════════════════════

def load_final_scores(path):
    """{起床日: final_score}。檔案還不存在（第一次跑）回空 dict。"""
    if not path.exists():
        return {}
    return {row["date"]: row.get("final_score")
            for row in json.loads(path.read_text(encoding="utf-8"))}


def compare_nights(before, after):
    """回 (不見的, 新增的, 分數變了的)。「不見的」不是空的就要停。"""
    missing = sorted(set(before) - set(after))
    added = sorted(set(after) - set(before))
    rescored = sorted(d for d in set(before) & set(after) if before[d] != after[d])
    return missing, added, rescored


def make_backup(paths, stamp):
    dest = paths.backup_root / stamp
    shutil.copytree(paths.garmin_data, dest / "garmin_data")
    if paths.payload.exists():
        shutil.copy2(paths.payload, dest / "app_payload.json")
    return dest


def restore_backup(paths, backup):
    shutil.copytree(backup / "garmin_data", paths.garmin_data, dirs_exist_ok=True)
    if (backup / "app_payload.json").exists():
        shutil.copy2(backup / "app_payload.json", paths.payload)


def prune_backups(backup_root, keep=KEEP_BACKUPS):
    """只刪這支自己建的（名稱是時間戳記的）資料夾。"""
    if not backup_root.exists():
        return
    stamps = sorted(p for p in backup_root.iterdir()
                    if p.is_dir() and BACKUP_STAMP.match(p.name))
    for old in stamps[:-keep]:
        shutil.rmtree(old)


# ═══════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════

def run_script(argv, root, env):
    """跑一支專案裡的 Python 腳本，回傳 exit code。輸出直接印在畫面上。"""
    print(f"\n$ python {' '.join(argv)}", flush=True)
    return subprocess.run([sys.executable, *argv], cwd=str(root), env=env).returncode


def section(title):
    print(f"\n{'═' * 70}\n{title}\n{'═' * 70}", flush=True)


def run(args, paths, now, env, runner=None, db_check=check_database, analyse=onset.analyse):
    """回傳 exit code。runner(argv) → exit code，測試會換掉它。"""
    child_env = {**env, "PYTHONIOENCODING": "utf-8"}
    if runner is None:
        def runner(argv):
            return run_script(argv, paths.root, child_env)

    try:
        return _run(args, paths, now, runner, db_check, env, analyse)
    except Stop as exc:
        print(f"\n✗ 停下來了：{exc}")
        return 1


def _run(args, paths, now, runner, db_check, env, analyse):
    section("① 資料庫")
    ok, message = db_check(env)
    if not ok:
        raise Stop(f"{message}\n  資料庫一筆都沒寫，檔案也都沒動。")
    print("✓ 連得上")

    section("② 昨晚的錄影")
    camera_csv = None
    if args.skip_camera:
        print("● --skip-camera：這次不匯入攝影機")
    else:
        if args.camera_csv:
            camera_csv = Path(args.camera_csv)
            skipped = []
        else:
            _night, camera_csv, skipped = last_night_recording(paths.metrics_dir, now)
            if camera_csv is None:
                print("● 找不到昨晚的錄影（起床日是今天或昨天的），這次不匯入攝影機")
        if camera_csv is not None:
            verdict = check_camera(camera_csv, analyse)
            if not verdict.ok:
                raise Stop("\n".join([
                    verdict.reason,
                    "  資料庫一筆都沒寫，手錶資料也還沒抓。",
                    "  → 這晚的攝影機不要了、只匯手錶：加 --skip-camera 重跑",
                    "  → 要匯入另一份錄影：加 --camera-csv <路徑> 重跑",
                ]))
            print(f"✓ {camera_csv.name}：錄了 {verdict.recorded_minutes:.0f} 分鐘，"
                  f"臥床 {verdict.time_in_bed_minutes:.0f} 分鐘")
            for other in skipped:
                print(f"  （同一晚另有 {other.name}，錄得較短，不匯入）")

    section("③ 手錶：抓資料、評分、檢查晚數")
    before = load_final_scores(paths.final_json)
    backup = make_backup(paths, now.strftime("%Y%m%d_%H%M%S"))
    print(f"● 備份 {backup}")

    def fail_and_restore(reason):
        restore_backup(paths, backup)
        return Stop(f"{reason}\n  已經把手錶資料還原成跑之前的樣子，資料庫一筆都沒寫。\n"
                    f"  備份在 {backup}")

    # ⚠️ 一定要給完整區間。只給 --days（或不給）會把整份歷史換成最近幾天。
    fetch = ["garmin/garmin_connect_fetch.py",
             "--start-date", FETCH_START, "--end-date", now.date().isoformat()]
    print(f"● 從 {FETCH_START} 抓到今天，要連 Garmin 伺服器，會跑幾分鐘")
    if runner(fetch) != 0:
        raise fail_and_restore("抓手錶資料失敗（上面有錯誤訊息）。")
    if runner(["garmin/run_pipeline.py"]) != 0:
        raise fail_and_restore("評分 pipeline 失敗（上面有錯誤訊息）。")

    after = load_final_scores(paths.final_json)
    missing, added, rescored = compare_nights(before, after)
    if missing:
        shown = "、".join(missing[:10]) + ("…" if len(missing) > 10 else "")
        raise fail_and_restore(f"原本有的 {len(missing)} 晚不見了：{shown}。"
                               "多半是抓資料的日期範圍不完整。")
    print(f"\n✓ 手錶：{len(before)} 晚 → {len(after)} 晚，原本的夜晚都還在")
    if added:
        print(f"  新增：{'、'.join(added)}")
    else:
        print("  ⚠ 沒有新的夜晚——手錶同步到 Garmin Connect 了嗎？（不擋，照樣寫入）")
    if rescored:
        print(f"  ⚠ 這幾晚的分數和上次不同：{'、'.join(rescored[:10])}"
              + ("…" if len(rescored) > 10 else ""))
        print("    Garmin 有時會事後修正最近一兩晚的資料，那是正常的；"
              "舊的夜晚也在變就要查。（不擋）")

    section("④ 寫入")
    if runner(["migrate_garmin_to_db.py"]) != 0:
        raise Stop("手錶資料寫入資料庫失敗（上面有錯誤訊息）。攝影機、夢境都還沒跑。\n"
                   "  修好之後整支重跑就好，兩支匯入腳本都可以重複執行。")
    if camera_csv is not None:
        if runner(["migrate_camera_to_db.py", "--csv", str(camera_csv)]) != 0:
            raise Stop("攝影機寫入資料庫失敗（上面有錯誤訊息）。手錶那份已經寫進去了。\n"
                       "  修好之後整支重跑就好。")
    if args.no_ai:
        print("\n● --no-ai：這次不補夢境")
    elif runner(["ai/generate_advice.py"]) != 0:
        # 比照 run_pipeline.py：LLM 掛掉不該讓已經算好、寫好的資料作廢
        print("  ⚠ 夢境生成失敗，其餘不受影響。之後可以單獨跑 ai/generate_advice.py 補")
    if runner(["build_app_payload.py"]) != 0:
        raise Stop("重建 App 資料檔失敗（上面有錯誤訊息）。資料庫那邊已經寫好了。")

    prune_backups(paths.backup_root)
    section("✓ 完成")
    print("  打開手機的 Sonnap App：它會自己上傳昨晚放下手機的時間，")
    print("  Insights 頁不應該出現「Backend unreachable」。")
    return 0


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="每天早上：手錶與攝影機 → 資料庫（有檢查、沒過就停）")
    ap.add_argument("--skip-camera", action="store_true", help="不匯入攝影機")
    ap.add_argument("--camera-csv", help="指定要匯入的錄影 CSV（預設挑昨晚最長的那份）")
    ap.add_argument("--no-ai", action="store_true", help="不補夢境（夢境要花 Claude API 額度）")
    ap.add_argument("--backup-dir", type=Path,
                    default=ROOT.parent / "sonnap-data" / "morning-backups",
                    help="手錶資料的備份放哪（預設在專案外面的 sonnap-data）")
    return ap.parse_args(argv)


def main():
    args = parse_args()
    paths = Paths(root=ROOT, backup_root=args.backup_dir)
    sys.exit(run(args, paths, datetime.now(), dict(os.environ)))


if __name__ == "__main__":
    main()
