import argparse
import csv
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert Garmin manual export CSV files into project JSON format."
    )
    parser.add_argument(
        "--input-dir",
        default="garmin_export",
        help="Folder containing Garmin CSV exports.",
    )
    parser.add_argument(
        "--output",
        default="garmin_standard_data.json",
        help="Output path for normalized JSON records.",
    )
    parser.add_argument(
        "--device-id",
        default="garmin_vivoactive3_01",
        help="Device id to write into output JSON.",
    )
    parser.add_argument(
        "--tz",
        default="+08:00",
        help="Timezone suffix for timestamps without timezone (example: +08:00).",
    )
    parser.add_argument(
        "--project-output",
        default="garmin_project_payload.json",
        help="Output path for Sonnap API contract payload.",
    )
    return parser.parse_args()


def normalize_timestamp(raw: str, tz: str) -> Optional[str]:
    text = (raw or "").strip()
    if not text:
        return None

    if text.endswith("Z"):
        return text
    if len(text) >= 6 and (text[-6] == "+" or text[-6] == "-") and text[-3] == ":":
        return text

    formats = (
        "%Y-%m-%d %H:%M:%S",
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y/%m/%d %H:%M",
        "%Y-%m-%dT%H:%M:%S",
    )
    for fmt in formats:
        try:
            dt = datetime.strptime(text, fmt)
            return dt.strftime("%Y-%m-%dT%H:%M:%S") + tz
        except ValueError:
            continue
    return None


def _find_value(row: Dict[str, str], candidates: List[str]) -> str:
    lowered = {k.lower().strip(): v for k, v in row.items()}
    for key in candidates:
        if key in lowered and lowered[key] not in ("", None):
            return str(lowered[key]).strip()
    return ""


def add_record(records: List[Dict[str, Any]], ts: Optional[str], metric: str, value: Any, unit: str) -> None:
    if not ts:
        return
    records.append(
        {
            "timestamp": ts,
            "metric": metric,
            "value": value,
            "unit": unit,
        }
    )


def normalize_stage(stage: str) -> Optional[str]:
    mapping = {
        "rem": "rem",
        "deep": "deep",
        "light": "light",
        "awake": "awake",
        "wake": "awake",
    }
    key = stage.strip().lower()
    return mapping.get(key)


def parse_csv_file(path: Path, records: List[Dict[str, Any]], tz: str) -> int:
    """
    Parse one CSV and append normalized records.
    Expected columns can vary; parser tries common names used in exports.
    """
    before_count = len(records)

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = normalize_timestamp(
                _find_value(row, ["timestamp", "datetime", "time", "start_time", "start"]),
                tz,
            )
            end_ts = normalize_timestamp(_find_value(row, ["end_time", "end"]), tz)

            hr = _find_value(row, ["heart_rate", "hr", "bpm"])
            if hr:
                try:
                    add_record(records, ts, "heart_rate", int(float(hr)), "bpm")
                except ValueError:
                    pass

            stress = _find_value(row, ["stress_score", "stress"])
            if stress:
                try:
                    add_record(records, ts, "stress_score", int(float(stress)), "score")
                except ValueError:
                    pass

            steps = _find_value(row, ["steps", "step_count"])
            if steps:
                try:
                    add_record(records, ts, "steps", int(float(steps)), "count")
                except ValueError:
                    pass

            movement = _find_value(row, ["movement", "restlessness", "motion"])
            if movement:
                try:
                    add_record(records, ts, "movement", float(movement), "arb")
                except ValueError:
                    pass

            stage_raw = _find_value(row, ["sleep_stage", "stage"])
            if stage_raw:
                stage = normalize_stage(stage_raw)
                if stage:
                    add_record(records, ts, "sleep_stage", stage, "stage")

            sleep_start = _find_value(row, ["sleep_start_time", "sleep_start", "bed_time"])
            if sleep_start:
                normalized_start = normalize_timestamp(sleep_start, tz)
                add_record(records, normalized_start, "sleep_start_time", normalized_start, "datetime")

            wake_time = _find_value(row, ["wake_time", "sleep_end_time", "wake_up_time"])
            if wake_time:
                normalized_wake = normalize_timestamp(wake_time, tz)
                add_record(records, normalized_wake, "wake_time", normalized_wake, "datetime")

            # If file has explicit start/end but no sleep_start_time/wake_time fields,
            # treat segment boundaries as nightly markers when stage exists.
            if stage_raw and ts:
                add_record(records, ts, "sleep_segment_start", ts, "datetime")
            if stage_raw and end_ts:
                add_record(records, end_ts, "sleep_segment_end", end_ts, "datetime")

    return len(records) - before_count


def build_standard_payload(device_id: str, records: List[Dict[str, Any]]) -> Dict[str, Any]:
    date_str = datetime.now().strftime("%Y-%m-%d")
    sorted_records = sorted(records, key=lambda x: x["timestamp"])
    return {
        "device_id": device_id,
        "source": "garmin_connect_manual_export",
        "date": date_str,
        "total_records": len(sorted_records),
        "records": sorted_records,
    }


def build_project_payload(standard: Dict[str, Any]) -> Dict[str, Any]:
    records = standard.get("records", [])
    motion_like_events = [r for r in records if r.get("metric") in ("movement", "sleep_stage")]
    sleep_start_values = [r["value"] for r in records if r.get("metric") == "sleep_start_time"]
    wake_values = [r["value"] for r in records if r.get("metric") == "wake_time"]

    return {
        "session_id": datetime.now().strftime("%Y%m%d_%H%M"),
        "status": {
            "pet_mood": "tired",
            "current_activity": "sleeping",
            "energy_level": 70,
        },
        "metrics": {
            "motion_count": len(motion_like_events),
            "sleep_duration_minutes": None,
            "ambient_noise_db": None,
            "sleep_start_time": sleep_start_values[0] if sleep_start_values else None,
            "wake_time": wake_values[-1] if wake_values else None,
            "garmin_records": len(records),
        },
        "ai_content": {
            "dream_summary": None,
            "advice": None,
        },
        "timestamp": datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def main() -> None:
    args = parse_args()
    input_dir = Path(args.input_dir)
    output_path = Path(args.output)
    project_output = Path(args.project_output)

    if not input_dir.exists():
        raise FileNotFoundError(f"Input folder not found: {input_dir}")

    csv_files = sorted(input_dir.glob("*.csv"))
    if not csv_files:
        raise FileNotFoundError(
            f"No CSV files found in {input_dir}. Place Garmin export CSV files there first."
        )

    records: List[Dict[str, Any]] = []
    per_file_counts: Dict[str, int] = {}
    for csv_path in csv_files:
        parsed = parse_csv_file(csv_path, records, args.tz)
        per_file_counts[csv_path.name] = parsed

    standard_payload = build_standard_payload(args.device_id, records)
    project_payload = build_project_payload(standard_payload)

    output_path.write_text(json.dumps(standard_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    project_output.write_text(json.dumps(project_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    print("Garmin import complete.")
    for file_name, count in per_file_counts.items():
        print(f"- {file_name}: {count} records parsed")
    print(f"- Standard output: {output_path}")
    print(f"- Project output:  {project_output}")


if __name__ == "__main__":
    main()
