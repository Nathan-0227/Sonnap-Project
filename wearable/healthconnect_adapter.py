"""
wearable/healthconnect_adapter.py — Health Connect → 既有評分器

═══════════════════════════════════════════════════════════════════
這支程式解決什麼問題
═══════════════════════════════════════════════════════════════════

D2 的受測者要拿到深睡／REM／心率／睡眠分數，但**不能借錶給每個人**
（經費只有一支手環，而且輪流出借也拿不到 Tier3——見下方）。

解法是 Android 的健康資料標準層 **Health Connect**：受測者**自備**的
裝置會把資料寫進同一個介面，App 接一次就全部通吃。

    Garmin / Samsung / Fitbit / 小米(Mi Fitness) / Amazfit  ✅ 寫入
    Apple Watch                                             ❌ 不寫入（蘋果生態封閉）

SleepSessionRecord 帶完整分期 AWAKE / LIGHT / DEEP / REM，
所以 **Tier1/2 那 100 分的五項全部拿得到**：

    睡眠時長 30 ✅   睡眠效率 25 ✅   WASO 25 ✅（AWAKE 分期加總）
    深睡 10 ✅       REM 10 ✅

→ **現有評分邏輯原封不動套用，一個門檻都不用改。**

═══════════════════════════════════════════════════════════════════
⚠️ 最重要的一個決定：效率要用哪個分母
═══════════════════════════════════════════════════════════════════

Health Connect 的 session 起點是「**上床**」，不是「入睡」。
也就是說，它給得出 PROJECT_STATUS.md 3.9 說「拿不到」的那個東西：

    臥床時間 TIB     = session 結束 − session 開始
    入睡潛伏期       = 第一個睡眠分期 − session 開始
    **臨床**睡眠效率 = 總睡眠 ÷ 臥床時間

這是個意外收穫：攝影機原本要解的問題，對有穿戴裝置的受測者來說，
Health Connect 直接就給了，而且一個新參數都不用訂。

**但我們刻意不拿它去計分。** 理由是分母不一致會製造假差異：

    Garmin 的效率分母 = 起床 − 入睡          （不含入睡潛伏期，偏高）
    臨床效率的分母    = 起床 − 上床          （含入睡潛伏期，較低）

    → 同一個人、同一晚，臨床定義算出來的數字一定比較低
    → 兩種數字餵進**同一個評分器、同一組門檻**（EFFICIENCY_GOOD = 85）
    → **L1 同學會被系統性地扣分，而那個差異來自裝置不是來自睡眠**

所以：**餵進評分器的是 Garmin 相容定義**（第一個睡眠分期 → 最後一個
睡眠分期），臨床定義另外算、另外存，只供報告呈現。

⚠️ 日後若 3.9 解決了（Garmin 側也拿得到上床時間），兩邊應該
   **同時**切換成臨床定義，並重跑全部歷史資料。不要只切一邊。

═══════════════════════════════════════════════════════════════════
⚠️ Tier3 與 SRI：L1 同學拿不到，而且這不是 bug
═══════════════════════════════════════════════════════════════════
1. **壓力分數（Tier3 額度最大的一項，±4）是 Garmin 專有指標**，
   不寫進 Health Connect。Body Battery、Intensity Minutes 同理。
2. **一到兩週的研究，Tier3 每一項都還在冷啟動**（需要 14–28 晚的
   個人 baseline）；SRI 更需要 28 天窗格內 ≥10 組相鄰配對——
   研究者自己 46 晚也只有 28 晚算得出來。

→ 換句話說：**就算借錶給同學戴兩週，也一樣拿不到 Tier3。**
  這正是「借錶不會比 Health Connect 多拿到任何資料」的原因。

而這正是 apply_recovery_modifier.py 已經處理好的情況（各訊號**獨立**
冷啟動、非全有全無），所以這裡輸出 0／NULL 並在 modifier_note 說明即可，
**不需要為此改任何評分程式碼**。

⚠️ modifier_note 要能區分「冷啟動」與「此資料來源根本沒有這個欄位」——
   沿用 apply_recovery_modifier.py 既有那個「資料無效 vs 冷啟動講法不同」
   的處理原則。對前者說「繼續戴就好」是正確的，對後者說同樣的話
   會讓使用者一直等一個永遠不會來的東西。
"""

import importlib.util
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# ═══════════════════════════════════════════════════════════════════
# 載入既有的評分器
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ garmin/ **不是 Python package**（沒有 __init__.py），所以不能寫
#    `from garmin.evaluate_sleep_quality import evaluate_night`。
#
#    三種做法裡選了第三種：
#      (a) 在 garmin/ 加 __init__.py          → 要動到已驗證的 pipeline 目錄
#      (b) sys.path.insert(garmin 目錄)       → 讓 evaluate_sleep_quality 這種
#                                               通用名稱進入全域搜尋路徑，
#                                               日後可能跟別的模組撞名
#      (c) importlib 直接指定檔案路徑          → 零副作用，不碰 sys.path，
#                                               也不改 garmin/ 任何東西  ← 用這個
#
#    這樣做的另一個好處是**依賴關係看得見**：任何人讀到這裡就知道
#    這支程式跟 garmin/evaluate_sleep_quality.py 綁在一起，
#    不必去猜某個 import 是從哪裡來的。

def _load_scorer():
    """
    載入 garmin/evaluate_sleep_quality.py。

    ⚠️ 找不到檔案時給明確訊息並指出路徑，不要讓它變成一個難懂的
       ModuleNotFoundError——這是最可能在別人的 clone 上出問題的地方。
    """
    path = ROOT / "garmin" / "evaluate_sleep_quality.py"
    if not path.exists():
        raise FileNotFoundError(
            f"Scorer not found: {path}. wearable/ must reuse the scoring logic in "
            "garmin/evaluate_sleep_quality.py and must not implement its own "
            "(see wearable/__init__.py)."
        )
    spec = importlib.util.spec_from_file_location("evaluate_sleep_quality", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_scorer = _load_scorer()

# 直接借用評分器的公開函式與常數。**不要在這裡重新定義任何門檻。**
evaluate_night = _scorer.evaluate_night
DURATION_RANGE = _scorer.DURATION_RANGE


# ═══════════════════════════════════════════════════════════════════
# Health Connect 的睡眠分期代碼
# ═══════════════════════════════════════════════════════════════════
#
# androidx.health.connect.client.records.SleepSessionRecord.Stage 的整數常數。
# Flutter 的 health 套件會轉成字串（SLEEP_DEEP 之類），而不同版本的字串
# 形式不一樣，所以**兩種都接**——整數、字串都能餵進來。
#
# ⚠️ 這裡不是「猜」而是照 Android 官方常數表寫的。若哪天 Google 加了
#    新的分期代碼，normalize_stage() 會回 None 而不是靜靜當成清醒——
#    見那個函式的說明。

STAGE_UNKNOWN = 0
STAGE_AWAKE = 1
STAGE_SLEEPING = 2        # 睡著但分不出是哪一期
STAGE_OUT_OF_BED = 3
STAGE_LIGHT = 4
STAGE_DEEP = 5
STAGE_REM = 6
STAGE_AWAKE_IN_BED = 7

_STAGE_ALIASES = {
    # 整數（Health Connect 原生）
    0: "unknown", 1: "awake", 2: "sleeping", 3: "out_of_bed",
    4: "light", 5: "deep", 6: "rem", 7: "awake_in_bed",
    # 字串（各版本 health 套件與手刻測試資料的寫法）
    "unknown": "unknown",
    "awake": "awake",
    "asleep": "sleeping",
    "sleeping": "sleeping",
    "out_of_bed": "out_of_bed",
    "light": "light",
    "deep": "deep",
    "rem": "rem",
    "awake_in_bed": "awake_in_bed",
}

# 算進「總睡眠時間」的分期。
#
# ⚠️ sleeping（睡著但分不出期別）**要算進總睡眠**。有些裝置只回報
#    「有沒有睡著」而不分期，若不算進去，那些人的睡眠時長會是 0，
#    然後拿到極低的分數——那是裝置能力問題不是睡眠問題。
#    這跟 REM=0 視為「未測得」而非「REM 極差」是同一個原則。
SLEEP_STAGES = {"light", "deep", "rem", "sleeping"}

# 算進 WASO 的分期。
#
# ⚠️ out_of_bed **要算**。入睡之後、最終起床之前跑去廁所或客廳的那段時間，
#    臨床上就是 wake after sleep onset。不算的話，一個晚上起來三次的人
#    會跟一覺到天亮的人看起來一樣。
WAKE_STAGES = {"awake", "awake_in_bed", "out_of_bed"}


def normalize_stage(value):
    """
    把各種寫法的分期代碼統一成內部字串。**認不得的回 None。**

    ⚠️ 回 None 而不是預設成 awake 或 light，是刻意的。認不得的分期
       通常代表兩件事之一：新版 Health Connect 加了代碼，或上游傳錯了。
       兩種情況下猜一個值都會安靜地污染分數；回 None 則會讓那段時間
       同時被排除在睡眠與清醒之外，效率自然變低，異常看得出來。
    """
    if value is None:
        return None
    if isinstance(value, bool):          # bool 是 int 的子類，先擋掉
        return None
    if isinstance(value, int):
        return _STAGE_ALIASES.get(value)

    key = str(value).strip().lower()
    # 去掉常見前綴：STAGE_TYPE_DEEP / SLEEP_DEEP / HealthDataType.SLEEP_DEEP
    for prefix in ("healthdatatype.", "stage_type_", "sleep_session_", "sleep_"):
        if key.startswith(prefix):
            key = key[len(prefix):]
    return _STAGE_ALIASES.get(key)


# ═══════════════════════════════════════════════════════════════════
# 時間處理
# ═══════════════════════════════════════════════════════════════════

def parse_time(value):
    """
    解析 ISO8601 時間字串。**失敗回 None，不丟例外。**

    上游是手機送上來的 JSON，格式錯誤是預期內的事（不同 Android 版本、
    不同套件版本的序列化方式不同），不該讓整個 API 掛掉。

    ⚠️ 接受結尾的 Z（UTC）——Python 3.11 之前的 fromisoformat 不吃它，
       而 Health Connect 的 Instant 序列化出來常常就是 Z 結尾。
       這行不加的話，會變成「某些手機送上來的資料一律解析失敗」，
       而且失敗得很安靜。
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except (TypeError, ValueError):
        return None


def _minutes(start, end):
    """兩個時間點相差幾分鐘。任一為 None 或倒序時回 0。"""
    if start is None or end is None:
        return 0.0
    delta = (end - start).total_seconds() / 60.0
    return delta if delta > 0 else 0.0


# ═══════════════════════════════════════════════════════════════════
# 主要轉換
# ═══════════════════════════════════════════════════════════════════

class HealthConnectError(ValueError):
    """輸入的 session 無法轉換。訊息要能直接回給 App 端顯示。"""


def parse_session(session):
    """
    把一筆 Health Connect SleepSessionRecord 拆解成時間統計。

    輸入格式（App 上傳時要照這個組）::

        {
          "startTime": "2026-08-25T23:10:00+08:00",   # 上床
          "endTime":   "2026-08-26T07:30:00+08:00",   # 起床
          "stages": [
            {"startTime": "...", "endTime": "...", "stage": "LIGHT"},
            {"startTime": "...", "endTime": "...", "stage": 5},
            ...
          ],
          "avgHeartRate": 58.2,        # 選填
          "restingHeartRate": 52       # 選填
        }

    回傳一個 dict，欄位意義見底下的註解。
    """
    start = parse_time(session.get("startTime"))
    end = parse_time(session.get("endTime"))
    if start is None or end is None:
        raise HealthConnectError(
            "Session is missing a parsable startTime / endTime. Times must be ISO8601 "
            "(for example 2026-08-25T23:10:00+08:00)."
        )
    if end <= start:
        raise HealthConnectError(
            f"Session endTime ({session.get('endTime')}) "
            f"is not later than startTime ({session.get('startTime')}); cannot compute."
        )

    raw_stages = session.get("stages") or []
    if not raw_stages:
        raise HealthConnectError(
            "Session has no stages. Without sleep staging, deep / REM / WASO cannot be "
            "derived, so Tier1/2 scoring cannot be applied."
        )

    # 解析每一段，順便丟掉時間無效的段落
    segments = []
    unknown_labels = set()
    for s in raw_stages:
        s_start = parse_time(s.get("startTime"))
        s_end = parse_time(s.get("endTime"))
        kind = normalize_stage(s.get("stage"))
        if kind is None:
            unknown_labels.add(str(s.get("stage")))
            continue
        if s_start is None or s_end is None or s_end <= s_start:
            continue
        segments.append((s_start, s_end, kind))

    if not segments:
        raise HealthConnectError(
            "All stages in the session are invalid (bad times or stage codes)."
        )

    # ⚠️ 一定要自己排序，不要相信上游的順序。Health Connect 本身不保證
    #    stages 是排好的，而底下「第一個睡眠分期 / 最後一個睡眠分期」
    #    的判斷完全建立在順序上——順序錯了不會報錯，只會算出錯的數字。
    segments.sort(key=lambda seg: seg[0])

    sleep_segments = [seg for seg in segments if seg[2] in SLEEP_STAGES]
    if not sleep_segments:
        raise HealthConnectError(
            "The session contains no sleep stages at all (only awake or unknown), "
            "so it is judged not to be a sleep session."
        )

    # ── Garmin 相容的睡眠區間：第一個睡眠分期 → 最後一個睡眠分期 ──
    # 這對應 Garmin 的 [sleep_start_time, wake_time]，兩邊都由「實際睡著」
    # 界定，所以都不含入睡潛伏期、也都不含最終醒來後賴床的時間。
    sleep_onset = sleep_segments[0][0]
    final_wake = sleep_segments[-1][1]

    # 各分期加總
    by_kind = {}
    for s_start, s_end, kind in segments:
        by_kind[kind] = by_kind.get(kind, 0.0) + _minutes(s_start, s_end)

    total_sleep = sum(by_kind.get(k, 0.0) for k in SLEEP_STAGES)

    # ── WASO：**只算落在 [sleep_onset, final_wake] 之內的清醒** ──
    # ⚠️ 這是這支程式最容易寫錯的地方。直接把所有 awake 分期加總的話：
    #      - session 開頭的清醒 → 那是**入睡潛伏期**，不是 WASO
    #      - session 結尾的清醒 → 那是醒來後還躺在床上，也不是 WASO
    #    WASO 的定義是「入睡後、最終醒來前」的清醒。多算的話，
    #    躺床上滑半小時手機才睡的人會被當成整夜片段化。
    waso = 0.0
    for s_start, s_end, kind in segments:
        if kind not in WAKE_STAGES:
            continue
        overlap_start = max(s_start, sleep_onset)
        overlap_end = min(s_end, final_wake)
        waso += _minutes(overlap_start, overlap_end)

    sleep_period = _minutes(sleep_onset, final_wake)
    time_in_bed = _minutes(start, end)
    latency = _minutes(start, sleep_onset)

    return {
        "session_start": start,
        "session_end": end,
        "sleep_onset": sleep_onset,
        "final_wake": final_wake,
        "total_sleep_min": round(total_sleep, 1),
        "deep_min": round(by_kind.get("deep", 0.0), 1),
        "light_min": round(by_kind.get("light", 0.0), 1),
        "rem_min": round(by_kind.get("rem", 0.0), 1),
        # 「睡著但分不出期別」單獨留著。它算進總睡眠，但**不能**被當成
        # 淺睡——那會讓深睡／REM 比例的分母意義改變。
        "unstaged_sleep_min": round(by_kind.get("sleeping", 0.0), 1),
        "waso_min": round(waso, 1),
        "sleep_period_min": round(sleep_period, 1),
        "time_in_bed_min": round(time_in_bed, 1),
        "sleep_latency_min": round(latency, 1),
        # 認不得的分期代碼。有值時代表上游或 Health Connect 版本有變動，
        # 要讓它可見而不是吞掉。
        "unknown_stage_labels": sorted(unknown_labels),
    }


def to_features(session, date=None, age_band="young_adult"):
    """
    把 Health Connect session 轉成 **evaluate_sleep_quality.evaluate_night()
    吃得下的特徵 dict**——欄位名稱與 garmin/extract_sleep_features.py 的
    輸出完全一致。

    ⚠️ 「完全一致」是這支程式的全部價值所在。只要欄位對得上，
       Health Connect 的資料就會走**同一個評分器、同一組文獻門檻**，
       而不需要為它另寫一套標準。

    date 是「起床日」（與全專案的分組約定一致，見 db.py 的 schema 說明）。
    不給的話從 final_wake 推出來。
    """
    parsed = parse_session(session)

    if date is None:
        date = parsed["final_wake"].date().isoformat()

    total = parsed["total_sleep_min"]
    period = parsed["sleep_period_min"]

    def ratio(part):
        """占總睡眠的比例（0–1）。分母 <= 0 回 None，不回 0。"""
        if total <= 0:
            return None
        return round(part / total, 4)

    # ⚠️ 效率用 Garmin 相容的分母（sleep_period），不是臥床時間。
    #    理由見檔案開頭——分母不一致會讓 L1 同學被系統性扣分。
    #    min(..., 100.0) 是照抄 extract_sleep_features.py 的處理，
    #    因為分期時間加總可能因四捨五入略微超過區間長度。
    efficiency = min(round(total / period * 100, 2), 100.0) if period > 0 else None

    return {
        "date": date,
        "age_band": age_band,
        # ── evaluate_night() 實際會讀的五項 ──
        "sleep_duration_hours": round(total / 60.0, 2),
        "sleep_efficiency": efficiency,
        "waso_minutes": parsed["waso_min"],
        "deep_ratio": ratio(parsed["deep_min"]),
        "rem_ratio": ratio(parsed["rem_min"]),
        # ── 以下不進評分，供 App 顯示與存進 wearable_nightly ──
        "total_sleep_minutes": total,
        "deep_minutes": parsed["deep_min"],
        "light_minutes": parsed["light_min"],
        "rem_minutes": parsed["rem_min"],
        "unstaged_sleep_minutes": parsed["unstaged_sleep_min"],
        "sleep_period_hours": round(period / 60.0, 2),
        "sleep_start_time": parsed["sleep_onset"].isoformat(),
        "wake_time": parsed["final_wake"].isoformat(),
        # ── 臥床時間相關：Garmin 給不出來，Health Connect 給得出來 ──
        "time_in_bed_minutes": parsed["time_in_bed_min"],
        "sleep_latency_minutes": parsed["sleep_latency_min"],
        "clinical_sleep_efficiency": (
            round(total / parsed["time_in_bed_min"] * 100, 2)
            if parsed["time_in_bed_min"] > 0 else None
        ),
        "avg_heart_rate": session.get("avgHeartRate"),
        "resting_heart_rate": session.get("restingHeartRate"),
        "unknown_stage_labels": parsed["unknown_stage_labels"],
    }


# Tier3 說明文字。⚠️ 兩種情況要用不同的講法，混用會誤導：
#
#   冷啟動          → 「繼續戴就會有」          （正確：14–28 晚後就會啟動）
#   來源無此欄位    → 「這個裝置永遠不會有」    （正確：講「繼續戴」是騙人的）
#
# 這沿用 apply_recovery_modifier.py 對「資料無效 vs 冷啟動」的既有處理原則。
HC_MODIFIER_NOTE = (
    "Tier3 modifier is 0, for two reasons: (1) the stress score is a Garmin-proprietary "
    "metric that Health Connect does not expose, so this source will never carry a stress "
    "modifier; (2) the remaining signals (resting heart rate, sleep-period average heart "
    "rate, awakenings, sleep segments) need a 14-28 night personal baseline and are still "
    "cold-starting — keep wearing the device and they will come online. "
    "SRI likewise needs ≥10 adjacent-night pairs within a 28-day window, "
    "which has not been reached yet."
)


def to_wearable_row(session, date=None, age_band="young_adult",
                    device_brand=None):
    """
    一步到位：Health Connect session →（評分）→ 可直接寫進
    db.upsert_wearable_nightly() 的 metrics dict。

    回傳 (date, metrics, features)。features 一併回傳是為了讓呼叫端
    （API 層）能把睡眠結構等非計分欄位也吐給 App，不必再算一次。

    ⚠️ 這裡呼叫的 evaluate_night 是**原封不動的既有評分器**，
       沒有包裝、沒有調整、沒有為 Health Connect 開任何特例。
       這正是驗收第 5b 項要驗的東西。
    """
    features = to_features(session, date=date, age_band=age_band)
    scored = evaluate_night(features)

    metrics = {
        "device_brand": device_brand,
        "duration_min": features["total_sleep_minutes"],
        "efficiency": features["sleep_efficiency"],
        "waso_min": features["waso_minutes"],
        "deep_min": features["deep_minutes"],
        "rem_min": features["rem_minutes"],
        "avg_hr": features["avg_heart_rate"],
        "resting_hr": features["resting_heart_rate"],
        # ⚠️ 用 sleep_onset / final_wake，**不是** session_start / session_end。
        #    session 起點是「上床」（那個值已經在 time_in_bed_min 裡），
        #    這兩欄要與 Garmin 同構念，才能放進同一張表、同一條 history。
        "sleep_start_time": features["sleep_start_time"],
        "wake_time": features["wake_time"],
        # 臥床時間：只有這個來源有
        "time_in_bed_min": features["time_in_bed_minutes"],
        "clinical_efficiency": features["clinical_sleep_efficiency"],
        # Tier1/2：走既有評分器
        "base_score": scored["score"],
        "base_quality": scored["quality"],
        "rem_measured": 1 if scored["rem_measured"] else 0,
        # ── Tier3 與 SRI ──
        # ⚠️ total_modifier 存 0.0 而 sri 存 None，兩者刻意不同：
        #    修正值**確實是 0**（各項都算過了，只是都在冷啟動）；
        #    SRI 則是**根本算不出來**（窗格內配對數不足）。
        #    0 與「無法計算」在本專案一律分開表示。
        "total_modifier": 0.0,
        "sri": None,
        "modifier_note": HC_MODIFIER_NOTE,
        # Health Connect 沒有 Tier3，所以最終分數 = 基礎分數。
        # 仍然明確寫入而不是留 NULL 讓讀取端自己推——見 db.py schema 的說明。
        "final_score": scored["score"],
        "final_quality": scored["quality"],
    }

    return features["date"], metrics, features
