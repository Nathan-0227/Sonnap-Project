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


DAY_BUCKET_MINUTES = 10


def day_heart_rate(records: Iterable[dict], day: str, tz: str = "+08:00") -> Optional[dict]:
    """一整個日曆日（00:00–24:00）的心率曲線，每 10 分鐘一點；外加那天的靜止心率。

    首頁 Activity 卡的「整天心率」（2026-11-13 使用者定）。**只呈現、不給 Normal／High。**
    - 最低／最高從那天的原始讀數（每 2 分鐘）算，跟曲線同一份資料。
    - 靜止心率是 Garmin 每天一個數字（resting_heart_rate 紀錄，時間戳落在那一天）。
    ⚠️ 整天的心率**算不出 HRV**：HRV 要每一下心跳之間的毫秒間隔，手錶只存 2 分鐘平均。
    """
    try:
        start = datetime.fromisoformat(f"{day}T00:00:00{tz}")
    except ValueError:
        return None
    # ⚠️ _curve 的終點是**含**的：用 24:00 會把隔天 00:00 那一筆也收進來（測試抓到過）
    end = start + timedelta(days=1) - timedelta(seconds=1)
    records = list(records)
    curve = _curve(records, "heart_rate", start.isoformat(), end.isoformat(),
                   DAY_BUCKET_MINUTES, digits=0)
    if curve is None:
        return None
    resting = None
    for r in records:
        if r.get("metric") == "resting_heart_rate" and str(r.get("timestamp", "")).startswith(day):
            v = r.get("value")
            if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0:
                resting = round(v)
    curve["resting"] = resting
    return curve


# 2026-11-15 使用者定（早晨報告 Stress 點開的「一整天的壓力線」）：Garmin 本來就每 3 分鐘一筆，
# 用 3 分鐘的格子＝每一筆原始讀數一格，不平均掉尖峰。
STRESS_BUCKET_MINUTES = 3


def day_stress(records: Iterable[dict], day: str, tz: str = "+08:00") -> Optional[dict]:
    """一整個日曆日的壓力線（0–100，Garmin 的分數）。量不到的時候（在動、沒戴錶）就沒有那一點，
    App 斷開不連線。avg／min／max 從原始讀數算。**只呈現，不判斷**（不寫 Elevated、不用紅黃）。"""
    try:
        start = datetime.fromisoformat(f"{day}T00:00:00{tz}")
    except ValueError:
        return None
    end = start + timedelta(days=1) - timedelta(seconds=1)
    return _curve(list(records), "stress_score", start.isoformat(), end.isoformat(),
                  STRESS_BUCKET_MINUTES, digits=0)


def stress_day_averages(records: Iterable[dict]) -> dict:
    """每個日曆日（照讀數自己的牆鐘日期）的平均壓力，一次掃完。負數＝沒有值，不算。"""
    sums: dict = {}
    for r in records:
        if r.get("metric") != "stress_score":
            continue
        v, ts = r.get("value"), str(r.get("timestamp") or "")
        if not isinstance(v, (int, float)) or isinstance(v, bool) or v < 0 or len(ts) < 10:
            continue
        s = sums.setdefault(ts[:10], [0.0, 0])
        s[0] += v
        s[1] += 1
    return {d: round(t / n) for d, (t, n) in sums.items() if n}


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
         "min_at": 最低那一筆原始讀數的時刻（同一個值出現好幾次取最早的）,
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
    # 最低那一刻用**原始讀數**（2026-11-15 早晨報告心率點開「Lowest 46 at 03:48」）：
    # 5 分鐘平均的最低點會跟 min 對不上
    low_t, _ = min(sorted(readings), key=lambda tv: tv[1])
    return {
        "points": points,
        "avg": rnd(sum(values) / len(values)),
        "min": rnd(min(values)),
        "max": rnd(max(values)),
        "min_at": low_t.isoformat(),
        "bucket_minutes": bucket_minutes,
    }


# ── 醒著的心率（2026-11-15 使用者定：早晨報告 Yesterday 的 Awake HR） ──
#
# 那一個日曆日裡**扣掉睡著的時段**之後的心率：平均、最高（含時刻）、各區間幾分鐘。
# 睡著那段已經在上面的 Sleeping HR，這裡不重複；**不放靜止心率、不放最低**（使用者定，
# 靜止心率在報告上半部已經有了）。
#
# 🔴 不寫 Normal／High、不比「平常」：Research-Background/心率門檻.md 查過，醒著的平均心率
#    沒有結果關聯的切點（把臨床「>80」套上去，本人 76 天裡 47 天會被標 High），而它主要
#    取決於那天走了多少路，跟自己平常比也沒有意義。區間只寫「幾分鐘」，不說哪一區好。
#
# 區間是 **Garmin Connect 裡本人的設定**（2026-11-15 讀到：方法 HR_MAX、最大心率 199，
# 五區下緣 100／119／139／159／179＝最大心率的 50／60／70／80／90%）。不是文獻門檻，
# 是手錶 App 自己用的區間，App 照寫「max 199」讓人知道是哪一把尺。
# ⚠️ 只對本人（wearer_c）成立；換人戴要重讀 Garmin 的設定。
GARMIN_HR_ZONES = {"max": 199, "floors": [100, 119, 139, 159, 179]}

# 手錶每 2 分鐘一筆心率：一筆＝2 分鐘（區間時間這樣換算）
HR_READING_MINUTES = 2

# 醒著的讀數少於 1 小時就不給（只戴了一下子，平均沒有代表性）
AWAKE_MIN_READINGS = 30


def _spans_from_quarters(quarters, day_start):
    """96 格的 [程度, 步數]：程度是 sleep 的那幾格 → [(起, 迄)]。"""
    out = []
    for i, q in enumerate(quarters or []):
        if isinstance(q, (list, tuple)) and q and q[0] == "sleep":
            s = day_start + timedelta(minutes=15 * i)
            out.append((s, s + timedelta(minutes=15)))
    return out


def _merge_spans(spans):
    spans = sorted(spans)
    out = []
    for s, e in spans:
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out


def awake_heart_rate(
    records: Iterable[dict],
    day: str,
    sleep_windows: Iterable = (),
    quarters=None,
    zones: Optional[dict] = None,
    tz: str = "+08:00",
) -> Optional[dict]:
    """那個日曆日醒著的心率。資料不夠（醒著的讀數 < 1 小時）回 None。

    睡著＝下面兩個的聯集（都裁到這一天之內）：
    - sleep_windows：手錶的入睡 → 起床（跨進這天的那兩晚，同 Sleeping HR 用的那一段）
    - quarters：Garmin 每 15 分鐘的活動程度裡標成 sleep 的格子（補午睡、補沒有那一晚資料的時候）

    回傳：
        {"avg", "max", "max_at",                       ← 只從醒著的讀數算
         "readings": [{"t", "value"}, …],              ← 那天**全部**原始讀數（含睡著），App 畫整天的線
         "asleep": [{"start", "end"}, …],              ← 睡著的時段，App 把那段畫淡
         "zones": {"max", "floors", "minutes": [低於 1 區, 1 區, …, 5 區]} 或 None}
    """
    try:
        start = datetime.fromisoformat(f"{day}T00:00:00{tz}")
    except ValueError:
        return None
    end = start + timedelta(days=1)

    spans = []
    for w in sleep_windows or ():
        s, e = (_parse(w[0]), _parse(w[1])) if w else (None, None)
        if s is None or e is None or s.tzinfo is None or e.tzinfo is None or e <= s:
            continue
        s, e = max(s, start), min(e, end)
        if s < e:
            spans.append((s, e))
    spans = _merge_spans(spans + _spans_from_quarters(quarters, start))

    def asleep(t):
        return any(s <= t < e for s, e in spans)

    readings = []
    for r in records:
        if r.get("metric") != "heart_rate":
            continue
        t, v = _parse(r.get("timestamp")), r.get("value")
        if t is None or t.tzinfo is None or not isinstance(v, (int, float)) or isinstance(v, bool):
            continue
        if v <= 0 or not (start <= t < end):
            continue
        readings.append((t, float(v)))
    readings.sort(key=lambda tv: tv[0])
    awake = [(t, v) for t, v in readings if not asleep(t)]
    if len(awake) < AWAKE_MIN_READINGS:
        return None

    values = [v for _, v in awake]
    top_t, top_v = max(awake, key=lambda tv: (tv[1], -tv[0].timestamp()))  # 同值取最早
    zone_out = None
    if zones and zones.get("floors"):
        floors = list(zones["floors"])
        minutes = [0] * (len(floors) + 1)
        for v in values:
            minutes[sum(1 for f in floors if v >= f)] += HR_READING_MINUTES
        zone_out = {"max": zones.get("max"), "floors": floors, "minutes": minutes}
    return {
        "avg": round(sum(values) / len(values)),
        "max": round(top_v),
        "max_at": top_t.isoformat(),
        "readings": [{"t": t.isoformat(), "value": round(v)} for t, v in readings],
        "asleep": [{"start": s.isoformat(), "end": e.isoformat()} for s, e in spans],
        "zones": zone_out,
    }
