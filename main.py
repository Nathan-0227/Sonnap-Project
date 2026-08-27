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
from datetime import date as date_cls
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import db
from behavior import adherence, challenges as challenge_engine, pet_state
from wearable.healthconnect_adapter import HealthConnectError, to_wearable_row

# ⚠️ 直接 import 舊路徑的映射函式，**不要在這裡重寫一份**。
#    pet_mood 的 Tier B 規則（QUALITY_TO_MOOD + anxious 生理覆寫）
#    必須只有一個定義處，否則 App 的 asset 畫面與 API 回傳的心情
#    會在某次改動後悄悄地不一致——那正是本專案最想避免的那類 bug。
from build_app_payload import DISPLAY_STRINGS, QUALITY_TO_COLOR, map_pet_mood

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
    source: str = Field("phone", description="phone | self_report")


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


def _row_for(rows: List[dict], target_date: Optional[str]) -> Optional[dict]:
    """從列表裡挑出指定日期那一列。"""
    if target_date is None:
        return None
    return next((r for r in rows if r.get("date") == target_date), None)


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

    db.upsert_nightly_behavior(
        user_id=req.user_id,
        date=night["date"],
        target_bedtime=night["target_bedtime"],
        lights_out_at=night["lights_out_at"],
        adherence_minutes=night["adherence_minutes"],
        is_late=night["is_late"],
        source=night["source"],
    )
    return night


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

    # ── display：兩層各有自己的文案，依 driver 決定用哪一套 ──
    if driver in ("wearable", "wearable_override") and w_row:
        quality = w_row.get("final_quality") or "Normal"
        display = {
            "lang": "en",
            "score_color": QUALITY_TO_COLOR.get(quality, "#FFC83D"),
            **DISPLAY_STRINGS.get(quality, DISPLAY_STRINGS["Normal"]),
        }
    else:
        display = pet_state.build_display(mood)

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
        },
        "display": display,
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

    ratio, late_nights, recorded = adherence.late_night_ratio(behavior_rows)
    spread, spread_n = adherence.bedtime_spread_minutes(behavior_rows)

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
            "history": [
                {
                    "date": r["date"],
                    "lights_out_at": r["lights_out_at"],
                    "adherence_minutes": r["adherence_minutes"],
                    "is_late": bool(r["is_late"]) if r["is_late"] is not None else None,
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
                    "final_score": r["final_score"],
                    "final_quality": r["final_quality"],
                    "sleep_duration_hours": (
                        round(r["duration_min"] / 60.0, 2)
                        if r["duration_min"] is not None else None
                    ),
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
        "notes": {
            "tier_b_comparability": (
                "Values in wearable.history support within-person trends only; "
                "they must not be compared across users (staging algorithms differ by brand)."
            ),
        },
    }


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
