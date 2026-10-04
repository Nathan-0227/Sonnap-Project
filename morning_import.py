"""
morning_import.py — 每天早上一條指令：把昨晚的手錶與攝影機資料寫進資料庫。

    ① 資料庫連得上嗎                                   ← 沒過就停，什麼都沒動
    ② 昨晚的錄影：還在錄？太短？後半夜斷線？中間斷成好幾段？ ← 沒過就停，什麼都沒動
    ③ 手錶：備份 → 抓 Garmin（最近幾天，併進既有的）→ 評分 → 晚數檢查 ← 沒過就還原檔案再停
    ④ 全部過了才寫：手錶 → DB、攝影機 → DB、補夢境、重建 App 資料檔

═══════════════════════════════════════════════════════════════════
為什麼要包成一支
═══════════════════════════════════════════════════════════════════
早上那一串原本是九條要照順序打的指令，其中三個錯**不會報錯**：

1. **抓資料曾經是覆寫。** 少給日期範圍會把整份歷史換成最近一天，
   之後的評分、匯入全部照常成功。（2026-10-03 起 fetch 預設改成合併，
   這條路已經堵住；這裡的晚數檢查留著當第二道。）
2. **攝影機半夜斷線時，臥床時間會被算短，而且短得很合理。**
   09-13 那晚錄了 304 分鐘，後半段串流沒回來，算出 124 分鐘——
   剛好過了「不到 120 分鐘不算一晚」的門檻，會被當成正常的一晚寫進去。

3. **錄影中間斷掉時，連「錄了多久」都是假的。**
   09-20 那晚筆電在電池模式下進了待機（4 分鐘就會進），醒來繼續寫同一個檔案，
   所以首尾相減是 625 分鐘、實際只錄到 17.9 分鐘。更糟的是當時那條
   「臥床 ÷ 錄影時長」的擋法**完全失效**——分子分母都是首尾相減，
   中間的空洞在兩邊同時出現、互相抵銷，比率算出來是完美的 1.00。

三個都得靠人看數字才擋得住，而早上剛起床正是最不會仔細看的時候。

═══════════════════════════════════════════════════════════════════
停下來的規則
═══════════════════════════════════════════════════════════════════
| 檢查 | 什麼時候停 | 停下來時的狀態 |
|---|---|---|
| 資料庫 | 沒設 `SONNAP_DB_URL`，或 5 秒內連不上 | 什麼都還沒動 |
| 攝影機 | 還在錄、不到 120 分鐘、臥床 ÷ 錄影時長 < 0.8、最長連續片段 < 120 分鐘 | 什麼都還沒動（排在抓手錶**之前**） |
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
    --check-camera <路徑>  只檢查一份錄影的連續性就結束，不匯入任何東西
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "garmin"))

import db_backend                                   # noqa: E402
import merge_standard_data                          # noqa: E402
import migrate_camera_to_db                         # noqa: E402
import tapo_sleep_onset as onset                    # noqa: E402
from apply_recovery_modifier import WEARER_SEGMENTS  # noqa: E402
from behavior import adherence                      # noqa: E402
from tapo_metric_logger import read_started         # noqa: E402

# 還沒有任何手錶資料時，從第一個戴錶者分段的起日抓起。不另外寫一個日期：
# 分段表是唯一定義處，哪天往前補資料時兩邊才不會各說各話。
FETCH_START = WEARER_SEGMENTS[0][0]

# 已經有資料時只重抓最近這幾天，更早的原樣保留（2026-10-03）。
#
# 為什麼不再每次抓全部：Garmin 會把約 4 個月前的日子的細節收掉。10-02 那次
# 全區間重抓，05-28 ~ 05-31 從 4768 筆掉到 441 筆，10 個六月夜晚的分數跟著變。
# 為什麼不是只抓今天：最近幾天會晚到補齊——實測 09-08、09-12、09-29 都是
# 隔幾天重抓才完整（09-29：55 → 1578 筆）。
REFETCH_DAYS = 7

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

# 兩筆資料的間隔超過這麼多秒，就當成「中間斷掉了」。
#
# 校準（2026-10-04，tapo_metrics/ 裡全部的整夜錄影）：
#   正常錄影（約 4 幀/秒）         最大間隔 1.3 秒         ← 不能算斷
#   09-20（筆電進待機）            349 / 13369 / 22690 秒  ← 要算斷
# 60 秒比正常值大 46 倍、比最小的真空洞小 5.8 倍，兩邊都有餘裕。
#
# ⚠️ 這條只看**時間上有沒有列**，不管那些列裡有沒有可用資料。
#    「有列但全是空值」（串流斷掉但 logger 還活著，約 25 秒寫一列標記）
#    這條看不到——那是 MIN_BED_COVERAGE 在守。兩條各守一個失效模式：
#
#      筆電睡著 → 完全沒有列、時間上有空隙      → MAX_SAMPLE_GAP_SECONDS
#      串流斷掉 → 有列但沒資料、間隔 < 60 秒    → MIN_BED_COVERAGE
#
#    ⚠️ 缺一不可，不要以為新的那條涵蓋了舊的。實測既有的 09-13 測試案例
#       （可用 124 分 + 斷線 180 分）最長連續片段是 124 分鐘，**過得了**
#       這條，只有 MIN_BED_COVERAGE 擋得住。
#    ⚠️ 所以兩條的分工依賴 logger 的重試間隔。那個間隔若改成大於 60 秒，
#       串流斷線會變成這條看得到的空隙，分工就變了。
MAX_SAMPLE_GAP_SECONDS = 60

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
    def standard_json(self):
        return self.garmin_data / "garmin_standard_data.json"

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


@dataclass
class Continuity:
    """
    錄影在時間上的連續性。

    「片段」= 被超過 MAX_SAMPLE_GAP_SECONDS 的空隙隔開的一段資料。
    斷線標記列（每 10 分鐘一列）各自會成為一個長度 0 的片段，所以
    片段數會把它們算進去——那是刻意的，片段數本身就是在講「斷了幾次」。
    """
    segments: int = 1
    longest_minutes: float = 0.0
    covered_minutes: float = 0.0
    span_minutes: float = 0.0

    @property
    def coverage(self):
        """實際錄到的時間 ÷ 首尾橫跨的時間。沒有資料時回 1.0（交給別的檢查擋）。"""
        return self.covered_minutes / self.span_minutes if self.span_minutes > 0 else 1.0

    @property
    def intact(self):
        """一整段沒斷過。成功訊息只在**不是**這樣的時候才多印一行。"""
        return self.segments == 1 and self.coverage >= 0.999


def recording_continuity(csv_path):
    """
    這份錄影中間有沒有斷掉。

    ⚠️ 為什麼不能用首尾相減：09-20 那晚筆電進待機九小時又醒來繼續寫同一個
       檔案，首尾相減 625 分鐘、實際只錄到 17.9 分鐘。**首尾相減看不到中間的洞。**

    ⚠️ 讀的是**所有**列、包含斷線標記列（與 recording_last_row 一致）。
       判準是「時間上有沒有列」，不是「列裡有沒有資料」——後者是
       MIN_BED_COVERAGE 的工作，理由寫在那個常數上面。
    """
    times = []
    with csv_path.open(encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#") or line.startswith("t,") or not line.strip():
                continue
            times.append(datetime.fromisoformat(line.split(",", 1)[0]))
    if not times:
        return Continuity(segments=0)

    bounds = []
    start = prev = times[0]
    for t in times[1:]:
        if (t - prev).total_seconds() > MAX_SAMPLE_GAP_SECONDS:
            bounds.append((start, prev))
            start = t
        prev = t
    bounds.append((start, prev))

    lengths = [(b - a).total_seconds() for a, b in bounds]
    return Continuity(segments=len(bounds),
                      longest_minutes=max(lengths) / 60,
                      covered_minutes=sum(lengths) / 60,
                      span_minutes=(times[-1] - times[0]).total_seconds() / 60)


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
    continuity: Continuity = field(default_factory=Continuity)


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
    # ⚠️ 連續性在這裡就算好，不是等到要用它的那條規則才算。
    #    不然被前面的規則擋下的夜晚，verdict.continuity 會是一組全 0 的預設值，
    #    而 --check-camera 會把 18 個片段的檔案印成「1 片段、0 分鐘」——
    #    那正是這次要修的那種「看起來正常」的毛病。
    cont = recording_continuity(csv_path)
    if tib < migrate_camera_to_db.MIN_NIGHT_MINUTES:
        return CameraVerdict(False, f"{csv_path.name} 的臥床時間只有 {tib:.0f} 分鐘，"
                                    f"不到 {migrate_camera_to_db.MIN_NIGHT_MINUTES} 分鐘不算一晚。",
                             recorded, tib, cont)
    if recorded > 0 and tib / recorded < MIN_BED_COVERAGE:
        return CameraVerdict(False, f"{csv_path.name} 錄了 {recorded:.0f} 分鐘，臥床時間卻只算出 "
                                    f"{tib:.0f} 分鐘（{tib / recorded:.0%}）——"
                                    "多半是半夜斷線、後段沒有資料，寫進去會是一個偏短的臥床時間。",
                             recorded, tib, cont)
    # ⚠️ 這條**刻意排在最後**。短的夜晚（最長連續片段本來就 < 120）應該聽到
    #    「臥床時間只有 N 分鐘」那個說法，而不是被這條搶著說「中間斷掉」——
    #    一段 60 分鐘、完全沒斷的錄影不是斷線問題，是錄太短。
    #    排在最後之後，會走到這裡的只剩「首尾夠長、比率也正常，但中間有洞」
    #    那一種，也就是這條專門要擋的那一種。
    if cont.longest_minutes < migrate_camera_to_db.MIN_NIGHT_MINUTES:
        return CameraVerdict(False, "\n".join([
            f"{csv_path.name} 首尾橫跨 {cont.span_minutes:.0f} 分鐘，但中間斷成 "
            f"{cont.segments} 段，最長連續只錄到 {cont.longest_minutes:.0f} 分鐘"
            f"（涵蓋 {cont.coverage:.0%}）——不到 "
            f"{migrate_camera_to_db.MIN_NIGHT_MINUTES} 分鐘不算一晚。",
            "  最常見的原因是筆電沒插電（電池模式下 4 分鐘就會進待機），"
            "但熱點掉線也會這樣，兩個都查一下。",
        ]), recorded, tib, cont)
    return CameraVerdict(True, "", recorded, tib, cont)


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

def fetch_start(standard_json, today):
    """
    這次從哪一天抓起（ISO 日期字串）。

    最近 REFETCH_DAYS 天，或「檔案裡最晚的那一天」，取較早者。後者是為了
    停跑很久之後：只抓最近 7 天的話，中間那段會是永遠補不上的空洞，
    而且不會有任何錯誤訊息（晚數檢查只看「原本有的還在不在」）。
    """
    if not standard_json.exists():
        return FETCH_START
    try:
        records = json.loads(standard_json.read_text(encoding="utf-8"))["records"]
        last = merge_standard_data.last_record_day(
            records, merge_standard_data.parse_tz("+08:00"))
    except (ValueError, KeyError, TypeError) as exc:
        # 不退回「從頭抓」：fetch 那邊讀不出舊檔會直接停下（它不會覆寫），
        # 在這裡先講清楚比讓使用者看一段 traceback 好。
        raise Stop(f"讀不出既有的手錶資料檔 {standard_json}（{exc}）。\n"
                   "  先確認那個檔案，或從備份還原，再重跑。")
    if last is None:
        return FETCH_START
    return min(today - timedelta(days=REFETCH_DAYS), last).isoformat()


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
            # 完整的夜晚不多印一行；斷過的要講出來——09-20 的教訓是
            # 「看起來正常」最危險，而那一晚通過檢查時什麼異狀都沒顯示。
            if not verdict.continuity.intact:
                cont = verdict.continuity
                print(f"  ⚠ 中間斷成 {cont.segments} 段（實際錄到 "
                      f"{cont.covered_minutes:.0f} 分鐘、涵蓋 {cont.coverage:.0%}），"
                      f"最長連續 {cont.longest_minutes:.0f} 分鐘。"
                      "不擋，但這一晚不是完整的一段")
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

    # fetch 預設是合併：只換這次抓的日子，更早的原樣保留。
    # ⚠️ 不可以加 --replace，那會把整份歷史換成這幾天。
    start = fetch_start(paths.standard_json, now.date())
    fetch = ["garmin/garmin_connect_fetch.py",
             "--start-date", start, "--end-date", now.date().isoformat()]
    print(f"● 從 {start} 抓到今天（更早的日子不動），要連 Garmin 伺服器")
    if runner(fetch) != 0:
        raise fail_and_restore("抓手錶資料失敗（上面有錯誤訊息）。")
    if runner(["garmin/run_pipeline.py"]) != 0:
        raise fail_and_restore("評分 pipeline 失敗（上面有錯誤訊息）。")

    after = load_final_scores(paths.final_json)
    missing, added, rescored = compare_nights(before, after)
    if missing:
        shown = "、".join(missing[:10]) + ("…" if len(missing) > 10 else "")
        raise fail_and_restore(f"原本有的 {len(missing)} 晚不見了：{shown}。"
                               "抓資料是合併的，不該少夜晚——"
                               "看上面抓取那一段的輸出是不是有人加了 --replace。")
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


def report_camera(csv_path):
    """
    單獨檢查一份錄影並印出結果，不碰資料庫、不匯入任何東西。
    回 0 代表這份過得了早上匯入的檢查。

    存在的理由：同一段連續性檢查在 2026-10-03~04 被手寫了三次（查 09-20、
    查 09-21、回頭查 09-09/12/13）。手寫第三次就該變成工具。
    """
    path = Path(csv_path)
    if not path.exists():
        print(f"✗ 找不到 {path}")
        return 1
    verdict = check_camera(path)
    cont = verdict.continuity
    print(f"● {path.name}")
    print(f"  首尾橫跨   {cont.span_minutes:8.1f} 分鐘")
    print(f"  片段數     {cont.segments:8d}   （間隔超過 {MAX_SAMPLE_GAP_SECONDS} 秒算斷一次）")
    print(f"  最長連續   {cont.longest_minutes:8.1f} 分鐘   （門檻 "
          f"{migrate_camera_to_db.MIN_NIGHT_MINUTES} 分鐘）")
    print(f"  實際錄到   {cont.covered_minutes:8.1f} 分鐘   （涵蓋 {cont.coverage:.1%}）")
    print(f"  臥床時間   {verdict.time_in_bed_minutes:8.1f} 分鐘")
    if verdict.ok:
        print("  ✓ 過得了早上匯入的檢查")
        return 0
    print(f"  ✗ 擋下：{verdict.reason}")
    return 1


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="每天早上：手錶與攝影機 → 資料庫（有檢查、沒過就停）")
    ap.add_argument("--skip-camera", action="store_true", help="不匯入攝影機")
    ap.add_argument("--camera-csv", help="指定要匯入的錄影 CSV（預設挑昨晚最長的那份）")
    ap.add_argument("--no-ai", action="store_true", help="不補夢境（夢境要花 Claude API 額度）")
    ap.add_argument("--check-camera",
                    help="只檢查一份錄影的連續性就結束，不匯入任何東西")
    ap.add_argument("--backup-dir", type=Path,
                    default=ROOT.parent / "sonnap-data" / "morning-backups",
                    help="手錶資料的備份放哪（預設在專案外面的 sonnap-data）")
    return ap.parse_args(argv)


def main():
    args = parse_args()
    # ⚠️ 排在建 Paths 與連資料庫之前：只查一份檔案不需要那些東西，
    #    而且在主 clone 之外的目錄也要能用。
    if args.check_camera:
        sys.exit(report_camera(args.check_camera))
    paths = Paths(root=ROOT, backup_root=args.backup_dir)
    sys.exit(run(args, paths, datetime.now(), dict(os.environ)))


if __name__ == "__main__":
    main()
