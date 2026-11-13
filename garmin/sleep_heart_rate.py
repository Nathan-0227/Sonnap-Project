"""一晚睡著期間的心率與手錶動作曲線（2026-11-13，Sleep Stages 卡上點 Heart rate／Movement 疊上去的線）。
**只呈現、不計分。**（動作那條同 CLAUDE.md「movement 永不進評分」。）

從 garmin_standard_data.json 的 heart_rate 紀錄（手錶每 2 分鐘一筆）取入睡 → 起床那一段，
每 5 分鐘取平均當一個點。純函式，`tests/test_sleep_heart_rate.py` 守著。

⚠️ 平均、最低都從**這一段**算，不用 wearable_nightly.avg_hr：那個欄位把睡眠區間與
   起床日其餘時段的讀數混在一起（CLAUDE.md「四個名字會騙人的欄位」），跟曲線放在一起
   會出現兩個不同的「平均心率」。
⚠️ 不給 Normal／High 之類的判斷：夜間心率沒有文獻門檻（紅線 2）。
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Iterable, Optional

BUCKET_MINUTES = 5

# 點太少就不畫（例如手錶只記到幾分鐘）：一條只有兩三點的線比沒有更容易被讀錯
MIN_POINTS = 6


def _parse(ts: str) -> Optional[datetime]:
    try:
        return datetime.fromisoformat(ts)
    except (TypeError, ValueError):
        return None


def heart_rate_curve(
    records: Iterable[dict],
    sleep_start: str,
    wake_time: str,
    bucket_minutes: int = BUCKET_MINUTES,
) -> Optional[dict]:
    """心率（bpm，整數）。見 _curve。"""
    return _curve(records, "heart_rate", sleep_start, wake_time, bucket_minutes, digits=0)


def movement_curve(
    records: Iterable[dict],
    sleep_start: str,
    wake_time: str,
    bucket_minutes: int = BUCKET_MINUTES,
) -> Optional[dict]:
    """手錶的動作量（Garmin 每分鐘一筆，**沒有單位的相對值**，約 0–4）。見 _curve。

    ⚠️ 沒有單位，所以 App 的軸只寫 More／Less，不寫數字；也不判斷動得多是好是壞。
    """
    return _curve(records, "movement", sleep_start, wake_time, bucket_minutes, digits=2)


def _curve(
    records: Iterable[dict],
    metric: str,
    sleep_start: str,
    wake_time: str,
    bucket_minutes: int,
    digits: int,
) -> Optional[dict]:
    """入睡 → 起床之間某一項的曲線。資料不夠就回 None。

    回傳：
        {"points": [{"t": ISO 牆鐘時間, "value": 數字}, …],
         "avg": 睡著期間平均, "min": 最低, "max": 最高,
         "bucket_minutes": 5}
    數字四捨五入到 digits 位（心率 0 位＝整數）。
    t 是每一格的起點，與 sleep_start 同一個時區標記（App 用 parseWallClock 讀）。
    """
    start, wake = _parse(sleep_start), _parse(wake_time)
    if start is None or wake is None or wake <= start:
        return None

    readings = []
    for r in records:
        if r.get("metric") != metric:
            continue
        t = _parse(r.get("timestamp"))
        v = r.get("value")
        if t is None or not isinstance(v, (int, float)) or isinstance(v, bool):
            continue
        # 心率 0 或負數是沒有讀數；動作 0 是「沒動」，是真的值
        if (v <= 0) if metric == "heart_rate" else (v < 0):
            continue
        # 時區標記不同（理論上不會）就換成同一個再比
        if (t.tzinfo is None) != (start.tzinfo is None):
            continue
        if start <= t <= wake:
            readings.append((t, float(v)))
    if not readings:
        return None

    step = timedelta(minutes=bucket_minutes)
    buckets: dict[int, list[float]] = {}
    for t, v in readings:
        buckets.setdefault(int((t - start) / step), []).append(v)
    def rnd(x: float):
        return round(x) if digits == 0 else round(x, digits)

    points = [
        {"t": (start + step * i).isoformat(), "value": rnd(sum(vs) / len(vs))}
        for i, vs in sorted(buckets.items())
    ]
    if len(points) < MIN_POINTS:
        return None

    values = [v for _, v in readings]
    return {
        "points": points,
        "avg": rnd(sum(values) / len(values)),
        "min": rnd(min(values)),
        "max": rnd(max(values)),
        "bucket_minutes": bucket_minutes,
    }
