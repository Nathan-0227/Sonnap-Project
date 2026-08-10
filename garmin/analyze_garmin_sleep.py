import json
import csv
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path


# 【2026-08-11】所有生成的資料檔集中放在 garmin/data/，讓 garmin/ 目錄下只留程式碼。
# 用 Path(__file__).parent 而不是相對路徑字串，這樣不管從哪個工作目錄執行
# （例如從專案根目錄跑 python garmin/analyze_garmin_sleep.py）都能正確找到檔案。
DATA_DIR = Path(__file__).parent / "data"

INPUT_FILE = DATA_DIR / "garmin_standard_data.json"
OUTPUT_CSV = DATA_DIR / "garmin_sleep_summary.csv"
OUTPUT_JSON = DATA_DIR / "garmin_sleep_summary.json"

# 一次睡眠最長的合理長度（小時）。用來把 sleep_start 配對到正確的 wake_time，
# 避免把相隔很多天的 start / end 誤配成同一段（例如資料缺漏時）。
MAX_SLEEP_HOURS = 16


def parse_iso(ts):
    """
    把 ISO8601 字串（含時區，如 2026-06-11T02:58:00+08:00）轉成 datetime。
    失敗回傳 None。
    """
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts)
    except (TypeError, ValueError):
        return None


def get_date(timestamp):
    """
    從 ISO timestamp 取「日曆日期」字串。
    Example: 2026-05-19T23:10:00+08:00 -> 2026-05-19
    """
    return timestamp[:10]


def safe_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def build_sleep_sessions(records):
    """
    從 sleep_start_time / wake_time 記錄配對出「睡眠區間」清單。

    回傳 [(start_dt, end_dt, session_date_str), ...]，已依開始時間排序。

    session_date = 「起床當天」的日期字串，與 Garmin 官方一致。
    已用 Garmin 原始資料的 calendarDate 欄位驗證：例如 7/10 22:42 上床、7/11 07:51 起床
    的那一晚，Garmin 自己標記為 calendarDate = 2026-07-11（起床那天）。這裡採用相同慣例，
    我們的每日結果才能直接跟 Garmin Connect App 對照；跨午夜的夜晚也因此不會被切成兩段。
    """
    # 蒐集所有入睡時間點與起床時間點（各自排序）
    starts = sorted(
        dt
        for r in records
        if r.get("metric") == "sleep_start_time"
        for dt in [parse_iso(r.get("value"))]
        if dt is not None
    )
    ends = sorted(
        dt
        for r in records
        if r.get("metric") == "wake_time"
        for dt in [parse_iso(r.get("value"))]
        if dt is not None
    )

    sessions = []
    used_ends = set()
    for start in starts:
        # 為這個 start 找出「時間在它之後、且在合理睡眠長度內、尚未被配對過」的最早 wake_time
        best_end = None
        for end in ends:
            if end in used_ends or end < start:
                continue
            if (end - start) > timedelta(hours=MAX_SLEEP_HOURS):
                break  # ends 已排序，再往後只會離更遠，不用再看
            best_end = end
            break
        if best_end is None:
            continue
        used_ends.add(best_end)
        # 用「起床當天」當作這段睡眠的歸屬日期（對齊 Garmin calendarDate）
        sessions.append((start, best_end, best_end.date().isoformat()))

    sessions.sort(key=lambda s: s[0])
    return sessions


def session_date_for(ts_dt, sessions):
    """
    若時間點 ts_dt 落在某個睡眠區間 [start, end] 內，回傳該區間的 session_date；
    否則回傳 None（代表這是白天、非睡眠期間的記錄）。
    """
    if ts_dt is None:
        return None
    for start, end, sdate in sessions:
        if start <= ts_dt <= end:
            return sdate
    return None


def main():
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    records = data.get("records", [])

    # 先建立睡眠區間，之後用來判斷每筆記錄該歸到哪一「晚」
    sessions = build_sleep_sessions(records)

    summary = defaultdict(lambda: {
        "date": "",
        "sleep_start_time": "",
        "wake_time": "",
        # 睡眠階段【時長，秒】。Garmin 官方就是用時長顯示，不是段數。
        # 這些值直接來自 Garmin dailySleepDTO 的 deep/light/rem/awakeSleepSeconds。
        "deep_sec": 0,
        "light_sec": 0,
        "rem_sec": 0,
        "awake_sec": 0,
        "movement_count": 0,
        "steps_total": 0,
        "heart_rate_count": 0,
        "heart_rate_sum": 0,
        "heart_rate_min": None,
        "heart_rate_max": None,
        "stress_count": 0,
        "stress_sum": 0,
        "resting_heart_rate": None,
        # 【新增，J/M 修正值用】awake_count：當晚清醒的段數（sleep_stage=="awake" 的筆數）。
        # sleep_segment_count：當晚睡眠總段數（每次階段轉換都會有一筆 sleep_segment_start）。
        # 兩者都是「當晚原始事件計數」，不是時長，跟已有的 awake_minutes（清醒總分鐘）是互補資訊：
        # 同樣的清醒總分鐘，可能是「醒一次躺很久」或「醒很多次但每次很短」，這兩種情況只有
        # 靠段數/次數才分得出來，見 Garmin手錶分數.md M 節。
        "awake_count": 0,
        "sleep_segment_count": 0,
    })

    for r in records:
        metric = r.get("metric")
        value = r.get("value")
        timestamp = r.get("timestamp", "")

        if not timestamp:
            continue

        # 先看這筆記錄的時間是否落在某個睡眠區間內。
        # 是 -> 歸到該睡眠區間的日期（= 起床當天，跨午夜也不會被切開）
        # 否 -> 照它自己的日曆日期歸類（白天的步數、心率等）
        ts_dt = parse_iso(timestamp)
        date = session_date_for(ts_dt, sessions) or get_date(timestamp)

        row = summary[date]
        row["date"] = date

        if metric == "sleep_start_time":
            row["sleep_start_time"] = value

        elif metric == "wake_time":
            row["wake_time"] = value

        # 睡眠階段時長（秒）：這才是 Garmin 顯示的數字來源
        elif metric == "deep_duration_sec":
            n = safe_number(value)
            if n is not None:
                row["deep_sec"] += int(n)
        elif metric == "light_duration_sec":
            n = safe_number(value)
            if n is not None:
                row["light_sec"] += int(n)
        elif metric == "rem_duration_sec":
            n = safe_number(value)
            if n is not None:
                row["rem_sec"] += int(n)
        elif metric == "awake_duration_sec":
            n = safe_number(value)
            if n is not None:
                row["awake_sec"] += int(n)

        elif metric == "movement":
            row["movement_count"] += 1

        # 每次睡眠階段轉換（深→淺、淺→REM…）都會有一筆 sleep_segment_start，
        # 用來算「當晚睡眠被切成幾段」，見 M 節（片段化）
        elif metric == "sleep_segment_start":
            row["sleep_segment_count"] += 1

        # sleep_stage 這個 metric 記錄的是「這一段是深/淺/REM/清醒」，
        # 只數 value=="awake" 的筆數，就是「當晚醒來幾次」
        elif metric == "sleep_stage" and value == "awake":
            row["awake_count"] += 1

        elif metric == "daily_steps":
            # 官方每日總步數（與 Garmin App 一致），直接設定而非加總
            n = safe_number(value)
            if n is not None:
                row["steps_total"] = int(n)

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

        # 秒 -> 分鐘（四捨五入到整數分鐘，跟 Garmin App 顯示一致）
        deep_min = round(row["deep_sec"] / 60)
        light_min = round(row["light_sec"] / 60)
        rem_min = round(row["rem_sec"] / 60)
        awake_min = round(row["awake_sec"] / 60)
        # 總睡眠時長 = 深 + 淺 + REM（不含清醒），與 Garmin sleepTimeSeconds 定義相同
        total_sleep_min = deep_min + light_min + rem_min

        # 【重要】awake_count / sleep_segment_count 只在「當晚真的有睡眠區間」時才有意義。
        # 沒戴錶睡覺的日子（sleep_start_time 是空字串），這兩個計數器從頭到尾都不會被加到，
        # 若直接輸出 0，會被 J/M 修正值的 baseline 計算誤判成「那晚醒來 0 次、超規律」，
        # 但事實是「那晚根本沒量到」，兩者意義完全不同。這裡比照 resting_heart_rate
        # 缺資料時輸出 None（CSV 裡是空字串）的既有慣例，讓後續程式能用「是否為 None」
        # 正確判斷「有沒有資料」，而不是把「沒資料」誤當成「資料是 0」。
        has_sleep_session = bool(row["sleep_start_time"])

        final_row = {
            "date": row["date"],
            "sleep_start_time": row["sleep_start_time"],
            "wake_time": row["wake_time"],
            "total_sleep_minutes": total_sleep_min,
            "deep_minutes": deep_min,
            "light_minutes": light_min,
            "rem_minutes": rem_min,
            "awake_minutes": awake_min,
            "movement_count": row["movement_count"],
            "steps_total": row["steps_total"],
            "avg_heart_rate": avg_hr,
            "min_heart_rate": row["heart_rate_min"],
            "max_heart_rate": row["heart_rate_max"],
            "avg_stress_score": avg_stress,
            "resting_heart_rate": row["resting_heart_rate"],
            "awake_count": row["awake_count"] if has_sleep_session else None,
            "sleep_segment_count": row["sleep_segment_count"] if has_sleep_session else None,
        }

        final_rows.append(final_row)

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(final_rows, f, ensure_ascii=False, indent=2)

    with open(OUTPUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=final_rows[0].keys())
        writer.writeheader()
        writer.writerows(final_rows)

    print("Garmin sleep analysis complete.")
    print(f"- sleep sessions detected: {len(sessions)}")
    print(f"- output json: {OUTPUT_JSON}")
    print(f"- output csv:  {OUTPUT_CSV}")
    print(f"- days: {len(final_rows)}")

    for row in final_rows:
        print(row)


if __name__ == "__main__":
    main()
