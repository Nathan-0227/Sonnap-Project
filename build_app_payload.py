"""
build_app_payload.py

把各子系統的產出組成 App 要吃的**單一** payload 檔。

═══════════════════════════════════════════════════════════════════
這支腳本在整條資料流的哪個位置
═══════════════════════════════════════════════════════════════════

    garmin/data/garmin_sleep_quality_final.json ─┐
    garmin/data/garmin_sleep_features.json      ─┤
    ai/data/ai_advice.json（有才用）             ─┼→ 本腳本
    app/sleep_report.json（過不了門檻就跳過）     ─┘      │
                                                          ▼
                                      app/assets/data/app_payload.json
                                                          │
                              ┌───────────────────────────┴──────────────┐
                              ▼                                          ▼
                Flutter 用 rootBundle 讀（bundled asset）    main.py 讀同一個檔對外服務

**為什麼只產一份檔，而不是 asset 一份、API 一份**
兩份就會出現「App 畫面顯示的」跟「API 回傳的」對不上這種最難查的 bug。
同一個檔案兩種讀法，結構上就不可能不一致。

**為什麼讀 JSON 不讀 CSV**
JSON 保留 null 與 0 的區別，而本專案正好在意這個差異：
rem_ratio「未測得」vs「為 0」、sri「無法計算」vs「等於 0」，語意完全不同。
CSV 會把兩者都寫成空字串或 0，資訊就沒了。

═══════════════════════════════════════════════════════════════════
設計原則：Python 判斷，Dart 只負責畫
═══════════════════════════════════════════════════════════════════
這是專案既有原則「Python 判斷，模型只負責敘事」的延伸。所有「這個分數
算好還是壞」「該顯示哪種心情」「該說哪句鼓勵的話」的判斷都留在這裡，
Flutter 只做渲染。理由跟 AI 那邊完全一樣：判斷邏輯集中在一處才可稽核，
也才不會前後端各自訂一套標準。

═══════════════════════════════════════════════════════════════════
使用方式
═══════════════════════════════════════════════════════════════════
    python build_app_payload.py                 # 用最新一晚
    python build_app_payload.py --date 2026-08-06   # 指定某一晚（除錯用）
"""

import argparse
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════
# 路徑：一律以本檔案位置為基準，從任何工作目錄執行都能正確定位
# （沿用 garmin/ 各腳本在 2026-08-11 整理時採用的作法）
# ═══════════════════════════════════════════════════════════════════
ROOT = Path(__file__).parent
GARMIN_DATA = ROOT / "garmin" / "data"
AI_DATA = ROOT / "ai" / "data"
OUTPUT_PATH = ROOT / "app" / "assets" / "data" / "app_payload.json"

# TAPO 單檔報告的候選位置。
#
# ⚠️ 2026-08-12 起 `app/sleep_report.json` 已刪除（它與 `tapo/` 那份是同一支程式
#    跑錯資料夾的複本）。剩下的 `tapo/sleep_report.json` 內容是 17:26 開始、
#    只有 29 秒的測試錄影，會被 load_tapo_report() 的白天時段門檻擋掉——
#    這是正確行為，不是 bug。
#
#    真正的整晚資料在 `tapo/sleep_reports/<日期>/sleep_report_*.json`（每夜一份），
#    尚未接入。接入時要注意那邊的 report_date 是「報告產生時間」不是「那一夜」，
#    日期必須從 video_clip 檔名取。
TAPO_REPORT_CANDIDATES = [
    ROOT / "tapo" / "sleep_report.json",
    ROOT / "app" / "sleep_report.json",  # 已刪除，留著讓舊 clone 仍能運作
]

SCHEMA_VERSION = 1
MAPPING_VERSION = 1  # pet_mood 映射表的版本，改映射規則時要 +1
HISTORY_NIGHTS = 30  # history 陣列帶幾晚

TZ_TAIPEI = timezone(timedelta(hours=8))  # 專案規範：時間一律 ISO8601 (+08:00)

# Windows 主控台預設編碼是 cp1252，印 ✓ / 中文會丟 UnicodeEncodeError。
# 這在 PowerShell 不會發生但在 Git Bash 會，而且崩潰點在寫檔之後——
# 檔案其實已經產生了，卻回傳非零 exit code，會讓 run_pipeline.py 誤判整條失敗。
# 加這一行讓輸出不受主控台編碼影響。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════
# pet_mood / energy_level 映射
# ═══════════════════════════════════════════════════════════════════
# ⚠️ 這張表是**待 PM 核可**的預設值，不是已議定的規格。
#    CLAUDE.md 把「分數 → pet_mood / energy_level 的映射」列為開放問題，
#    但一直空著的話 App 就永遠動不了，所以先實作一組有依據的預設值，
#    集中在這一個地方並標明待核可，而不是散落在 Dart 各處。
#
# README 定義的合法值只有四個：happy / tired / bored / anxious
QUALITY_TO_MOOD = {
    "Good": "happy",
    "Normal": "bored",
    "Poor": "tired",
    "Bad": "tired",
}

# anxious 的覆寫門檻。用 Tier3 的生理修正值而不是總分，理由：
# Tier3 量的正是「相對個人 baseline 的自律神經偏離」——壓力分數與心率
# 同時高於自己的常態，語意上就是焦慮，而這件事總分看不出來
# （總分可能因為睡得夠久而仍然不低）。
ANXIOUS_STRESS_THRESHOLD = -3.0  # stress_modifier 低於此值
ANXIOUS_HR_THRESHOLD = -3.0      # rhr_modifier + avg_hr_modifier 低於此值


# ═══════════════════════════════════════════════════════════════════
# UI 顯示字串
# ═══════════════════════════════════════════════════════════════════
# App 目前的 UI 是英文（"Great job!"、"Sweet dreams are waiting for us!"），
# 所以這裡產生的短字串也用英文，才不會在英文介面裡蹦出中文。
#
# ⚠️ 但 scoring.recommendation 維持中文原文不翻譯——它是規則式評分層的
#    產物、是事實來源，翻譯等於引入第二個版本。語言不一致的問題已寫進
#    PROJECT_STATUS 待團隊決定 i18n 方案（app 已經有 intl 套件）。
DISPLAY_STRINGS = {
    "Good": {
        "score_message": "Great job!",
        "mood_description": "Your buddy is feeling great!",
        "header_message": "Let's keep this rhythm going!",
        "pet_message": "Sweet dreams\nare waiting\nfor us! 🌙",
    },
    "Normal": {
        "score_message": "Not bad.",
        "mood_description": "Your buddy is a little restless.",
        "header_message": "Let's get a good night's sleep!",
        "pet_message": "Let's rest\na little\nearlier tonight.",
    },
    "Poor": {
        "score_message": "Rough one.",
        "mood_description": "Your buddy needs more rest.",
        "header_message": "Let's take it easy tonight.",
        "pet_message": "I could use\na longer\nnap today...",
    },
    "Bad": {
        "score_message": "Tough one.",
        "mood_description": "Your buddy is worn out.",
        "header_message": "Let's take it easy tonight.",
        "pet_message": "I could use\na longer\nnap today...",
    },
}

# ⚠️ score_message 有長度上限：SleepScoreCard 是固定 height: 150 的卡片，
#    文字超過約 10 個字元就會換行並撐破版面（實測 "Tough night." 會 overflow 15px，
#    "Tough one." 剛好放得下）。改這些字串時請一併跑 app/test/widget_test.dart。
MAX_SCORE_MESSAGE_CHARS = 10

# 讓上面那段註解不只是註解——加太長的字串會在 import 時就爆掉，
# 而不是等到有人打開 App 才看到黃黑斜線。
for _quality, _strings in DISPLAY_STRINGS.items():
    _message = _strings["score_message"]
    if len(_message) > MAX_SCORE_MESSAGE_CHARS:
        raise ValueError(
            f"DISPLAY_STRINGS[{_quality!r}]['score_message'] = {_message!r} "
            f"長度 {len(_message)} 超過 {MAX_SCORE_MESSAGE_CHARS}，"
            "會撐破 SleepScoreCard 的固定高度版面"
        )

# 分數環的顏色，跟著等級走（Flutter 端只做字串→Color 的查表，不做判斷）
QUALITY_TO_COLOR = {
    "Good": "#9AD36A",
    "Normal": "#FFC83D",
    "Poor": "#FF9518",
    "Bad": "#FF4F63",
}


def load_json(path: Path):
    """讀 JSON，檔案不存在回傳 None（呼叫端自己決定這是不是問題）。"""
    if not path.exists():
        return None
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def index_by_date(rows):
    """把 [{date: ...}, ...] 轉成 {date: row}，方便兩張表對齊。"""
    return {row["date"]: row for row in rows or []}


def map_pet_mood(quality_row):
    """
    依當晚的評分結果決定寵物心情。

    回傳 (mood, reason)。reason 會寫進 payload，讓 UI 上的心情可以追溯到
    是哪一條規則造成的——這跟評分系統一路以來「數字要能講出理由」是同一個要求。
    """
    quality = quality_row.get("final_quality")
    mood = QUALITY_TO_MOOD.get(quality, "bored")
    reason = f"final_quality={quality}"

    # 覆寫：生理訊號顯示自律神經明顯偏離個人 baseline
    # None 代表該項修正值因冷啟動或資料無效而未啟用，當 0 處理（不觸發覆寫）
    stress = quality_row.get("stress_modifier") or 0.0
    hr_total = (quality_row.get("rhr_modifier") or 0.0) + (
        quality_row.get("avg_hr_modifier") or 0.0
    )

    if stress <= ANXIOUS_STRESS_THRESHOLD:
        mood = "anxious"
        reason = f"stress_modifier={stress} ≤ {ANXIOUS_STRESS_THRESHOLD}"
    elif hr_total <= ANXIOUS_HR_THRESHOLD:
        mood = "anxious"
        reason = f"rhr+avg_hr modifier={hr_total} ≤ {ANXIOUS_HR_THRESHOLD}"

    return mood, reason


def compute_streak(quality_rows, latest_date):
    """
    算出 UI 的 Sleep Streak 卡要顯示的兩個數字。

    streak_days     = 到最新一晚為止，連續有睡眠記錄的夜數
    completed_days  = 最近 7 個日曆日內，final_quality 為 Good 或 Normal 的晚數
                      （對應 UI 上那 7 個圈）

    ⚠️ 實測資料下這兩個數字會偏小（46 晚有效 / 74 個日曆日，配戴斷斷續續）。
       這是誠實的結果，不要為了畫面好看而改定義——它剛好讓「起床後取下手錶」
       這個已知問題浮上檯面，而那正是專案目前最該解決的資料品質問題。
    """
    by_date = index_by_date(quality_rows)

    # 連續夜數：從最新一晚往回數，遇到缺口就停
    streak = 0
    cursor = latest_date
    while cursor.isoformat() in by_date:
        streak += 1
        cursor -= timedelta(days=1)

    # 最近 7 個日曆日（含最新一晚當天）
    window_start = latest_date - timedelta(days=6)
    completed = 0
    for iso, row in by_date.items():
        day = date.fromisoformat(iso)
        if window_start <= day <= latest_date:
            if row.get("final_quality") in ("Good", "Normal"):
                completed += 1

    return {
        "streak_days": streak,
        "completed_days": completed,
        "definition": (
            "streak_days = 到最新一晚為止連續有睡眠記錄的夜數；"
            "completed_days = 最近 7 個日曆日內評級為 Good 或 Normal 的晚數。"
            "手錶未配戴的夜晚不算在內，所以數字偏小反映的是配戴率而非睡眠品質。"
        ),
    }


def load_tapo_report():
    """
    載入 TAPO 攝影機的報告——**但只在資料真的可用時才回傳**。

    回傳 (data_or_None, note)。note 一定有值，會寫進 payload 讓「為什麼沒有
    攝影機資料」這件事對團隊可見，而不是安靜地消失。

    ⚠️ 光檢查檔案存在**不夠**。app/sleep_report.json 確實存在，但內容是廢的：
       - report_date 2026-06-11，timeline 從 15:47 開始 → 下午的測試錄影，不是整晚
       - motion_intensity 高達 2073600 = 正好 1920×1080 → 整個畫面都在動
       - 15 分鐘內 large_turn_count 301 → 平均每 3 秒翻身一次
       - sleep_quality_score 50 → 撞到 max(50, ...) 的地板
       把這種資料餵給使用者的建議，跟本專案一路的誠實標準直接衝突。

    ⚠️ decibel / snore_count 一律不採用，無論其他檢查過不過。
       那兩個欄位是 np.random 產生的（motion_detector.py 與 sleep_monitor.py
       都沒有麥克風、沒有音訊擷取），不是量測值。
    """
    path = next((p for p in TAPO_REPORT_CANDIDATES if p.exists()), None)
    if path is None:
        return None, "攝影機資料不可用：找不到 sleep_report.json"

    try:
        data = json.load(path.open(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return None, f"攝影機資料不可用：{path.name} 讀取失敗（{exc}）"

    timeline = data.get("timeline") or []
    if not timeline:
        return None, "攝影機資料不可用：timeline 為空"

    # 檢查一：時段。整段錄影都落在白天 → 是測試不是睡眠
    hours = {int(ev["time"].split(":")[0]) for ev in timeline if ev.get("time")}
    if hours and all(6 <= h < 20 for h in hours):
        return None, (
            f"攝影機資料不可用：{path.name} 的錄影時段全在白天"
            f"（{min(hours):02d}:00–{max(hours):02d}:59），研判為測試錄影而非整晚睡眠"
        )

    # 檢查二：翻身頻率。人一整晚翻身約 10–40 次，每小時超過 30 次不合生理
    summary = data.get("summary") or {}
    large_turns = summary.get("large_turn_count", 0)
    span_hours = max(len(hours), 1)
    if large_turns / span_hours > 30:
        return None, (
            f"攝影機資料不可用：{path.name} 偵測到每小時約 "
            f"{large_turns / span_hours:.0f} 次大翻身，超出生理合理範圍，"
            "研判動作偵測捕捉到的是整個畫面的變化而非人體翻身"
        )

    # 通過門檻：只取視覺類欄位，聲音類一律丟棄
    return {
        "report_date": data.get("report_date"),
        "large_turn_count": large_turns,
        "total_events": summary.get("total_events"),
    }, "攝影機資料已納入（僅視覺類欄位；分貝與打鼾為模擬值，一律不採用）"


def load_ai_advice(target_date, fallback_recommendation):
    """
    載入 AI 產生的建議。ai/ 還沒建立或該晚還沒生成時，優雅降級成規則式文字。

    降級後使用者**一點實質內容都沒少**，只少了語氣潤飾——因為 AI 的 advice
    本來就設計成「規則式文字的重新配音 + 跨夜趨勢」，而不是取代它。
    """
    advice_file = load_json(AI_DATA / "ai_advice.json")
    entry = None
    if advice_file:
        entry = (advice_file.get("entries") or {}).get(target_date)

    if entry and entry.get("source") == "llm":
        return {
            "advice": entry.get("advice"),
            "dream_summary": entry.get("dream_summary"),
            "trend_note": entry.get("trend_note"),
            "is_ai_generated": True,
            "content_type": "fiction+advice",
            "source": "llm",
            "model": entry.get("model"),
        }

    return {
        "advice": fallback_recommendation,
        "dream_summary": None,
        "trend_note": None,
        "is_ai_generated": False,
        "content_type": "advice",
        "source": "rule_based",
        "model": None,
    }


def build_payload(target_date=None):
    """組出完整 payload。找不到資料時丟 SystemExit，讓 pipeline 停在這裡。"""
    quality_rows = load_json(GARMIN_DATA / "garmin_sleep_quality_final.json")
    feature_rows = load_json(GARMIN_DATA / "garmin_sleep_features.json")

    if not quality_rows:
        sys.exit(
            "✗ 找不到 garmin/data/garmin_sleep_quality_final.json。\n"
            "  請先執行：python garmin/run_pipeline.py"
        )

    by_date_quality = index_by_date(quality_rows)
    by_date_features = index_by_date(feature_rows)

    # 挑出目標夜晚
    if target_date:
        if target_date not in by_date_quality:
            sys.exit(f"✗ 找不到 {target_date} 的評分資料。")
        night_iso = target_date
    else:
        night_iso = quality_rows[-1]["date"]

    quality = by_date_quality[night_iso]
    features = by_date_features.get(night_iso, {})
    night_date = date.fromisoformat(night_iso)

    mood, mood_reason = map_pet_mood(quality)
    final_score = quality.get("final_score")
    final_quality = quality.get("final_quality", "Normal")
    display = DISPLAY_STRINGS.get(final_quality, DISPLAY_STRINGS["Normal"])

    tapo, tapo_note = load_tapo_report()
    ai_content = load_ai_advice(night_iso, quality.get("recommendation"))

    data_sources = ["garmin"]
    if tapo:
        data_sources.append("tapo")

    streak = compute_streak(quality_rows, night_date)

    # history：最近 N 晚，給 Insights 頁之後接圖表用。
    # 現在還沒接 ReportScreen，但先帶著，之後接的時候不用再改後端。
    history = []
    for row in quality_rows[-HISTORY_NIGHTS:]:
        feat = by_date_features.get(row["date"], {})
        history.append(
            {
                "date": row["date"],
                "final_score": row.get("final_score"),
                "final_quality": row.get("final_quality"),
                "sleep_duration_hours": feat.get("sleep_duration_hours"),
            }
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "mapping_version": MAPPING_VERSION,
        "generated_at": datetime.now(TZ_TAIPEI).isoformat(timespec="seconds"),
        # ── 以下沿用團隊 README 議定的 data contract 頂層結構 ──
        # 刻意不另開一套格式：那份 contract 是全隊共識，該做的是擴充並提報 PM
        "session_id": f"{night_iso.replace('-', '')}_001",
        "status": {
            "pet_mood": mood,
            # current_activity 需要「此刻」的狀態，但本 pipeline 是隔日批次產出，
            # 給不出來。硬填一個值就是編造，所以留 null，App 端 fallback 到 idle 動畫。
            "current_activity": None,
            "energy_level": round(final_score) if final_score is not None else None,
            "mood_reason": mood_reason,
        },
        "metrics": {
            # ⚠️ README 定義 motion_count 是「翻身次數，由影像組提供」。
            #    Garmin 的 movement_count 是我們自訂的翻動取樣筆數，語意不同，
            #    CLAUDE.md 明訂「不該默默對映」。留 null 會讓這個缺口對 PM 可見；
            #    硬塞則會永久掩蓋它。真值另外放在下一個欄位，資訊不會遺失。
            "motion_count": None,
            "garmin_movement_samples": features.get("movement_count"),
            "sleep_duration_minutes": features.get("total_sleep_minutes"),
            # ⚠️ Garmin 手錶沒有環境音量這個數據；TAPO 的分貝是 np.random 產生的。
            #    兩個來源都給不出真值，所以留 null。
            "ambient_noise_db": None,
            "sleep_start_time": features.get("sleep_start_time"),
            "wake_time": features.get("wake_time"),
            "deep_minutes": features.get("deep_minutes"),
            "rem_minutes": features.get("rem_minutes"),
            "waso_minutes": features.get("waso_minutes"),
            "sleep_efficiency": features.get("sleep_efficiency"),
            "avg_heart_rate": features.get("avg_heart_rate"),
            "resting_heart_rate": features.get("resting_heart_rate"),
        },
        "ai_content": ai_content,
        # ── 以下是為了這個 App 擴充的區塊，不在原 contract 裡 ──
        "scoring": {
            "final_score": final_score,
            "final_quality": final_quality,
            "base_score": quality.get("base_score"),
            "total_modifier": quality.get("total_modifier"),
            "sri": quality.get("sri"),
            "modifier_note": quality.get("modifier_note"),
            # 規則式建議原文照搬，不改寫不翻譯——它是事實來源
            "recommendation": quality.get("recommendation"),
        },
        "display": {
            "lang": "en",
            "score_color": QUALITY_TO_COLOR.get(final_quality, "#FFC83D"),
            **display,
            "streak_encouragement": (
                "Amazing consistency!"
                if streak["streak_days"] >= 5
                else "Let's build a streak!"
            ),
        },
        "streak": streak,
        "history": history,
        "data_sources": data_sources,
        "notes": {
            "tapo": tapo_note,
            "mapping": (
                "pet_mood / energy_level 的映射為預設值，尚待 PM 核可"
                f"（mapping_version={MAPPING_VERSION}）"
            ),
        },
        "disclaimer": (
            "睡眠分數由 Garmin 手錶資料經文獻加權規則計算，不構成醫療診斷。"
            "夢境內容若有生成，為 AI 依睡眠數據想像的創作，非使用者實際夢境的紀錄。"
        ),
        "timestamp": features.get("wake_time"),
    }


def _report_pending_ai(payload):
    """
    印出「還有幾晚沒有 AI 建議」。

    零成本補洞：不呼叫任何 API，純粹在本地數。目的是讓「AI 這一步存在」
    永遠不會隱形——否則沒加 --ai 時整條 pipeline 完全不會提到它，
    幾週後就沒人記得還有這個步驟。
    """
    quality_rows = load_json(GARMIN_DATA / "garmin_sleep_quality_final.json") or []
    advice = load_json(AI_DATA / "ai_advice.json") or {}
    done = {
        date
        for date, entry in (advice.get("entries") or {}).items()
        if entry.get("source") == "llm"
    }
    pending = len({row["date"] for row in quality_rows} - done)
    if pending:
        print(f"  尚有 {pending} 晚未生成 AI 建議"
              f"（執行 python garmin/run_pipeline.py --ai 產生）")


def main():
    parser = argparse.ArgumentParser(
        description="把 Garmin / AI / TAPO 的產出組成 App 用的單一 payload。"
    )
    parser.add_argument(
        "--date",
        default=None,
        help="指定要組哪一晚（YYYY-MM-DD）。預設用最新一晚。",
    )
    args = parser.parse_args()

    payload = build_payload(args.date)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    # 先寫 .tmp 再 os.replace：中途中斷不會留下截斷的檔案，
    # 而 App 與 main.py 都會讀這個檔，半個檔案會讓它們拿到壞資料。
    tmp_path = OUTPUT_PATH.with_suffix(".json.tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    tmp_path.replace(OUTPUT_PATH)

    rel = OUTPUT_PATH.relative_to(ROOT).as_posix()
    print(f"✓ 已產生 {rel}")
    _report_pending_ai(payload)
    print(f"  夜晚：{payload['session_id'][:8]}  "
          f"分數：{payload['scoring']['final_score']} "
          f"（{payload['scoring']['final_quality']}）")
    print(f"  寵物心情：{payload['status']['pet_mood']}"
          f"（{payload['status']['mood_reason']}）  "
          f"活力：{payload['status']['energy_level']}")
    print(f"  連續記錄：{payload['streak']['streak_days']} 晚  "
          f"本週達標：{payload['streak']['completed_days']}/7")
    print(f"  資料來源：{', '.join(payload['data_sources'])}")
    print(f"  {payload['notes']['tapo']}")


if __name__ == "__main__":
    main()
