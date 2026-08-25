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

    -- ── 原始生理量測（兩種來源都有）──────────────────────────────
    -- 這幾欄是「事實」，不是判斷。存原始值而不是只存分數，是因為
    -- 評分規則之後可能改版（Tier3 就改過三次），而原始值改不了。
    -- 只存分數的話，改規則就得重抓資料；存了原始值就只要重算。
    duration_min   REAL,                      -- 實際睡著的分鐘數（不含清醒）
    efficiency     REAL,                      -- %，定義見下方 clinical_efficiency 的說明
    waso_min       REAL,                      -- 入睡後清醒（Wake After Sleep Onset）
    deep_min       REAL,
    rem_min        REAL,
    avg_hr         REAL,                      -- 睡眠期間平均心率
    resting_hr     REAL,                      -- 靜止心率（每日單一數字）

    -- ── 臥床時間（只有 Health Connect 來源會有值）────────────────
    -- ⚠️ 這兩欄記錄的正是 PROJECT_STATUS.md 3.9 說「拿不到」的那個東西。
    --
    --    對 L1 同學來說它其實拿得到，而且不花任何額外力氣：
    --    Health Connect 的 SleepSessionRecord 以「上床」為 session 起點
    --    （不是以入睡為起點），所以 session 長度**就是**臥床時間 TIB。
    --    → 睡眠效率終於有臨床定義的分母
    --    → 入睡潛伏期 = 第一個睡眠分期的開始 − session 開始
    --
    --    這是個值得寫進報告的意外收穫：攝影機原本要解的問題（3.9），
    --    對有穿戴裝置的受測者來說，Health Connect 直接就給了。
    --    Garmin 只給入睡時刻，所以 **Garmin 來源這兩欄一律 NULL**。
    --
    -- ⚠️ **clinical_efficiency 不進評分**，只供報告呈現。
    --    理由見 wearable/healthconnect_adapter.py 的完整說明，一句話版本是：
    --    兩個來源必須用**同一個**效率定義餵進同一個評分器，否則分母較大的
    --    那一邊（L1 同學）會被系統性地扣分，而那個差異來自裝置不是來自睡眠。
    time_in_bed_min     REAL,                 -- 臥床總分鐘數（上床 → 起床）
    clinical_efficiency REAL,                 -- 總睡眠 ÷ 臥床時間 × 100

    -- ── Tier1/2 基礎分數（0–100）─────────────────────────────────
    -- 兩種來源都算得出來——Health Connect 的 SleepSessionRecord 帶完整的
    -- AWAKE/LIGHT/DEEP/REM 分期，時長 30／效率 25／WASO 25／深睡 10／
    -- REM 10 這五項全部拿得到。
    --
    -- ⚠️ 而且走的是**同一個評分器** garmin/evaluate_sleep_quality.py，
    --    連參數都不改。絕對不要為 Health Connect 另寫一套——一旦有兩套，
    --    「這個分數是怎麼來的」就再也答不清楚，而那是本專案最難複製的資產。
    base_score     REAL,
    base_quality   TEXT,                      -- Good / Normal / Poor / Bad
    -- 0 = 裝置沒測到 REM，該項已排除計分並把權重分配給其他指標。
    -- ⚠️ 這跟「REM 為 0 分鐘」是兩件事：前者是裝置限制，後者是生理事實。
    --    Vivoactive 3 有多晚屬於前者（已實測 Garmin 官方 App 也顯示無 REM），
    --    當成後者就會因為錶舊而懲罰使用者。
    rem_measured   INTEGER,

    -- ── Tier3 修正值與 SRI：**只有 Garmin 來源會有值**，其餘為 NULL ──
    -- 兩個原因，都不是 bug、也都不需要修：
    --   1. Garmin 的壓力分數（Tier3 額度最大的一項，±4）是**專有指標**，
    --      不寫進 Health Connect。Body Battery、Intensity Minutes 同理。
    --   2. 一到兩週的研究，Tier3 每一項**都還在冷啟動**（需要 14–28 晚的
    --      個人 baseline）；SRI 更需要 28 天窗格內 ≥10 組相鄰配對——
    --      研究者自己 46 晚也只有 28 晚算得出來。
    --      → 換句話說：就算借錶給同學戴兩週，也一樣拿不到 Tier3。
    --        這正是「借錶不會比 Health Connect 多拿到任何資料」的原因。
    total_modifier REAL,
    sri            REAL,
    modifier_note  TEXT,                      -- 說明為何是這個修正值（冷啟動／資料無效／…）

    -- ── 最終分數 ────────────────────────────────────────────────
    -- ⚠️ 存實際值，**不要讓 API 層自己算 base + modifier**。兩個理由：
    --
    --   (1) final_score = clamp(base + total_modifier, 0, 100)，**有夾擠**。
    --       base=98、modifier=+3 時 final 是 100 而不是 101。
    --       「反正加一加就好」會在滿分附近安靜地算錯——而那種只在邊界
    --       出錯、平時都對的 bug 正是最難發現的一類。
    --   (2) 本檔案開頭那條紅線：這個模組不計算任何分數。存實際值，
    --       API 層就**結構上**不需要碰計分邏輯，而不是靠人記得別碰。
    --
    -- Health Connect 來源沒有 Tier3，所以 final_score = base_score。
    final_score    REAL,
    final_quality  TEXT,

    -- 複合主鍵：一個使用者一晚只會有一筆。重送（App 網路重試）會覆寫
    -- 而不是變成兩筆，見 upsert_wearable_nightly 的說明。
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
# 欄位遷移
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ **這一段存在的理由，是 `CREATE TABLE IF NOT EXISTS` 有一個很容易
#    被忽略的性質：表已經存在時它什麼都不做——連新加的欄位也不會補。**
#
#    也就是說，如果只改上面的 SCHEMA 就以為完事了：
#      - 全新的環境（clone 下來第一次跑）→ 正常，新欄位有
#      - 已經跑過 --init 的環境（例如開發機）→ **舊表原封不動，新欄位不存在**
#    然後寫入時會丟 `no such column`。這種「在我的機器上是壞的、在你的
#    機器上是好的」正是最難查的一類問題，而且原因跟程式碼無關。
#
#    這也是本專案一再遇到的那種失敗模式（安靜地少做一件事），
#    所以在這裡明確處理掉，不靠任何人記得手動刪掉資料庫重建。
#
# 每一項是 (表名, 欄位名, 型別)。⚠️ **只能新增欄位**：
#   - SQLite 的 ALTER TABLE 不支援改型別、不支援刪欄位
#   - 新增欄位對既有資料是安全的（舊列的新欄位一律是 NULL，
#     而本專案的慣例正好是「NULL = 沒有這個值」而非 0）
#   - 所以這張表只會往下長，不會有人改到既有欄位
#
# 要改型別或刪欄位的話，SQLite 的標準作法是「建新表 → 搬資料 → 換名」，
# 那已經超出這個機制的範圍，屆時請另寫一次性腳本。
COLUMN_MIGRATIONS = [
    # 2026-08-26：Health Connect 能給臥床時間（Garmin 不能），
    #             以及把 final_score 存起來不讓 API 層自己算。
    ("wearable_nightly", "time_in_bed_min", "REAL"),
    ("wearable_nightly", "clinical_efficiency", "REAL"),
    ("wearable_nightly", "final_score", "REAL"),
    ("wearable_nightly", "final_quality", "TEXT"),
    # 2026-08-26：三個**自律神經**類的 Tier3 分項。
    #
    # ⚠️ 只存這三個、不存另外三個（活動量／醒來次數／睡眠段數），
    #    分界不是隨便劃的：`anxious` 這個寵物心情的定義就是
    #    「壓力分數與心率同時明顯偏離個人 baseline」
    #    （build_app_payload.py 的 ANXIOUS_* 門檻），而那正好是
    #    自律神經那一組。另外三項不屬於這個構念，也沒有任何程式
    #    個別讀它們，已經包含在 total_modifier 裡。
    #
    #    不存的話，API 層就算不出 anxious，只能拿 total_modifier 湊——
    #    而那是不同的東西（總和可能因為別項加分而被抵銷掉）。
    ("wearable_nightly", "rhr_modifier", "REAL"),
    ("wearable_nightly", "avg_hr_modifier", "REAL"),
    ("wearable_nightly", "stress_modifier", "REAL"),
]


def existing_columns(conn, table):
    """
    回傳某張表目前有哪些欄位（set）。表不存在時回空 set。

    用 PRAGMA table_info 而不是查 sqlite_master 的建表 SQL 字串——
    後者要自己解析 SQL，而欄位名稱可能被引號、換行、註解包住，
    正則式遲早會出錯。PRAGMA 直接給結構化結果。
    """
    try:
        return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    except sqlite3.OperationalError:
        return set()


def apply_column_migrations(conn, verbose=False):
    """
    把 COLUMN_MIGRATIONS 裡還不存在的欄位補上。回傳實際新增了幾欄。

    可以重複執行：已經存在的欄位會被跳過，所以每次 --init 都跑一次也無妨。
    """
    added = 0
    for table, column, coltype in COLUMN_MIGRATIONS:
        cols = existing_columns(conn, table)
        if not cols:
            # 表還不存在。這不是錯誤——SCHEMA 會在同一次 init_db 裡建好它，
            # 而新建的表本來就已經含有這些欄位，沒有東西要遷移。
            continue
        if column in cols:
            continue
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {coltype}")
        added += 1
        if verbose:
            print(f"  + 新增欄位 {table}.{column} ({coltype})")
    return added


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


def init_db(db_path=None, verbose=False):
    """
    建表並套用欄位遷移。可重複執行。回傳新增的欄位數。

    ⚠️ **順序不能顛倒**，兩步各自負責不同的情況：

        1. executescript(SCHEMA)      → 表不存在時建好（含所有最新欄位）
        2. apply_column_migrations()  → 表已存在時，補上後來才加的欄位

    全新環境走第 1 步、第 2 步發現欄位都在就跳過；
    舊環境第 1 步什麼都不做（IF NOT EXISTS）、由第 2 步補齊。
    兩種環境最後結構相同，這正是重點——否則同一份程式碼在不同人的
    機器上會有不同的資料庫結構。
    """
    conn = connect(db_path)
    try:
        conn.executescript(SCHEMA)
        added = apply_column_migrations(conn, verbose=verbose)
        conn.commit()
        return added
    finally:
        conn.close()


def now_iso():
    """
    現在時間，ISO8601 +08:00。

    專案規範：時間格式一律 ISO8601 (+08:00)。timespec="seconds" 是刻意的——
    微秒對「幾點上床」這個尺度毫無意義，只會讓人讀日誌時多掃過六位數字。
    """
    return datetime.now(TZ_TAIPEI).isoformat(timespec="seconds")


# ═══════════════════════════════════════════════════════════════════
# 使用者
# ═══════════════════════════════════════════════════════════════════

def create_user(display_name, target_bedtime="23:30", age_band="young_adult",
                study_cohort="L0", wearable_brand=None, db_path=None,
                user_id=None):
    """
    建立使用者，回傳 user_id。

    user_id 用 uuid4 而不是流水號：D2 的資料之後要拿來分析，
    流水號會洩漏「你是第幾個受測者」以及招募順序，UUID 不會。

    ⚠️ user_id 參數是給**遷移腳本**用的，一般情況不要傳。
       傳了就能指定一個固定 id，讓「把 46 晚灌進資料庫」這件事
       可以重複執行而不會每次都長出一個新使用者
       （見 migrate_garmin_to_db.py 的 RESEARCHER_USER_ID）。

    ⚠️ 沒有帳號密碼是刻意的（暱稱制免註冊，見 users 表的說明）。
       所以 **user_id 本身就是憑證**——誰拿到它就能讀寫那個人的資料。
       在 D2 這個「側載 APK、區網、十來個同學」的情境下這是可接受的取捨，
       但要在同意書裡講清楚，而且**日後真的要上架時必須先補認證**。
       這件事寫在這裡而不是只寫在文件裡，因為改動這個檔案的人才是
       最需要看到它的人。
    """
    user_id = user_id or str(uuid.uuid4())
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
    """
    取單一使用者；**不存在回 None，不丟例外**。

    回 None 而不是丟例外，是因為「這個 user_id 不存在」在 API 層是一個
    正常的結果（要回 404），不是程式錯誤。丟例外會逼呼叫端寫 try/except
    來處理一件很常見的事。
    """
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

    ⚠️ 這是最值得寫一次驗收測試的地方：忘了開 PRAGMA 的話，
       這個函式**照樣回 True**（users 那一列確實刪掉了），但
       nightly_behavior 等表會留下一堆抓不回主人的孤兒資料——
       而我們卻已經對受測者承諾「退出即刪除」。
       失敗時完全沒有錯誤訊息，只有資料還在。

    回傳 True 代表真的刪掉了一列；False 代表那個 user_id 本來就不存在。
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

    ⚠️ **缺的欄位一律存 NULL 而不是 0。** 本專案一貫在意這個區別：
       rem「未測得」vs「為 0 分鐘」、sri「無法計算」vs「等於 0」，
       語意完全不同，而一旦混在一起就再也分不開了。
       （這也正是 build_app_payload.py 讀 JSON 不讀 CSV 的理由——
       CSV 會把兩者都寫成空字串。）

    ⚠️ **這個函式不算任何分數。** 傳進來的 base_score / final_score 必須
       已經由上游算好（garmin/ pipeline 或 wearable/healthconnect_adapter.py）。
       這是本檔案開頭那條紅線的具體落實。
    """
    # 允許寫入的欄位白名單。user_id / date / source 是位置參數，不在這裡。
    #
    # ⚠️ 有了白名單，呼叫端打錯鍵名會**立刻拋錯**而不是被安靜忽略。
    #    沒有白名單的話 metrics.get(c) 只會拿不到那個值、寫進 NULL，
    #    然後某天有人發現「怎麼深睡都是空的」再回頭查半天。
    columns = ["duration_min", "efficiency", "waso_min", "deep_min", "rem_min",
               "avg_hr", "resting_hr",
               # 臥床時間：只有 Health Connect 給得出來（Garmin 一律 None）
               "time_in_bed_min", "clinical_efficiency",
               "base_score", "base_quality", "rem_measured",
               # Tier3 與 SRI：只有 Garmin 有值
               "total_modifier", "sri", "modifier_note",
               # 自律神經三分項，pet_mood 的 anxious 覆寫要用（見 COLUMN_MIGRATIONS）
               "rhr_modifier", "avg_hr_modifier", "stress_modifier",
               # 最終分數：存實際值，不讓讀取端自己 base + modifier（有夾擠）
               "final_score", "final_quality",
               "device_brand"]

    unknown = set(metrics) - set(columns)
    if unknown:
        raise ValueError(f"wearable_nightly 沒有這些欄位：{sorted(unknown)}")

    # 動態組 SQL。⚠️ 這裡用 f-string 拼字串是安全的，因為拼進去的
    #    **只有 columns 這個寫死在程式碼裡的清單**，沒有任何外部輸入。
    #    真正的資料一律走 ? 佔位符（下面那個 tuple），所以沒有注入風險。
    #    ——如果哪天有人想把 columns 改成由參數傳入，這個前提就破了。
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

# ⚠️ **難度已於 2026-08-26 用研究者的 46 晚實測校準過**，不是憑感覺訂的。
#    完整過程見 PROJECT_STATUS.md；每一項的結論寫在各自的註解裡。
#    校準指令：python migrate_garmin_to_db.py --simulate-challenges
#
# ⚠️ **但校準樣本 n = 1，而且那個人特別不規律**（平均入睡 02:34、
#    就寢標準差 84 分鐘）。所以這些數字是**暫定值**，D2 收到十來個人的
#    真實資料之後應該重跑一次校準。這件事現在就寫下來，免得半年後
#    有人把它們當成定案。

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
        # ── 實測（46 晚模擬）──────────────────────────────────────
        # 這一項的難度**完全由使用者自己設的目標決定**，不是挑戰設計的問題：
        #     目標 23:30 → 準時  2%      目標 02:30 → 準時 43%
        #     目標 01:00 → 準時 11%      目標 03:00 → 準時 59%
        # （該使用者平均入睡 02:34）
        #
        # ⚠️ **但這反過來揭露一個真的產品問題，要記下來：**
        #    新使用者若照 users.target_bedtime 的預設值 23:30 開始用，
        #    而他實際上兩三點才睡，**第一天就會看到 0% 然後放棄**。
        #    → 註冊流程必須問「你現在通常幾點睡」，並據此建議一個
        #      往前挪一點的目標，而不是給所有人同一個 23:30。
        #    → 這是 App 端的事（Jeremy 負責），已列為交接事項。
    },
    {
        "challenge_id": "streak_nights",
        "kind": "streak",
        "title": "連續 3 晚達成",
        "description": "連續 3 個晚上都在目標就寢時間前放下手機。",
        "target_value": 3.0,
        "window_days": 14,
        "literature_ref": (
            "Johnson et al. (2016) Gamification for Health and Wellbeing —— "
            "進度追蹤與連續達成可提升健康行為的參與度。"
        ),
        # ── 實測：原本是「連續 5 晚」，改成 3 晚 ────────────────────
        # 把 46 晚重排成連續日曆日（去掉手錶配戴造成的斷點，因為 Tier A
        # 的資料來源是手機、不會有那種斷點）之後量到的最長連續達成：
        #     目標 02:00（準時 35%）→ 最長 3 晚，≥5 晚出現 0 次
        #     目標 02:30（準時 43%）→ 最長 4 晚，≥5 晚出現 0 次
        #     目標 03:00（準時 59%）→ 最長 9 晚，≥5 晚出現 7 次
        # → 準時率要到約 55–60% 才連得到 5 晚。目標設得合理的人
        #   （準時率約 40–50%）**永遠達不到 5 晚**，那個挑戰只會讓人放棄。
        # → 3 晚在同樣條件下是「常見但不自動」，梯度才對：
        #   1 晚（time）→ 3 晚（streak）→ 7 天收斂（consistency）。
        #
        # ⚠️ 第一次跑出來三個挑戰全是 0%，一度以為是挑戰設計壞了。
        #    查下去發現**有一部分是手錶配戴率造成的假象**：46 晚散在
        #    74 個日曆日裡，只有 1 段連續 ≥5 天。而連續紀錄的定義是
        #    「缺資料就中斷」，所以斷點吃掉了大部分的連續。
        #    那個限制在 Tier A 不存在（手機天天都在），所以校準時
        #    必須先把斷點拿掉，否則會把門檻訂得過低。
    },
    {
        "challenge_id": "bedtime_consistency_7d",
        "kind": "consistency",
        "title": "作息收斂",
        "description": "最近 7 晚的就寢時間都落在自己平均值的 ±60 分鐘內。",
        "target_value": 60.0,       # 允許的最大離散度（分鐘）
        "window_days": 7,
        "literature_ref": (
            "Windred et al. (2024) —— 作息規律性預測死亡率優於睡眠時長。"
            "⚠️ 這裡量的是**個人內**的就寢時間收斂度，不是 SRI，"
            "也不拿去跟任何外部常模比較（理由見 PROJECT_STATUS.md 6.5）。"
        ),
        # ── 實測：原本是 ±30 分鐘，改成 ±60 ───────────────────────
        # 36 個可評估的 7 天窗格，離散度（最大偏離自己平均的分鐘數）分布：
        #     第 10 百分位  46 分    第 50 百分位 103 分    第 90 百分位 155 分
        # 各門檻的達成率：
        #     ±30 →  0/36 =  0%   ← 原設定，**完全達不到**
        #     ±45 →  2/36 =  6%
        #     ±60 →  8/36 = 22%   ← 改成這個
        #     ±90 → 18/36 = 50%
        #     ±120→ 21/36 = 58%
        # → 選 ±60 的理由：對這個資料集裡**最不規律的情況**都還有 22%
        #   （約五週一次），不是 0；而對本來就規律的人（就寢標準差 20 分鐘
        #   左右）它會經常達成——那也對，因為他們已經做到了。
        #   ±60 也剛好有一句話講得清楚的意思：「就寢時間維持在自己平均的
        #   一小時內」，不需要額外解釋。
        #
        # ⚠️ 這一項用「最大偏離」而不是標準差，是脆弱的：7 晚裡有 1 晚
        #    失控整個窗格就爆掉（實測最大偏離的中位數是標準差的 1.5 倍）。
        #    保留這個統計量是因為它跟描述文字完全一致（「都落在 ±X 內」），
        #    使用者看得懂自己為什麼沒達成。若 D2 顯示太多人卡在這裡，
        #    改用標準差是第一個該試的方向。
    },
]


def seed_challenges(db_path=None):
    """
    灌入挑戰定義。可重複執行——已存在的會被**更新**成目前的定義。

    用 upsert 而不是「不存在才插入」，是因為挑戰的文案與門檻一定會在
    D2 期間微調（描述不夠清楚、目標太難）。若只在不存在時插入，
    改了 DEFAULT_CHALLENGES 卻不會生效，而且沒有任何提示——
    又是一個安靜失效。

    ⚠️ 但 challenge_progress **不會**被這個函式碰到。改了挑戰定義之後，
       既有的進度值仍然是用舊定義算出來的。目前三個挑戰的進度都是
       每次查詢時即時重算（見 behavior/challenges.py），所以沒有這個問題；
       日後若改成把進度存起來累加，這裡就要一併處理。

    ⚠️ **不在 DEFAULT_CHALLENGES 裡的挑戰會被停用（active = 0），
       但不會被刪除。**

       這是必要的：challenge_id 改過名（2026-08-26 把 streak_5_nights
       改成 streak_nights）之後，舊的那筆仍然躺在資料庫裡而且 active = 1，
       於是 App 上會**同時出現新舊兩個挑戰**，內容還互相矛盾。
       upsert 只會更新同 id 的那筆，管不到被改名的舊資料。

       停用而不刪除，是因為 challenge_progress 有外鍵指向這張表，
       刪定義會 CASCADE 掉受測者的歷史進度——而那是研究資料。
    """
    conn = connect(db_path)
    try:
        keep = [c["challenge_id"] for c in DEFAULT_CHALLENGES]
        placeholders = ", ".join("?" for _ in keep)
        conn.execute(
            f"UPDATE challenges SET active = 0 "
            f"WHERE challenge_id NOT IN ({placeholders})",
            keep,
        )

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
                    literature_ref = excluded.literature_ref,
                    -- ⚠️ active 一定要一起更新，否則一個曾經被停用的
                    --    challenge_id 重新加回 DEFAULT_CHALLENGES 之後
                    --    會**永遠復活不了**——upsert 更新了內容卻留著
                    --    active = 0，於是 get_challenges() 永遠看不到它，
                    --    而程式碼與資料庫看起來都沒有錯。
                    active         = 1
                """,
                (c["challenge_id"], c["kind"], c["title"], c["description"],
                 c["target_value"], c["window_days"], c["literature_ref"]),
            )
        conn.commit()
    finally:
        conn.close()


def get_challenges(db_path=None):
    """
    取所有啟用中的挑戰定義。

    按 window_days 排序，所以 UI 上會是「今晚 → 7 天 → 14 天」由近到遠，
    這正好是使用者對「我現在該做什麼」的關注順序。

    ⚠️ 用 active = 1 過濾而不是刪除停用的挑戰：challenge_progress 有
       外鍵指向這張表，刪定義會連帶 CASCADE 掉受測者的歷史進度，
       而那是研究資料。停用只是不再顯示。
    """
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
    """
    寫入挑戰進度快照。

    ⚠️ 這張表是**快取，不是事實來源**。事實來源永遠是 nightly_behavior，
       進度由 behavior/challenges.py 每次即時重算。存下來只為了兩件事：
       (1) 記錄 completed_at（「你是哪一天完成的」重算不出來，
           因為重算只看得到當下的窗格）
       (2) 讓查詢不必每次都跑一輪計算

       所以**這裡的值跟重算結果不一致時，以重算為準**。
    """
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
    """
    取某使用者的所有挑戰進度，回傳 **{challenge_id: row}** 而不是 list。

    回 dict 是因為呼叫端一定是拿它去跟挑戰定義對齊（「這個挑戰的進度是
    多少」），回 list 的話每個呼叫端都得自己再轉一次。
    """
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
    """
    看目前有多少資料。

    ⚠️ 表不存在時給**明確指示**而不是丟 traceback。這是刻意的：
       這支 CLI 是給隊友用的，而「python db.py --init」這個答案
       應該直接寫在錯誤訊息裡，不該要求對方看得懂 OperationalError。
    """
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
        # verbose=True 讓「補了哪些欄位」顯示出來。遷移悄悄跑掉的話，
        # 之後查問題的人無從得知資料庫結構在什麼時候變過。
        added = init_db(args.db, verbose=True)
        print(f"建表完成：{Path(args.db) if args.db else DB_PATH}")
        if added:
            print(f"（同時補上 {added} 個後來新增的欄位）")

    if args.seed:
        seed_challenges(args.db)
        print(f"挑戰定義已灌入（{len(DEFAULT_CHALLENGES)} 項）")

    if args.stats:
        print_stats(args.db)


if __name__ == "__main__":
    main()
