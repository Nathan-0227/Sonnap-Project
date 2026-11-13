"""
main.py — Sonnap 後端 API

═══════════════════════════════════════════════════════════════════
兩條資料路徑，刻意並存
═══════════════════════════════════════════════════════════════════

【舊路徑】單一使用者、打包成 asset

    garmin/ pipeline → build_app_payload.py → app_payload.json
                                                   ├→ Flutter rootBundle 讀
                                                   └→ GET /get-sleep-data

    只有研究者本人的資料，沒有使用者概念。**行為完全不變**，
    Flutter 現行的 asset 路徑不受這一輪任何改動影響。

【新路徑】多使用者、走資料庫

    App → POST /nightly（行為）      ┐
    App → POST /wearable（生理）      ├→ data/sonnap.db → GET /home?user_id=
    pipeline → migrate_garmin_to_db  ┘                    GET /insights
                                                          GET /challenges

    D2 要把 APK 給十來個同學裝，而舊路徑會讓他們全部看到同一個人的
    睡眠分數——新路徑就是為了這件事。

⚠️ 兩條路徑**共用同一份判斷邏輯**，沒有第二套：
   - pet_mood 的 Tier B 映射直接 import build_app_payload.map_pet_mood
   - 睡眠評分一律走 garmin/evaluate_sleep_quality.py
   只有 Tier A（行為驅動）的部分是新的，因為舊路徑根本沒有行為資料。

═══════════════════════════════════════════════════════════════════
啟動
═══════════════════════════════════════════════════════════════════
    uvicorn main:app --reload
    uvicorn main:app --host 0.0.0.0 --port 8000    # 要讓手機連進來時用

    先跑一次：python db.py --init && python db.py --seed
"""

import json
from datetime import date as date_cls, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import camera_clips
import camera_usual
import db
import score_claim
from behavior import (adherence, challenges as challenge_engine, morning_tips,
                      pet_state, sleep_efficiency)
from wearable.healthconnect_adapter import HealthConnectError, to_wearable_row

# 遊戲化層。⚠️ 只讀評分層（設計紅線 4），見 game/__init__.py。
from game import inventory, state as game_state

# 好友。⚠️ 只分享行為指標，別人的 user_id 永遠不出後端，見 social/__init__.py。
from social import friends as social_friends

# ⚠️ 直接 import 舊路徑的映射函式，**不要在這裡重寫一份**。
#    pet_mood 的 Tier B 規則（QUALITY_TO_MOOD + anxious 生理覆寫）
#    必須只有一個定義處，否則 App 的 asset 畫面與 API 回傳的心情
#    會在某次改動後悄悄地不一致——那正是本專案最想避免的那類 bug。
from build_app_payload import DISPLAY_STRINGS, QUALITY_TO_COLOR, map_pet_mood
import build_app_payload as _payload
from build_app_payload import sleep_heart_rate  # noqa: E402  garmin/ 由 build_app_payload 加進 sys.path

app = FastAPI(title="Sonnap API")

# Flutter web 版（flutter run -d chrome）是從另一個 origin 發請求，
# 沒有 CORS 設定一定會被瀏覽器擋掉，而且錯誤訊息出現在瀏覽器 console、
# 後端這邊完全看不到，很容易誤判成「API 壞了」。
#
# ⚠️ 2026-08-26 新增 POST / PATCH / DELETE。原本只開 GET，
#    所以**結構上就不可能寫入**——App 上傳行為資料會被瀏覽器擋掉。
#    OPTIONS 是 preflight 用的，漏掉的話非簡單請求全部失敗。
#
# 學生專案的開發階段全開；正式部署要收斂成實際的前端網域。
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

PAYLOAD_PATH = Path(__file__).parent / "app" / "assets" / "data" / "app_payload.json"

# /home 與 /insights 預設回幾晚
DEFAULT_HISTORY_DAYS = 30

# 逐晚配對（手機那一晚 ↔ 手錶那一晚）時，查找用的資料要取多少筆。
#
# ⚠️ db.get_*_nightly(days=N) 的 N 是「最近 N 筆」，不是「最近 N 天」。
#    兩張表各取最近 30 筆時，晚數多的那張回推得比較短，兩邊的窗格就錯開了。
#    2026-11-06 實測：手錶 65 晚、手機 37 晚 → 手錶的 30 筆只到 10 月初，
#    手機的 30 筆回到 09-13，於是 09-13 ~ 10-04 每一晚的手機畫面都說
#    「No sleep data from your watch」，而手錶其實有資料（沒有任何錯誤訊息）。
#    → 顯示用的列表照舊取 N 筆；**配對一律從這個大窗格按日期查**。
JOIN_LOOKUP_ROWS = 3650

SCHEMA_VERSION = 2   # 1 = build_app_payload 的 asset 格式；2 = 多使用者 API 格式


# ═══════════════════════════════════════════════════════════════════
# 舊路徑（行為完全不變）
# ═══════════════════════════════════════════════════════════════════

@app.get("/get-sleep-data")
async def get_sleep_data():
    """
    回傳最新一晚的完整睡眠資料（研究者本人，來自打包的 asset 檔）。

    ⚠️ 檔案不存在時回 503，**不 fallback 回假資料**。
       這是刻意的：本專案 2026-08-10 踩過「漏跑中間步驟不會報錯，
       只會安靜地用舊資料算出結果」的坑。若這裡回一份寫死的 mock，
       「忘記跑 pipeline」看起來就會跟正常運作一模一樣，
       而那正是最難發現的失敗模式。寧可明確地壞掉。
    """
    if not PAYLOAD_PATH.exists():
        raise HTTPException(
            status_code=503,
            detail=(
                "Data file app/assets/data/app_payload.json has not been generated yet. "
                "Run this first: python garmin/run_pipeline.py"
            ),
        )

    # 每次請求都重讀而不快取在記憶體：檔案只有幾 KB，重讀的成本可以忽略，
    # 換來的是重跑 pipeline 之後不必重啟伺服器就能看到新資料。
    try:
        with PAYLOAD_PATH.open(encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"app_payload.json is malformed: {exc}. Re-run the pipeline to regenerate it.",
        ) from exc


@app.get("/health")
async def health():
    """讓前端/隊友快速確認伺服器活著、以及資料檔在不在。"""
    return {
        "status": "ok",
        "payload_available": PAYLOAD_PATH.exists(),
        # 新增：資料庫在不在。D2 期間最常見的問題會是「忘了跑 db.py --init」，
        # 讓它在這裡一眼看得到，不用去猜。
        "database_available": db.DB_PATH.exists(),
    }


# ═══════════════════════════════════════════════════════════════════
# 請求/回應的資料模型
# ═══════════════════════════════════════════════════════════════════
#
# 用 pydantic 而不是自己驗證 dict，理由是它會把格式錯誤變成
# 422 + 明確的欄位訊息，而不是後端某處丟 KeyError 然後回 500。
# App 端 debug 時看得到「哪個欄位錯了」差別很大。

class CreateUserRequest(BaseModel):
    display_name: str = Field(..., min_length=1, max_length=40,
                              description="Nickname. No email, no password.")
    target_bedtime: str = Field("23:30", description='Target bedtime, "HH:MM".')
    age_band: str = Field("young_adult", description="Age band used for scoring.")
    study_cohort: str = Field("L0", description="L0 phone only / L1 wearable / L2 researcher")
    wearable_brand: Optional[str] = Field(
        None, description="Cross-brand physiological metrics are not comparable, so the source must always be recorded.")


class UpdateUserRequest(BaseModel):
    display_name: Optional[str] = Field(None, min_length=1, max_length=40)
    target_bedtime: Optional[str] = None
    age_band: Optional[str] = None
    study_cohort: Optional[str] = None
    wearable_brand: Optional[str] = None


class NightlyRequest(BaseModel):
    """App 每日上傳的 Tier A 行為資料。"""
    user_id: str
    lights_out_at: str = Field(
        ...,
        description=(
            "Timestamp of the last phone interaction (ISO8601). "
            "This is a proxy, not sleep onset - people often lie down for another half hour."
        ),
    )
    # ⚠️ 一般不要傳。留這個欄位是給「補填歷史資料」用的——當晚的目標
    #    可能跟現在的設定不同，而 nightly_behavior 存的是**當晚的快照**
    #    （見 db.py schema：使用者改目標不該追溯性地改寫歷史達成度）。
    target_bedtime: Optional[str] = None
    # 使用者在畫面上按「開始／結束睡覺」的時刻（ISO8601）。兩個都給才算得出
    # 行為版睡眠效率；沒給就是 null（不是 0 —— 沒按與效率 0% 是兩件事）。
    # ⚠️ 這是**自述**的上床／下床，不是量到的入睡／醒來。
    bed_start_at: Optional[str] = Field(
        None, description="When the user marked getting into bed (self-reported)."
    )
    bed_end_at: Optional[str] = Field(
        None, description="When the user marked getting out of bed (self-reported)."
    )
    source: str = Field("phone", description="phone | self_report")
    # 2026-11-12：那兩個時刻是當下按的還是事後補的。沒給 = 'tap'（舊版 App）。
    # ⚠️ 'recalled' 照樣算進效率（使用者決定），但攝影機驗證不拿它當標準答案，
    #    分數卡也會多一句警語（score_claim.RECALLED_EFFICIENCY_NOTE）。
    bed_start_kind: Optional[Literal["tap", "recalled"]] = None
    bed_end_kind: Optional[Literal["tap", "recalled"]] = None


class WearableRequest(BaseModel):
    """App 上傳的 Health Connect 睡眠 session。"""
    user_id: str
    session: Dict[str, Any] = Field(
        ...,
        description="Health Connect SleepSessionRecord; see "
                    "wearable/healthconnect_adapter.py parse_session() for the format.",
    )
    device_brand: Optional[str] = None
    date: Optional[str] = Field(None, description="Wake date; inferred from the session when omitted.")


# ═══════════════════════════════════════════════════════════════════
# 共用小工具
# ═══════════════════════════════════════════════════════════════════

def require_user(user_id: str) -> dict:
    """
    取使用者，不存在就回 404。

    抽出來是因為每個端點都要做這件事，而漏做的話會變成
    「查不到資料 → 回一個空的 payload」，看起來像「這個人還沒開始用」，
    但其實是 user_id 打錯了。兩者在畫面上長得一模一樣。
    """
    user = db.get_user(user_id)
    if user is None:
        raise HTTPException(
            status_code=404,
            detail=f"User {user_id} not found. POST /users to create one first.",
        )
    return user


def pick_latest_date(*row_lists) -> Optional[str]:
    """幾組資料裡最新的那個日期。全空回 None。"""
    dates = [r["date"] for rows in row_lists for r in rows if r.get("date")]
    return max(dates) if dates else None


def _light_minutes(w_row: dict) -> Optional[float]:
    """淺睡分鐘 = 總睡眠 − 深睡 − REM。沒量到 REM 或缺任何一項時回 None。"""
    if not w_row.get("rem_measured"):
        return None
    total, deep, rem = w_row.get("duration_min"), w_row.get("deep_min"), w_row.get("rem_min")
    if total is None or deep is None or rem is None:
        return None
    return round(max(0.0, total - deep - rem), 1)


def display_for(mood, driver, w_row):
    """畫面上的那幾句話：兩層各有自己的文案，依 driver 決定用哪一套。
    /home 與早晨報告的 AI 退回文字共用這一份（兩份的話同一晚會講兩種話）。"""
    if driver in ("wearable", "wearable_override") and w_row:
        quality = w_row.get("final_quality") or "Normal"
        return {
            "lang": "en",
            "score_color": QUALITY_TO_COLOR.get(quality, "#FFC83D"),
            **DISPLAY_STRINGS.get(quality, DISPLAY_STRINGS["Normal"]),
        }
    return pet_state.build_display(mood)


# ── 每一晚的睡眠階段時間軸（2026-11-12，早晨報告用）──────────────────
# 原始檔 garmin_standard_data.json 約 25 MB：讀一次留在記憶體，檔案更新（mtime 變了）才重讀。
_STANDARD_CACHE = {"mtime": None, "records": None}


def _garmin_records():
    path = _payload.GARMIN_DATA / "garmin_standard_data.json"
    try:
        mtime = path.stat().st_mtime
    except OSError:
        return None
    if _STANDARD_CACHE["mtime"] != mtime:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        _STANDARD_CACHE.update(mtime=mtime, records=data.get("records", []))
    return _STANDARD_CACHE["records"]


# VO2 max 不是每天都有（只有 GPS 走路、跑步的日子會更新），報告顯示最近一次；
# 太舊就不顯示（2026-11-13 使用者定）。
VO2MAX_LOOKBACK_DAYS = 90


def yesterday_block(user_id, night_date):
    """
    早晨報告「Yesterday」那一塊：那一晚（起床日）**前一個日曆日**的 Garmin 白天資料。

    ⚠️ 只呈現、不計分（紅線 4）；不給 Good/Normal、不判斷步數有沒有達標（紅線 2，
       步數目標只照實給 step_goal）。好友端點不讀這裡。
    ⚠️ 那一天沒有資料（沒戴錶、只有 Health Connect、還沒匯入）→ 整塊 None，App 整塊不畫；
       不回 0。單一項沒有值 → 那一項是 null。
    """
    if not night_date:
        return None
    try:
        day = date_cls.fromisoformat(night_date) - timedelta(days=1)
    except ValueError:
        return None
    row = db.get_garmin_daily(user_id, day.isoformat())
    if not row or not any(row.get(k) not in (None, []) for k in db.GARMIN_DAILY_FIELDS):
        return None
    vo2 = db.latest_vo2max(
        user_id, on_or_before=day.isoformat(),
        since=(day - timedelta(days=VO2MAX_LOOKBACK_DAYS - 1)).isoformat())

    def group(**kw):
        return kw if any(v is not None for v in kw.values()) else None

    return {
        "date": day.isoformat(),
        "steps": row.get("steps"),
        "step_goal": row.get("step_goal"),
        "distance_m": row.get("distance_m"),
        "active_kcal": row.get("active_kcal"),
        "floors_up": row.get("floors_up"),
        "activity": group(
            highly_active_sec=row.get("highly_active_sec"),
            active_sec=row.get("active_sec"),
            sedentary_sec=row.get("sedentary_sec"),
        ),
        "stress": group(
            rest_sec=row.get("stress_rest_sec"),
            low_sec=row.get("stress_low_sec"),
            medium_sec=row.get("stress_medium_sec"),
            high_sec=row.get("stress_high_sec"),
        ),
        "body_battery": group(
            charged=row.get("body_battery_charged"),
            drained=row.get("body_battery_drained"),
        ),
        "vo2max": None if vo2 is None else {"value": vo2[0], "measured_on": vo2[1]},
        # 沒有事件是 []（照實），沒抓到是 null
        "move_iq": row.get("move_iq"),
    }


def night_stages(w_row):
    """
    那一晚的 Sleep phases 曲線（與打包檔 metrics.sleep_stages 同一個形狀，App 用同一個解析）。

    ⚠️ 只有 Garmin 來源才有：逐段時間軸只存在電腦上的 Garmin 原始檔。
       Health Connect 上傳時有逐段資料，但後端算完分數就沒存——那些晚上 App 改畫比例條。
    ⚠️ 圖例數字用手錶自己的總數，還原出來的段只畫曲線（理由同 build_app_payload.sleep_stages_block）。
    """
    if not w_row or w_row.get("source") != "garmin":
        return None
    start, wake = w_row.get("sleep_start_time"), w_row.get("wake_time")
    if not start or not wake:
        return None
    records = _garmin_records()
    if not records:
        return None
    segments = _payload.sleep_stages.stage_segments(records, start, wake)
    if not segments:
        return None
    return {
        "segments": segments,
        "minutes": {
            "awake": w_row.get("waso_min"),
            "rem": w_row.get("rem_min"),
            "light": _light_minutes(w_row),
            "deep": w_row.get("deep_min"),
        },
        "rem_measured": bool(w_row.get("rem_measured")),
    }


def night_heart_rate(w_row):
    """
    那一晚睡著期間的心率曲線（早晨報告的 Heart rate 卡，2026-11-13）。

    ⚠️ 只有 Garmin 來源才有（逐 2 分鐘的心率只存在電腦上的 Garmin 原始檔），同 night_stages。
    ⚠️ 平均與最低從曲線那一段自己算，不用 w_row["avg_hr"]（那個混了清醒時段）。
    ⚠️ 不判斷 Normal／High（紅線 2）。資料不夠 → None，App 整張卡不畫。
    """
    if not w_row or w_row.get("source") != "garmin":
        return None
    start, wake = w_row.get("sleep_start_time"), w_row.get("wake_time")
    if not start or not wake:
        return None
    records = _garmin_records()
    if not records:
        return None
    return sleep_heart_rate.heart_rate_curve(records, start, wake)


def night_movement(w_row):
    """那一晚睡著期間的**手錶**動作曲線（Sleep Stages 卡點 Movement 疊上去的線，2026-11-13）。

    ⚠️ 只呈現、不計分（movement 永不進評分）。沒有單位，App 只寫 More／Less。
    ⚠️ 這是手錶的，不是攝影機的動作（那個在 camera 區塊，是另一個量）。
    """
    if not w_row or w_row.get("source") != "garmin":
        return None
    start, wake = w_row.get("sleep_start_time"), w_row.get("wake_time")
    if not start or not wake:
        return None
    records = _garmin_records()
    if not records:
        return None
    return sleep_heart_rate.movement_curve(records, start, wake)


def night_camera_curve(user_id, night_date, w_row):
    """那一晚**攝影機**的動作曲線，只留手錶的入睡 → 起床那段（Sleep Stages 卡點 Camera，2026-11-13）。

    每 5 分鐘一點、值是那 5 分鐘裡有幾成時間在動（0–1），在早晨匯入時從錄影 CSV 算好存進
    camera_nightly.motion_curve（CSV 只在電腦上）。
    ⚠️ 只呈現、不計分：攝影機動作率已驗證與任何結果都沒有相關。不判斷動得多是好是壞。
    ⚠️ 只收有床鋪 ROI 的夜晚（motion_threshold_basis == "roi"）。
    ⚠️ 攝影機的時間沒有時區標記、手錶的有：兩邊都當**牆鐘**比，不換 UTC。
    """
    if not night_date or not w_row:
        return None
    start, wake = w_row.get("sleep_start_time"), w_row.get("wake_time")
    if not start or not wake:
        return None
    rows = [r for r in db.get_camera_nightly(user_id, days=60) if r.get("date") == night_date]
    if not rows or rows[0].get("motion_threshold_basis") != "roi" or not rows[0].get("motion_curve"):
        return None
    try:
        curve = json.loads(rows[0]["motion_curve"])
        lo = datetime.fromisoformat(start).replace(tzinfo=None)
        hi = datetime.fromisoformat(wake).replace(tzinfo=None)
        pts = [p for p in curve.get("points", [])
               if lo <= datetime.fromisoformat(p["t"]).replace(tzinfo=None) <= hi]
    except (TypeError, ValueError, KeyError):
        return None
    if len(pts) < 6:
        return None
    values = [p["value"] for p in pts]
    return {
        "points": pts,
        "avg": round(sum(values) / len(values), 3),
        "min": min(values),
        "max": max(values),
        "bucket_minutes": curve.get("bucket_minutes", 5),
    }


def rating_block(rating):
    """起床自評給畫面的樣子；沒填就是 None。"""
    if not rating:
        return None
    return {
        "rested": rating["rested"],
        "label": morning_tips.RESTED_LABELS.get(rating["rested"]),
        "tags": [{"id": t, "label": morning_tips.TAGS[t]} for t in rating["tags"]
                 if t in morning_tips.TAGS],
        "minutes_after_wake": rating.get("minutes_after_wake"),
    }


def _previous(rows, target_date, need):
    """target_date 之前、最近一個 need 欄位有值的那一列（「跟上一晚比」用）。"""
    best = None
    for r in rows:
        if target_date and r["date"] < target_date and r.get(need) is not None:
            best = r
    return best


def _row_for(rows: List[dict], target_date: Optional[str]) -> Optional[dict]:
    """從列表裡挑出指定日期那一列。"""
    if target_date is None:
        return None
    return next((r for r in rows if r.get("date") == target_date), None)


# ═══════════════════════════════════════════════════════════════════
# 分數是由哪幾項組成的
# ═══════════════════════════════════════════════════════════════════
#
# 為什麼要回這個：**裝置組合因人而異**。只有手機的人、有手錶的人、
# 手錶加攝影機的人，量得到的構念不一樣。評分器對量不到的項目走權重
# 正規化（把它的配分按比例分給其他項，見 evaluate_sleep_quality.py 末段），
# 所以兩個都是「82 分」的夜晚**可能由不同的項目組成**。
# 只回一個數字，讀的人無從知道這件事。
#
# ⚠️ 這裡是**刻意寫的第二份判準**，與 evaluate_sleep_quality.evaluate_night()
#    的 component_scores 必須給出一樣的答案。不 import 那支的理由同
#    has_measured_sleep：garmin/ 五支是各自獨立的行程、不是 package。
#    防止漂移的方法是測試而不是耦合——tests/test_score_composition.py
#    拿真實資料逐夜比對兩邊。
#
# ⚠️ 判斷一律用 `is not None`，**不可用真假值**：WASO 0 分鐘會拿滿分 25、
#    深睡 0 分鐘會拿 0 分，兩者都是「有測到」。用真假值會把它們誤判成沒資料。

# 宣稱、警語、配分與輸出形狀全部集中在 score_claim.py。
# ⚠️ 為什麼不寫在這裡：build_app_payload.py 也要輸出同一組文字，而它
#    **不能 import main.py**（main.py 反過來 import 了它，會循環）。
#    文字複製兩份的話，改一邊沒改另一邊，使用者會在 App 與 API 看到
#    不同的警語，而且不會有任何錯誤訊息。
#
# ⚠️ 「哪幾項有算」的**判準**留在下面那支函式裡（從資料庫的原始度量推論），
#    與 build_app_payload 那份（直讀 pipeline 的分項得分）刻意各寫一份，
#    由 tests/test_score_composition.py 逐夜比對守著。

def score_composition(wearable_row: Optional[dict],
                      behavior_row: Optional[dict] = None) -> Optional[dict]:
    """
    這一晚的分數由哪幾項組成。沒有手錶資料那一晚回 None。

    `rem` 那一項讀的是資料庫裡存著的 `rem_measured`——那是**評分器自己的判定**
    （migrate_garmin_to_db.py 專門為此把 Tier1/2 那份輸出的欄位帶過來），
    不是在這裡重新判斷一次 REM 有沒有測到。
    """
    if not wearable_row:
        return None

    # ⚠️ 判斷一律用 `is not None`，**不可用真假值**：WASO 0 分鐘會拿滿分 25、
    #    深睡 0 分鐘會拿 0 分，兩者都是「有測到」。用真假值會把它們誤判成沒資料
    #    （實測真實資料有 16 晚 WASO 是 0）。
    present = {
        "duration": wearable_row.get("duration_min") is not None,
        # 效率有沒有算、用哪一種，都是評分器存下來的判定（同 rem_measured）
        "efficiency": wearable_row.get("efficiency_basis") is not None,
        "waso": wearable_row.get("waso_min") is not None,
        "deep": wearable_row.get("deep_min") is not None,
        "rem": bool(wearable_row.get("rem_measured")),
    }
    basis = wearable_row.get("efficiency_basis")
    b = behavior_row or {}
    return score_claim.compose(
        (k for k, v in present.items() if v),
        efficiency_basis=basis,
        efficiency_recalled=score_claim.efficiency_uses_recalled(
            basis, b.get("bed_start_kind"), b.get("bed_end_kind")),
    )


# ═══════════════════════════════════════════════════════════════════
# 心情：兩層如何合併
# ═══════════════════════════════════════════════════════════════════

def resolve_mood(behavior_row: Optional[dict], wearable_row: Optional[dict]):
    """
    決定寵物心情。回傳 (mood, reason, driver)。

    ⚠️ **有行為資料時，行為優先，生理只做 anxious 覆寫。** 這是刻意的，
       而且理由跟「挑戰標的必須是行為不是生理結果」完全一樣：

       如果使用者準時放下手機、卻因為感冒睡得很差而看到一隻難過的寵物，
       他就是**因為自己控制不了的事而被懲罰**。那條回饋迴圈一旦斷掉，
       整個計畫書的機制（情感連結 → 行為改變）就失效了。

       生理的 anxious 覆寫保留，因為那是一個值得讓使用者看到的訊號
       （壓力與心率同時偏離個人 baseline），而且它是**資訊**不是懲罰。

    ⚠️ 沒有行為資料時**完全走舊路徑的規則**（build_app_payload.map_pet_mood），
       所以 API 回傳的心情與打包 asset 顯示的心情逐字相同，
       不會出現「同一個人在兩個畫面看到不同心情」。
    """
    has_behavior = (
        behavior_row is not None
        and behavior_row.get("adherence_minutes") is not None
    )

    if not has_behavior:
        if wearable_row is None:
            return None, "no_data: no records for this night", "none"
        mood, reason = map_pet_mood(wearable_row)
        return mood, reason, "wearable"

    mood, reason = pet_state.mood_for_adherence(behavior_row["adherence_minutes"])
    driver = "behavior"

    # 生理覆寫：只在真的有穿戴資料時才套用。
    # 用 map_pet_mood 算一次，若它判定為 anxious 就採用它的結論與理由——
    # 這樣 anxious 的門檻仍然只有一個定義處。
    if wearable_row is not None:
        physio_mood, physio_reason = map_pet_mood(wearable_row)
        if physio_mood == "anxious":
            return "anxious", f"{physio_reason} (physiological override; behaviour: {reason})", "wearable_override"

    return mood, reason, driver


# ═══════════════════════════════════════════════════════════════════
# 使用者
# ═══════════════════════════════════════════════════════════════════

@app.post("/users", status_code=201)
async def create_user(req: CreateUserRequest):
    """
    建立使用者（暱稱制免註冊）。回傳 user_id。

    ⚠️ **user_id 本身就是憑證**——沒有帳號密碼，誰拿到它就能讀寫
       那個人的資料。在 D2「側載 APK、區網、十來個同學」的情境下
       這是可接受的取捨，但同意書要寫清楚，日後上架前必須先補認證。
    """
    try:
        adherence.parse_bedtime(req.target_bedtime)
    except (ValueError, IndexError):
        raise HTTPException(
            status_code=422,
            detail=f'target_bedtime is malformed: {req.target_bedtime!r}; expected "HH:MM".',
        )

    db.init_db()   # 第一次呼叫就把表建好，省掉「忘了跑 db.py --init」這個坑
    user_id = db.create_user(
        display_name=req.display_name,
        target_bedtime=req.target_bedtime,
        age_band=req.age_band,
        study_cohort=req.study_cohort,
        wearable_brand=req.wearable_brand,
    )
    return {"user_id": user_id, **db.get_user(user_id)}


@app.get("/users/{user_id}")
async def get_user(user_id: str):
    """取使用者設定。"""
    return require_user(user_id)


@app.patch("/users/{user_id}")
async def update_user(user_id: str, req: UpdateUserRequest):
    """
    更新使用者設定（主要是改目標就寢時間）。

    ⚠️ 改目標**不會**追溯性地改寫歷史達成度——nightly_behavior 存的是
       當晚的 target_bedtime 快照。否則「我上週明明有達成」會在改了
       目標之後變成「沒有達成」，而使用者完全不知道發生什麼事。
    """
    require_user(user_id)

    fields = {k: v for k, v in req.model_dump().items() if v is not None}
    if not fields:
        raise HTTPException(status_code=422, detail="No fields to update.")

    if "target_bedtime" in fields:
        try:
            adherence.parse_bedtime(fields["target_bedtime"])
        except (ValueError, IndexError):
            raise HTTPException(
                status_code=422,
                detail=f'target_bedtime is malformed: {fields["target_bedtime"]!r}; '
                       f'expected "HH:MM".',
            )

    try:
        db.update_user(user_id, **fields)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return db.get_user(user_id)


@app.delete("/users/{user_id}")
async def delete_user(user_id: str):
    """
    刪除使用者及其**所有**資料。

    ⚠️ 這不是可有可無的端點。知情同意書必須寫明受測者可以隨時退出並
       刪除資料，而這就是那個動作的實作。靠 ON DELETE CASCADE 一次清乾淨
       （前提是 PRAGMA foreign_keys 有開，見 db.connect()）。
    """
    require_user(user_id)
    # ⚠️ 先刪片段檔案再刪資料列：CASCADE 會把 camera_clips 的列一起清掉，
    #    之後就再也查不到這個人有哪些檔案了。片段是**原始畫面**，
    #    留在磁碟上就違反「退出即刪除」。
    camera_clips.delete_user_clips(user_id)
    db.delete_user(user_id)
    return {"deleted": True, "user_id": user_id}


# ═══════════════════════════════════════════════════════════════════
# 上傳
# ═══════════════════════════════════════════════════════════════════

@app.post("/nightly", status_code=201)
async def post_nightly(req: NightlyRequest):
    """
    App 上傳一晚的 Tier A 行為資料。

    target_bedtime 沒給的話用使用者**當下**的設定，並存成當晚的快照。
    """
    user = require_user(req.user_id)
    target = req.target_bedtime or user["target_bedtime"]

    try:
        night = adherence.evaluate_night(
            req.lights_out_at, target, source=req.source
        )
    except (ValueError, IndexError) as exc:
        raise HTTPException(
            status_code=422,
            detail=f"Could not parse lights_out_at / target_bedtime: {exc}",
        ) from exc

    if night["date"] is None:
        raise HTTPException(
            status_code=422,
            detail="lights_out_at must not be empty - not-measured and on-time are different things; "
                   "do not upload nights that were not measured.",
        )

    # 行為版睡眠效率。⚠️ 與 wearable_nightly.efficiency 是**不同的量**，
    #    限制與反向判讀的完整說明在 behavior/sleep_efficiency.py 的檔頭。
    #    沒按開始／結束睡覺時每個欄位都是 None，不是 0。
    # ⚠️ 這一列的日期來自 lights_out_at，但按鈕的時刻是**它自己那一晚**的。
    #    兩者不一致時把標記掛上去就是張冠李戴——實測 2026-09-07 早上，
    #    App 在新的安靜期還不是最長之前先上傳了一次，於是 09-07 03:36 的
    #    「開始睡覺」被寫進了 09-06 那一列（算出 −1282 分鐘的荒謬差值）。
    #
    #    不一致就整組不收。等 lights_out 追上那一晚，App 下次上傳自然會
    #    掛對——實測就是這樣自己修好的，09-07 那一列完全正確。
    bed_start_dt = None
    if req.bed_start_at:
        try:
            bed_start_dt = datetime.fromisoformat(req.bed_start_at)
        except ValueError:
            bed_start_dt = None
    same_night = (
        bed_start_dt is not None
        and adherence.night_date(bed_start_dt).isoformat() == night["date"]
    )

    # ═══ 這次請求沒有可用的同晚標記時，沿用資料庫裡已經存的那一組 ═══
    # （2026-09-11）upsert 是整列覆寫，先前這裡直接傳 None，於是兩條路都會
    # 把已存的標記抹成 NULL，而且都回 201：
    #   ① App 每次回到前景都重傳同一晚；第一次收下後本機就清掉，
    #      之後的重傳不帶標記 → 抹掉。
    #   ② 晚上按了「開始睡覺」再切回 App，送出的是**上一晚**的 lights_out
    #      配**今晚**的開始 → same_night 正確地拒收 → 但拒收寫進去的是 NULL。
    # 實測 MySQL 裡每一晚的 bed_start_at 都是 NULL，包括補登時回過 84.6% 的 09-09。
    req_start = req.bed_start_at if same_night else None
    req_end = req.bed_end_at if same_night else None
    req_start_kind = (req.bed_start_kind or "tap") if req_start else None
    req_end_kind = (req.bed_end_kind or "tap") if req_end else None
    stored_start, stored_end = db.get_bed_marks(req.user_id, night["date"])
    stored_start_kind, stored_end_kind = db.get_bed_mark_kinds(
        req.user_id, night["date"])
    stored_start_kind = (stored_start_kind or "tap") if stored_start else None
    stored_end_kind = (stored_end_kind or "tap") if stored_end else None

    # ⚠️ 當下按的不能被事後回想的蓋掉（2026-11-12 使用者定）：按鈕是攝影機上床
    #    偵測的標準答案，比回想準。App 端也只讓使用者補缺的那一個，這裡再守一次。
    if (req_start_kind == "recalled" and stored_start_kind == "tap"
            and not _same_instant(stored_start, req_start)):
        req_start, req_start_kind = stored_start, stored_start_kind
    if (req_end_kind == "recalled" and stored_end_kind == "tap"
            and not _same_instant(stored_end, req_end)):
        req_end, req_end_kind = stored_end, stored_end_kind

    if req_start is not None:
        # 帶了就照帶的（更正仍然有效）。只帶上床、而且是同一次按的，
        # 下床沿用先前存下的——上床先傳、下床後補是正常的順序。
        use_start, use_end = req_start, req_end
        start_kind, end_kind = req_start_kind, req_end_kind
        if use_end is None and _same_instant(stored_start, req_start):
            use_end, end_kind = stored_end, stored_end_kind
        marks_source = "request"
    elif stored_start is not None:
        use_start, use_end, marks_source = stored_start, stored_end, "stored"
        start_kind, end_kind = stored_start_kind, stored_end_kind
    else:
        use_start = use_end = marks_source = None
        start_kind = end_kind = None

    try:
        eff = sleep_efficiency.evaluate_efficiency(
            use_start,
            req.lights_out_at,
            use_end,
            source=req.source,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=f"Could not parse bed_start_at / bed_end_at: {exc}",
        ) from exc

    db.upsert_nightly_behavior(
        user_id=req.user_id,
        date=night["date"],
        target_bedtime=night["target_bedtime"],
        lights_out_at=night["lights_out_at"],
        adherence_minutes=night["adherence_minutes"],
        is_late=night["is_late"],
        source=night["source"],
        efficiency=eff,
        bed_start_kind=start_kind,
        bed_end_kind=end_kind,
    )
    # 回應把兩者合起來。⚠️ 達成度與效率都**只在後端算**，Dart 端照抄不重算
    #    （CLAUDE.md「達成度只在後端算」——兩份定義漂移時不會有任何錯誤訊息）。
    resp = {**night, **{k: v for k, v in eff.items() if k != "source"}}
    # ⚠️ App 拿回應裡的 bed_start_at 判斷「我送出去的標記被收下了」，收下就清本機
    #    （nightly_uploader.dart 的 marksStored）。沿用舊標記時若把它放進回應，
    #    App 會以為收下的是它剛送的——上面第 ② 條路送的是**今晚**的開始，
    #    被清掉就是今晚的標記沒了。所以這兩欄只回報**這次請求**被接受的；
    #    效率欄位照實反映實際存下的那一組，由 bed_marks_source 說明是哪一組。
    if marks_source != "request":
        resp["bed_start_at"] = None
        resp["bed_end_at"] = None
    resp["bed_marks_source"] = marks_source
    resp["bed_start_kind"] = start_kind if eff.get("bed_start_at") else None
    resp["bed_end_kind"] = end_kind if eff.get("bed_end_at") else None
    return resp


def _same_instant(a, b):
    """兩個 ISO 時刻字串是不是同一個時刻。缺值或解析不了就當作不是。

    ⚠️ 不能直接比字串：存進去的是 evaluate_efficiency 正規化過的 isoformat，
       App 送來的格式不一定逐字相同。
    """
    if not a or not b:
        return False
    try:
        return datetime.fromisoformat(a) == datetime.fromisoformat(b)
    except ValueError:
        return False


@app.post("/wearable", status_code=201)
async def post_wearable(req: WearableRequest):
    """
    App 上傳一筆 Health Connect 睡眠 session。

    ⚠️ 分數在**這裡**算完才寫進資料庫，走的是 garmin/evaluate_sleep_quality.py
       這個既有評分器，一個門檻都沒改。API 層對 wearable_nightly 是唯讀的
       （紅線 8.7），寫入只由這條上傳路徑與 migrate_garmin_to_db.py 進行。
    """
    user = require_user(req.user_id)

    try:
        night_date, metrics, features = to_wearable_row(
            req.session,
            date=req.date,
            age_band=user["age_band"],
            device_brand=req.device_brand or user.get("wearable_brand"),
        )
    except HealthConnectError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    # ⚠️ **同一晚已經有 Garmin 就不蓋（Garmin 優先，2026-09-13 使用者決定）。**
    #
    #    主鍵是 (帳號, 日期)，一晚只能留一列。實機上兩個來源常常是**同一支錶**：
    #    Garmin Connect 會把睡眠同步進 Health Connect，Sonnap 再從那裡讀一次。
    #    不擋的話，同一晚的分數會跟著「誰最後送」跳動（09-11：Garmin 69.8、
    #    Health Connect 75.9），而且沒有任何錯誤訊息。
    #    留 Garmin 的理由：它走完整 pipeline，有戴錶者分段與 Tier3 個人化修正；
    #    Health Connect 來源的 Tier3 一律是 0（見 adapter 的 HC_MODIFIER_NOTE）。
    #
    #    回 409 而不是 201：App 要能分辨「收下了」與「那晚已經有 Garmin、不必再送」，
    #    後者不重送（見 health_connect.dart 的 WearableUploadStatus.keptGarmin）。
    #    反方向（Garmin 蓋掉 Health Connect）由 migrate_garmin_to_db.py 負責。
    if db.get_wearable_source(req.user_id, night_date) == "garmin":
        raise HTTPException(
            status_code=409,
            detail=f"{night_date} already has Garmin data; the Garmin night is kept.",
        )

    db.upsert_wearable_nightly(
        user_id=req.user_id, date=night_date,
        source="health_connect", metrics=metrics,
    )

    return {
        "date": night_date,
        "base_score": metrics["base_score"],
        "base_quality": metrics["base_quality"],
        "final_score": metrics["final_score"],
        "rem_measured": bool(metrics["rem_measured"]),
        # 臥床時間是 Health Connect 才有的東西，回給 App 讓它可以顯示
        # 入睡潛伏期與臨床效率（Garmin 這兩項一律 null）。
        "time_in_bed_min": metrics["time_in_bed_min"],
        "sleep_latency_min": features["sleep_latency_minutes"],
        "clinical_efficiency": metrics["clinical_efficiency"],
        "modifier_note": metrics["modifier_note"],
        # 認不得的分期代碼要浮出來，代表 Health Connect 版本可能有變動
        "unknown_stage_labels": features["unknown_stage_labels"],
    }


# ═══════════════════════════════════════════════════════════════════
# 讀取
# ═══════════════════════════════════════════════════════════════════

@app.get("/home")
async def get_home(
    user_id: str = Query(..., description="User ID"),
    date: Optional[str] = Query(None, description="A specific night; defaults to the latest."),
):
    """
    某使用者的今日主頁資料。

    結構刻意與舊路徑的 payload 相容（status / metrics / scoring / display /
    streak / data_sources / notes / disclaimer 都在），另加一個 behavior 區塊。
    這樣 Flutter 端不需要為兩種使用者寫兩套解析。
    """
    user = require_user(user_id)

    behavior_rows = db.get_nightly_behavior(user_id, days=DEFAULT_HISTORY_DAYS)
    wearable_rows = db.get_wearable_nightly(user_id, days=DEFAULT_HISTORY_DAYS)

    target_date = date or pick_latest_date(behavior_rows, wearable_rows)
    b_row = _row_for(behavior_rows, target_date)
    w_row = _row_for(wearable_rows, target_date)

    mood, mood_reason, driver = resolve_mood(b_row, w_row)
    display = display_for(mood, driver, w_row)

    # ── streak：用 Tier A 算，因為那是每個人都有的 ──
    streak_days, streak_as_of = challenge_engine.current_streak(behavior_rows)

    data_sources = []
    if b_row:
        data_sources.append("behavior")
    if w_row:
        data_sources.append(w_row.get("source") or "wearable")

    ratio, late_nights, recorded = adherence.late_night_ratio(behavior_rows)

    return {
        "schema_version": SCHEMA_VERSION,
        "user": {
            "user_id": user["user_id"],
            "display_name": user["display_name"],
            "target_bedtime": user["target_bedtime"],
            "study_cohort": user["study_cohort"],
        },
        "date": target_date,
        "status": {
            "pet_mood": mood,
            # 需要「此刻」的狀態，但兩層都是「昨晚」的批次資料，給不出來。
            # 硬填就是編造，留 null 讓 App fallback 到 idle 動畫。
            "current_activity": None,
            # ⚠️ energy_level 的定義是睡眠分數。沒有穿戴資料的人是 null，
            #    **不要**拿 adherence 換算一個出來——那會製造第二個
            #    看起來像分數、卻沒有任何文獻依據的數字（見 pet_state.py）。
            "energy_level": (
                round(w_row["final_score"])
                if w_row and w_row.get("final_score") is not None else None
            ),
            "mood_reason": mood_reason,
            "mood_driver": driver,
        },
        # ── Tier A：每個人都有 ──
        "behavior": {
            "target_bedtime": b_row["target_bedtime"] if b_row else user["target_bedtime"],
            "lights_out_at": b_row["lights_out_at"] if b_row else None,
            "adherence_minutes": b_row["adherence_minutes"] if b_row else None,
            "is_late": bool(b_row["is_late"]) if b_row and b_row["is_late"] is not None else None,
            "source": b_row["source"] if b_row else None,
            # ── 行為版睡眠效率 ──
            # ⚠️ 這個 sleep_efficiency 與底下 metrics.sleep_efficiency
            #    （Garmin 的）是**不同的量**：那個分子是手錶量的總睡眠、
            #    有文獻、進 final_score；這個分子是**假定**的、不進任何分數。
            #    兩者同時出現在這個回應裡，所以 basis 與 note 一定要一起給
            #    —— 少了它們，前端無從分辨自己拿到的是哪一個。
            "bed_start_at": b_row["bed_start_at"] if b_row else None,
            "bed_end_at": b_row["bed_end_at"] if b_row else None,
            "time_in_bed_minutes": b_row["time_in_bed_minutes"] if b_row else None,
            "phone_in_bed_minutes": b_row["phone_in_bed_minutes"] if b_row else None,
            "sleep_efficiency": b_row["sleep_efficiency"] if b_row else None,
            "efficiency_basis": b_row["efficiency_basis"] if b_row else None,
            "efficiency_note": (
                "Assumes sleep begins when the phone is put down and that there "
                "are no awakenings. Not comparable with clinical sleep efficiency."
                if b_row and b_row["sleep_efficiency"] is not None else None
            ),
            # ⚠️ 分子改用手錶實測的那個效率。與 /insights 逐夜那一份**走同一支
            #    純函式**——兩邊各寫一次算式的話，同一晚會在首頁與 Insights
            #    顯示兩個不同的百分比，而且不會有任何錯誤訊息。
            **sleep_efficiency.measured_efficiency(
                (w_row or {}).get("duration_min"),
                b_row["time_in_bed_minutes"] if b_row else None,
                # ⚠️ 標記本身也要給：算不出來時，「沒按」與「按了但那一對
                #    不能用」要講不同的話（10-01 實測兩下差 1.8 秒）。
                b_row["bed_start_at"] if b_row else None,
                b_row["bed_end_at"] if b_row else None,
            ),
            # ⚠️ 並列的第二個：結束時刻改用**手錶認定的起床**，所以忘了按
            #    Out of bed 的夜晚也算得出來（實測 3 晚 → 6 晚）。
            #    **兩個都要回**：它們的分母不一樣，少了任何一個，前端就只能
            #    拿到半邊的事實。各自帶 basis，不會被混為一談。
            **sleep_efficiency.watch_wake_efficiency(
                (w_row or {}).get("duration_min"),
                b_row["bed_start_at"] if b_row else None,
                (w_row or {}).get("wake_time"),
            ),
            "late_night_ratio": ratio,
            "late_nights": late_nights,
            "recorded_nights": recorded,
            "lights_out_note": (
                "lights_out_at is a proxy for the last phone interaction, "
                "not the moment of sleep onset."
            ),
        },
        # ── Tier B：有穿戴裝置的人才有 ──
        "metrics": None if not w_row else {
            "sleep_duration_minutes": w_row["duration_min"],
            "sleep_efficiency": w_row["efficiency"],
            "waso_minutes": w_row["waso_min"],
            "deep_minutes": w_row["deep_min"],
            "rem_minutes": w_row["rem_min"],
            # 早晨報告的淺睡／深睡／REM 比例條用（2026-11-12）。表裡沒有淺睡欄位，
            # 所以是「總睡眠 − 深睡 − REM」。⚠️ 那晚沒量到 REM 時回 null：
            # 減出來的數字會把 REM 吃進淺睡裡，跟 Sleep Stages 圖「沒量到就不畫」同一條規矩。
            "light_minutes": _light_minutes(w_row),
            # 每一晚的曲線（早晨報告）。只有 Garmin 來源才有，見 night_stages()。
            "sleep_stages": night_stages(w_row),
            # 睡著期間的心率與手錶動作曲線（2026-11-13）。只呈現、不計分。
            "heart_rate_curve": night_heart_rate(w_row),
            "movement_curve": night_movement(w_row),
            "camera_curve": night_camera_curve(user_id, target_date, w_row),
            "avg_heart_rate": w_row["avg_hr"],
            "resting_heart_rate": w_row["resting_hr"],
            # ⚠️ 「睡著」與「醒來」的時刻，不是「上床」與「下床」。
            #    上床時刻在 behavior.lights_out_at，那是另一個構念。
            "sleep_start_time": w_row["sleep_start_time"],
            "wake_time": w_row["wake_time"],
            # 只有 Health Connect 給得出來；Garmin 一律 null（見 3.9）
            "time_in_bed_minutes": w_row["time_in_bed_min"],
            "clinical_sleep_efficiency": w_row["clinical_efficiency"],
            # 這兩個欄位兩種來源都給不出真值，維持 null（與舊路徑一致）
            "motion_count": None,
            "ambient_noise_db": None,
        },
        "scoring": None if not w_row else {
            "final_score": w_row["final_score"],
            "final_quality": w_row["final_quality"],
            "base_score": w_row["base_score"],
            "total_modifier": w_row["total_modifier"],
            "sri": w_row["sri"],
            "modifier_note": w_row["modifier_note"],
            "rem_measured": bool(w_row["rem_measured"]),
            "source": w_row["source"],
            "device_brand": w_row["device_brand"],
            # ⚠️ 分數由哪幾項組成。裝置組合因人而異，兩個都是 82 分的夜晚
            #    可能不是同一回事——見 score_composition() 的說明。
            "composition": score_composition(w_row, b_row),
        },
        "display": display,
        # ── 早晨報告（2026-11-12）──
        # 起床自評：**不進分數、不給 XP**，只並列顯示。
        "morning_rating": rating_block(
            db.get_morning_rating(user_id, target_date) if target_date else None),
        # 「跟上一晚比」的箭頭：給上一個有資料的晚上的原始數字，箭頭方向由 App 比
        # （只代表方向，上升紅、下降綠，與首頁同一條規矩；好壞不在這裡判斷）。
        # Garmin 白天資料（2026-11-13）：只呈現、不計分；沒有資料就整塊 null
        "yesterday": yesterday_block(user_id, target_date),
        "previous_night": {
            "time_in_bed_minutes": (_previous(behavior_rows, target_date, "time_in_bed_minutes")
                                    or {}).get("time_in_bed_minutes"),
            "sleep_duration_minutes": (_previous(wearable_rows, target_date, "duration_min")
                                       or {}).get("duration_min"),
        },
        "streak": {
            "streak_days": streak_days,
            "as_of": streak_as_of.isoformat() if streak_as_of else None,
            "definition": (
                "Consecutive nights with lights out before the target bedtime. "
                "A night with no data breaks the streak - treating missing data as skipped "
                "would let people build streaks by only opening the app on good days."
            ),
        },
        # ⚠️ AI 夢境／建議目前只為研究者本人批次生成（ai/data/ai_advice.json），
        #    還沒有 per-user 的生成流程，所以這條路徑一律 null。
        #    留 null 而不省略欄位，是讓這個缺口對 App 端可見。
        "ai_content": None,
        "data_sources": data_sources,
        "notes": {
            "tier_b_comparability": (
                "Sleep staging algorithms differ across brands, so Tier B values support "
                "within-person comparison only, never cross-user ranking. Use the behaviour block instead."
            ),
            "ai": "AI dreams and advice do not support multiple users yet; this path is always null.",
        },
        "disclaimer": (
            "Sleep scores are computed from wearable data using literature-weighted rules and do not constitute a medical diagnosis."
        ),
    }


@app.get("/insights")
async def get_insights(
    user_id: str = Query(...),
    days: int = Query(DEFAULT_HISTORY_DAYS, ge=1, le=365),
):
    """
    趨勢資料 + 熬夜比率。

    熬夜比率就是計畫書圖五統計頁那個「過去 30 天熬夜比率 40%」——
    在這一輪之前，那個數字**沒有任何程式算得出來**。
    """
    require_user(user_id)

    behavior_rows = db.get_nightly_behavior(user_id, days=days)
    wearable_rows = db.get_wearable_nightly(user_id, days=days)
    # ⚠️ 多抓一段，只拿來當「跟你平常比」的基線，**不顯示**。
    #    理由：get_camera_nightly 的 days 參數其實是「最近 N 列」不是「N 天」，
    #    只抓要顯示的那幾晚的話，視窗裡最舊的幾晚會誤報「還需要幾晚」——
    #    即使資料庫裡有更早的夜晚。多抓的量要蓋得住 28 天的窗格。
    camera_all = db.get_camera_nightly(user_id, days=days + camera_usual.BASELINE_WINDOW_DAYS)
    camera_usual.annotate(camera_all)
    camera_rows = camera_all[-days:] if days else camera_all
    clip_nights = db.get_camera_clip_nights(user_id) if camera_rows else {}

    ratio, late_nights, recorded = adherence.late_night_ratio(behavior_rows)
    spread, spread_n = adherence.bedtime_spread_minutes(behavior_rows)

    # 每晚的寵物心情，給 Insights 頁「點某一晚 → 寵物跟著換」用。
    #
    # ⚠️ 用 resolve_mood 而不是直接用 map_pet_mood，理由是 /home 的
    #    status.pet_mood 也走 resolve_mood——兩邊規則不一致的話，有行為
    #    資料的使用者會在首頁與 Insights 對**同一晚**看到兩隻不同的寵物，
    #    而那種 bug 不會有任何錯誤訊息。沒有行為資料時 resolve_mood 會
    #    完全退回 map_pet_mood，所以與打包 asset 的 history 逐字相同。
    #
    # ⚠️ 心情不在 Dart 端推。history 沒有 stress/rhr/avg_hr modifier 三欄，
    #    照 final_quality 硬推會把 anxious 的夜晚畫成 happy。
    # ⚠️ 配對用的查找表從大窗格取，理由見 JOIN_LOOKUP_ROWS。
    #    兩個方向都會錯：手機那晚找不到手錶（效率說沒資料），
    #    手錶那晚找不到手機（心情退回純生理規則，與首頁不一致）。
    behavior_by_date = {
        r["date"]: r for r in db.get_nightly_behavior(user_id, days=JOIN_LOOKUP_ROWS)}
    wearable_by_date = {
        r["date"]: r for r in db.get_wearable_nightly(user_id, days=JOIN_LOOKUP_ROWS)}

    moods = {
        r["date"]: resolve_mood(behavior_by_date.get(r["date"]), r)
        for r in wearable_rows
    }

    scored = [r for r in wearable_rows if r.get("final_score") is not None]
    distribution: Dict[str, int] = {}
    for r in scored:
        q = r.get("final_quality") or "unknown"
        distribution[q] = distribution.get(q, 0) + 1

    return {
        "user_id": user_id,
        "days": days,
        "behavior": {
            # ⚠️ 分母是「有測到資料的夜數」而不是日曆天數。把沒資料的日子
            #    當成「沒熬夜」會讓數字好看但沒有意義；當成「熬夜」則是
            #    憑空捏造。所以連 recorded_nights 一起回，讓看的人知道
            #    樣本有多大。
            "late_night_ratio": ratio,
            "late_nights": late_nights,
            "recorded_nights": recorded,
            "bedtime_spread_minutes": spread,
            "bedtime_spread_sample": spread_n,
            # ⚠️ history 裡那個 sleep_efficiency 與 wearable.history 裡的
            #    **不是同一個量**（見 behavior/sleep_efficiency.py 檔頭）。
            #    這句說明放在這裡一次，逐夜的 efficiency_basis 則跟著每一列走
            #    —— 之後 WASO 有來源時 basis 會換值，舊夜晚要保留舊的那個。
            "efficiency_note": (
                "behavior.*.sleep_efficiency assumes sleep begins when the phone "
                "is put down and that there are no awakenings. It is NOT the same "
                "quantity as wearable sleep efficiency and must not be compared "
                "with clinical thresholds."
            ),
            "history": [
                {
                    "date": r["date"],
                    "lights_out_at": r["lights_out_at"],
                    "adherence_minutes": r["adherence_minutes"],
                    "is_late": bool(r["is_late"]) if r["is_late"] is not None else None,
                    "bed_start_at": r["bed_start_at"],
                    "bed_end_at": r["bed_end_at"],
                    "time_in_bed_minutes": r["time_in_bed_minutes"],
                    "phone_in_bed_minutes": r["phone_in_bed_minutes"],
                    "sleep_efficiency": r["sleep_efficiency"],
                    "efficiency_basis": r["efficiency_basis"],
                    # ⚠️ 分子改用手錶實測的那個效率。**在這裡 join、不存資料庫**：
                    #    手機與手錶的寫入時機不固定（手機早上自己上傳，手錶要有人
                    #    跑 morning_import），寫入時算的話手錶晚到的夜晚會永遠是
                    #    null 且不會回頭補。讀取時算則手錶哪天進來哪天就對。
                    **sleep_efficiency.measured_efficiency(
                        wearable_by_date.get(r["date"], {}).get("duration_min"),
                        r["time_in_bed_minutes"],
                        r["bed_start_at"],
                        r["bed_end_at"],
                    ),
                    # 並列的第二個，理由同 /home。
                    **sleep_efficiency.watch_wake_efficiency(
                        wearable_by_date.get(r["date"], {}).get("duration_min"),
                        r["bed_start_at"],
                        wearable_by_date.get(r["date"], {}).get("wake_time"),
                    ),
                }
                for r in behavior_rows
            ],
        },
        "wearable": None if not wearable_rows else {
            "average_score": (
                round(sum(r["final_score"] for r in scored) / len(scored), 1)
                if scored else None
            ),
            "quality_distribution": distribution,
            "history": [
                {
                    "date": r["date"],
                    "pet_mood": moods[r["date"]][0],
                    "mood_reason": moods[r["date"]][1],
                    "final_score": r["final_score"],
                    "final_quality": r["final_quality"],
                    # ⚠️ 逐夜都帶，因為組成會隨當晚量到什麼而變（例如某幾晚
                    #    手錶測不到 REM）。只在最上層給一次會讓人以為每晚一樣。
                    "composition": score_composition(
                        r, behavior_by_date.get(r["date"])),
                    "sleep_duration_hours": (
                        round(r["duration_min"] / 60.0, 2)
                        if r["duration_min"] is not None else None
                    ),
                    # 首頁「跟上一晚比」要逐夜的效率與深睡（2026-11-12）。
                    # ⚠️ 與 /home 的 metrics 同一個欄位（wearable_nightly.efficiency /
                    #    deep_min），欄名與 asset 路徑的 history 相同。
                    "sleep_efficiency": r["efficiency"],
                    "deep_minutes": r["deep_min"],
                    # Insights 頁要畫「幾點睡→幾點醒」。與 asset 路徑
                    # （build_app_payload.py 的 history）同一個來源，欄名也相同。
                    "sleep_start_time": r["sleep_start_time"],
                    "wake_time": r["wake_time"],
                    "sri": r["sri"],
                    "source": r["source"],
                    "device_brand": r["device_brand"],
                }
                for r in wearable_rows
            ],
        },
        # ⚠️ 呈現用，**不計分**。攝影機目前沒有任何合格的計分項
        #    （Research-Background/攝影機分數.md 的結論是 0 項），所以這個
        #    區塊刻意只有量與 provenance，沒有 score／quality。
        # ⚠️ 沒有資料時回 None 而不是空陣列：畫面要能說「沒有攝影機資料」，
        #    而不是畫出一排 0。
        "camera": None if not camera_rows else {
            "note": (
                "Camera metrics are presentational only and never enter any score. "
                "Time in bed is SELF-REPORTED (recording start/stop), not detected. "
                "Sleep onset is detected from motion density and has been compared "
                "against a physiological criterion on 2 nights only."
            ),
            "floor_note": (
                "When sleep_onset_below_floor is true, the latency is shorter than "
                "the detector can resolve: read it as 'at most floor minutes'. "
                "It is NOT zero - latency and onset are null in that case."
            ),
            # ⚠️ 只在 camera_usual.py 定義，這裡與 Dart 都照抄。
            "usual_note": camera_usual.NOTE,
            "history": [
                {
                    "date": r["date"],
                    "bed_start_at": r["bed_start_at"],
                    "bed_end_at": r["bed_end_at"],
                    "time_in_bed_minutes": r["time_in_bed_minutes"],
                    "sleep_onset_at": r["sleep_onset_at"],
                    "sleep_onset_latency_minutes": r["sleep_onset_latency_minutes"],
                    "sleep_onset_below_floor": bool(r["sleep_onset_below_floor"]),
                    "sleep_onset_floor_minutes": r["sleep_onset_floor_minutes"],
                    "events_total": r["events_total"],
                    "events_per_hour": r["events_per_hour"],
                    "bed_times_provenance": r["bed_times_provenance"],
                    "sleep_onset_provenance": r["sleep_onset_provenance"],
                    "motion_threshold_pct": r["motion_threshold_pct"],
                    "motion_threshold_basis": r["motion_threshold_basis"],
                    # 「跟你平常比」。⚠️ label 是給人讀的那句話，Dart 照抄不重寫。
                    "usual": r.get("usual"),
                    "roi": r["roi"],
                    "csv_name": r["csv_name"],
                    **_camera_clips_for(clip_nights.get(r["date"])),
                }
                for r in camera_rows
            ],
        },
        "notes": {
            "tier_b_comparability": (
                "Values in wearable.history support within-person trends only; "
                "they must not be compared across users (staging algorithms differ by brand)."
            ),
        },
    }


def _camera_clips_for(night):
    """
    一晚的動作片段 → {clips, clips_note}。沒有片段時 clips 是空陣列、note 講原因。

    ⚠️ note 的文字只在 camera_clips.py 定義，這裡與 Dart 都照抄。
    ⚠️ 網址只有 clip_id、不含 user_id（camera_clips.py 檔頭第 2 點）。
    """
    if not night:
        return {"clips": [], "clips_note": camera_clips.NOT_MADE_NOTE}
    return {
        "clips": [
            {
                "url": camera_clips.clip_url(c["clip_id"]),
                "label": c["label"],
                "start_at": c["start_at"],
                "duration_seconds": c["duration_seconds"],
                "rank": c["clip_rank"],
            }
            for c in night["clips"]
        ],
        "clips_note": None if night["clips"] else night["note"],
    }


@app.get("/camera/clips/{name}")
async def get_camera_clip(name: str):
    """
    一段動作片段的 GIF。

    ⚠️ 刻意**不收 user_id**：網址會原樣出現在 uvicorn 的 access log 裡，
       而 user_id 是憑證。片段靠 clip_id（隨機 128 位元）本身擋人——
       只有 /insights（要 user_id）會告訴你自己的片段叫什麼。
    ⚠️ 格式不對、查無此片段、檔案不見，一律回同一個 404，不透露是哪一種。
    """
    clip_id = name[:-4] if name.endswith(".gif") else None
    path = camera_clips.clip_path(clip_id)
    if path is None or db.get_camera_clip(clip_id) is None or not path.exists():
        raise HTTPException(status_code=404, detail="Clip not found.")
    return FileResponse(path, media_type="image/gif",
                        headers={"Cache-Control": "private, max-age=86400"})


@app.get("/challenges")
async def get_challenges(
    user_id: str = Query(...),
    as_of: Optional[str] = Query(None, description="Reference day; defaults to the latest recorded day."),
):
    """
    挑戰清單與進度。

    ⚠️ 進度是**每次即時重算**的，不是從 challenge_progress 讀出來累加。
       事實來源永遠是 nightly_behavior，所以受測者事後補填某一晚，
       進度會自動更正。

    ⚠️ 三個挑戰的標的**全部是行為**，沒有一個讀 wearable_nightly——
       使用者控制得了「幾點放下手機」，控制不了「深睡幾分鐘」。
    """
    require_user(user_id)

    if as_of is not None:
        try:
            date_cls.fromisoformat(as_of)
        except ValueError:
            raise HTTPException(
                status_code=422, detail=f"as_of is malformed: {as_of!r}; expected YYYY-MM-DD"
            )

    defs = db.get_challenges()
    if not defs:
        raise HTTPException(
            status_code=503,
            detail="Challenge definitions are not loaded. Run: python db.py --seed",
        )

    # ⚠️ 取的夜數要涵蓋最長的窗格，否則長窗格的挑戰會少看到資料
    #    而回報 insufficient_data。不要寫死 30。
    need_days = max(DEFAULT_HISTORY_DAYS, max(c["window_days"] for c in defs))
    rows = db.get_nightly_behavior(user_id, days=need_days)

    results = challenge_engine.evaluate_all(defs, rows, as_of=as_of)
    return {
        "user_id": user_id,
        "as_of": as_of,
        "challenges": results,
        "notes": {
            "targets_are_behavioral": (
                "Every challenge targets a behaviour (when you put the phone down), "
                "not a physiological outcome (minutes of deep sleep) - users cannot control the latter."
            ),
            "calibration": (
                "Difficulty thresholds were calibrated on the researcher's 46 nights, but n=1; "
                "recalibrate once D2 provides real data."
            ),
        },
    }


# ═══════════════════════════════════════════════════════════════════
# 遊戲化（B2）
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ 設計紅線 4：這四個端點**只讀**評分層與行為層，唯一會寫的是
#    user_game_state / user_inventory / achievements 三張遊戲表。
#    tests/test_game_rewards.py 會在打完所有端點後比對評分表逐欄沒變。
# ⚠️ 設計紅線 5：熬夜又睡不好的一晚是 0 XP，只是「有資料」拿不到東西。
#    數字在 game/xp.py，這裡不重算任何一格。

# XP 是累積的，要看全部夜晚。LIMIT 只是保險，十年夠用。
GAME_HISTORY_DAYS = 3650


class ClaimRequest(BaseModel):
    user_id: str
    challenge_id: str


class EquipRequest(BaseModel):
    user_id: str
    item_id: Optional[str] = None     # None = 脫掉


def _game_inputs(user_id):
    """一次撈齊 game/state.py 要的東西。挑戰達成與否一律由挑戰引擎判定。"""
    behavior_rows = db.get_nightly_behavior(user_id, days=GAME_HISTORY_DAYS)
    wearable_rows = db.get_wearable_nightly(user_id, days=GAME_HISTORY_DAYS)
    achievement_rows = db.get_achievements(user_id)
    defs = db.get_challenges()
    evaluated = challenge_engine.evaluate_all(defs, behavior_rows) if defs else []
    return behavior_rows, wearable_rows, achievement_rows, evaluated, defs


@app.get("/game")
async def get_game(user_id: str = Query(...)):
    """
    XP、等級、寵物成長階段、可以領的挑戰獎勵、徽章。

    ⚠️ 每一格都是即時算的，沒有任何一格存在資料庫裡（除了「領過了沒」）。
    """
    require_user(user_id)
    behavior_rows, wearable_rows, achievement_rows, evaluated, _ = _game_inputs(user_id)
    state = game_state.build_game_state(
        behavior_rows, wearable_rows, achievement_rows, evaluated)
    return {
        "user_id": user_id,
        **state,
        "notes": {
            "rewards_follow_quality": (
                "A late night with poor sleep earns 0 XP; having a record alone earns nothing."
            ),
            "behaviour_first": (
                "Most XP comes from when you put the phone down, which you control; "
                "sleep quality is a smaller bonus and only exists for nights with a watch."
            ),
            "not_a_score": (
                "XP and levels are a game layer. They never feed back into the sleep score."
            ),
        },
    }


@app.post("/game/claim", status_code=201)
async def claim_reward(req: ClaimRequest):
    """
    領一個已完成挑戰的獎勵。每個挑戰每個窗格一次（見 game/rewards.py）。

    404 = 沒有這個挑戰；422 = 還沒完成；409 = 這個窗格已經領過了。
    ⚠️ 422 與 409 要分開：前者是「去做」，後者是「做過了、下個窗格再來」，
       給使用者的話完全不同。
    """
    require_user(req.user_id)
    behavior_rows, wearable_rows, achievement_rows, evaluated, defs = _game_inputs(req.user_id)
    if not any(d["challenge_id"] == req.challenge_id for d in defs):
        raise HTTPException(status_code=404, detail=f"Unknown challenge {req.challenge_id!r}.")

    before = game_state.build_game_state(
        behavior_rows, wearable_rows, achievement_rows, evaluated)
    match = next(
        (c for c in before["claimable"] if c["challenge_id"] == req.challenge_id), None)
    if match is None:
        ch = next((c for c in evaluated if c["challenge_id"] == req.challenge_id), None)
        if ch is not None and ch.get("status") == "completed":
            raise HTTPException(
                status_code=409,
                detail="Already claimed for this window. Come back in the next one.")
        raise HTTPException(status_code=422, detail="This challenge is not completed yet.")

    if not db.add_achievement(req.user_id, match["achievement_id"], match["xp"]):
        raise HTTPException(status_code=409, detail="Already claimed for this window.")

    after = game_state.build_game_state(
        behavior_rows, wearable_rows, db.get_achievements(req.user_id), evaluated)
    return {
        "user_id": req.user_id,
        "claimed": match,
        "level": after["level"],
        "xp_total": after["xp_total"],
        "leveled_up": after["level"] > before["level"],
    }


def _closet_level(user_id):
    behavior_rows, wearable_rows, achievement_rows, evaluated, _ = _game_inputs(user_id)
    return game_state.build_game_state(
        behavior_rows, wearable_rows, achievement_rows, evaluated)["level"]


@app.get("/closet")
async def get_closet(user_id: str = Query(...)):
    """衣櫃：每一件衣服、幾級解鎖、解鎖了沒、現在穿哪一件。"""
    require_user(user_id)
    level = _closet_level(user_id)
    gs = db.get_game_state(user_id)
    equipped = gs["equipped_item_id"] if gs else None
    return {
        "user_id": user_id,
        "level": level,
        "equipped_item_id": equipped,
        "items": inventory.closet_view(level, db.get_inventory(user_id), equipped),
    }


@app.post("/closet/equip")
async def equip_item(req: EquipRequest):
    """
    換衣服。item_id=None 代表脫掉。

    404 = 沒有這件衣服；403 = 還沒解鎖（訊息裡講幾級解鎖）。
    """
    require_user(req.user_id)
    if req.item_id is not None:
        item = inventory.ITEMS.get(req.item_id)
        if item is None:
            raise HTTPException(status_code=404, detail=f"Unknown item {req.item_id!r}.")
        level = _closet_level(req.user_id)
        if not inventory.is_unlocked(req.item_id, level, db.get_inventory(req.user_id)):
            raise HTTPException(
                status_code=403,
                detail=f"{item['name']} unlocks at level {item['unlock_level']} (you are level {level}).")
        # 穿過就記下來，之後規則改了也不收回。
        db.add_inventory_item(req.user_id, req.item_id)
    db.set_equipped_item(req.user_id, req.item_id)
    return {"user_id": req.user_id, "equipped_item_id": req.item_id}


# ═══════════════════════════════════════════════════════════════════
# 好友（B5）
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ 兩條紅線，tests/test_friends.py 都守著：
#    1. 只分享 Tier A 行為指標（白名單在 social/friends.py 的 FRIEND_FIELDS）。
#       不得回傳深睡／REM／心率／分數——跨裝置不能比，而且是健康資訊。
#    2. 別人的 user_id 永遠不出後端。user_id 就是憑證；好友之間用邀請碼當名牌。

FRIEND_HISTORY_DAYS = 3650


class AddFriendRequest(BaseModel):
    user_id: str
    invite_code: str


def _friend_summary(friend_id):
    user = db.get_user(friend_id)
    handle = db.ensure_invite_code(friend_id)
    rows = db.get_nightly_behavior(friend_id, days=FRIEND_HISTORY_DAYS)
    return social_friends.build_friend_summary(user, handle, rows)


def _friend_by_handle(user_id, handle):
    """邀請碼 → 朋友的 user_id。不是朋友一律 404（不透露那個碼存不存在）。"""
    friend_id = db.user_for_invite_code(handle)
    if friend_id is None or not db.are_friends(user_id, friend_id):
        raise HTTPException(status_code=404, detail="Not in your friends.")
    return friend_id


@app.get("/friends")
async def get_friends(user_id: str = Query(...)):
    """
    我的邀請碼、我的朋友們（行為摘要）、依連續達成的排行。

    ⚠️ 第一次呼叫時會替這個人建立邀請碼（之後永遠同一個）。
    """
    require_user(user_id)
    summaries = [_friend_summary(fid) for fid in db.list_friend_ids(user_id)]
    return {
        "my_invite_code": db.ensure_invite_code(user_id),
        "friends": summaries,
        "leaderboard": social_friends.leaderboard(summaries),
        "notes": {
            "what_is_shared": (
                "Friends only see behaviour: when the phone was put down, streaks and late nights. "
                "Sleep scores, sleep stages and heart rate are never shared."
            ),
            "streak_breaks_on_missing_nights": (
                "A night without a record breaks the streak, so streaks cannot be built by only "
                "recording the good nights."
            ),
        },
    }


@app.post("/friends", status_code=201)
async def add_friend(req: AddFriendRequest):
    """
    用邀請碼加好友（雙向）。

    404 = 沒有這個碼；422 = 那是你自己的碼；409 = 已經是朋友了。
    """
    require_user(req.user_id)
    friend_id = db.user_for_invite_code(req.invite_code)
    if friend_id is None:
        raise HTTPException(status_code=404, detail="No one has that invite code.")
    if friend_id == req.user_id:
        raise HTTPException(status_code=422, detail="That is your own invite code.")
    if not db.add_friendship(req.user_id, friend_id):
        raise HTTPException(status_code=409, detail="You are already friends.")
    return {"friend": _friend_summary(friend_id)}


@app.get("/friends/{handle}")
async def get_friend(handle: str, user_id: str = Query(...)):
    require_user(user_id)
    return {"friend": _friend_summary(_friend_by_handle(user_id, handle))}


@app.delete("/friends/{handle}")
async def remove_friend(handle: str, user_id: str = Query(...)):
    """解除好友，兩邊一起消失。"""
    require_user(user_id)
    friend_id = _friend_by_handle(user_id, handle)
    db.remove_friendship(user_id, friend_id)
    return {"removed": handle.strip().upper()}


# ═══════════════════════════════════════════════════════════════════
# 睡眠助理（B6）
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ 會花錢：每問一次就是一次 Claude API 呼叫（ai/llm_client.py，標準庫 urllib，不裝 SDK）。
# ⚠️ 回答要通過 ai/chat.py 的四道驗證才回給 App；兩次都沒過就 503，
#    不把沒過驗證的回答交出去。
# ⚠️ `ai.chat` 在函式裡才 import：它會連帶 import ai/generate_advice.py，
#    而那一支在 import 時就讀 ai/.env、把真的金鑰放進環境變數。放在檔案頂端的話，
#    任何一支 import main 的測試都會帶著真的金鑰在跑。


class ChatRequest(BaseModel):
    user_id: str
    message: str = Field(..., min_length=1, max_length=500)


@app.post("/chat")
def chat(req: ChatRequest):
    """
    問睡眠助理一個問題。答案只根據這個人自己的資料。

    ⚠️ 用同步的 def 而不是 async：API 呼叫最多會等 60 秒，async 的話會卡住
       整個事件迴圈，其他人的請求全部跟著等。同步的 def 會被丟到 threadpool。

    503 = 伺服器沒設定金鑰／連不上 Claude／兩次都沒通過驗證。
    """
    user = require_user(req.user_id)
    from ai import chat as chat_engine

    if not chat_engine.key_available():
        raise HTTPException(status_code=503, detail="The AI assistant is not configured on this server.")

    behavior_rows = db.get_nightly_behavior(req.user_id, days=DEFAULT_HISTORY_DAYS)
    wearable_rows = db.get_wearable_nightly(req.user_id, days=DEFAULT_HISTORY_DAYS)
    streak, _ = challenge_engine.current_streak(behavior_rows)
    facts = chat_engine.build_facts(
        user,
        behavior_rows[-1] if behavior_rows else None,
        wearable_rows[-1] if wearable_rows else None,
        streak,
        adherence.late_night_ratio(behavior_rows),
    )
    try:
        result = chat_engine.answer_question(req.message.strip(), facts)
    except chat_engine.ChatUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    return {"answer": result["answer"], "source": "llm"}


# ═══════════════════════════════════════════════════════════════════
# 早晨報告：起床自評與 AI 分析（2026-11-12）
# ═══════════════════════════════════════════════════════════════════

class RestedRequest(BaseModel):
    user_id: str
    date: str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$",
                      description="The night (wake-up day), same convention as /nightly.")
    rested: int = Field(..., ge=1, le=5,
                        description="Consensus Sleep Diary-M item 10, 1 = Not at all rested.")
    tags: List[str] = Field(default_factory=list)
    minutes_after_wake: Optional[int] = Field(None, ge=0, le=24 * 60)


@app.post("/rested")
def post_rested(req: RestedRequest):
    """
    存一晚的起床自評（同一晚再送一次就覆蓋）。

    ⚠️ **不進分數、不給 XP、不給好友看。** 評分層與遊戲化層都不讀 morning_ratings。
    ⚠️ 標籤只收 behavior/morning_tips.TAGS 裡的 id：不收自由文字（隱私、無法統計，
       送進 AI 還可能被拿來改寫指令）。
    """
    require_user(req.user_id)
    try:
        date_cls.fromisoformat(req.date)
    except ValueError:
        raise HTTPException(status_code=422, detail="date must be a real YYYY-MM-DD date")
    unknown = [t for t in req.tags if t not in morning_tips.TAGS]
    if unknown:
        raise HTTPException(status_code=422, detail=f"unknown tags: {unknown}")
    tags = list(dict.fromkeys(req.tags))            # 去重、保留順序
    db.upsert_morning_rating(req.user_id, req.date, req.rested, tags, req.minutes_after_wake)
    return {"date": req.date,
            "morning_rating": rating_block(db.get_morning_rating(req.user_id, req.date))}


# fallback 那一列多久之後再試一次（避免連不上時每打開一次報告就花一次額度）
SUMMARY_RETRY_MINUTES = 60


@app.get("/night-summary")
def get_night_summary(
    user_id: str = Query(...),
    date: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}$"),
):
    """
    早晨報告那張「From your buddy」卡：AI 寫的兩三句（寵物口吻）＋一句從清單挑的小建議。

    - 手錶資料還沒到 → status "waiting"，**不呼叫 AI**（使用者定）。
    - 每晚只生成一次；事實變了（手錶晚到、補了自評）才重生。
    - AI 沒設定／連不上／兩次沒過驗證 → 退回 /home 那兩句話（score_message + mood_description），
      source = "fallback"；過 SUMMARY_RETRY_MINUTES 才再試。
    - 小建議 tip 由 behavior/morning_tips.pick_tip() 挑，**逐字**；AI 碰不到它。

    ⚠️ 用同步的 def：AI 呼叫最多等 60 秒，async 會卡住整個事件迴圈（同 /chat）。
    """
    from ai import night_summary as ns

    user = require_user(user_id)
    wearable_rows = db.get_wearable_nightly(user_id, days=366)
    behavior_rows = db.get_nightly_behavior(user_id, days=366)
    w_row = _row_for(wearable_rows, date)
    b_row = _row_for(behavior_rows, date)
    rating = db.get_morning_rating(user_id, date)

    if not w_row or w_row.get("final_score") is None:
        return {"date": date, "status": "waiting", "text": None, "source": None, "tip": None}

    tip = morning_tips.pick_tip(
        rating["tags"] if rating else (),
        b_row.get("adherence_minutes") if b_row else None,
    )
    facts = ns.build_night_facts(
        date, user, w_row, _previous(wearable_rows, date, "final_score"), b_row,
        rating_label=morning_tips.RESTED_LABELS.get(rating["rested"]) if rating else None,
        tag_labels=[morning_tips.TAGS[t] for t in (rating["tags"] if rating else [])
                    if t in morning_tips.TAGS],
    )
    digest = ns.facts_hash(facts)

    mood, _, driver = resolve_mood(b_row, w_row)
    shown = display_for(mood, driver, w_row)
    fallback_text = " ".join(x for x in (shown.get("score_message"), shown.get("mood_description")) if x)

    def reply(text, source):
        return {"date": date, "status": "ok", "text": text, "source": source, "tip": tip}

    stored = db.get_night_summary(user_id, date)
    if stored and stored["facts_hash"] == digest:
        if stored["source"] == "llm":
            return reply(stored["text"], "llm")
        try:
            age = (datetime.now(datetime.fromisoformat(stored["created_at"]).tzinfo)
                   - datetime.fromisoformat(stored["created_at"])).total_seconds() / 60
        except (TypeError, ValueError):
            age = SUMMARY_RETRY_MINUTES
        if age < SUMMARY_RETRY_MINUTES:
            return reply(fallback_text, "fallback")

    if not ns.key_available():
        # 沒設定金鑰：一次都沒試，不寫進資料庫（設定好之後下一次打開就會生成）
        return reply(fallback_text, "fallback")
    try:
        result = ns.summarize_night(facts)
    except ns.SummaryUnavailable as exc:
        print(f"night-summary: fallback for one night - {exc}")   # 不印 user_id
        db.save_night_summary(user_id, date, fallback_text, "fallback", digest)
        return reply(fallback_text, "fallback")
    db.save_night_summary(user_id, date, result["text"], "llm", digest, result.get("model"))
    return reply(result["text"], "llm")
