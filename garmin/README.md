# Garmin 睡眠資料 Pipeline

從 Garmin 手錶抓資料 → 整理 → 評分，最終產出每晚的睡眠品質分數。

評分邏輯的完整文獻依據見 [`../Research-Background/Garmin手錶分數.md`](../Research-Background/Garmin手錶分數.md)。

---

## 快速開始

```bash
# 用現有資料重算（改了評分邏輯後最常用）。實測約 3 秒
python run_pipeline.py
```

最終結果在 `data/garmin_sleep_quality_final.csv`，目前是
**57 晚**（2026-05-29 ~ 09-01；Good 38 / Normal 12 / Poor 5 / Bad 2）。

`run_pipeline.py` 跑完 ②~⑤ 之後**還會順便跑 `build_app_payload.py`**
產生 App 讀的 `app/assets/data/app_payload.json`；加 `--ai` 才會另外呼叫 Claude 重生夢境。

⚠️ **重抓資料是覆寫不是增量。** `garmin_connect_fetch.py` 用 `open(output, "w")`，
所以 `--days N` 會把整個 `garmin_standard_data.json` 換掉、只留最近 N 天，
**弄丟前面所有歷史且沒有任何警告**。要重抓請給完整區間：

```bash
python garmin/garmin_connect_fetch.py --start-date 2026-05-28 --end-date <今天>
python garmin/run_pipeline.py
```

抓之前先備份 `garmin_standard_data.json` 與 `garmin_sleep_quality_final.csv`，
抓完**一定要比對歷史夜晚的分數有沒有被改寫**。

---

## Pipeline 流程

```
                    ┌─────────────────────────┐
  Garmin Connect →  │ garmin_connect_fetch.py │  ① 抓取（需 .env 帳密）
       API          └───────────┬─────────────┘
                                ↓  data/garmin_standard_data.json（6.7 MB，逐筆事件流）
                    ┌───────────┴─────────────┐
                    │ analyze_garmin_sleep.py │  ② 整理成「每晚一列」
                    └───────────┬─────────────┘
                                ↓  data/garmin_sleep_summary.csv
                    ┌───────────┴──────────────┐
                    │ extract_sleep_features.py│  ③ 挑有效夜晚、算特徵
                    └───────────┬──────────────┘
                                ↓  data/garmin_sleep_features.csv
                    ┌───────────┴──────────────┐
                    │ evaluate_sleep_quality.py│  ④ Tier1/2 基礎分數（0–100）
                    └───────────┬──────────────┘
                                ↓  data/garmin_sleep_quality.csv
                    ┌───────────┴───────────────┐
                    │ apply_recovery_modifier.py│  ⑤ Tier3 修正值 + SRI
                    └───────────┬───────────────┘
                                ↓
                     data/garmin_sleep_quality_final.csv  ← 最終結果
```

| 步驟 | 腳本 | 做什麼 |
|---|---|---|
| ① | `garmin_connect_fetch.py` | 連 Garmin Connect API 抓睡眠/心率/壓力/步數，存成逐筆事件流 |
| ② | `analyze_garmin_sleep.py` | 把事件流按「一晚」分組，算出每晚的睡眠階段分鐘數、平均心率等 |
| ③ | `extract_sleep_features.py` | 濾掉沒戴錶的日子，算出評分要用的特徵（時長、效率、各階段比例）|
| ④ | `evaluate_sleep_quality.py` | Tier1/2 基礎分數：時長 30、效率 25、WASO 25、深睡 10、REM 10 |
| ⑤ | `apply_recovery_modifier.py` | Tier3 修正值（±12）+ SRI（呈現用不計分），產出最終分數。**依 `WEARER_SEGMENTS` 分配戴者計算**，見下 |

---

## ⚠️ 最容易踩的坑：漏跑中間步驟

**每一步都吃前一步的輸出，但漏跑中間某步不會報錯**——後面的步驟會照樣用「上次留下來的舊檔案」跑完，安靜地算出用過期資料算的結果。

這在 2026-08-10 真的發生過：改完 `analyze_garmin_sleep.py` 後只跑了 ②→④，漏掉 ③，`evaluate` 讀到的是三週前的 features 檔，完全沒有任何錯誤訊息。

**所以請一律用 `run_pipeline.py`**，它會依序執行、任一步失敗就中止。只有在單獨除錯某一步時才手動跑個別腳本。

---

## 資料夾結構

```
garmin/
├── README.md                    ← 本文件
├── run_pipeline.py              ← 一鍵執行（建議用這個）
├── garmin_connect_fetch.py      ← ① 抓取
├── analyze_garmin_sleep.py      ← ② 整理
├── extract_sleep_features.py    ← ③ 特徵
├── evaluate_sleep_quality.py    ← ④ 基礎分數
├── apply_recovery_modifier.py   ← ⑤ 修正值
├── .env                         ← Garmin 帳密（已 gitignore，不會進版控）
└── data/                        ← 所有生成的資料檔集中在這
    ├── garmin_standard_data.json      （① 的產出，最大的檔）
    ├── garmin_sleep_summary.csv/.json （②）
    ├── garmin_sleep_features.csv/.json（③）
    ├── garmin_sleep_quality.csv/.json （④）
    └── garmin_sleep_quality_final.csv/.json  （⑤ 最終結果）
```

所有腳本都用 `Path(__file__).parent / "data"` 定位資料夾，**從任何工作目錄執行都可以**：

```bash
python garmin/run_pipeline.py          # 從專案根目錄
cd garmin && python run_pipeline.py    # 從 garmin/ 目錄
```

---

## 抓取設定（步驟 ①）

需要 `garminconnect` 套件：

```bash
pip install garminconnect
```

帳密放在 `garmin/.env`（已在 `.gitignore` 中，不會被提交）：

```
GARMIN_EMAIL=your_email@example.com
GARMIN_PASSWORD=your_password
```

也可以用命令列參數或環境變數覆蓋。常用參數：

```bash
python garmin_connect_fetch.py --days 30                        # 最近 30 天
python garmin_connect_fetch.py --start-date 2026-05-19 --end-date 2026-07-11
python garmin_connect_fetch.py --days 3 --raw-debug-output data/raw_debug.json  # 除錯用
```

`--raw-debug-output` 會記錄每天每個 API 的呼叫結果、回傳資料形狀、轉換筆數，
用來確認「到底有沒有抓到東西」。**這是排查抓取問題的第一站。**

⚠️ `garminconnect` 是社群維護的非官方套件，Garmin 改介面時可能失效。

---

## 目前的已知限制

| 項目 | 狀況 |
|---|---|
| **這 57 晚跨 3 名配戴者** | 手錶 2026-05-28 ~ 08-27 之間經手三個人：`wearer_a` 41 晚（05-28~07-27，可信）、`unverified` 11 晚（07-28~08-27，已知多人戴過）、`wearer_c` 5 晚（08-28 起，專題負責人本人）。Tier3 每一項都是「今晚的你 vs 過去的你」，SRI 也是個人內比較，**跨人比較沒有意義**——所以 `trusted=False` 的區段把 Tier3 與 SRI 全部關掉。定義在 `apply_recovery_modifier.py` 的 `WEARER_SEGMENTS`。**報告要寫「跨 3 名配戴者、57 晚」** |
| **負責人本人的 Tier3 還在冷啟動** | `MIN_BASELINE_NIGHTS = 14`，而 `wearer_c` 目前只有 5 晚（08-28 ~ 09-01），所以那 5 晚的 `total_modifier` **全部是 0**、`modifier_note` 寫 "Building personal baseline"。這不是 bug——個人化修正的前提就是「有足夠的你自己的過去」。**Tier1/2 基礎分數不受影響** |
| **baseline 有兩個門檻，管的是不同的事** | `MAX_BASELINE_DAYS = 28` 管「多舊的資料還算數」（日曆天），`MIN_BASELINE_NIGHTS = 14` 管「要有幾晚才夠穩」（有效晚數）。配戴稀疏時兩者會同時咬到，那是正確行為 |
| **沒量到睡眠的夜晚不進 baseline** | `total_sleep_minutes = 0` 時手錶根本沒偵測到睡眠，那一列的 `avg_heart_rate` 量的是**清醒時段**（真正睡眠夜是 52–58，這些無效列是 85–95）。`compute_modifiers()` 的 `has_measured_sleep()` 會排除睡眠衍生的欄位，但**保留** `resting_heart_rate` 與 `steps_total`——那兩個不是從睡眠期算出來的 |
| **活動量修正值** | 自動停用中。因使用者起床後即取下手錶，`steps_total` 只記錄到傍晚在家的活動量（中位數僅 185 步），無法反映真實活動量。程式偵測到步數 baseline < 1000 就會停用此項並在 `modifier_note` 說明。**改成整天配戴、累積 14 天後會自動啟用。** |
| **SRI（睡眠規律指數）** | 只呈現數值與趨勢，**不計分**。因 Czeisler 2026 證實 SRI 會因計算方法不同而顯著改變，本專案的近似實作無法對照外部常模計分。詳見 `Garmin手錶分數.md` J 節。 |
| **HRV** | Vivoactive 3 不支援，改用 Garmin 內建壓力分數替代（該分數本身即由 HRV 推算）。 |
| **睡眠效率** | 因缺「上床時間」，分母用的是（起床 − 入睡），實為「睡眠期間效率」，不含入睡潛伏期。需 TAPO 攝影機提供上床時間才能算真實效率。 |
| **入睡潛伏期** | 同上，需等 TAPO。 |
| **REM = 0 的夜晚** | 部分夜晚 Garmin 本身就沒測到 REM（舊錶限制，非 bug），這些夜晚的 REM 項會排除計分而非給 0 分。 |

---

## 資料語意注意事項

避免踩過的坑再踩一次：

- **睡眠階段是「分鐘數」不是「段數」**——`deep_minutes` 等欄位來自 Garmin 的 `*SleepSeconds`，與 App 顯示一致。
- **一晚歸屬在「起床日」**——跟 Garmin 自己的 `calendarDate` 慣例一致。7/10 22:42 上床、7/11 07:51 起床，這晚算 7/11。
- **`steps_total` 用官方每日總數**（`get_daily_steps`），不是加總 96 個 15 分鐘區間（那樣會多算）。
- **`movement_sample_minutes`（原名 `movement_count`）是取樣分鐘數，不是動作量。**
  每分鐘一筆，99.98% 的間隔正好 60 秒；與睡眠時長 r=+0.929、與 WASO 只有 r=−0.138。
  改名就是因為舊名字會被讀成「翻身次數」。不要拿去跟 App 對照。
- **`avg_stress_score` 不是睡眠期間的壓力**，是該日曆日**白天**的平均
  （11439 筆讀數只有 8.6% 落在睡眠期間）。**已不計分**；Tier3 用的是
  `presleep_stress_score`（上一次起床 → 這一次入睡那整段清醒時段）。
- **`movement_level_mean/max` 與 `movement_active_minutes` 永不進評分**——
  `MOVEMENT_ACTIVE_THRESHOLD = 1.0` 是看資料分布訂的、沒有文獻依據，
  而本專案每一項計分都有引文，不破例。
- **HRV ≠ 心率**——心率是每分鐘幾下，HRV 是心跳間隔的變化量（ms），從每分鐘平均心率無法反推 HRV。

---

## 歷史沿革

- **2026-08-11**：資料夾整理。生成物移入 `data/`，新增 `run_pipeline.py` 與本 README。
  刪除 `garmin_importer.py`（讀手動匯出 CSV 的替代入口，`garmin_export/` 從未存在過，
  實際從未使用）——其中被 fetch 借用的 `build_standard_payload()` 已搬進
  `garmin_connect_fetch.py`，並順手修正 `source` 標籤（原本 API 抓的資料會被誤標成
  `garmin_connect_manual_export`）。同時移除有已知 bug 且無人讀取的
  `build_project_payload()` 與其產出 `garmin_project_payload.json`（該函式未按「一晚」
  分組，會把多日資料混算成一晚）。
- 本文件取代原本的 `GARMIN_IMPORT_GUIDE.md`（內容全是已刪除的 `garmin_importer.py` 用法）。
- **2026-08-28**：Tier3 改成依配戴者分段（`WEARER_SEGMENTS`）——先前所有夜晚被當成同一個人，
  導致 08-02 之後 10 晚裡 9 晚被誤判 `anxious`（含兩個 90 分以上的夜晚）。
  分界是用生理訊號本身找的：A→B 分界處靜止心率跳 5.73~6.74、睡眠期間平均心率跳 4.13，
  而前 41 晚內部三個訊號的最大跳躍都 ≤ 1.03。同一輪把 baseline 窗格從「筆數」改成「日曆天」。
