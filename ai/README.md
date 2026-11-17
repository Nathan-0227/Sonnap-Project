# AI（寵物 notes 與睡眠助理）

兩個功能都走 Claude API，**每呼叫一次花一次額度**，測試一律換掉 API、不打真的網路。

| 功能 | 檔案 | 什麼時候呼叫 |
|---|---|---|
| **寵物 notes**（草地上那本日記：總結＋0–3 條建議） | `night_summary.py`，端點 `GET /night-summary` | 起床自評之後、手錶資料到了，每晚一次（存起來，事實變了才重生） |
| **睡眠助理**（問答） | `chat.py`，端點 `POST /chat` | 使用者每問一次 |

⚠️ **輸出語言是英文**（2026-08-26 決定，全系統一致）。`ADVICE_LANG` 這個變數**沒有實作**。

## 設定

```bash
cp ai/.env.example ai/.env        # 填入 ANTHROPIC_API_KEY
```

金鑰在 `chat.py` 被 import 時讀進來（`notes` 也經由它）。**沒有金鑰不會壞**：
notes 退回原句、助理回 503 照實說答不出來。

## 檔案

| 檔案 | 做什麼 |
|---|---|
| `llm_client.py` | Claude API 呼叫。**所有 HTTP 細節只在這一個檔案裡**（標準庫 `urllib`，不裝 SDK） |
| `text_guards.py` | 共用驗證規則：禁用字、中文洩漏、拼字數字。**只能有這一份** |
| `chat.py` | 睡眠助理；`validate_answer()` 也給 notes 用 |
| `night_summary.py` | 寵物 notes：判讀、事實區塊、驗證（清單外的行動、「AI 不准說」） |
| `env_utils.py` | 讀 `.env`（刻意複製自 `garmin/`，理由寫在檔案裡） |
| `data/ai_advice.json`／`.csv` | **退場的夢境日記的歷史資料**（117 筆、116 晚），沒有程式再讀它 |

## 寵物 notes 的規則從哪裡來

建議清單與每一句的出處在 `behavior/morning_tips.py` 與
`Research-Background/起床小建議與自評.md`（逐篇原文在 `生理狀況原因.md`）。
**行動只能來自那份清單**；AI 寫總結、挑建議、換成寵物口吻、說可能的原因（只准 might／can）。
不交給 AI 的：攝影機資料、Garmin 壓力分數；步數會給但不准當原因。完整規則見 CLAUDE.md
「早晨報告的後端」那張表。

## 夢境日記（2026-11-17 退場）

原本每晚在電腦上批次生成一篇寵物的夢（`generate_advice.py`、`night_profile.py`，2026-11-18 刪除）。
使用者決定改成能幫忙改善睡眠的 notes：「沒有人會去讀夢」。
那一代留下、仍然有效的教訓寫在 CLAUDE.md「AI 輸出的共用規則」：驗證規則寫寬很省事，
但每一次誤判都讓使用者拿不到內容。要看當時的 prompt 與意象去重，從 git 歷史找這兩支檔案。
