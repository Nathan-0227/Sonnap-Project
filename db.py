"""
db.py — Sonnap 的持久化層（SQLite）

═══════════════════════════════════════════════════════════════════
這個檔案存在的理由
═══════════════════════════════════════════════════════════════════

在此之前，整個系統**假設世界上只有一個使用者**：
`app_payload.json` 只有一份、`main.py` 的端點不接受任何參數、
App 端的使用者名稱寫死。那在 demo 沒問題，但 D2「找同學裝 APK 實際使用」
一旦成立就完全不能用——十個人會看到同一個人的睡眠分數。

這個模組補上「使用者」這個概念，以及讓資料能被**寫入**
（先前 `main.py` 的 CORS 只開 `allow_methods=["GET"]`，結構上就不可能寫入）。

═══════════════════════════════════════════════════════════════════
為什麼是 SQLite，而且用標準庫的 sqlite3
═══════════════════════════════════════════════════════════════════
`requirements.txt` **不會因此多任何一行**。這延續本專案既有的取捨——
AI 功能用標準庫 `urllib.request` 打 API 而不裝 SDK，理由完全相同。

⚠️ `tapo/` 那邊有一個 MySQL 的 `sleep_records` 表，那是影像組存偵測事件用的，
   跟這裡**沒有關係、不要合併**。兩者的生命週期與擁有者都不同。

═══════════════════════════════════════════════════════════════════
⚠️ 架構紅線：這個模組不計算任何分數
═══════════════════════════════════════════════════════════════════
`PROJECT_STATUS.md` 8.7 的紅線是「遊戲化層只讀，不得回寫評分層」。
在新架構下這條紅線不再需要靠紀律守住，而是**結構上不可能違反**：

    Tier A（行為：就寢達成度、挑戰、寵物狀態）  ← behavior/，絕不 import 評分器
    Tier B（生理：睡眠分數）                      ← wearable/ 與 garmin/ 才算分數

本檔案只負責存取，兩層都不計算。`wearable_nightly` 的分數欄位一律由
上游算好後寫入，API 層對它**唯讀**。

═══════════════════════════════════════════════════════════════════
使用方式
═══════════════════════════════════════════════════════════════════
    python db.py --init          # 建表（可重複執行）
    python db.py --seed          # 灌入挑戰定義（可重複執行）
    python db.py --stats         # 看目前有多少資料
"""

import argparse
import sqlite3
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Windows 主控台預設編碼是 cp1252，印中文會丟 UnicodeEncodeError。
# PowerShell 不會發生但 Git Bash 會——同一台機器兩種結果。
# 沿用 build_app_payload.py 與 run_pipeline.py 的處理方式。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent

# ⚠️ 這個路徑在 .gitignore 的 `/data/` 規則內，**絕不進版控**。
#    裡面是受測者的個資（就寢時間、手機 App 使用紀錄、睡眠生理數值），
#    跟 garmin/.env 是同一個等級的東西。
#    schema 就在本檔案裡，任何人 clone 下來跑 `python db.py --init` 就能重建，
#    所以不進版控不會有人少了東西。
DB_PATH = ROOT / "data" / "sonnap.db"

TZ_TAIPEI = timezone(timedelta(hours=8))  # 專案規範：時間一律 ISO8601 (+08:00)


# ═══════════════════════════════════════════════════════════════════
# Schema
# ═══════════════════════════════════════════════════════════════════
#
# 幾個貫穿全表的約定：
#
# 1. **日期一律是「起床日」**（wake date），與 garmin/analyze_garmin_sleep.py
#    的分組方式一致。2026-08-11 已用 Garmin 原始的 calendarDate 欄位驗證過：
#    7/10 22:42 上床、7/11 07:51 起床的那晚，Garmin 自己標記為 07-11。
#    兩邊用同一個約定，Tier A 與 Tier B 才對得起來。
#
# 2. **時間欄位存 ISO8601 字串**（含 +08:00 時區），不存 epoch。
#    理由：本專案所有既有輸出都是 ISO8601，換成 epoch 會讓人得在兩種
#    表示法之間換算，而那正是最容易出錯的地方。
#
# 3. **ON DELETE CASCADE**：知情同意書必須寫明「如何退出並刪除」。
#    有了 CASCADE，退出就是一句 DELETE FROM users，不會留下孤兒資料。
#    ⚠️ SQLite 預設**不啟用**外鍵約束，每條連線都要 PRAGMA foreign_keys = ON
#       （見 connect()）。忘了開的話 CASCADE 不會生效，而且不會報錯。

SCHEMA = """
-- ── 使用者 ────────────────────────────────────────────────────
-- 暱稱制免註冊：App 首次啟動產生 UUID，使用者只填暱稱。
-- **不收 email、不收密碼**——對 D2 最友善（受測者不用註冊就能開始用），
-- 隱私面也最乾淨（沒有可識別個人的欄位，也不必處理密碼儲存與重設）。
CREATE TABLE IF NOT EXISTS users (
    user_id         TEXT PRIMARY KEY,
    display_name    TEXT NOT NULL,
    created_at      TEXT NOT NULL,

    -- 目標就寢時間，"HH:MM"。這是 Tier A 一切計算的基準。
    target_bedtime  TEXT NOT NULL DEFAULT '23:30',
    timezone        TEXT NOT NULL DEFAULT '+08:00',

    -- 評分的分齡門檻要用（睡眠時長／REM／WASO 的參考區間都分齡）。
    -- 合法值見 garmin/evaluate_sleep_quality.py 的 DURATION_RANGE。
    age_band        TEXT NOT NULL DEFAULT 'young_adult',

    -- D2 的受測者分層：
    --   L0 = 只有手機（Tier A）
    --   L1 = 自備 Health Connect 相容裝置（Tier A + Tier1/2 分數）
    --   L2 = 研究者本人（全部 + Tier3 + SRI + 攝影機）
    study_cohort    TEXT NOT NULL DEFAULT 'L0',

    -- NULL = 沒有穿戴裝置。有值時記錄品牌，理由見 wearable_nightly 的說明。
    wearable_brand  TEXT
);

-- ── Tier A：行為資料（每個使用者都有，手機自己產生）────────────
-- 這是遊戲化與行為介入的**唯一**資料來源。裝置無關，所以也是
-- 唯一可以拿來做跨使用者比較的東西（社交功能只能建在這上面）。
CREATE TABLE IF NOT EXISTS nightly_behavior (
    user_id           TEXT NOT NULL,
    date              TEXT NOT NULL,          -- 起床日 YYYY-MM-DD

    -- 當晚的目標就寢時間**快照**。不要在查詢時去 join users.target_bedtime——
    -- 使用者隨時可以改目標，改了之後歷史紀錄的達成度就會被追溯性地改寫，
    -- 那會讓「我上週明明有達成」變成「沒有達成」。存快照才可稽核。
    target_bedtime    TEXT NOT NULL,

    -- 手機最後一次互動的時間。⚠️ 這**不是入睡時間**，是替代測量（proxy）。
    -- 有人放下手機後還會躺半小時。報告中必須誠實標註，比照本專案對
    -- sleep_efficiency（非臨床真效率）與 movement_count（取樣分鐘數）的處理。
    lights_out_at     TEXT,

    -- lights_out_at − target_bedtime，單位分鐘。正值＝拖延，負值＝提早。
    adherence_minutes REAL,
    is_late           INTEGER,                -- 0/1，門檻見 behavior/adherence.py

    -- 'phone'       = Android UsageStats 推得
    -- 'self_report' = 使用者自己填（Android 端還沒做時的過渡，或授權被拒時）
    source            TEXT NOT NULL DEFAULT 'phone',
    created_at        TEXT NOT NULL,

    PRIMARY KEY (user_id, date),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ── Tier A：睡前 App 使用分布 ─────────────────────────────────
-- ⚠️ 這張表現在不會有任何資料——Android 的 UsageStats platform channel
--    還沒實作。**但現在就建表**，否則之後補 Android 端要再做一次 schema 遷移。
--    這跟 app/lib/services/sleep_repository.dart 先抽介面、之後才實作
--    ApiSleepRepository 是同一個思路。
CREATE TABLE IF NOT EXISTS app_usage_daily (
    user_id        TEXT NOT NULL,
    date           TEXT NOT NULL,
    package_name   TEXT NOT NULL,             -- com.google.android.youtube
    app_label      TEXT,                      -- "YouTube"（可能取不到）
    prebed_minutes REAL NOT NULL,             -- 睡前 60 分鐘內的前景時間

    PRIMARY KEY (user_id, date, package_name),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ── Tier A：阻斷事件 ──────────────────────────────────────────
-- 同上，現在不會有資料。user_overrode 是刻意要記的：
-- 計畫書第二節說「傳統強制阻斷容易引發反感與抵抗心理」，
-- 那個假設值得用資料驗證——使用者到底多常直接略過阻斷？
CREATE TABLE IF NOT EXISTS block_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id       TEXT NOT NULL,
    date          TEXT NOT NULL,
    package_name  TEXT NOT NULL,
    blocked_at    TEXT NOT NULL,
    user_overrode INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ── Tier B：穿戴裝置的客觀睡眠資料（API 層唯讀）────────────────
--
-- ⚠️ **source 與 device_brand 不是備註欄位，是方法學上的必要資訊。**
--    不同品牌的睡眠分期演算法不互通——Garmin 的 REM 20% 與 Fitbit 的
--    REM 20% 不是同一個東西。這與本專案已記錄的 Czeisler (2026) SRI 問題
--    完全同型（「光是計算方法不同，就足以改變結論與詮釋」），
--    當初正是因此決定 SRI 不計分（PROJECT_STATUS.md 6.5）。
--
--    → 個人內比較成立（你這週比上週深睡多）
--    → **跨使用者排名不成立**（你的深睡比小明多）
--
--    所以社交功能的「好友平均睡眠比較」**不能比這張表的任何欄位**，
--    只能比 nightly_behavior 的行為指標。
CREATE TABLE IF NOT EXISTS wearable_nightly (
    user_id        TEXT NOT NULL,
    date           TEXT NOT NULL,
    source         TEXT NOT NULL,             -- 'garmin' | 'health_connect'
    device_brand   TEXT,

    duration_min   REAL,
    efficiency     REAL,                      -- %
    waso_min       REAL,
    deep_min       REAL,
    rem_min        REAL,
    avg_hr         REAL,
    resting_hr     REAL,

    -- Tier1/2 基礎分數。兩種來源都算得出來（Health Connect 的
    -- SleepSessionRecord 帶完整的 AWAKE/LIGHT/DEEP/REM 分期），
    -- 而且走的是**同一個評分器** garmin/evaluate_sleep_quality.py。
    -- 絕對不要為 Health Connect 另寫一套——那樣就有兩套標準了。
    base_score     REAL,
    base_quality   TEXT,                      -- Good/Normal/Poor/Bad
    rem_measured   INTEGER,                   -- 0 = 裝置未測得，已排除計分

    -- Tier3 與 SRI：**只有 Garmin 來源會有值**，其餘為 NULL。
    -- 兩個原因，都不是 bug：
    --   1. Garmin 的壓力分數（Tier3 佔 ±4）是專有指標，不寫進 Health Connect
    --   2. 一到兩週的研究，Tier3 全部處於冷啟動（需 14–28 晚個人 baseline）；
    --      SRI 更需要 28 天窗格內 ≥10 組相鄰配對——研究者自己 46 晚
    --      也只有 28 晚算得出來
    total_modifier REAL,
    sri            REAL,
    modifier_note  TEXT,

    PRIMARY KEY (user_id, date),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ── 挑戰定義 ──────────────────────────────────────────────────
-- ⚠️ 挑戰的標的必須是**行為**（幾點放下手機），不能是**生理結果**
--    （深睡幾分鐘）。使用者控制得了前者，控制不了後者。
--    因此 target_value 一律對應 nightly_behavior 的欄位，
--    永遠不會讀到 wearable_nightly。
CREATE TABLE IF NOT EXISTS challenges (
    challenge_id   TEXT PRIMARY KEY,
    kind           TEXT NOT NULL,             -- 'time' | 'streak' | 'consistency'
    title          TEXT NOT NULL,
    description    TEXT NOT NULL,
    target_value   REAL NOT NULL,
    window_days    INTEGER NOT NULL,
    literature_ref TEXT,                      -- 每個挑戰都要說得出依據
    active         INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS challenge_progress (
    user_id       TEXT NOT NULL,
    challenge_id  TEXT NOT NULL,
    current_value REAL NOT NULL DEFAULT 0,
    achieved_days INTEGER NOT NULL DEFAULT 0,
    completed_at  TEXT,
    updated_at    TEXT NOT NULL,

    PRIMARY KEY (user_id, challenge_id),
    FOREIGN KEY (user_id)      REFERENCES users(user_id)           ON DELETE CASCADE,
    FOREIGN KEY (challenge_id) REFERENCES challenges(challenge_id) ON DELETE CASCADE
);

-- 查詢模式幾乎都是「某個使用者的最近 N 天」，所以索引建在 (user_id, date)。
-- 主鍵已經涵蓋 nightly_behavior 與 wearable_nightly，只有 block_events 要補。
CREATE INDEX IF NOT EXISTS idx_block_events_user_date
    ON block_events(user_id, date);
"""


# ═══════════════════════════════════════════════════════════════════
# 連線
# ═══════════════════════════════════════════════════════════════════

def connect(db_path=None):
    """
    開一條連線。

    兩個 PRAGMA 都是必要的，而且都是「不開也不會報錯」的那種——
    正因為安靜失效，所以集中在這裡設定，不讓呼叫端自己記得：

    - foreign_keys：SQLite **預設關閉**外鍵約束。不開的話
      ON DELETE CASCADE 完全不生效，刪掉使用者會留下一堆孤兒資料，
      而知情同意書承諾的「退出即刪除」就變成沒有真的做到。
    - journal_mode=WAL：讓「uvicorn 正在讀」與「pipeline 正在寫」
      可以同時進行。預設模式下寫入會鎖住整個資料庫，
      而本專案的使用情境正好是這兩件事並行。
    """
    path = Path(db_path) if db_path else DB_PATH
    path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row      # 讓查詢結果可以用欄位名取值
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db(db_path=None):
    """建表。可重複執行（全部都是 IF NOT EXISTS）。"""
    conn = connect(db_path)
    try:
        conn.executescript(SCHEMA)
        conn.commit()
    finally:
        conn.close()


def now_iso():
    """現在時間，ISO8601 +08:00。專案規範。"""
    return datetime.now(TZ_TAIPEI).isoformat(timespec="seconds")


# ═══════════════════════════════════════════════════════════════════
# 使用者
# ═══════════════════════════════════════════════════════════════════

def create_user(display_name, target_bedtime="23:30", age_band="young_adult",
                study_cohort="L0", wearable_brand=None, db_path=None):
    """
    建立使用者，回傳 user_id。

    user_id 用 uuid4 而不是流水號：D2 的資料之後要拿來分析，
    流水號會洩漏「你是第幾個受測者」以及招募順序，UUID 不會。
    """
    user_id = str(uuid.uuid4())
    conn = connect(db_path)
    try:
        conn.execute(
            """
            INSERT INTO users
                (user_id, display_name, created_at, target_bedtime,
                 age_band, study_cohort, wearable_brand)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, display_name, now_iso(), target_bedtime,
             age_band, study_cohort, wearable_brand),
        )
        conn.commit()
    finally:
        conn.close()
    return user_id


def get_user(user_id, db_path=None):
    """取單一使用者；不存在回 None。"""
    conn = connect(db_path)
    try:
        row = conn.execute(
            "SELECT * FROM users WHERE user_id = ?", (user_id,)
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def update_user(user_id, db_path=None, **fields):
    """
    更新使用者設定。只允許改白名單內的欄位——
    否則呼叫端一個打錯的鍵名就能寫進 user_id，而 SQLite 不會攔。
    """
    allowed = {"display_name", "target_bedtime", "timezone",
               "age_band", "study_cohort", "wearable_brand"}

    # ⚠️ 順序很重要：先擋未知欄位，再處理「沒有東西要更新」。
    #    反過來寫的話，**所有**欄位都打錯時 updates 會是空的而提早 return，
    #    未知欄位的檢查永遠走不到，打錯的鍵名就被安靜吞掉了。
    #    這正是本專案最在意的失敗模式（安靜地少做一件事、沒有錯誤訊息）。
    unknown = set(fields) - allowed
    if unknown:
        raise ValueError(f"不允許更新的欄位：{sorted(unknown)}")

    updates = {k: v for k, v in fields.items() if k in allowed}
    if not updates:
        return False

    assignments = ", ".join(f"{k} = ?" for k in updates)
    conn = connect(db_path)
    try:
        cur = conn.execute(
            f"UPDATE users SET {assignments} WHERE user_id = ?",
            (*updates.values(), user_id),
        )
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


def delete_user(user_id, db_path=None):
    """
    刪除使用者及其所有資料。

    知情同意書必須寫明受測者可以隨時退出並刪除資料，這就是那個動作。
    靠 ON DELETE CASCADE 一次清乾淨——**前提是 PRAGMA foreign_keys 有開**
    （見 connect() 的說明）。
    """
    conn = connect(db_path)
    try:
        cur = conn.execute("DELETE FROM users WHERE user_id = ?", (user_id,))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


# ═══════════════════════════════════════════════════════════════════
# Tier A：行為資料
# ═══════════════════════════════════════════════════════════════════

def upsert_nightly_behavior(user_id, date, target_bedtime, lights_out_at,
                            adherence_minutes, is_late, source="phone",
                            db_path=None):
    """
    寫入或覆寫某一晚的行為資料。

    用 upsert 而不是 insert：App 可能重送（網路不穩時的重試），
    也可能先送一個粗略值、稍後補上更準的。重送不該變成兩筆或直接失敗。
    """
    conn = connect(db_path)
    try:
        conn.execute(
            """
            INSERT INTO nightly_behavior
                (user_id, date, target_bedtime, lights_out_at,
                 adherence_minutes, is_late, source, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, date) DO UPDATE SET
                target_bedtime    = excluded.target_bedtime,
                lights_out_at     = excluded.lights_out_at,
                adherence_minutes = excluded.adherence_minutes,
                is_late           = excluded.is_late,
                source            = excluded.source
            """,
            (user_id, date, target_bedtime, lights_out_at,
             adherence_minutes, 1 if is_late else 0, source, now_iso()),
        )
        conn.commit()
    finally:
        conn.close()


def get_nightly_behavior(user_id, days=30, db_path=None):
    """取最近 N 晚的行為資料，**由舊到新**排序。

    刻意回傳升冪：挑戰引擎要算「連續達成」與「就寢時間收斂度」，
    兩者都是沿時間軸往前走的計算，降冪排序會讓呼叫端每次都得先反轉。
    """
    conn = connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT * FROM (
                SELECT * FROM nightly_behavior
                WHERE user_id = ?
                ORDER BY date DESC
                LIMIT ?
            ) ORDER BY date ASC
            """,
            (user_id, days),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


# ═══════════════════════════════════════════════════════════════════
# Tier B：穿戴裝置資料（唯讀給 API，寫入只由上游 pipeline / adapter 呼叫）
# ═══════════════════════════════════════════════════════════════════

def upsert_wearable_nightly(user_id, date, source, metrics, db_path=None):
    """
    寫入某一晚的穿戴裝置資料。

    `metrics` 是一個 dict，鍵名對應 wearable_nightly 的欄位。
    缺的欄位一律存 NULL 而不是 0——本專案一貫在意這個區別
    （rem「未測得」vs「為 0」、sri「無法計算」vs「等於 0」語意完全不同，
    這也是 build_app_payload.py 讀 JSON 不讀 CSV 的理由）。
    """
    columns = ["duration_min", "efficiency", "waso_min", "deep_min", "rem_min",
               "avg_hr", "resting_hr", "base_score", "base_quality",
               "rem_measured", "total_modifier", "sri", "modifier_note",
               "device_brand"]

    unknown = set(metrics) - set(columns)
    if unknown:
        raise ValueError(f"wearable_nightly 沒有這些欄位：{sorted(unknown)}")

    values = [metrics.get(c) for c in columns]
    col_sql = ", ".join(columns)
    placeholders = ", ".join("?" for _ in columns)
    update_sql = ", ".join(f"{c} = excluded.{c}" for c in columns)

    conn = connect(db_path)
    try:
        conn.execute(
            f"""
            INSERT INTO wearable_nightly (user_id, date, source, {col_sql})
            VALUES (?, ?, ?, {placeholders})
            ON CONFLICT(user_id, date) DO UPDATE SET
                source = excluded.source, {update_sql}
            """,
            (user_id, date, source, *values),
        )
        conn.commit()
    finally:
        conn.close()


def get_wearable_nightly(user_id, days=30, db_path=None):
    """取最近 N 晚的穿戴資料，由舊到新。"""
    conn = connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT * FROM (
                SELECT * FROM wearable_nightly
                WHERE user_id = ?
                ORDER BY date DESC
                LIMIT ?
            ) ORDER BY date ASC
            """,
            (user_id, days),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


# ═══════════════════════════════════════════════════════════════════
# 挑戰
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ 三個挑戰的標的**全部是行為**，沒有一個讀 wearable_nightly。
#    這不只是巧合，是紅線：使用者控制得了「幾點放下手機」，
#    控制不了「深睡幾分鐘」。拿後者當挑戰目標等於懲罰使用者的生理。
#
# ⚠️ consistency 這一項是對 PROJECT_STATUS.md 8.6 的修正。
#    8.6 寫「挑戰標的用 SRI」，但那是在「單使用者、有手錶」的前提下寫的——
#    **SRI 需要 Garmin 的睡眠時間軸，受測者沒有錶**。改用 lights_out_at
#    的收斂程度：同一個構念（作息規律性）、同樣是個人內比較
#    （因此同樣繞開 6.5「不同計算方法的 SRI 不能對照外部常模」那個顧慮），
#    但資料來源換成手機。研究者本人兩者都有 → 正是 N=1 交叉驗證的標的。

DEFAULT_CHALLENGES = [
    {
        "challenge_id": "on_time_tonight",
        "kind": "time",
        "title": "準時放下手機",
        "description": "今晚在目標就寢時間前放下手機。",
        "target_value": 0.0,        # adherence_minutes <= 0
        "window_days": 1,
        "literature_ref": (
            "Kroese et al. (2014) Bedtime Procrastination, "
            "Front Psychol 5:611 —— 睡眠拖延的定義即「未能在預定時間上床」，"
            "所以標的直接對應該定義。"
        ),
    },
    {
        "challenge_id": "streak_5_nights",
        "kind": "streak",
        "title": "連續 5 晚達成",
        "description": "連續 5 個晚上都在目標就寢時間前放下手機。",
        "target_value": 5.0,
        "window_days": 14,
        "literature_ref": (
            "Johnson et al. (2016) Gamification for Health and Wellbeing —— "
            "進度追蹤與連續達成可提升健康行為的參與度。"
        ),
    },
    {
        "challenge_id": "bedtime_consistency_7d",
        "kind": "consistency",
        "title": "作息收斂",
        "description": "最近 7 晚的就寢時間都落在自己平均值的 ±30 分鐘內。",
        "target_value": 30.0,       # 允許的最大離散度（分鐘）
        "window_days": 7,
        "literature_ref": (
            "Windred et al. (2024) —— 作息規律性預測死亡率優於睡眠時長。"
            "⚠️ 這裡量的是**個人內**的就寢時間收斂度，不是 SRI，"
            "也不拿去跟任何外部常模比較（理由見 PROJECT_STATUS.md 6.5）。"
        ),
    },
]


def seed_challenges(db_path=None):
    """灌入挑戰定義。可重複執行——已存在的會被更新成目前的定義。"""
    conn = connect(db_path)
    try:
        for c in DEFAULT_CHALLENGES:
            conn.execute(
                """
                INSERT INTO challenges
                    (challenge_id, kind, title, description,
                     target_value, window_days, literature_ref, active)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1)
                ON CONFLICT(challenge_id) DO UPDATE SET
                    kind           = excluded.kind,
                    title          = excluded.title,
                    description    = excluded.description,
                    target_value   = excluded.target_value,
                    window_days    = excluded.window_days,
                    literature_ref = excluded.literature_ref
                """,
                (c["challenge_id"], c["kind"], c["title"], c["description"],
                 c["target_value"], c["window_days"], c["literature_ref"]),
            )
        conn.commit()
    finally:
        conn.close()


def get_challenges(db_path=None):
    """取所有啟用中的挑戰定義。"""
    conn = connect(db_path)
    try:
        rows = conn.execute(
            "SELECT * FROM challenges WHERE active = 1 ORDER BY window_days"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def upsert_challenge_progress(user_id, challenge_id, current_value,
                              achieved_days, completed_at=None, db_path=None):
    """寫入挑戰進度。"""
    conn = connect(db_path)
    try:
        conn.execute(
            """
            INSERT INTO challenge_progress
                (user_id, challenge_id, current_value, achieved_days,
                 completed_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, challenge_id) DO UPDATE SET
                current_value = excluded.current_value,
                achieved_days = excluded.achieved_days,
                completed_at  = excluded.completed_at,
                updated_at    = excluded.updated_at
            """,
            (user_id, challenge_id, current_value, achieved_days,
             completed_at, now_iso()),
        )
        conn.commit()
    finally:
        conn.close()


def get_challenge_progress(user_id, db_path=None):
    """取某使用者的所有挑戰進度，回傳 {challenge_id: row}。"""
    conn = connect(db_path)
    try:
        rows = conn.execute(
            "SELECT * FROM challenge_progress WHERE user_id = ?", (user_id,)
        ).fetchall()
        return {r["challenge_id"]: dict(r) for r in rows}
    finally:
        conn.close()


# ═══════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════

def print_stats(db_path=None):
    """看目前有多少資料。表不存在時給明確指示，不要丟 traceback。"""
    path = Path(db_path) if db_path else DB_PATH
    if not path.exists():
        print(f"資料庫還不存在：{path}")
        print("請先執行：python db.py --init")
        return

    tables = ["users", "nightly_behavior", "app_usage_daily", "block_events",
              "wearable_nightly", "challenges", "challenge_progress"]
    conn = connect(db_path)
    try:
        print(f"資料庫：{path}")
        for t in tables:
            try:
                n = conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
            except sqlite3.OperationalError:
                print(f"  {t:<20} ⚠️ 表不存在，請執行 python db.py --init")
                continue
            print(f"  {t:<20} {n} 列")
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Sonnap 持久化層的維護指令。")
    parser.add_argument("--init", action="store_true", help="建表（可重複執行）")
    parser.add_argument("--seed", action="store_true", help="灌入挑戰定義")
    parser.add_argument("--stats", action="store_true", help="顯示各表列數")
    parser.add_argument("--db", default=None, help="指定資料庫路徑（測試用）")
    args = parser.parse_args()

    if not (args.init or args.seed or args.stats):
        parser.print_help()
        return

    if args.init:
        init_db(args.db)
        print(f"建表完成：{Path(args.db) if args.db else DB_PATH}")

    if args.seed:
        seed_challenges(args.db)
        print(f"挑戰定義已灌入（{len(DEFAULT_CHALLENGES)} 項）")

    if args.stats:
        print_stats(args.db)


if __name__ == "__main__":
    main()
