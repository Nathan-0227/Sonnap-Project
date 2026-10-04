"""
garmin/migrate_daily_series_tz.py — 一次性：把既有原始檔裡「每日心率／壓力」的時刻修正 8 小時

    python garmin/migrate_daily_series_tz.py            # 轉換（先備份）
    python garmin/migrate_daily_series_tz.py --dry-run  # 只印報告，不寫檔

═══════════════════════════════════════════════════════════════════
錯在哪（2026-10-03 發現）
═══════════════════════════════════════════════════════════════════
`garmin_connect_fetch._iso_from_epoch_ms` 把 UTC 的鐘面時間直接貼上 `+08:00`，
沒有真的換算。睡眠那幾段另外過了一次 `gmt_to_local_iso`（把鐘面當 UTC 再加
8 小時）所以是對的；**每日心率與壓力沒有過那一步，整批早了 8 小時**。

證據：心率有兩個來源（睡眠 API 的 sleepHeartRate、每日心率 API），同一個
真實時刻應該是同一個值。實測睡眠時段裡同一時刻有兩個值的 8312 個時刻，
往前 8 小時找得到一模一樣的值的佔 99.7%；對照組（6／7／9 小時）是 6.5~7.6%。

後果：`avg_heart_rate`（Tier3 ±2）、`presleep_stress_score`（Tier3 壓力修正）
用到的是錯位的時段。基礎分數（時長／WASO／深睡／REM）不受影響。

═══════════════════════════════════════════════════════════════════
為什麼是轉換而不是重抓
═══════════════════════════════════════════════════════════════════
Garmin 會把約 4 個月前的日子的細節收掉（見 merge_standard_data.py 檔頭），
重抓拿到的是殘缺的版本。能修的只有檔案裡現有的紀錄。

═══════════════════════════════════════════════════════════════════
怎麼分辨兩個心率來源（紀錄本身沒有標）
═══════════════════════════════════════════════════════════════════
睡眠來源的 S(t) 是真實時刻 t 的值；每日來源的 D(t) 其實是真實時刻 t+8h 的值。
所以 **S(t) == D(t−8h)**。由早到晚處理，處理到 t 時 D(t−8h) 已經定案：

  同一時刻有兩個值 → 與 D(t−8h) 相同（都不同就取較接近）的那個是睡眠來源。
                    D(t−8h) 不存在時（每日來源那個時刻沒有讀數），取與
                    前一筆睡眠心率 S(t−2分) 較接近的那個——心率是連續的，
                    而另一個值來自 8 小時後，通常差很多
  只有一個值       → 預設是每日來源。例外：它落在睡眠區間內，而且連同前後
                    共 RUN 個時刻都與 8 小時前的每日值相同 → 睡眠來源
                    （單獨一筆相同可能是巧合，實測巧合率約 7%；連續 3 筆不是）

轉換後：每日來源全部 +8 小時；睡眠來源只留每日來源沒涵蓋到的時刻（去重）。

⚠️ 轉過的檔案標頭會有 `"daily_series_tz": "local"`。有這個標記就不再轉——
   再轉一次會變成晚 8 小時，而且不會有任何錯誤訊息。
"""
import argparse
import json
import shutil
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

import merge_standard_data as merge

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

DATA_FILE = Path(__file__).parent / "data" / "garmin_standard_data.json"
BACKUP_DIR = Path(__file__).resolve().parent.parent.parent / "sonnap-data" / "garmin-earliest-full"

# 標頭裡的標記。fetch 寫新檔時也會寫（build_standard_payload），
# 合併前會檢查既有檔案有沒有——沒有就代表還是錯位的，不能把對的併進去。
TZ_MARKER_KEY = "daily_series_tz"
TZ_MARKER_VALUE = "local"

SHIFT = timedelta(hours=8)
STEP = timedelta(minutes=2)      # 心率的取樣間隔
RUN = 3                          # 連續幾個時刻都相同才算「不是巧合」

Record = Dict[str, Any]


def _ts(record: Record) -> datetime:
    return datetime.fromisoformat(record["timestamp"])


def convert(records: Sequence[Record]) -> Tuple[List[Record], Dict[str, int]]:
    """回傳（轉換後的紀錄, 報告）。純函式，不看也不寫標記。"""
    intervals = merge.sleep_intervals(records)

    def asleep(t: datetime) -> bool:
        return any(start <= t <= wake for start, wake in intervals)

    values: Dict[datetime, List[Any]] = defaultdict(list)
    units: Dict[datetime, str] = {}
    for r in records:
        if r["metric"] == "heart_rate":
            values[_ts(r)].append(r["value"])
            units[_ts(r)] = r.get("unit", "bpm")

    daily: Dict[datetime, List[Any]] = {}      # 標籤時刻 → 每日來源的值
    sleep: Dict[datetime, Any] = {}            # 真實時刻 → 睡眠來源的值
    closest = by_neighbour = unresolved = 0
    for t in sorted(values):
        vals = list(values[t])
        twin = daily.get(t - SHIFT)            # D(t−8h)，已定案
        if len(vals) >= 2:
            if twin:
                target = twin[0]
                if target not in vals:
                    closest += 1
            elif t - STEP in sleep:
                target = sleep[t - STEP]
                by_neighbour += 1
            else:
                target = None                  # 分不出來：兩個都當每日來源，回報筆數
                unresolved += 1
            if target is not None:
                pick = min(vals, key=lambda v: abs(v - target))
                sleep[t] = pick
                vals.remove(pick)
        daily[t] = vals

    # 只有一個值、卻其實是睡眠來源的（那個時刻每日來源剛好沒有讀數）
    def matches(t: datetime) -> bool:
        twin = daily.get(t - SHIFT)
        return bool(twin) and len(values[t]) == 1 and values[t][0] == twin[0]

    reassigned = []
    for t in sorted(values):
        if len(values[t]) != 1 or not asleep(t) or not matches(t):
            continue
        run = 1
        for step in (-1, 1):
            u = t + step * STEP
            while u in values and matches(u):
                run += 1
                u += step * STEP
        if run >= RUN:
            reassigned.append(t)
    for t in reassigned:
        sleep[t] = values[t][0]
        daily[t] = []

    out = [r for r in records if r["metric"] not in ("heart_rate", "stress_score")]
    covered = set()
    n_daily = 0
    for t, vals in daily.items():
        for v in vals:
            out.append({"timestamp": (t + SHIFT).isoformat(), "metric": "heart_rate",
                        "value": v, "unit": units[t]})
            covered.add(t + SHIFT)
            n_daily += 1
    kept_sleep = 0
    for t, v in sleep.items():
        if t not in covered:
            out.append({"timestamp": t.isoformat(), "metric": "heart_rate", "value": v, "unit": units[t]})
            kept_sleep += 1
    n_stress = 0
    for r in records:
        if r["metric"] == "stress_score":
            out.append({**r, "timestamp": (_ts(r) + SHIFT).isoformat()})
            n_stress += 1

    out.sort(key=lambda r: r["timestamp"])
    return out, {
        "heart_rate_before": sum(len(v) for v in values.values()),
        "daily_shifted": n_daily,
        "sleep_source": len(sleep),
        "sleep_source_dropped_as_duplicate": len(sleep) - kept_sleep,
        "sleep_source_kept": kept_sleep,
        "picked_closest_not_equal": closest,
        "picked_by_previous_sleep_value": by_neighbour,
        "two_values_unresolved": unresolved,
        "single_value_reassigned_to_sleep": len(reassigned),
        "stress_shifted": n_stress,
        "untouched": len(records) - sum(len(v) for v in values.values()) - n_stress,
    }


def is_converted(payload: Dict[str, Any]) -> bool:
    return payload.get(TZ_MARKER_KEY) == TZ_MARKER_VALUE


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--file", type=Path, default=DATA_FILE)
    ap.add_argument("--backup-dir", type=Path, default=BACKUP_DIR)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    payload = json.loads(args.file.read_text(encoding="utf-8"))
    if is_converted(payload):
        print(f"Already converted ({TZ_MARKER_KEY}={TZ_MARKER_VALUE}); nothing to do.")
        return 0

    records, report = convert(payload["records"])
    for key, value in report.items():
        print(f"  {key}: {value}")
    if args.dry_run:
        print("--dry-run: file not written.")
        return 0

    args.backup_dir.mkdir(parents=True, exist_ok=True)
    backup = args.backup_dir / f"garmin_standard_data_before_tz_fix_{datetime.now():%Y%m%d_%H%M%S}.json"
    shutil.copy2(args.file, backup)
    print(f"Backup: {backup}")

    payload["records"] = records
    payload["total_records"] = len(records)
    payload[TZ_MARKER_KEY] = TZ_MARKER_VALUE
    tmp = args.file.with_name(args.file.name + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(args.file)
    print(f"Converted: {args.file} ({len(records)} records)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
