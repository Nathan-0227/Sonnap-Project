import argparse
import json
import os
from datetime import UTC, date, datetime, timedelta
from typing import Any, Dict, Iterable, List, Optional

from garmin_importer import build_project_payload, build_standard_payload


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
        default="garmin_standard_data.json",
        help="Output path for normalized records.",
    )
    parser.add_argument(
        "--project-output",
        default="garmin_project_payload.json",
        help="Output path for project payload format.",
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
    _add(records, sleep_start, "sleep_start_time", sleep_start, "datetime")
    _add(records, sleep_end, "wake_time", sleep_end, "datetime")

    stage_map = {
        "remSleepSeconds": "rem",
        "deepSleepSeconds": "deep",
        "lightSleepSeconds": "light",
        "awakeSleepSeconds": "awake",
    }
    for key, stage_name in stage_map.items():
        duration = sleep_root.get(key)
        if duration is not None:
            _add(records, sleep_start or f"{day_str}T00:00:00{tz}", "sleep_stage", stage_name, "stage")
            _add(records, sleep_start or f"{day_str}T00:00:00{tz}", f"{stage_name}_duration_sec", int(duration), "sec")

    sleep_levels = raw.get("sleepLevelsMap")
    if isinstance(sleep_levels, dict):
        for level in ("awake", "light", "deep", "rem"):
            level_data = sleep_levels.get(level, [])
            if not isinstance(level_data, list):
                continue
            for item in level_data:
                if not isinstance(item, dict):
                    continue
                ts = _iso_from_epoch_any(item.get("startTimeGMT"), tz)
                end_ts = _iso_from_epoch_any(item.get("endTimeGMT"), tz)
                _add(records, ts, "sleep_stage", level, "stage")
                _add(records, ts, "sleep_segment_start", ts, "datetime")
                _add(records, end_ts, "sleep_segment_end", end_ts, "datetime")

    # Vivoactive shape: sleepLevels with numeric activityLevel (0=deep,1=light,2=rem,3=awake)
    if isinstance(raw.get("sleepLevels"), list):
        for item in raw.get("sleepLevels", []):
            if not isinstance(item, dict):
                continue
            level = _sleep_stage_from_activity_level(
                item.get("activityLevel", item.get("sleepLevel", item.get("level")))
            )
            ts = _iso_from_garmin_str(item.get("startGMT", item.get("startTimeGMT")), tz)
            if ts is None:
                ts = _iso_from_epoch_any(item.get("startGMT", item.get("startTimeGMT")), tz)
            end_ts = _iso_from_garmin_str(item.get("endGMT", item.get("endTimeGMT")), tz)
            if end_ts is None:
                end_ts = _iso_from_epoch_any(item.get("endGMT", item.get("endTimeGMT")), tz)
            if level:
                _add(records, ts, "sleep_stage", level, "stage")
            _add(records, ts, "sleep_segment_start", ts, "datetime")
            _add(records, end_ts, "sleep_segment_end", end_ts, "datetime")

    if isinstance(raw.get("sleepHeartRate"), list):
        for item in raw["sleepHeartRate"]:
            if not isinstance(item, dict):
                continue
            ts = _iso_from_epoch_any(item.get("startGMT"), tz)
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
            ts = _iso_from_garmin_str(item.get("startGMT"), tz)
            level = item.get("activityLevel")
            if level is not None:
                try:
                    _add(records, ts, "movement", float(level), "arb")
                except (TypeError, ValueError):
                    pass

    resting_hr = raw.get("restingHeartRate")
    if resting_hr is not None and sleep_start:
        try:
            _add(records, sleep_start, "resting_heart_rate", int(resting_hr), "bpm")
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
        steps_result = _safe_get_with_meta(client, ["get_steps_data", "get_stats_and_body"], day_str)

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
        _parse_steps_data(day_str, steps_data, args.tz, records)
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
    project_payload = build_project_payload(standard_payload)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(standard_payload, f, ensure_ascii=False, indent=2)
    with open(args.project_output, "w", encoding="utf-8") as f:
        json.dump(project_payload, f, ensure_ascii=False, indent=2)

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
    print(f"- project output:  {args.project_output}")
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
