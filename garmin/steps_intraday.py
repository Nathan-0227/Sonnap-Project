"""Garmin 每 15 分鐘的步數 → 每個鐘頭走了幾步（2026-11-15 使用者定，早晨報告 Steps 點開用）。

這支只放**純函式**（解析、換成每小時、合併、決定還要補哪幾天），I/O 在
`garmin_connect_fetch.py`（抓）與 `migrate_garmin_to_db.py`（寫資料庫），全部測得到
（`tests/test_steps_intraday.py`）。

⚠️ **只呈現、不計分、不判斷**（紅線 2、4）：不寫達標、不分好壞。
⚠️ 一天的總數照用官方的 `get_stats.totalSteps`，這裡的數字只回答「什麼時候在走」。
   2026-11-15 實抓 30 天（08-28 ~ 09-26）：**照當地日期切之後，96 格加起來與官方總數逐天完全相同**
   （差 0）；專案早期加總多算，最可能是沒照當地日期切、把隔天的格子算進來。畫面上仍不寫加總
   （大數字已經是官方總數）。睡眠格落在當地 02–08 點，與作息相符＝時區換對了。
⚠️ 「none＝沒戴錶」**還沒在真資料上看過**：那 30 天每天 96 格都有戴（沒有一格是 none）。
   另有 `generic` 這種程度（意思不明），照有戴處理。
🔴 **時間是 GMT**（`startGMT`），要換成當地時間。這個專案的每日心率／壓力曾經整批早 8 小時、
   一個月沒人發現（CLAUDE.md「每日心率與壓力的時刻」）——`test_steps_intraday.py`【1】守著。
⚠️ 檔案 `garmin/data/garmin_steps_intraday.json` **不進版控**（使用者定）：每 15 分鐘在不在動
   等於公開作息，比 Move IQ 細得多。資料照樣進資料庫，手機照樣看得到。

檔案格式：
    {"version": 1, "days": {"2026-11-13": [{"start": "00:00", "steps": 0, "level": "sleeping"}, …]}}
"""
from __future__ import annotations

import json
import os
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

DATA_FILE = Path(__file__).parent / "data" / "garmin_steps_intraday.json"
FILE_VERSION = 1

# Garmin 標「沒有資料」的活動程度（沒戴錶）。其他（sedentary／active／highlyActive／sleeping…）都算有戴。
NO_DATA_LEVELS = ("none",)


def _parse_gmt(text: Any) -> Optional[datetime]:
    if not isinstance(text, str) or len(text) < 16:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", ""))
    except ValueError:
        return None


def parse_steps_chart(resp: Any, day_iso: str, tz_hours: float = 8.0) -> Optional[List[Dict[str, Any]]]:
    """`get_steps_data(day)` 的回應 → 那個**當地日曆日**的每 15 分鐘
    [{"start": "HH:MM"（當地）, "steps": int, "level": str}]，照時間排。

    沒抓到（不是 list）→ None；抓到但那天一格都沒有 → []。
    回應會跨到隔天或前一天（GMT 切的），只留落在那個當地日期的格子。
    """
    if not isinstance(resp, list):
        return None
    out = []
    seen = set()
    for item in resp:
        if not isinstance(item, dict):
            continue
        start = _parse_gmt(item.get("startGMT"))
        if start is None:
            continue
        local = start + timedelta(hours=tz_hours)
        if local.date().isoformat() != day_iso:
            continue
        hhmm = local.strftime("%H:%M")
        if hhmm in seen:
            continue
        seen.add(hhmm)
        steps = item.get("steps")
        steps = int(steps) if isinstance(steps, (int, float)) and not isinstance(steps, bool) and steps >= 0 else 0
        level = str(item.get("primaryActivityLevel") or "none")
        out.append({"start": hhmm, "steps": steps, "level": level})
    return sorted(out, key=lambda x: x["start"])


def hourly(slots: Optional[List[Dict[str, Any]]]) -> Optional[List[Optional[int]]]:
    """每 15 分鐘 → 24 個鐘頭的步數。

    - 那個鐘頭**每一格都是沒資料**（none 或根本沒有那一格）→ None（沒戴錶，畫面空著，不畫成 0）
    - 有戴、走 0 步 → 0（真的值）
    - 整天都沒資料 → None（不回 24 個 None）
    """
    if not slots:
        return None
    hours: List[Optional[int]] = [None] * 24
    for s in slots:
        try:
            h = int(str(s["start"])[:2])
        except (KeyError, ValueError):
            continue
        if not 0 <= h < 24 or s.get("level") in NO_DATA_LEVELS:
            continue
        hours[h] = (hours[h] or 0) + int(s.get("steps") or 0)
    return hours if any(v is not None for v in hours) else None


# 2026-11-15 使用者定（Active time 點開的時間軸）：Garmin 的活動程度 → 畫面上的四種＋一種。
# ⚠️ generic 是 Garmin 自己標的另一種程度（58 天裡 78 格，多半有步數），意思不明，照實標 other，
#    不硬塞進「活動」或「久坐」。none（沒戴錶）與不認得的 → None（畫面空著，不畫成任何一種）。
LEVEL_CODES = {
    "sleeping": "sleep",
    "sedentary": "still",
    "active": "active",
    "highlyActive": "high",
    "generic": "other",
}


def quarters(slots: Optional[List[Dict[str, Any]]]) -> Optional[List[Optional[List]]]:
    """每 15 分鐘 → 96 格 [程度, 步數]；沒戴錶／沒有那一格是 None；整天都沒有 → None。"""
    if not slots:
        return None
    out: List[Optional[List]] = [None] * 96
    for s in slots:
        try:
            hh, mm = str(s["start"]).split(":")
            i = int(hh) * 4 + int(mm) // 15
        except (KeyError, ValueError):
            continue
        code = LEVEL_CODES.get(s.get("level"))
        if 0 <= i < 96 and code is not None:
            out[i] = [code, int(s.get("steps") or 0)]
    return out if any(v is not None for v in out) else None


def merge_days(existing: Dict[str, List], fetched: Dict[str, Optional[List]]) -> Dict[str, List]:
    """只增不減：這次抓到（非空）的那天整天換新的；沒抓到或空的留舊的；從不刪一天。"""
    merged = dict(existing)
    for day, slots in fetched.items():
        if slots:
            merged[day] = slots
    return merged


def has_data(slots: Optional[List]) -> bool:
    return hourly(slots) is not None


def days_to_backfill(existing: Dict[str, List], since: date, until: date,
                     already: Iterable[date] = (), limit: int = 30) -> List[date]:
    """since..until 之間還沒有資料的日子（最舊的先），最多 limit 天、不含 already。
    有上限：Garmin 問太多會回 429。"""
    skip = set(already)
    out: List[date] = []
    d = since
    while d <= until and len(out) < limit:
        if d not in skip and not has_data(existing.get(d.isoformat())):
            out.append(d)
        d += timedelta(days=1)
    return out


def load(path: Path = DATA_FILE) -> Dict[str, List]:
    """讀檔。不存在 → 空的。⚠️ 讀不出來就讓它拋例外——不要當成空的再整份覆寫。"""
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        payload = json.load(f)
    return dict(payload.get("days") or {})


def save(days: Dict[str, List], path: Path = DATA_FILE) -> None:
    """先寫暫存檔再換名。"""
    payload = {"version": FILE_VERSION, "days": dict(sorted(days.items()))}
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    os.replace(tmp, path)
