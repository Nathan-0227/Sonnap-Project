"""
garmin/sleep_stages.py

把 garmin_standard_data.json 裡一晚的「睡眠階段紀錄」還原成一段一段的時間軸，
給 App 首頁的 Sleep Stages 圖用（2026-11-12）。**純函式，只呈現、不計分。**

原始資料長這樣（見 garmin_connect_fetch.py 寫入的那兩段）：

  ① 每一段真的時間段：  (段起點, "sleep_stage", 階段) ＋ (段起點, "sleep_segment_start")
  ② 整晚的摘要：在**入睡時刻**對每個階段各寫一筆
       (入睡時刻, "sleep_stage", 階段) ＋ (入睡時刻, "{階段}_duration_sec", 秒數)

⚠️ ② 不是時間段。不排除的話，入睡那一刻會多出四段長度 0 的「rem/deep/light/awake」，
   而如果第一段真的時間段剛好也從入睡時刻開始，同一個時刻會有兩筆同樣的階段——
   所以排除是「按次數扣掉」：那個時刻有幾筆 *_duration_sec，就扣掉幾筆同階段的紀錄。

每一段的結束 = 下一段的起點；最後一段結束在起床時刻。
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Iterable

STAGES = ("deep", "light", "rem", "awake")

# 第一段常常比 Garmin 給的「入睡時刻」早一兩分鐘開始（實測 11-02：段起點 03:52、入睡 03:53）。
# 嚴格只收入睡之後的段，會把那整段（51 分鐘淺睡）丟掉。所以入睡前這麼久以內開始的段也收，
# 再把起點夾到入睡時刻。不能放太寬：入睡前不久的午睡段會被誤接進來。
EARLY_START_TOLERANCE = timedelta(minutes=15)


def _parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts)


def stage_segments(records: Iterable[dict], sleep_start: str, wake_time: str) -> list[dict]:
    """回傳 [{"stage", "start", "end"}, ...]，依時間排序，只含 [入睡, 起床] 之間的段。

    [records] 是 garmin_standard_data.json 的 records（可以是整份，會自己篩時間）。
    [sleep_start]、[wake_time] 是 ISO8601（+08:00）。
    """
    start = _parse(sleep_start)
    end = _parse(wake_time)
    if end <= start:
        return []

    # 先找出摘要紀錄：(時刻, 階段) → 要扣掉幾筆
    summary: dict[tuple[str, str], int] = {}
    stage_rows = []
    for r in records:
        metric = r.get("metric")
        ts = r.get("timestamp")
        if not ts:
            continue
        if metric == "sleep_stage":
            stage_rows.append(r)
        elif isinstance(metric, str) and metric.endswith("_duration_sec"):
            stage = metric[: -len("_duration_sec")]
            if stage in STAGES:
                key = (ts, stage)
                summary[key] = summary.get(key, 0) + 1

    starts: dict[datetime, str] = {}
    for r in stage_rows:
        ts, stage = r["timestamp"], r.get("value")
        if stage not in STAGES:
            continue
        key = (ts, stage)
        if summary.get(key, 0) > 0:
            summary[key] -= 1
            continue
        t = _parse(ts)
        if start - EARLY_START_TOLERANCE <= t < end:
            starts[t] = stage

    ordered = sorted(starts.items())
    segments = []
    for i, (t, stage) in enumerate(ordered):
        seg_end = ordered[i + 1][0] if i + 1 < len(ordered) else end
        seg_start = max(t, start)  # 早開始的段夾到入睡時刻
        if seg_end <= seg_start:
            continue
        segments.append({
            "stage": stage,
            "start": seg_start.isoformat(),
            "end": seg_end.isoformat(),
        })
    return segments


def stage_minutes(segments: list[dict]) -> dict[str, int]:
    """每個階段加總幾分鐘（四捨五入）。"""
    total = {s: 0.0 for s in STAGES}
    for seg in segments:
        total[seg["stage"]] += (_parse(seg["end"]) - _parse(seg["start"])).total_seconds() / 60
    return {s: round(v) for s, v in total.items()}
