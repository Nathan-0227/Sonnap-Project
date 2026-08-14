# Sonnap: AI Sleep Companion 🌙

Sonnap 是一款結合「睡眠監測」與「AI 寵物陪伴」的創新應用。我們透過影像辨識技術分析使用者的睡眠狀態，並由 AI 生成專屬的夢境日記，讓睡眠不再只是休息，更是一場療癒的體驗。

## 👥 團隊成員與分工
- 李嘉友：專案經理 (PM) / 系統整合
- 王皓渝：UI/UX 設計（用Figma）
- Jeremy：前端開發 (App)
- Elvira：影像工程 (Python/OpenCV)
- 陳泰銘：AI 與數據處理

## 🚀 專案進度（2026-08-15）

| | 項目 | 狀態 |
|---|---|---|
| ✅ | 攝影機影像串流測試 | 5 晚真實整晚資料 |
| ✅ | UI 原型設計 (Figma) | 五個分頁已實作 |
| ✅ | 翻身偵測演算法開發 | 見 [`tapo/README.md`](tapo/README.md) |
| ✅ | 睡眠品質評分 | 46 晚實測，文獻加權 |
| ✅ | AI 夢境生成 API 串接 | 46 晚全數生成（改用 Claude API） |
| 🟡 | 系統整合與 Demo 測試 | 資料鏈路已打通；**五個分頁只有 Home 接了真資料** |

**目前最大的缺口**：整個系統假設只有一個使用者，而且資料不會自己更新。
完整盤點與優先順序見 **[`PROJECT_STATUS.md`](PROJECT_STATUS.md)**。

## 📖 文件在哪裡

| 想知道什麼 | 看這裡 |
|---|---|
| **整體現況、待決策事項、下一步** | [`PROJECT_STATUS.md`](PROJECT_STATUS.md) |
| Garmin 資料 pipeline 怎麼跑 | [`garmin/README.md`](garmin/README.md) |
| AI 睡眠顧問的設計與驗證機制 | [`ai/README.md`](ai/README.md) |
| Flutter App 結構、哪頁是真資料 | [`app/README.md`](app/README.md) |
| 攝影機模組、資料陷阱、已知問題 | [`tapo/README.md`](tapo/README.md) |
| 評分權重的文獻依據 | [`Research-Background/Garmin手錶分數.md`](Research-Background/Garmin手錶分數.md) |
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

### ⚠️ 實作與這份契約的三個差異（2026-08-15）

上面那份 JSON 是團隊最初議定的格式，**實際 payload 有三處不同**，
都是刻意的、也都寫進了 `PROJECT_STATUS.md` 給 PM 決策：

| 欄位 | 實際值 | 為什麼 |
|---|---|---|
| `motion_count` | **`null`** | Garmin 給不出「翻身次數」。TAPO 才是語意相符的來源，但目前只有 5 晚且尚未接入。**刻意不用 Garmin 的動作資料硬填**——語意不同，硬塞會永久掩蓋這個缺口 |
| `ambient_noise_db` | **`null`** | Garmin 沒有這個感測器。TAPO 新版雖然真的收音，但算出來的是未校準的相對值不是聲壓級（詳見 [`tapo/README.md`](tapo/README.md)） |
| `current_activity` | **`null`** | 需要「此刻」的狀態，但目前是隔日批次產出，給不出來 |

> **UI 遇到 `null` 應顯示「—」或隱藏該欄，不要顯示 0。**
> 「沒量到」和「量到是 0」是兩件事。

**另外**：`dream_summary` 最初規劃用 Gemini，**實際採用 Claude API**
（用標準庫 `urllib.request` 直接呼叫，不裝 SDK，所以沒有增加任何相依）。
實際 payload 還擴充了 `scoring` / `streak` / `history` 三個區塊——
沿用原有的頂層結構往下加，沒有另開一套。設計理由見 [`ai/README.md`](ai/README.md)。



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
python garmin/run_pipeline.py --fetch --days 30   # 重新抓資料並計算
python garmin/run_pipeline.py                     # 用現有資料重算
```

結果在 `garmin/data/garmin_sleep_quality_final.csv`。

詳細流程、各步驟說明、已知限制見 [`garmin/README.md`](garmin/README.md)；
評分權重的文獻依據見 [`Research-Background/Garmin手錶分數.md`](Research-Background/Garmin手錶分數.md)。
