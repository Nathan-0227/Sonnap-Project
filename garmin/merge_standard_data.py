"""
garmin/merge_standard_data.py — 把新抓的 Garmin 紀錄併進既有的 garmin_standard_data.json

**純函式，沒有 I/O、不 import garminconnect**，所以測得到（tests/test_garmin_fetch_merge.py）。

為什麼需要它（2026-10-03）：
    garmin_connect_fetch.py 原本每次都整份覆寫。兩個後果：
    1. `--days N` 會把整份歷史換成最近 N 天，沒有任何警告。
    2. 就算每次都給完整區間，Garmin 會把約 4 個月前的日子的細節收掉——
       10-02 那次重抓，05-28 ~ 05-31 從 4768 筆掉到 441 筆（心率、壓力、
       動作、睡眠分段幾乎全沒了），連帶讓 10 個六月夜晚的分數變了。
       「每次重抓全部」等於每次都把上游的遺失抄進來。

規則：
    只換「這次抓的那幾天」，其餘原樣保留。

    ⚠️ 切點不能落在一段睡眠中間。紀錄是一長串（時刻, 指標, 值），一晚的
       睡眠橫跨兩個日曆日，而且這份資料的作息很晚（實測入睡 22:00~08:00、
       起床最晚 16:00）——用「午夜」或「中午」切都會切到人。切到的話那一晚
       會是前半舊、後半新，`sleep_start_time` 還可能出現兩筆。
       所以切點落在睡眠中間時一律**往視窗內縮**：那一晚整晚留舊的。
       視窗因此只會變小不會變大，也就不需要多抓一天。

    視窗內新的贏（Garmin 會事後補齊最近幾天，09-29 那晚是 55 → 1578 筆）。
    唯一的例外：某一天的某個來源（睡眠／心率／壓力／步數）這次**一筆都沒
    抓到**，而舊的有 → 留舊的並回報。那是 API 那一次沒回東西，不是資料沒了。

    ⚠️ 「沒抓到」用抓取當下的事實判斷（那一天那支 API 產生了幾筆），
       不是事後拿紀錄的時刻去猜它屬於哪一天——`heart_rate` 同時來自
       每日心率與睡眠心率兩支 API，光看紀錄分不出來。
"""
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

Record = Dict[str, Any]

SOURCES = ("sleep", "heart_rate", "stress", "steps")

# 每個來源會寫出哪些指標。睡眠那組另外用「落在那一晚的入睡~起床之間」定範圍。
SOURCE_METRICS = {
    "heart_rate": frozenset({"heart_rate"}),
    "stress": frozenset({"stress_score"}),
    "steps": frozenset({"daily_steps", "step_goal"}),
    "sleep": frozenset({
        "sleep_start_time", "wake_time", "sleep_stage",
        "rem_duration_sec", "deep_duration_sec", "light_duration_sec", "awake_duration_sec",
        "sleep_segment_start", "sleep_segment_end", "movement", "resting_heart_rate",
    }),
}

ONE_SECOND = timedelta(seconds=1)


def parse_tz(tz: str) -> timezone:
    """'+08:00' → timezone。與 fetch 的 --tz 同一個格式。"""
    sign = -1 if tz.startswith("-") else 1
    hours, minutes = tz.lstrip("+-").split(":")
    return timezone(sign * timedelta(hours=int(hours), minutes=int(minutes)))


def _ts(record: Record) -> datetime:
    return datetime.fromisoformat(record["timestamp"])


def sleep_intervals(records: Iterable[Record]) -> List[Tuple[datetime, datetime]]:
    """
    每一晚的（入睡, 起床）。入睡與起床各是一筆紀錄，照時間配對：
    一個入睡配它之後、下一個入睡之前的第一個起床。配不到的入睡不算。
    """
    starts = sorted(_ts(r) for r in records if r.get("metric") == "sleep_start_time")
    wakes = sorted(_ts(r) for r in records if r.get("metric") == "wake_time")
    intervals = []
    for i, start in enumerate(starts):
        limit = starts[i + 1] if i + 1 < len(starts) else None
        wake = next((w for w in wakes if w > start and (limit is None or w <= limit)), None)
        if wake is not None:
            intervals.append((start, wake))
    return intervals


def replace_window(
    fetch_days: Sequence[date],
    intervals: Sequence[Tuple[datetime, datetime]],
    tz: timezone,
) -> Tuple[datetime, datetime]:
    """
    這次要換掉的時間範圍 [lo, hi)。

    從「第一個抓取日 00:00 ~ 最後一個抓取日的隔天 00:00」出發，
    兩端只要落在某段睡眠中間就往內縮到那段睡眠之外。
    intervals 要同時放舊的與新的——兩邊任何一邊的睡眠被切到都不行。
    """
    lo = datetime.combine(min(fetch_days), time.min, tzinfo=tz)
    hi = datetime.combine(max(fetch_days) + timedelta(days=1), time.min, tzinfo=tz)

    moved = True
    while moved:                     # 縮完可能又落進另一段（新舊兩版的同一晚）
        moved = False
        for start, wake in intervals:
            if start < lo <= wake:
                lo, moved = wake + ONE_SECOND, True
            if start < hi <= wake:
                hi, moved = start, True
    return lo, hi


def merge_records(
    old: Sequence[Record],
    new: Sequence[Record],
    fetch_days: Sequence[date],
    empty: Set[Tuple[date, str]] = frozenset(),
    tz: timezone = timezone(timedelta(hours=8)),
) -> Tuple[List[Record], Dict[str, Any]]:
    """
    回傳（合併後的紀錄, 報告）。

    empty：這次「一筆都沒抓到」的（抓取日, 來源）。
    報告的 kept_when_empty 是 [(日期, 來源, 筆數)]——只列真的有舊資料被留下來的。
    """
    if not fetch_days:
        return list(old), {"replaced": 0, "taken": 0, "kept_when_empty": [], "window": None}

    old_intervals = sleep_intervals(old)
    new_intervals = sleep_intervals(new)
    lo, hi = replace_window(fetch_days, old_intervals + new_intervals, tz)

    def inside(record: Record) -> bool:
        return lo <= _ts(record) < hi

    kept = [r for r in old if not inside(r)]
    in_window_old = [r for r in old if inside(r)]
    taken = [r for r in new if inside(r)]

    # ── 有值不被空值蓋掉 ──────────────────────────────────────────
    rescued: List[Record] = []
    kept_when_empty = []
    for day, source in sorted(empty):
        if source == "sleep":
            # Garmin 的睡眠掛在起床日。新資料裡已經有重疊的一晚就不救——
            # 那代表這一晚其實有抓到（只是掛在別的抓取日），救了會變兩份。
            nights = [(s, w) for s, w in old_intervals
                      if w.astimezone(tz).date() == day
                      and not any(ns <= w and s <= nw for ns, nw in new_intervals)]
            rows = [r for r in in_window_old
                    if r.get("metric") in SOURCE_METRICS["sleep"]
                    and any(s <= _ts(r) <= w for s, w in nights)]
        else:
            rows = [r for r in in_window_old
                    if r.get("metric") in SOURCE_METRICS[source]
                    and _ts(r).astimezone(tz).date() == day]
        if rows:
            rescued.extend(rows)
            kept_when_empty.append((day.isoformat(), source, len(rows)))

    # 救回來的若與新抓的同一時刻同一指標（睡眠心率與每日心率重疊），以新的為準
    have = {(r["timestamp"], r["metric"]) for r in taken}
    rescued = [r for r in rescued if (r["timestamp"], r["metric"]) not in have]

    merged = sorted(kept + taken + rescued, key=lambda r: r["timestamp"])
    return merged, {
        "window": (lo.isoformat(), hi.isoformat()),
        "kept": len(kept),
        "replaced": len(in_window_old) - len(rescued),
        "taken": len(taken),
        "dropped_new_outside_window": len(new) - len(taken),
        "kept_when_empty": kept_when_empty,
    }


def last_record_day(records: Iterable[Record], tz: timezone) -> Optional[date]:
    """檔案裡最晚的一筆是哪一天。空的回 None。"""
    latest = max((r["timestamp"] for r in records), default=None, key=datetime.fromisoformat)
    return datetime.fromisoformat(latest).astimezone(tz).date() if latest else None
