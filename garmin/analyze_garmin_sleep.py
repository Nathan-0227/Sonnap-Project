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

# ═══════════════════════════════════════════════════════════════════
# 動作幅度門檻（2026-08-12 新增）
# ═══════════════════════════════════════════════════════════════════
#
# Garmin 的 sleepMovement 每分鐘給一筆 activityLevel（連續值，實測範圍 0.00–7.64）。
# 這個常數是「多大算有明顯動作」的切點，用來算 movement_active_minutes。
#
# ⚠️ 為什麼要把門檻寫成常數而不是直接寫 `if level > 1.0`：
#    因為這個數字**不是文獻推導出來的**，是我們自己看資料分布訂的
#    （實測 69.3% 的取樣落在 0–1，超過 1 的約佔 30%）。
#    把它獨立成常數並寫進輸出檔，是為了讓「這是人為選的切點」這件事
#    對之後看資料的人可見，而不是藏在程式碼裡看起來像客觀事實。
#
# ⚠️ 正因為沒有文獻依據，這個指標**只供呈現與 AI 敘事，絕對不進評分**。
#    本專案每一項計分都有引文（見 Research-Background/Garmin手錶分數.md），
#    不為了多一個好看的數字而破例。
MOVEMENT_ACTIVE_THRESHOLD = 1.0


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
        # 【動作，2026-08-12 修正】見檔案底部 MOVEMENT_ACTIVE_THRESHOLD 的說明。
        # 原本只有一個 movement_count，而它其實是取樣筆數（＝取樣分鐘數），
        # 跟身體動不動無關。已改名並補上真正用到 activityLevel 數值的三個欄位。
        "movement_sample_minutes": 0,
        "movement_level_sum": 0.0,
        "movement_level_max": 0.0,
        "movement_active_minutes": 0,
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
            # ⚠️ 2026-08-12 之前這裡只有 `row["movement_count"] += 1`——只數筆數、
            #    完全不看 value，等於把 Garmin 給的動作幅度丟掉。
            #    實測證據（46 晚）：舊的 movement_count 與「錄製跨距分鐘數」
            #    43/48 天誤差正好是 0，且與睡眠時長的相關係數 r = +0.929、
            #    與夜間清醒 r = −0.138。它測的是時鐘，不是身體。
            row["movement_sample_minutes"] += 1
            level = safe_number(value)
            if level is not None:
                row["movement_level_sum"] += level
                if level > row["movement_level_max"]:
                    row["movement_level_max"] = level
                if level > MOVEMENT_ACTIVE_THRESHOLD:
                    row["movement_active_minutes"] += 1

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
            # ── 動作相關四欄（2026-08-12 改版）──────────────────────
            # movement_sample_minutes：取樣了幾分鐘。這就是舊的 movement_count，
            #   只是換了誠實的名字。保留它是因為它能反映「手錶戴了多久」，
            #   對判斷資料完整性有用——但它**不是**動作指標。
            "movement_sample_minutes": row["movement_sample_minutes"],
            # movement_level_mean：整夜 activityLevel 的平均。
            #   ⚠️ 分母要用取樣筆數，不是「那晚有幾分鐘」——沒戴錶的分鐘
            #      根本沒有資料列，拿時長當分母會把平均值稀釋掉。
            #   ⚠️ 沒有任何取樣時輸出 None 而不是 0。這是本專案一貫的作法：
            #      「沒量到」和「量到是 0」意義完全不同，混在一起後續就分不出來了。
            "movement_level_mean": (
                round(row["movement_level_sum"] / row["movement_sample_minutes"], 3)
                if row["movement_sample_minutes"] else None
            ),
            "movement_level_max": (
                round(row["movement_level_max"], 3)
                if row["movement_sample_minutes"] else None
            ),
            "movement_active_minutes": (
                row["movement_active_minutes"] if row["movement_sample_minutes"] else None
            ),
            # 把門檻本身也寫進輸出，讓 movement_active_minutes 可稽核——
            # 之後若有人調整門檻，舊資料仍看得出當時是用哪個值算的。
            "movement_active_threshold": MOVEMENT_ACTIVE_THRESHOLD,
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
