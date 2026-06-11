import json
import csv
from collections import defaultdict
from datetime import datetime


INPUT_FILE = "garmin_standard_data.json"
OUTPUT_CSV = "garmin_sleep_summary.csv"
OUTPUT_JSON = "garmin_sleep_summary.json"


def get_date(timestamp):
    """
    Extract date from ISO timestamp.
    Example: 2026-05-19T23:10:00+08:00 -> 2026-05-19
    """
    return timestamp[:10]


def safe_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main():
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    records = data.get("records", [])

    summary = defaultdict(lambda: {
        "date": "",
        "sleep_start_time": "",
        "wake_time": "",
        "light_count": 0,
        "deep_count": 0,
        "rem_count": 0,
        "awake_count": 0,
        "movement_count": 0,
        "steps_total": 0,
        "heart_rate_count": 0,
        "heart_rate_sum": 0,
        "heart_rate_min": None,
        "heart_rate_max": None,
        "stress_count": 0,
        "stress_sum": 0,
        "resting_heart_rate": None,
    })

    for r in records:
        metric = r.get("metric")
        value = r.get("value")
        timestamp = r.get("timestamp", "")

        if not timestamp:
            continue

        date = get_date(timestamp)
        row = summary[date]
        row["date"] = date

        if metric == "sleep_start_time":
            row["sleep_start_time"] = value

        elif metric == "wake_time":
            row["wake_time"] = value

        elif metric == "sleep_stage":
            stage = str(value).lower()
            if stage == "light":
                row["light_count"] += 1
            elif stage == "deep":
                row["deep_count"] += 1
            elif stage == "rem":
                row["rem_count"] += 1
            elif stage == "awake":
                row["awake_count"] += 1

        elif metric == "movement":
            row["movement_count"] += 1

        elif metric == "steps":
            n = safe_number(value)
            if n is not None:
                row["steps_total"] += int(n)

        elif metric == "heart_rate":
            hr = safe_number(value)
            if hr is not None and 40 <= hr <= 180:
                row["heart_rate_count"] += 1
                row["heart_rate_sum"] += hr

                if row["heart_rate_min"] is None or hr < row["heart_rate_min"]:
                    row["heart_rate_min"] = hr

                if row["heart_rate_max"] is None or hr > row["heart_rate_max"]:
                    row["heart_rate_max"] = hr

        elif metric == "stress_score":
            stress = safe_number(value)
            if stress is not None and stress >= 0:
                row["stress_count"] += 1
                row["stress_sum"] += stress

        elif metric == "resting_heart_rate":
            rhr = safe_number(value)
            if rhr is not None:
                row["resting_heart_rate"] = int(rhr)

    final_rows = []

    for date in sorted(summary.keys()):
        row = summary[date]

        avg_hr = None
        if row["heart_rate_count"] > 0:
            avg_hr = round(row["heart_rate_sum"] / row["heart_rate_count"], 2)

        avg_stress = None
        if row["stress_count"] > 0:
            avg_stress = round(row["stress_sum"] / row["stress_count"], 2)

        final_row = {
            "date": row["date"],
            "sleep_start_time": row["sleep_start_time"],
            "wake_time": row["wake_time"],
            "light_count": row["light_count"],
            "deep_count": row["deep_count"],
            "rem_count": row["rem_count"],
            "awake_count": row["awake_count"],
            "movement_count": row["movement_count"],
            "steps_total": row["steps_total"],
            "avg_heart_rate": avg_hr,
            "min_heart_rate": row["heart_rate_min"],
            "max_heart_rate": row["heart_rate_max"],
            "avg_stress_score": avg_stress,
            "resting_heart_rate": row["resting_heart_rate"],
        }

        final_rows.append(final_row)

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(final_rows, f, ensure_ascii=False, indent=2)

    with open(OUTPUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=final_rows[0].keys())
        writer.writeheader()
        writer.writerows(final_rows)

    print("Garmin sleep analysis complete.")
    print(f"- output json: {OUTPUT_JSON}")
    print(f"- output csv:  {OUTPUT_CSV}")
    print(f"- days: {len(final_rows)}")

    for row in final_rows:
        print(row)


if __name__ == "__main__":
    main()