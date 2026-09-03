# Sonnap: AI Sleep Companion 🌙

Sonnap 是一款結合「睡眠監測」與「AI 寵物陪伴」的創新應用。我們透過影像辨識技術分析使用者的睡眠狀態，並由 AI 生成專屬的夢境日記，讓睡眠不再只是休息，更是一場療癒的體驗。

## 👥 團隊成員與分工
- 李嘉友：專案經理 (PM) / 系統整合
- 王皓渝：UI/UX 設計（用Figma）
- Jeremy：前端開發 (App)
- Elvira：影像工程 (Python/OpenCV)
- 陳泰銘：AI 與數據處理

## 🚀 專案進度（2026-09-04）

| | 項目 | 狀態 |
|---|---|---|
| ✅ | 睡眠品質評分 | **57 晚實測**（2026-05-29 ~ 09-01），文獻加權。⚠️ 跨 **3 名配戴者**，見下 |
| ✅ | AI 夢境生成 | 57 晚全數由 Claude 生成（`claude-sonnet-5`），**0 晚退回規則式** |
| ✅ | UI 原型設計 (Figma) | 五個分頁已實作 |
| ✅ | 後端多使用者 API | 11 個端點、七張表、暱稱制免註冊，含行為介入迴圈 |
| ✅ | Flutter APK | 能自己建置並裝進實體 Android 手機；已用實機連後端實測通過 |
| 🟡 | 攝影機影像串流 | 20 晚原始資料已進 `tapo_index.py`，19 晚通過有效性判準。**但還不能計分**，見下 |
| 🟡 | 系統整合與 Demo | 五頁**三頁接了真資料**（Home / Insights / Assistants）；Friends 與 Settings 仍是寫死內容 |

### ⚠️ 這 57 晚不是同一個人

手錶在 2026-05-28 ~ 08-27 之間經手三個人。**報告不能寫「單一使用者 57 晚」**，
誠實的寫法是「跨 3 名配戴者、57 晚」：

| 區段 | 期間 | 夜數 | Tier3 個人化修正 |
|---|---|---|---|
| `wearer_a` | 05-28 ~ 07-27 | 41 | ✅ 正常計算 |
| `unverified` | 07-28 ~ 08-27 | 11 | ❌ 已知多人戴過，Tier3 與 SRI 全部關掉 |
| `wearer_c`（專題負責人本人） | 08-28 起 | **5** | ⏳ 冷啟動中，修正值全為 0 |

⚠️ **負責人本人目前只有 5 晚，而 Tier3 需要 14 晚才會啟動**（`MIN_BASELINE_NIGHTS`），
所以本人的夜晚在報告期間**只有 Tier1/2 的基礎分數**。這不是 bug，是刻意的——
個人化修正值的前提就是「有足夠的你自己的過去」。

**Tier1/2 的基礎分數完全不受配戴者影響**（文獻加權、不依賴個人 baseline），
所以每一晚的分數本身仍然站得住。詳見 [`docs/REPORT_CAVEATS.md`](docs/REPORT_CAVEATS.md)。

### 目前最大的兩個缺口

**1. 攝影機的分數還不能用。** 不是靈敏度要調——`sleep_quality_score` 量的是事件時間軸
長度，而時間軸長度取決於**當晚的偵測門檻**，那個門檻逐晚變過且沒有記錄在任何欄位裡，
所以**跨夜比較在原理上就不成立**。要讓攝影機參與計分，得先補一份
`Research-Background/攝影機分數.md`（專案紅線 2：要計分，先有文獻依據）。
問題清單與偵測層規格：[`docs/TAPO_HANDOFF.md`](docs/TAPO_HANDOFF.md)。

**2. 設定存不下來。** Settings 頁的就寢時間現在兩頁同步了，但**沒有存到裝置、
也沒有送到後端**（`users.target_bedtime` 才是 Tier A 一切計算的基準）。
關掉 App 就忘記。

完整盤點與優先順序見 **[`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md)**。

## 📖 文件在哪裡

| 想知道什麼 | 看這裡 |
|---|---|
| **整體現況、待決策事項、下一步** | [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) |
| Garmin 資料 pipeline 怎麼跑 | [`garmin/README.md`](garmin/README.md) |
| AI 睡眠顧問的設計與驗證機制 | [`ai/README.md`](ai/README.md) |
| Flutter App 結構、哪頁是真資料 | [`app/README.md`](app/README.md) |
| 攝影機模組、資料陷阱、已知問題 | [`tapo/README.md`](tapo/README.md) |
| 評分權重的文獻依據 | [`Research-Background/Garmin手錶分數.md`](Research-Background/Garmin手錶分數.md) |
| **報告怎麼寫才誠實** | [`docs/REPORT_CAVEATS.md`](docs/REPORT_CAVEATS.md) |
| 逐輪的開發過程紀錄 | [`docs/DEVLOG.md`](docs/DEVLOG.md) |
| 攝影機偵測層要修什麼（交給影像組） | [`docs/TAPO_HANDOFF.md`](docs/TAPO_HANDOFF.md) |
| 企劃書與實作的落差盤點 | [`docs/PROPOSAL_GAP.md`](docs/PROPOSAL_GAP.md) |
| 社交功能的文獻依據 | [`Research-Background/社交功能設計.md`](Research-Background/社交功能設計.md) |

🔗 Figma： [(https://www.figma.com/files/team/1633021850224699912/recents-and-sharing?fuid=1633021848674802056)]

開發環境： Python 3.13、Flutter 3.44.9 / Dart 3.12.2

## ⚙️ 系統架構 (Data Contract)
我們使用 JSON 格式進行模組間的數據溝通：
```json
{
  "session_id": "20260512_001",
  "status": {
    "pet_mood": "happy", 
    "current_activity": "dreaming",
    "energy_level": 85
  },
  "metrics": {
    "motion_count": 12,
    "sleep_duration_minutes": 240,
    "ambient_noise_db": 35
  },
  "ai_content": {
    "dream_summary": "Tonight, the little creature dreamed of floating on a giant marshmallow in a starry sky.",
    "advice": "You had a very calm night, keep up the good work!"
  },
  "timestamp": "2026-05-12T22:00:00Z"
}

```

### 欄位說明（開發者指南）

- **`pet_mood`** (String)：寵物心情，支援 `happy` / `tired` / `bored` / `anxious`。
- **`current_activity`** (String)：動畫狀態，支援 `sleeping` / `dreaming` / `waking_up`。
- **`motion_count`** (Integer)：翻身次數，由影像組提供之偵測數據。
- **`dream_summary`** (String)：AI 生成的夢境描述文字。
- **`energy_level`** (Integer)：0–100，用於影響寵物動畫的活躍度。

### ⚠️ 實作與這份契約的差異（2026-09-04 對照實際 payload）

上面那份 JSON 是團隊最初議定的格式，**實際 payload 有三個欄位是 `null`**，都是刻意的：

| 欄位 | 實際值 | 為什麼 |
|---|---|---|
| `motion_count` | **`null`** | Garmin 給不出「翻身次數」。TAPO 才是語意相符的來源，但它的事件數還不可跨夜比較，**刻意不硬填**——硬塞會永久掩蓋這個缺口。Garmin 自己的動作取樣另外放在 `metrics.garmin_movement`，名字不同就是為了不讓人誤讀成翻身次數 |
| `ambient_noise_db` | **`null`** | Garmin 沒有這個感測器。TAPO 算得出數值，但那是未校準的數位振幅（dBFS）不是聲壓級，不能寫成「環境音 35 分貝」 |
| `current_activity` | **`null`** | 需要「此刻」的狀態，但目前是隔日批次產出，給不出來 |

> **UI 遇到 `null` 應顯示「—」或隱藏該欄，不要顯示 0。**
> 「沒量到」和「量到是 0」是兩件事。

**另外**：`dream_summary` 最初規劃用 Gemini，**實際採用 Claude API**
（用標準庫 `urllib.request` 直接呼叫，不裝 SDK，沒有增加任何相依）。
實際 payload 還擴充了 `scoring` / `display` / `streak` / `history` / `data_sources`
等區塊——沿用原有的頂層結構往下加，沒有另開一套。

⚠️ **輸出字串一律英文**（2026-08-26 決定）：payload 欄位、API 訊息、評分建議、
AI 夢境都是英文。**程式碼註解與 docstring 維持中文**——那是給團隊讀的說明不是輸出。

🛠 開發規範 (Workflow)

為了確保團隊協作順暢，請所有組員遵守以下規則：

1.請勿直接 Push 到 main 分支。請從 main 切出新分支開發：git checkout -b feature/功能名稱。

2.遇到 Bug 或需要討論功能時，請在 GitHub Issues 建立任務，避免資訊散落在通訊軟體。

3.Commit Message 請保持簡潔（如：feat: 新增睡眠數據欄位）。

## Garmin 睡眠資料與評分

從 Garmin 手錶抓資料，經過整理、特徵抽取，算出每晚的睡眠品質分數（0–100）。

快速開始：
1. 安裝套件：`pip install garminconnect`
2. 在 `garmin/.env` 填入 `GARMIN_EMAIL` 與 `GARMIN_PASSWORD`
3. 執行整條 pipeline：

```bash
python garmin/run_pipeline.py                     # 用現有資料重算（約 3 秒）
```

結果在 `garmin/data/garmin_sleep_quality_final.csv`。

⚠️ **要重抓資料請給完整區間，不要用 `--days N`**——抓取那一步是**覆寫**不是增量，
`--days 7` 會把整個 `garmin_standard_data.json` 換掉、只留最近 7 天，
**弄丟前面所有歷史且沒有任何警告**：

```bash
python garmin/garmin_connect_fetch.py --start-date 2026-05-28 --end-date <今天>
python garmin/run_pipeline.py
```

詳細流程、各步驟說明、已知限制見 [`garmin/README.md`](garmin/README.md)；
評分權重的文獻依據見 [`Research-Background/Garmin手錶分數.md`](Research-Background/Garmin手錶分數.md)。
