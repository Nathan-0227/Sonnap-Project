"""Garmin 白天資料：步數、距離、活動卡路里、活動時間、爬樓、各壓力程度的時間、
Body Battery、VO2 max、Move IQ（2026-11-13 使用者定，早晨報告的「Yesterday」那一塊用）。

這支只放**純函式**（解析、合併、決定還要補哪幾天），I/O 在 `garmin_connect_fetch.py`
與 `migrate_garmin_to_db.py`，所以全部測得到（`tests/test_garmin_daily.py`）。

⚠️ **只呈現、不計分**：這些數字不進 final_score、不影響寵物心情、XP、挑戰（紅線 4），
   也**不給 Good/Normal**（沒有文獻門檻，紅線 2）。VO2 max 的常模要年齡與性別，同樣不判斷。
⚠️ 寫到**另一個檔** `garmin/data/garmin_daily_activity.json`，不碰 `garmin_standard_data.json`
   （那份有自己的合併規則，也丟過資料）。
⚠️ 這個檔**只增不減**：某一天這次沒抓到某一項 → 留舊的值；從來不刪任何一天。

檔案格式：
    {"version": 1, "days": {"2026-11-12": {<FIELDS>…}, …}}
"""
from __future__ import annotations

import json
import os
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

DATA_FILE = Path(__file__).parent / "data" / "garmin_daily_activity.json"
FILE_VERSION = 1

# 每一天存的欄位（缺的就是 None）。名字與資料庫 garmin_daily 的欄位一一對應。
FIELDS = (
    "steps",                 # totalSteps
    "step_goal",             # dailyStepGoal（Garmin 自己會調）
    "distance_m",            # totalDistanceMeters
    "active_kcal",           # activeKilocalories
    "highly_active_sec",     # highlyActiveSeconds
    "active_sec",            # activeSeconds
    "sedentary_sec",         # sedentarySeconds
    "floors_up",             # floorsAscended
    "stress_rest_sec",       # restStressDuration
    "stress_low_sec",        # lowStressDuration
    "stress_medium_sec",     # mediumStressDuration
    "stress_high_sec",       # highStressDuration
    "body_battery_charged",  # get_body_battery()[0].charged
    "body_battery_drained",  # get_body_battery()[0].drained
    "vo2max",                # get_max_metrics()[0].generic.vo2MaxPreciseValue（只有量到的那天有）
    "move_iq",               # [{"type", "start", "minutes"}, …]；沒有事件是 []，沒抓到是 None
)

_STATS_MAP = {
    "steps": "totalSteps",
    "step_goal": "dailyStepGoal",
    "distance_m": "totalDistanceMeters",
    "active_kcal": "activeKilocalories",
    "highly_active_sec": "highlyActiveSeconds",
    "active_sec": "activeSeconds",
    "sedentary_sec": "sedentarySeconds",
    "floors_up": "floorsAscended",
    "stress_rest_sec": "restStressDuration",
    "stress_low_sec": "lowStressDuration",
    "stress_medium_sec": "mediumStressDuration",
    "stress_high_sec": "highStressDuration",
}

# Garmin 用負數表示「沒有這個值」（例如沒戴錶的那天壓力是 -1、-2）
def _num(v: Any) -> Optional[float]:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return None if v < 0 else v


def _int(v: Any) -> Optional[int]:
    n = _num(v)
    return None if n is None else int(round(n))


def parse_day(
    stats: Any = None,
    max_metrics: Any = None,
    events: Any = None,
    body_battery: Any = None,
) -> Dict[str, Any]:
    """四個 API 的回應 → 一天的 FIELDS。哪個回應是 None（沒抓到）就那幾欄是 None。"""
    row: Dict[str, Any] = {k: None for k in FIELDS}

    if isinstance(stats, dict):
        for field, key in _STATS_MAP.items():
            v = stats.get(key)
            row[field] = round(_num(v), 1) if field == "floors_up" and _num(v) is not None \
                else _int(v)
        # 一整天沒戴錶：步數 0 而且活動、靜態時間都是 0／None → 當作沒有資料，不是「走了 0 步」
        worn = any(row[k] for k in ("steps", "active_sec", "sedentary_sec", "highly_active_sec"))
        if not worn:
            for field in _STATS_MAP:
                row[field] = None

    if isinstance(max_metrics, list):
        for m in max_metrics:
            generic = (m or {}).get("generic") or {}
            v = _num(generic.get("vo2MaxPreciseValue")) or _num(generic.get("vo2MaxValue"))
            if v:
                row["vo2max"] = round(v, 1)
                break

    if isinstance(body_battery, list) and body_battery:
        first = body_battery[0] or {}
        row["body_battery_charged"] = _int(first.get("charged"))
        row["body_battery_drained"] = _int(first.get("drained"))

    if isinstance(events, list):
        out = []
        for e in events:
            if not isinstance(e, dict):
                continue
            start = str(e.get("startTimestampLocal") or "")
            minutes = _int(e.get("duration"))  # ⚠️ 單位是分鐘（對過起訖時刻，2026-11-13）
            kind = str(e.get("activityType") or "").lower() or None
            if len(start) >= 16 and minutes and kind:
                out.append({"type": kind, "start": start[11:16], "minutes": minutes})
        row["move_iq"] = sorted(out, key=lambda x: x["start"])

    return row


def has_any(row: Dict[str, Any]) -> bool:
    """這一天有沒有任何一項有值（Move IQ 的 [] 不算）。"""
    return any(row.get(k) not in (None, []) for k in FIELDS)


def merge_days(
    existing: Dict[str, Dict[str, Any]],
    fetched: Dict[str, Dict[str, Any]],
) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, List[str]]]:
    """只增不減：這次抓到的值蓋掉舊的；這次是 None 的欄位留舊的值；不刪任何一天。

    回傳（合併後, 報告）。報告列出 new（新的日子）、updated（有欄位變了）、
    kept（這次整天都沒抓到、留舊的）。
    """
    merged = {d: dict(r) for d, r in existing.items()}
    report: Dict[str, List[str]] = {"new": [], "updated": [], "kept": []}
    for day, row in sorted(fetched.items()):
        old = merged.get(day)
        if not has_any(row):
            if old is not None:
                report["kept"].append(day)
            continue
        if old is None:
            merged[day] = {k: row.get(k) for k in FIELDS}
            report["new"].append(day)
            continue
        new = dict(old)
        for k in FIELDS:
            if row.get(k) is not None:
                new[k] = row[k]
        if new != old:
            report["updated"].append(day)
        merged[day] = new
    return merged, report


def days_to_backfill(
    existing: Dict[str, Dict[str, Any]],
    since: date,
    until: date,
    already: Iterable[date] = (),
    limit: int = 30,
) -> List[date]:
    """since..until 之間還沒有任何資料的日子（最舊的先補），最多 limit 天、不含 already。

    ⚠️ 有上限是因為 Garmin 會回 429（太多請求）：一次補太多天就會被擋，
       每天早上補一點，幾天之內就補完。
    """
    skip = set(already)
    out: List[date] = []
    d = since
    while d <= until and len(out) < limit:
        row = existing.get(d.isoformat())
        if d not in skip and (row is None or not has_any(row)):
            out.append(d)
        d += timedelta(days=1)
    return out


def is_rate_limited(exc: BaseException) -> bool:
    """Garmin 擋請求（429）。看例外的類名與訊息，不綁特定套件版本的例外類別。"""
    text = f"{type(exc).__name__} {exc}"
    return "TooManyRequests" in text or "429" in text


def load(path: Path = DATA_FILE) -> Dict[str, Dict[str, Any]]:
    """讀檔。檔案不存在 → 空的。⚠️ 讀不出來就讓它拋例外——不要當成空的再整份覆寫。"""
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        payload = json.load(f)
    return dict(payload.get("days") or {})


def save(days: Dict[str, Dict[str, Any]], path: Path = DATA_FILE) -> None:
    """先寫暫存檔再換名：寫到一半被中斷時，原檔還在。"""
    payload = {"version": FILE_VERSION, "days": dict(sorted(days.items()))}
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, path)
