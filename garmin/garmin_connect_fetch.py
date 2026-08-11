import argparse
import json
import os
from datetime import UTC, date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

# 【2026-08-11】生成的資料檔集中放在 garmin/data/，讓 garmin/ 目錄下只留程式碼。
# 用 Path(__file__).parent 而非相對路徑字串，這樣不管從哪個工作目錄執行都能正確定位。
DATA_DIR = Path(__file__).parent / "data"
ENV_FILE = Path(__file__).parent / ".env"


def _load_env_file(path: Path = ENV_FILE) -> None:
    """
    把 garmin/.env 裡的設定讀進環境變數。

    【2026-08-11 修正】先前 .env 檔案雖然存在，但程式完全沒有讀它——只有
    os.getenv() 去讀環境變數，導致使用者以為填了 .env 就能用，實際上還是得
    每次手動設環境變數或帶 --email/--password 參數。

    不用 python-dotenv 套件而是自己解析，理由是專案規範「優先用標準庫，
    非必要不加依賴」，而 .env 的格式很單純（KEY=VALUE 一行一個），
    自己讀十幾行就夠了，不值得為此多一個外部套件。

    已存在的環境變數優先（不覆蓋），這樣臨時想用別的帳號時，
    可以直接設環境變數蓋過 .env，不必去改檔案。
    """
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        # 跳過空行與註解行
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        # 去掉包住值的引號（有些人習慣寫 KEY="value"）
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        # setdefault 語意：已經有的環境變數不覆蓋
        if key and key not in os.environ:
            os.environ[key] = value


# 一定要在 parse_args() 之前執行——argparse 的 default 是用 os.getenv() 取值，
# 那些 default 在函式定義時就會被求值，太晚載入 .env 就來不及了。
_load_env_file()


def build_standard_payload(device_id: str, records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    把抓下來的原始 records 包成標準格式的 JSON，寫入 garmin_standard_data.json。
    下游的 analyze_garmin_sleep.py 就是讀這個檔案。

    records 會先依 timestamp 排序——下游 analyze 在配對「入睡→起床」時假設
    資料是按時間順序的，這裡先排好可以避免下游拿到亂序資料。

    【2026-08-11 搬移記錄】此函式原本放在 garmin_importer.py（讀手動匯出 CSV 的
    替代入口），由本檔案 import 過來使用。因該替代入口實際從未被使用
    （garmin_export/ 資料夾從未存在），已刪除該檔並將此函式搬移至此，
    消除跨檔依賴。同時修正 source 標籤：原本寫死為 "garmin_connect_manual_export"，
    導致 API 抓下來的資料被標記成「手動匯出」，與事實不符，現改為正確標示來源。
    """
    return {
        "device_id": device_id,
        "source": "garmin_connect_api",
        "date": datetime.now().strftime("%Y-%m-%d"),
        "total_records": len(records),
        "records": sorted(records, key=lambda x: x["timestamp"]),
    }


def gmt_to_local_iso(gmt_value, tz_hours=8):
    """
    Force Garmin GMT/UTC time to local ISO time.

    Important:
    Some previous code may have already appended +08:00 to a GMT time.
    So here we ignore any existing timezone label and treat the clock time as UTC.
    Example:
    2026-06-10T18:58:00+08:00
    -> treat as 2026-06-10 18:58 UTC
    -> output 2026-06-11T02:58:00+08:00
    """
    if not gmt_value:
        return None

    text = str(gmt_value).replace("Z", "")

    # Remove timezone suffix if it already exists
    if "+" in text:
        text = text.split("+")[0]
    elif len(text) > 19 and "-" in text[19:]:
        text = text[:19]

    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None

    # Force Garmin GMT time to UTC
    dt = dt.replace(tzinfo=timezone.utc)

    local_tz = timezone(timedelta(hours=tz_hours))
    return dt.astimezone(local_tz).isoformat()

    
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch Garmin Connect data and convert to Sonnap standard JSON."
    )
    parser.add_argument(
        "--email",
        default=os.getenv("GARMIN_EMAIL", ""),
        help="Garmin account email. Falls back to GARMIN_EMAIL env.",
    )
    parser.add_argument(
        "--password",
        default=os.getenv("GARMIN_PASSWORD", ""),
        help="Garmin account password. Falls back to GARMIN_PASSWORD env.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=1,
        help="How many recent days to fetch (including today).",
    )
    parser.add_argument(
        "--start-date",
        default="",
        help="Start date in YYYY-MM-DD. If provided with --end-date, overrides --days.",
    )
    parser.add_argument(
        "--end-date",
        default="",
        help="End date in YYYY-MM-DD. If provided with --start-date, overrides --days.",
    )
    parser.add_argument(
        "--device-id",
        default="garmin_vivoactive3_01",
        help="Device id written into standard output.",
    )
    parser.add_argument(
        "--output",
        default=str(DATA_DIR / "garmin_standard_data.json"),
        help="Output path for normalized records.",
    )
    parser.add_argument(
        "--tz",
        default="+08:00",
        help="Timezone suffix for epoch conversion (example: +08:00).",
    )
    parser.add_argument(
        "--keep-negative-stress",
        action="store_true",
        help="Keep Garmin negative stress values (-1/-2). Default is filtered out.",
    )
    parser.add_argument(
        "--raw-debug-output",
        default="",
        help="Optional path to write raw Garmin API responses for debugging.",
    )
    parser.add_argument(
        "--raw-debug-include-data",
        action="store_true",
        help="Include a small sanitized sample of raw API data in debug output.",
    )
    return parser.parse_args()


def _iso_from_epoch_ms(epoch_ms: Any, tz: str) -> Optional[str]:
    try:
        ms = int(epoch_ms)
    except (TypeError, ValueError):
        return None
    dt = datetime.fromtimestamp(ms / 1000.0, UTC)
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + tz


def _iso_from_garmin_str(value: Any, tz: str) -> Optional[str]:
    text = str(value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        return text
    # e.g. 2026-05-18T16:00:00.0
    clean = text
    if "." in clean:
        head, tail = clean.rsplit(".", 1)
        if tail.isdigit() and len(tail) <= 3:
            clean = head
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = datetime.strptime(clean, fmt)
            return dt.strftime("%Y-%m-%dT%H:%M:%S") + tz
        except ValueError:
            continue
    return None


def _iso_from_epoch_any(value: Any, tz: str) -> Optional[str]:
    """
    Accept epoch in ms or sec, int or numeric string, or Garmin datetime string.
    """
    if isinstance(value, str) and ("T" in value or "-" in value):
        parsed = _iso_from_garmin_str(value, tz)
        if parsed:
            return parsed
    try:
        num = int(value)
    except (TypeError, ValueError):
        return None
    # Garmin payloads may mix seconds and milliseconds.
    if num < 10_000_000_000:
        num *= 1000
    return _iso_from_epoch_ms(num, tz)


def _sleep_stage_from_activity_level(level: Any) -> Optional[str]:
    try:
        key = float(level)
    except (TypeError, ValueError):
        text = str(level).strip().lower()
        return {"deep": "deep", "light": "light", "rem": "rem", "awake": "awake"}.get(text)
    mapping = {0.0: "deep", 1.0: "light", 2.0: "rem", 3.0: "awake"}
    return mapping.get(key)


def _resolve_fetch_days(args: argparse.Namespace) -> List[date]:
    if args.start_date and args.end_date:
        try:
            start = datetime.strptime(args.start_date, "%Y-%m-%d").date()
            end = datetime.strptime(args.end_date, "%Y-%m-%d").date()
        except ValueError as exc:
            raise ValueError("Invalid date format. Use YYYY-MM-DD for --start-date and --end-date.") from exc
        if start > end:
            raise ValueError("--start-date must be earlier than or equal to --end-date.")
        span = (end - start).days
        return [start + timedelta(days=i) for i in range(span + 1)]

    today = date.today()
    days_to_fetch = max(1, args.days)
    return [today - timedelta(days=i) for i in range(days_to_fetch)]


def _safe_get(client: Any, names: Iterable[str], *args: Any) -> Any:
    for method_name in names:
        fn = getattr(client, method_name, None)
        if callable(fn):
            try:
                return fn(*args)
            except Exception:
                continue
    return None


def _safe_get_with_meta(client: Any, names: Iterable[str], *args: Any) -> Dict[str, Any]:
    attempts: List[Dict[str, str]] = []
    for method_name in names:
        fn = getattr(client, method_name, None)
        if callable(fn):
            try:
                data = fn(*args)
                return {
                    "ok": True,
                    "method": method_name,
                    "data": data,
                    "attempts": attempts,
                    "error": "",
                }
            except Exception as exc:
                attempts.append({"method": method_name, "error": str(exc)})
                continue
        else:
            attempts.append({"method": method_name, "error": "method_not_found"})
    return {
        "ok": False,
        "method": "",
        "data": None,
        "attempts": attempts,
        "error": "all_methods_failed_or_missing",
    }


def _add(records: List[Dict[str, Any]], timestamp: Optional[str], metric: str, value: Any, unit: str) -> None:
    if not timestamp:
        return
    records.append(
        {
            "timestamp": timestamp,
            "metric": metric,
            "value": value,
            "unit": unit,
        }
    )


def _parse_sleep_data(day_str: str, raw: Any, tz: str, records: List[Dict[str, Any]]) -> None:
    if not isinstance(raw, dict):
        return

    sleep_root = raw.get("dailySleepDTO", raw)
    if not isinstance(sleep_root, dict):
        sleep_root = raw

    sleep_start = _iso_from_epoch_any(
        sleep_root.get("sleepStartTimestampGMT", sleep_root.get("startTimestampGMT")),
        tz,
    )
    sleep_end = _iso_from_epoch_any(
        sleep_root.get("sleepEndTimestampGMT", sleep_root.get("endTimestampGMT")),
        tz,
    )
    sleep_start_local = gmt_to_local_iso(sleep_start, 8)
    sleep_end_local = gmt_to_local_iso(sleep_end, 8)
    _add(records, sleep_start_local, "sleep_start_time", sleep_start_local, "datetime")
    _add(records, sleep_end_local, "wake_time", sleep_end_local, "datetime")

    stage_map = {
        "remSleepSeconds": "rem",
        "deepSleepSeconds": "deep",
        "lightSleepSeconds": "light",
        "awakeSleepSeconds": "awake",
    }
    for key, stage_name in stage_map.items():
        duration = sleep_root.get(key)
        if duration is not None:
            base_ts = sleep_start_local or f"{day_str}T00:00:00{tz}"
            _add(records, base_ts, "sleep_stage", stage_name, "stage")
            _add(records, base_ts, f"{stage_name}_duration_sec", int(duration), "sec")
    

    sleep_levels = raw.get("sleepLevelsMap")
    if isinstance(sleep_levels, dict):
        for level in ("awake", "light", "deep", "rem"):
            level_data = sleep_levels.get(level, [])
            if not isinstance(level_data, list):
                continue
            for item in level_data:
                if not isinstance(item, dict):
                    continue
                
                ts = gmt_to_local_iso(_iso_from_epoch_any(item.get("startTimeGMT"), tz), 8)
                end_ts = gmt_to_local_iso(_iso_from_epoch_any(item.get("endTimeGMT"), tz), 8)
                
                _add(records, ts, "sleep_stage", level, "stage")
                _add(records, ts, "sleep_segment_start", ts, "datetime")
                _add(records, end_ts, "sleep_segment_end", end_ts, "datetime")

    # Vivoactive 形狀：sleepLevels 是一個清單，每筆用數字 activityLevel 表示睡眠階段
    # (0=deep 深睡, 1=light 淺睡, 2=rem, 3=awake 清醒)
    if isinstance(raw.get("sleepLevels"), list):
        # 逐筆走訪清單裡的每一個睡眠時間段
        for item in raw.get("sleepLevels", []):
            # 不是 dict 的雜訊資料直接跳過
            if not isinstance(item, dict):
                continue

            # 把數字 activityLevel 轉成文字階段名稱 (deep/light/rem/awake)
            level = _sleep_stage_from_activity_level(
                item.get("activityLevel", item.get("sleepLevel", item.get("level")))
            )

            # --- 以下這整段必須在 for 迴圈「裡面」，才能逐筆處理每個時間段 ---
            # (原本的 bug：這段被縮排到迴圈外，導致 (a) 清單為空時 item 未定義而崩潰，
            #  (b) 有資料時也只處理最後一筆，其餘時間段全被丟掉)

            # 取這個時間段的「開始時間」：先試 Garmin 字串格式，失敗再試 epoch 數字格式
            ts_raw = _iso_from_garmin_str(item.get("startGMT", item.get("startTimeGMT")), tz)
            if ts_raw is None:
                ts_raw = _iso_from_epoch_any(item.get("startGMT", item.get("startTimeGMT")), tz)

            # 取這個時間段的「結束時間」：同樣先字串後 epoch
            end_ts_raw = _iso_from_garmin_str(item.get("endGMT", item.get("endTimeGMT")), tz)
            if end_ts_raw is None:
                end_ts_raw = _iso_from_epoch_any(item.get("endGMT", item.get("endTimeGMT")), tz)

            # 把 GMT 時間轉成本地時間 (+8 小時)
            ts = gmt_to_local_iso(ts_raw, 8)
            end_ts = gmt_to_local_iso(end_ts_raw, 8)

            # 寫入三筆記錄：睡眠階段、時間段起點、時間段終點
            if level:
                _add(records, ts, "sleep_stage", level, "stage")
            _add(records, ts, "sleep_segment_start", ts, "datetime")
            _add(records, end_ts, "sleep_segment_end", end_ts, "datetime")

    if isinstance(raw.get("sleepHeartRate"), list):
        for item in raw["sleepHeartRate"]:
            if not isinstance(item, dict):
                continue
            ts = gmt_to_local_iso(_iso_from_epoch_any(item.get("startGMT"), tz), 8)
            value = item.get("value")
            if value is not None:
                try:
                    _add(records, ts, "heart_rate", int(value), "bpm")
                except (TypeError, ValueError):
                    pass

    if isinstance(raw.get("sleepMovement"), list):
        for item in raw["sleepMovement"]:
            if not isinstance(item, dict):
                continue
            ts = gmt_to_local_iso(_iso_from_garmin_str(item.get("startGMT"), tz), 8)
            level = item.get("activityLevel")
            if level is not None:
                try:
                    _add(records, ts, "movement", float(level), "arb")
                except (TypeError, ValueError):
                    pass

    resting_hr = raw.get("restingHeartRate")
    if resting_hr is not None and sleep_start_local:
        try:
            _add(records, sleep_start_local, "resting_heart_rate", int(resting_hr), "bpm")
        except (TypeError, ValueError):
            pass


def _parse_heart_rate_data(raw: Any, tz: str, records: List[Dict[str, Any]]) -> None:
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, dict):
                ts = _iso_from_epoch_ms(
                    item.get("timeInSeconds", 0) * 1000 if item.get("timeInSeconds") else item.get("timestamp"),
                    tz,
                )
                value = item.get("value") if "value" in item else item.get("heartRate")
                if value is not None:
                    try:
                        _add(records, ts, "heart_rate", int(value), "bpm")
                    except (TypeError, ValueError):
                        continue
    elif isinstance(raw, dict):
        hr_values = raw.get("heartRateValues")
        if isinstance(hr_values, dict):
            for epoch_ms, value in hr_values.items():
                ts = _iso_from_epoch_any(epoch_ms, tz)
                try:
                    parsed = int(value)
                    if parsed <= 0:
                        continue
                    _add(records, ts, "heart_rate", parsed, "bpm")
                except (TypeError, ValueError):
                    continue
        elif isinstance(hr_values, list) and hr_values:
            if isinstance(hr_values[0], (list, tuple)):
                for row in hr_values:
                    if len(row) < 2:
                        continue
                    ts = _iso_from_epoch_any(row[0], tz)
                    try:
                        parsed = int(row[1])
                        if parsed <= 0:
                            continue
                        _add(records, ts, "heart_rate", parsed, "bpm")
                    except (TypeError, ValueError):
                        continue
            elif isinstance(hr_values[0], dict):
                for row in hr_values:
                    ts = _iso_from_epoch_any(row.get("timestamp", row.get("startGMT")), tz)
                    value = row.get("value", row.get("heartRate"))
                    if value is not None:
                        try:
                            _add(records, ts, "heart_rate", int(value), "bpm")
                        except (TypeError, ValueError):
                            continue
            else:
                start_ts = _iso_from_garmin_str(raw.get("startTimestampGMT"), tz)
                if not start_ts:
                    start_ts = _iso_from_epoch_any(raw.get("startTimestampGMT"), tz)
                if start_ts:
                    base = datetime.strptime(start_ts[:-6], "%Y-%m-%dT%H:%M:%S")
                    for idx, value in enumerate(hr_values):
                        try:
                            parsed = int(value)
                        except (TypeError, ValueError):
                            continue
                        if parsed <= 0:
                            continue
                        ts = (base + timedelta(minutes=idx)).strftime("%Y-%m-%dT%H:%M:%S") + tz
                        _add(records, ts, "heart_rate", parsed, "bpm")


def _parse_stress_data(raw: Any, tz: str, records: List[Dict[str, Any]], keep_negative_stress: bool) -> None:
    if isinstance(raw, list):
        for item in raw:
            if not isinstance(item, dict):
                continue
            ts = _iso_from_epoch_ms(item.get("timestamp"), tz)
            value = item.get("value", item.get("stressLevel"))
            if value is not None:
                try:
                    parsed = int(value)
                    if parsed < 0 and not keep_negative_stress:
                        continue
                    _add(records, ts, "stress_score", parsed, "score")
                except (TypeError, ValueError):
                    continue
    elif isinstance(raw, dict):
        stress_map = raw.get("stressValuesArray")
        if isinstance(stress_map, list):
            for row in stress_map:
                if isinstance(row, list) and len(row) >= 2:
                    ts = _iso_from_epoch_ms(row[0], tz)
                    try:
                        parsed = int(row[1])
                        if parsed < 0 and not keep_negative_stress:
                            continue
                        _add(records, ts, "stress_score", parsed, "score")
                    except (TypeError, ValueError):
                        continue


def _parse_steps_data(day_str: str, raw: Any, tz: str, records: List[Dict[str, Any]]) -> None:
    if isinstance(raw, dict):
        daily_steps = raw.get("totalSteps")
        if daily_steps is not None:
            _add(records, f"{day_str}T23:59:00{tz}", "steps", int(daily_steps), "count")

        timeline = raw.get("allDaySteps")
        if isinstance(timeline, list):
            for item in timeline:
                if not isinstance(item, dict):
                    continue
                ts = _iso_from_epoch_ms(item.get("epoch"), tz)
                value = item.get("steps")
                if value is not None:
                    try:
                        _add(records, ts, "steps", int(value), "count")
                    except (TypeError, ValueError):
                        continue
    elif isinstance(raw, list) and raw and isinstance(raw[0], dict):
        for item in raw:
            if not isinstance(item, dict):
                continue
            ts = _iso_from_garmin_str(item.get("startGMT"), tz)
            steps_val = item.get("steps")
            if steps_val is None:
                continue
            try:
                _add(records, ts, "steps", int(steps_val), "count")
            except (TypeError, ValueError):
                continue
    elif isinstance(raw, list):
        # Legacy shape: plain integer bins per 15 minutes.
        day_start = datetime.strptime(day_str, "%Y-%m-%d")
        interval_minutes = 15
        if len(raw) > 0 and len(raw) <= 48:
            interval_minutes = 30
        for idx, value in enumerate(raw):
            try:
                parsed = int(value)
            except (TypeError, ValueError):
                continue
            ts = (day_start + timedelta(minutes=idx * interval_minutes)).strftime("%Y-%m-%dT%H:%M:%S") + tz
            _add(records, ts, "steps", parsed, "count")


def _parse_daily_steps(day_str: str, raw: Any, tz: str, records: List[Dict[str, Any]]) -> None:
    """
    從 get_daily_steps 取「官方每日總步數」，與 Garmin App 主畫面顯示一致。
    回傳形狀：[{"calendarDate":"2026-06-11","totalSteps":195,"stepGoal":3860,...}]
    時間戳設在該日中午（避開睡眠區間），這樣在 analyze 會被歸到正確的日曆日。
    """
    items = raw if isinstance(raw, list) else [raw]
    for item in items:
        if not isinstance(item, dict):
            continue
        cal = item.get("calendarDate", day_str)
        ts = f"{cal}T15:00:00{tz}"
        total = item.get("totalSteps")
        if total is not None:
            try:
                _add(records, ts, "daily_steps", int(total), "count")
            except (TypeError, ValueError):
                pass
        goal = item.get("stepGoal")
        if goal is not None:
            try:
                _add(records, ts, "step_goal", int(goal), "count")
            except (TypeError, ValueError):
                pass


def _inject_movement_proxy(records: List[Dict[str, Any]]) -> None:
    # If no explicit movement metric from Garmin, use awake segments as coarse movement proxy.
    has_movement = any(r.get("metric") == "movement" for r in records)
    if has_movement:
        return
    for row in records:
        if row.get("metric") == "sleep_stage" and row.get("value") == "awake":
            records.append(
                {
                    "timestamp": row["timestamp"],
                    "metric": "movement",
                    "value": 1.0,
                    "unit": "proxy",
                }
            )


def _classify_data_shape(data: Any) -> str:
    if data is None:
        return "none"
    if isinstance(data, list):
        return f"list[{len(data)}]"
    if isinstance(data, dict):
        keys = sorted(list(data.keys()))[:8]
        return f"dict(keys={keys})"
    return type(data).__name__


def _sample_data(data: Any) -> Any:
    if isinstance(data, dict):
        out: Dict[str, Any] = {}
        for k in list(data.keys())[:8]:
            v = data[k]
            if isinstance(v, list):
                out[k] = {"type": "list", "len": len(v), "sample": v[:3]}
            elif isinstance(v, dict):
                keys = list(v.keys())[:8]
                small = {kk: v[kk] for kk in keys}
                out[k] = {"type": "dict", "len": len(v), "sample": small}
            else:
                out[k] = v
        return out
    if isinstance(data, list):
        return {"type": "list", "len": len(data), "sample": data[:5]}
    return data


def _debug_log(run_id: str, hypothesis_id: str, location: str, message: str, data: Dict[str, Any]) -> None:
    payload = {
        "sessionId": "54141a",
        "runId": run_id,
        "hypothesisId": hypothesis_id,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": int(datetime.now(UTC).timestamp() * 1000),
    }
    with open("debug-54141a.log", "a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def main() -> None:
    args = parse_args()
    # region agent log
    _debug_log(
        run_id="pre-fix",
        hypothesis_id="H1",
        location="garmin_connect_fetch.py:main:startup",
        message="Script startup context",
        data={
            "cwd": os.getcwd(),
            "script_exists": os.path.exists("garmin_connect_fetch.py"),
            "start_date": args.start_date,
            "end_date": args.end_date,
            "days": args.days,
        },
    )
    # endregion
    if not args.email or not args.password:
        # region agent log
        _debug_log(
            run_id="pre-fix",
            hypothesis_id="H4",
            location="garmin_connect_fetch.py:main:credentials",
            message="Credential presence check",
            data={
                "has_email": bool(args.email),
                "has_password": bool(args.password),
            },
        )
        # endregion
        raise ValueError("Missing credentials. Provide --email/--password or GARMIN_EMAIL/GARMIN_PASSWORD.")

    try:
        from garminconnect import Garmin
    except ImportError as exc:
        raise ImportError("garminconnect not installed. Run: pip install garminconnect") from exc

    client = Garmin(args.email, args.password)
    client.login()
    # region agent log
    _debug_log(
        run_id="pre-fix",
        hypothesis_id="H3",
        location="garmin_connect_fetch.py:main:login",
        message="Garmin login successful",
        data={"login": "ok"},
    )
    # endregion

    records: List[Dict[str, Any]] = []
    debug_rows: List[Dict[str, Any]] = []
    fetched_days = _resolve_fetch_days(args)

    for day in sorted(fetched_days):
        day_str = day.isoformat()
        sleep_result = _safe_get_with_meta(client, ["get_sleep_data"], day_str)
        heart_rate_result = _safe_get_with_meta(
            client,
            ["get_heart_rates", "get_heart_rate", "get_heart_rates_for_day"],
            day_str,
        )
        stress_result = _safe_get_with_meta(client, ["get_stress_data", "get_stress"], day_str)
        # 改用官方每日步數 get_daily_steps(start, end)，與 Garmin App 顯示一致
        steps_result = _safe_get_with_meta(client, ["get_daily_steps"], day_str, day_str)

        sleep_data = sleep_result["data"]
        heart_rate_data = heart_rate_result["data"]
        stress_data = stress_result["data"]
        steps_data = steps_result["data"]

        before = len(records)
        _parse_sleep_data(day_str, sleep_data, args.tz, records)
        sleep_count = len(records) - before

        before = len(records)
        _parse_heart_rate_data(heart_rate_data, args.tz, records)
        hr_count = len(records) - before

        before = len(records)
        _parse_stress_data(stress_data, args.tz, records, args.keep_negative_stress)
        stress_count = len(records) - before

        before = len(records)
        _parse_daily_steps(day_str, steps_data, args.tz, records)
        steps_count = len(records) - before

        debug_row: Dict[str, Any] = {
                "date": day_str,
                "sleep": {
                    "ok": sleep_result["ok"],
                    "method": sleep_result["method"],
                    "shape": _classify_data_shape(sleep_data),
                    "records_added": sleep_count,
                    "attempts": sleep_result["attempts"],
                },
                "heart_rate": {
                    "ok": heart_rate_result["ok"],
                    "method": heart_rate_result["method"],
                    "shape": _classify_data_shape(heart_rate_data),
                    "records_added": hr_count,
                    "attempts": heart_rate_result["attempts"],
                },
                "stress": {
                    "ok": stress_result["ok"],
                    "method": stress_result["method"],
                    "shape": _classify_data_shape(stress_data),
                    "records_added": stress_count,
                    "attempts": stress_result["attempts"],
                },
                "steps": {
                    "ok": steps_result["ok"],
                    "method": steps_result["method"],
                    "shape": _classify_data_shape(steps_data),
                    "records_added": steps_count,
                    "attempts": steps_result["attempts"],
                },
            }
        if args.raw_debug_include_data:
            debug_row["raw_sample"] = {
                "sleep": _sample_data(sleep_data),
                "heart_rate": _sample_data(heart_rate_data),
                "stress": _sample_data(stress_data),
                "steps": _sample_data(steps_data),
            }
        debug_rows.append(debug_row)

    _inject_movement_proxy(records)
    standard_payload = build_standard_payload(args.device_id, records)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(standard_payload, f, ensure_ascii=False, indent=2)

    if args.raw_debug_output:
        raw_debug_payload = {
            "generated_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "fetch_days": [d.isoformat() for d in sorted(fetched_days)],
            "summary": debug_rows,
        }
        with open(args.raw_debug_output, "w", encoding="utf-8") as f:
            json.dump(raw_debug_payload, f, ensure_ascii=False, indent=2)

    print("Garmin Connect fetch complete.")
    print(f"- fetched_days: {len(fetched_days)}")
    print(f"- records: {standard_payload['total_records']}")
    print(f"- standard output: {args.output}")
    if args.raw_debug_output:
        print(f"- raw debug:       {args.raw_debug_output}")
    print("- parser details per day:")
    for row in debug_rows:
        print(
            f"  {row['date']} | "
            f"sleep={row['sleep']['records_added']} ({row['sleep']['shape']}) "
            f"hr={row['heart_rate']['records_added']} ({row['heart_rate']['shape']}) "
            f"stress={row['stress']['records_added']} ({row['stress']['shape']}) "
            f"steps={row['steps']['records_added']} ({row['steps']['shape']})"
        )


if __name__ == "__main__":
    main()
