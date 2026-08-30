"""
night_profile.py — 把原始數據整理成「事實清單」餵給模型

═══════════════════════════════════════════════════════════════════
核心設計原則：Python 判斷，模型只負責敘事
═══════════════════════════════════════════════════════════════════
**絕對不要**把原始 JSON 丟給模型讓它自己解讀。所有「這個數字好不好」的判斷
都留在 Python，用已經有文獻依據的門檻算好，再把「數值 + 結論」一起餵過去。

為什麼：這樣所有價值判斷仍可追溯到 Hirshkowitz / Hertenstein / Ohayon 那層
規則式評分，模型只決定「怎麼說」不決定「好不好」。口試要用的稽核鏈才保得住。

而且門檻值是**直接 import 評分程式的常數**，不是抄一份過來——
抄一份的話，哪天有人改了評分權重，AI 講的參考範圍就會跟分數對不上，
而那種不一致沒有任何測試抓得到。

═══════════════════════════════════════════════════════════════════
跨夜趨勢：AI 真正的價值來源
═══════════════════════════════════════════════════════════════════
規則式 recommendation 一次只看一晚，46 晚只產生了 8 種不同字串。
它看不到「你這週的心率比前一個月高了 13 下」這種事，因為那需要比較多晚。
這一段是 AI 能補上、而規則式做不到的部分。
"""

import json
import statistics
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).parent.parent
GARMIN_DATA = ROOT / "garmin" / "data"

# ── 從評分層取用文獻門檻（單一事實來源）──────────────────────────
# garmin/evaluate_sleep_quality.py 只用標準庫，import 它不會多帶進任何相依套件。
# 這跟 env_utils.py 刻意複製的判斷標準一致：看的是「會不會多帶進第三方相依」。
sys.path.insert(0, str(ROOT / "garmin"))
from evaluate_sleep_quality import (  # noqa: E402
    DEEP_RANGE,
    DURATION_RANGE,
    EFFICIENCY_FAIR,
    EFFICIENCY_GOOD,
    REM_RANGE,
    WASO_THRESHOLD,
)

# 攝影機資料的單一事實來源。只用標準庫，import 它不會多帶進任何相依套件。
sys.path.insert(0, str(ROOT))
import tapo_index  # noqa: E402

RECENT_WINDOW = 7    # 「近期」= 最近 7 晚
BASELINE_WINDOW = 28  # 「先前」= 再往前 28 晚
MIN_SAMPLES = 3       # 兩個窗格各至少要有這麼多晚才敢講趨勢

# 攝影機首事件早於手錶入睡多久之內，還算得上是「上床時刻」。
#
# ⚠️ 這是**呈現層的閘門，不是計分門檻**——它決定要不要把那句話寫成
#    「這可以當上床時刻」，不影響任何分數，所以不需要文獻依據
#    （本專案「每項計分都要有引文」那條紀律管的是進 total_modifier 的東西）。
#    值取 120 分鐘：實測 5 個可用夜晚落在 30–98 分鐘，08-06 的 136 分與
#    08-18 的 244 分則明顯是「人在房間裡走動」而不是上床。
BEDTIME_PLAUSIBLE_MINUTES = 120


def load_nights():
    """讀 features + quality_final 並依日期合併，回傳依日期排序的清單。"""
    features = _load(GARMIN_DATA / "garmin_sleep_features.json")
    quality = _load(GARMIN_DATA / "garmin_sleep_quality_final.json")

    by_date = {row["date"]: dict(row) for row in features}
    for row in quality:
        by_date.setdefault(row["date"], {"date": row["date"]}).update(row)

    return [by_date[key] for key in sorted(by_date)]


def _load(path: Path):
    if not path.exists():
        sys.exit(
            f"\u2717 {path.relative_to(ROOT).as_posix()} not found.\n"
            "  Run this first: python garmin/run_pipeline.py"
        )
    with path.open(encoding="utf-8") as f:
        return json.load(f)


# ═══════════════════════════════════════════════════════════════════
# 當晚判讀
# ═══════════════════════════════════════════════════════════════════

def _judge_duration(hours, band):
    low, high = DURATION_RANGE.get(band, DURATION_RANGE["young_adult"])
    if hours is None:
        return None
    if hours < low:
        return f"Sleep duration {hours:.1f} h, below the recommended {low:.0f}-{high:.0f} h"
    if hours > high:
        return f"Sleep duration {hours:.1f} h, above the recommended {low:.0f}-{high:.0f} h"
    return f"Sleep duration {hours:.1f} h, within the recommended {low:.0f}-{high:.0f} h"


def _judge_efficiency(value):
    if value is None:
        return None
    if value >= EFFICIENCY_GOOD:
        verdict = f"good (>={EFFICIENCY_GOOD:.0f}%)"
    elif value >= EFFICIENCY_FAIR:
        verdict = f"fair ({EFFICIENCY_FAIR:.0f}-{EFFICIENCY_GOOD - 0.1:.0f}%)"
    else:
        verdict = f"low (<{EFFICIENCY_FAIR:.0f}%)"
    # 誠實標註：缺「上床時間」，分母是（起床 − 入睡），不是臨床真效率
    return f"Sleep efficiency {value:.1f}%, {verdict} (sleep-period efficiency; excludes sleep-onset latency)"


def _judge_waso(minutes, band):
    if minutes is None:
        return None
    good, fair = WASO_THRESHOLD.get(band, WASO_THRESHOLD["young_adult"])
    if minutes <= good:
        return f"Time awake at night {minutes:.0f} min, in the good range (<={good:.0f} min)"
    if minutes <= fair:
        return f"Time awake at night {minutes:.0f} min, fair ({good:.0f}-{fair:.0f} min)"
    return f"Time awake at night {minutes:.0f} min, long (>{fair:.0f} min)"


def _judge_deep(ratio):
    if ratio is None:
        return None
    pct = ratio * 100
    low, high = DEEP_RANGE
    inside = "within" if low <= pct <= high else ("below" if pct < low else "above")
    return f"Deep sleep {pct:.1f}%, {inside} the {low:.0f}-{high:.0f}% reference range"


def _judge_rem(ratio, minutes, band):
    """
    ⚠️ 這一段不能省，也不能簡化成「REM 0%」。

    46 晚裡有 11 晚 rem_ratio = 0，原因是 Vivoactive 3 這支舊錶偵測不到 REM，
    不是使用者真的沒有 REM 睡眠。若把 0 直接餵給模型，它會寫出
    「你昨晚完全沒有做夢」——那是資料明確不支持的宣稱。
    """
    if minutes in (None, 0) or ratio in (None, 0):
        return "REM: not measured (a watch detection limit; it does not mean there was no REM sleep)"
    pct = ratio * 100
    low, high = REM_RANGE.get(band, REM_RANGE["young_adult"])
    inside = "within" if low <= pct <= high else ("below" if pct < low else "above")
    return f"REM sleep {pct:.1f}%, {inside} the {low:.0f}-{high:.0f}% reference range"


def _tonight_facts(night):
    band = night.get("age_band") or "young_adult"
    lines = [
        _judge_duration(night.get("sleep_duration_hours"), band),
        _judge_efficiency(night.get("sleep_efficiency")),
        _judge_waso(night.get("waso_minutes"), band),
        _judge_deep(night.get("deep_ratio")),
        _judge_rem(night.get("rem_ratio"), night.get("rem_minutes"), band),
    ]
    score = night.get("final_score")
    quality = night.get("final_quality")
    if score is not None:
        lines.append(f"Overall rating: {quality} ({score} points)")
    return [line for line in lines if line]


# ═══════════════════════════════════════════════════════════════════
# 跨夜趨勢
# ═══════════════════════════════════════════════════════════════════

def _median_of(nights, field):
    values = [n[field] for n in nights if n.get(field) is not None]
    return statistics.median(values) if len(values) >= MIN_SAMPLES else None


def _trend_line(label, recent, baseline, unit, digits=1):
    if recent is None or baseline is None:
        return None
    delta = recent - baseline
    if abs(delta) < 0.05:
        return None
    direction = "up" if delta > 0 else "down"
    return (
        f"{label}: median over the last {RECENT_WINDOW} nights {recent:.{digits}f}{unit}, "
        f"versus {baseline:.{digits}f}{unit} over the {BASELINE_WINDOW} nights before that "
        f"({direction} {abs(delta):.{digits}f})"
    )


def _trend_facts(nights, target_date):
    """比較「近 7 晚」與「再往前 28 晚」的中位數。"""
    history = [n for n in nights if n["date"] <= target_date]
    recent = history[-RECENT_WINDOW:]
    baseline = history[-(RECENT_WINDOW + BASELINE_WINDOW):-RECENT_WINDOW]

    if len(recent) < MIN_SAMPLES or len(baseline) < MIN_SAMPLES:
        return ["(Not enough nights yet to compare recent values against earlier ones.)"]

    lines = [
        _trend_line(
            "Sleep-period average heart rate",
            _median_of(recent, "avg_heart_rate"),
            _median_of(baseline, "avg_heart_rate"),
            " bpm",
        ),
        _trend_line(
            "Resting heart rate",
            _median_of(recent, "resting_heart_rate"),
            _median_of(baseline, "resting_heart_rate"),
            " bpm",
            digits=0,
        ),
        _trend_line(
            "Stress score",
            _median_of(recent, "avg_stress_score"),
            _median_of(baseline, "avg_stress_score"),
            " points",
        ),
        _trend_line(
            "Sleep score",
            _median_of(recent, "final_score"),
            _median_of(baseline, "final_score"),
            " points",
        ),
    ]
    lines = [line for line in lines if line]

    # 配戴率：手錶沒戴的日子在資料裡根本不會出現，所以要用日曆天數當分母
    wear = _wear_rate(recent, target_date)
    if wear:
        lines.append(wear)

    return lines or ["(No clear change in recent values compared with earlier ones.)"]


def _wear_rate(recent, target_date):
    if not recent:
        return None
    span_days = (date.fromisoformat(target_date)
                 - date.fromisoformat(recent[0]["date"])).days + 1
    if span_days <= 0:
        return None
    rate = len(recent) / span_days * 100
    if rate >= 95:
        return None  # 天天有戴，不用特別講
    return (
        f"Wear: sleep was recorded on {len(recent)} of the last {span_days} nights "
        f"(about {rate:.0f}%)"
    )


# ═══════════════════════════════════════════════════════════════════
# 攝影機（TAPO）
# ═══════════════════════════════════════════════════════════════════

def _bedtime_line(night, cam):
    """
    攝影機首事件 vs 手錶入睡時刻。**這是攝影機唯一手錶量不到的東西。**

    三種結果分開講，因為它們的成因完全不同，混為一談會讓報告寫錯：
      早於入睡且在合理範圍   → 可以當上床時刻用
      早太多                → 攝影機分不出「上床」與「醒著在房裡走動」
      晚於入睡              → 攝影機那時還沒開機（SLEEP_START 設定問題）
    """
    onset_raw = night.get("sleep_start_time")
    if not onset_raw:
        return ("Watch sleep-onset time is not available for this night, so the "
                "camera's first event cannot be interpreted as a bedtime.")
    try:
        onset = datetime.fromisoformat(onset_raw).replace(tzinfo=None)
    except (TypeError, ValueError):
        return None

    first = cam["camera_first"]
    minutes = (first - onset).total_seconds() / 60
    clock = first.strftime("%H:%M")

    if minutes > 0:
        return (f"The camera's first event ({clock}) is {minutes:.0f} min AFTER the "
                f"watch's sleep onset ({onset.strftime('%H:%M')}), so the camera was "
                f"not yet recording when the user went to bed and did not capture "
                f"bedtime. [MEASURED, BUT NOT A BEDTIME]")
    if -BEDTIME_PLAUSIBLE_MINUTES <= minutes < 0:
        return (f"First in-bed movement {clock}, {abs(minutes):.0f} min before the "
                f"watch's sleep onset ({onset.strftime('%H:%M')}) - within a normal "
                f"sleep-onset latency, so this can be read as the time the user "
                f"settled into bed. [MEASURED]")
    return (f"The camera's first event ({clock}) is {abs(minutes):.0f} min before the "
            f"watch's sleep onset ({onset.strftime('%H:%M')}) - too far ahead to be "
            f"the moment of getting into bed. The camera cannot tell 'got into bed' "
            f"from 'awake and moving around the room'. [MEASURED, BUT NOT A BEDTIME]")


def _camera_facts(night, cam):
    """
    那一晚攝影機的事實 —— **每個欄位都輸出**，各自帶可信度標籤。

    為什麼全部給：先篩掉會讓「攝影機到底量到什麼」在 prompt 裡完全不可見。
    標籤讓模型知道哪一個能講、哪一個只是背景。標籤來自
    tapo_index.provenance()，不是在這裡各自判斷——那樣會漂移。

    ⚠️ 標成 SIMULATED 的值仍然會進 prompt，但 generate_advice.validate()
       另有一條硬檢查擋它們出現在輸出裡。只靠 prompt 指示不夠：
       這個專案已經三次踩到「驗證規則安靜失效」。
    """
    if cam is None:
        return ["No camera data for this night (the camera was not recording, or "
                "its recording could not be matched to this night)."]

    first, last = cam["camera_first"], cam["camera_last"]
    lines = [
        f"Camera recorded {first.strftime('%H:%M')}-{last.strftime('%H:%M')}, "
        f"{cam['total_events']} motion events. [MEASURED - times come from the "
        f"video filenames, which are the only trustworthy timestamps in this data]"
    ]

    # 不是一夜的睡眠（白天測試錄影、或翻身頻率不合生理）。
    # ⚠️ 仍然寫進 prompt——使用者要求所有資料都進去，而且「這一晚的攝影機
    #    紀錄不能用」本身就是模型該知道的事實，只是要標明它的等級。
    problem = tapo_index.sleep_recording_problem(cam)
    if problem:
        lines.append(f"This recording cannot be read as a night's sleep: "
                     f"{problem}. [NOT A SLEEP RECORDING]")
        return lines

    bedtime = _bedtime_line(night, cam)
    if bedtime:
        lines.append(bedtime)

    lines.append(
        f"Event counts: {cam['large_turn_count']} large turns, "
        f"{cam['micro_motion_count']} micro-motions. [MEASURED, BUT NOT COMPARABLE "
        f"ACROSS NIGHTS - the counts depend on detector settings that changed "
        f"between recordings]"
    )

    scores = ", ".join(f"{score}" for _, score in cam["scores"]) or "none recorded"
    score_line = (f"Camera sleep-quality score: {scores}. [NOT MEASUREMENT-GRADE - "
                  f"this score is a function of how long the event list is, not of "
                  f"how the user slept]")
    if cam["score_disagreement"]:
        score_line += (f" The two data sources for this same night disagree by "
                       f"{cam['score_disagreement']} points.")
    lines.append(score_line)

    if cam["decibel_min"] is not None:
        lines.append(
            f"Snore count {cam['snore_count']}, sound level "
            f"{cam['decibel_min']}-{cam['decibel_max']} dB. [SIMULATED - there is no "
            f"microphone; these are random numbers. Never mention them.]"
        )
    return lines


# ═══════════════════════════════════════════════════════════════════
# 對外介面
# ═══════════════════════════════════════════════════════════════════

def build_profile(target_date, nights):
    """組出某一晚的完整事實清單。找不到該晚回傳 None。"""
    night = next((n for n in nights if n["date"] == target_date), None)
    if night is None:
        return None

    # ⚠️ 依日期查，不是「載入唯一那份報告」。
    #    改之前這裡不傳日期，一旦讀成功會把同一份攝影機報告掛到全部 51 晚上。
    cam = tapo_index.get_index().get(target_date)
    sources = ["garmin"] + (["tapo"] if cam else [])

    return {
        "date": target_date,
        "final_score": night.get("final_score"),
        "final_quality": night.get("final_quality"),
        "rem_unmeasured": not night.get("rem_minutes"),
        "tonight": _tonight_facts(night),
        "trends": _trend_facts(nights, target_date),
        "camera": _camera_facts(night, cam),
        "recommendation": night.get("recommendation") or "",
        "modifier_note": night.get("modifier_note") or "",
        "data_sources": sources,
        "camera_raw": cam,
        "raw": night,
    }


def format_facts(profile):
    """把事實清單排版成要放進 prompt 的文字區塊。"""
    parts = [
        f"DATE: {profile['date']}",
        "",
        "TONIGHT:",
        *(f"- {line}" for line in profile["tonight"]),
        "",
        "RECENT TRENDS (the rule-based score cannot see this layer; it looks at one night at a time):",
        *(f"- {line}" for line in profile["trends"]),
        "",
        "RULE-BASED RECOMMENDATION, VERBATIM (this is the source of truth; your advice must not contradict it):",
        profile["recommendation"] or "(none)",
    ]
    if profile["modifier_note"]:
        parts += ["", "DATA STATUS NOTE:", profile["modifier_note"]]

    # ⚠️ CAMERA 區塊在「有」與「沒有」兩種情形都要輸出。
    #    改之前只有「沒有」那一支會寫進 prompt——攝影機真的有資料時，
    #    模型反而什麼都看不到。
    parts += [
        "",
        "CAMERA (a second device. The tag in brackets says how far each value can "
        "be trusted; anything tagged SIMULATED or NOT MEASUREMENT-GRADE is "
        "background only and must never appear in your output):",
        *(f"- {line}" for line in profile["camera"]),
    ]
    return "\n".join(parts)
