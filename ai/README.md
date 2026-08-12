# AI 睡眠顧問

用 Claude API 產生每晚的**睡眠建議**與**寵物夢境日記**。

## 快速開始

```bash
cp ai/.env.example ai/.env        # 填入 ANTHROPIC_API_KEY
python ai/generate_advice.py --dry-run            # 先看 prompt，不花錢
python ai/generate_advice.py --dates 2026-08-09   # 只做一晚，人工檢查品質
python ai/generate_advice.py --limit 0            # 滿意了再全量補完
```

或掛在整條 pipeline 上（會在 payload 之前執行）：

```bash
python garmin/run_pipeline.py --ai
```

**沒有 API key 也不會壞**：印出提示、正常結束、既有內容不動、pipeline 不中止。

## 檔案

| 檔案 | 做什麼 |
|---|---|
| `llm_client.py` | Claude API 呼叫。**所有 HTTP 細節只在這一個檔案裡** |
| `night_profile.py` | 把 Garmin（+TAPO）資料整理成「事實清單」 |
| `generate_advice.py` | 主腳本：快取、驗證、降級、寫檔 |
| `env_utils.py` | 讀 `.env`（刻意複製自 `garmin/`，理由寫在檔案裡） |
| `data/ai_advice.json` | 主要產出 |
| `data/ai_advice.csv` | 由 JSON 衍生，方便用 Excel 看 |

## 這個功能為什麼存在

規則式 `recommendation` 一次只看一晚，46 晚只產生了 **8 種**不同字串。
它看不到跨夜的變化——例如 8/02 起使用者的睡眠平均心率從 56 跳到 70、
壓力分數變成 3 倍，規則式評分完全反映不出來，因為它一次只看一晚。

AI 補的就是這一層。

## 三個關鍵設計決定

**1. Python 判斷，模型只負責敘事。**
所有「這個數字好不好」的判斷都在 `night_profile.py` 用文獻門檻算完，
才把「數值 + 結論」餵給模型。門檻值是直接 `import` 評分程式的常數，
不是抄一份——抄一份的話，改了評分權重之後 AI 講的參考範圍就會跟分數對不上。

**2. `advice` 是「重新配音 + 加上趨勢」，不是取代。**
規則式文字原封不動留在 `garmin_sleep_quality_final.*` 當事實來源。
理由來自本專案自己的歷史：2026-07-20 修過 `build_recommendation()` 的自相矛盾
（Good 的夜晚卻被說「睡眠時間不足」）。讓模型從零生成建議等於重新引入同一類 bug。

**3. 不裝 SDK，用標準庫 `urllib.request`。**
**這整個功能不會讓 `requirements.txt` 多任何一行。**
代價是 API 改版時會壞（SDK 會吸收那種變動），緩解方式是把 HTTP 細節
全關在 `llm_client.py` 裡，日後要換 SDK 是單檔改動。

## 誠實揭露

**Garmin 完全沒有量測任何夢境內容。** REM 分鐘數只說明睡眠階段發生過，
沒說夢到什麼，而且 46 晚裡有 11 晚連 REM 都沒測到。

緩解措施（依強度排序）：

1. **虛構的是寵物的夢，不是使用者的夢**。prompt 強制第一人稱為寵物，
   UI 文案應寫「小寵物昨晚的夢境日記」
2. payload 帶機器可讀標記：`is_ai_generated`、`content_type`、`data_sources`
3. `disclaimer` 存在資料檔裡，匯出到報告的 CSV 會帶著它
4. **`dream_summary` 不得含任何數字** → 夢境永遠無法斷言任何測量值
5. REM 未測得的夜晚**誠實敘述缺口**（「日記中間幾頁是空白的」）而非粉飾
6. **TAPO 的模擬分貝資料絕不進 AI**（見下）

**TAPO 攝影機資料目前一律被擋掉。** 不是因為檔案不存在（`app/sleep_report.json`
確實存在），而是內容過不了有效性門檻：下午 15:47 的測試錄影、`motion_intensity`
達 2073600（= 整個 1920×1080 畫面）、15 分鐘內 301 次「大翻身」。
而且 `decibel` / `snore_count` 是 `np.random` 產生的，無論如何都不採用。
隊友修好之後不用改程式就會自動納入。

**隱私**：只送出衍生的數值事實，不送 email、帳號 id、裝置 id。

**可重現性**：輸出**不可重現**。同樣的輸入跑兩次會得到不同文字。
（註：這不是因為調高 temperature——`claude-opus-5` 根本不接受 `temperature`
參數，送了會回 400。不可重現性來自模型本身的取樣。）

## 輸出驗證

便宜、確定性。通不過就重試一次，再不過就降級成規則式內容，
**絕不快取驗證失敗的文字**：

- 三個欄位的長度界限
- **`dream_summary` 不得含數字** — 這一條消滅了整類「AI 講錯測量值」的失敗
- `advice` 裡的數字必須也出現在事實區塊裡
- 禁詞掃描（診斷、治療、失眠症、憂鬱症、藥物…）

降級時 `advice` 直接用規則式 `recommendation` **原文**——因為 advice 本來就
設計成規則式文字的重新配音，所以 **LLM 全掛時使用者一點實質內容都沒少**，
只少了語氣潤飾。

## 快取

| 情況 | 行為 |
|---|---|
| 沒有紀錄 | 生成 |
| `source == "fallback"` | 重新生成（fallback 是佔位不是結果） |
| `fingerprint` 不符 | 只列為 stale，要 `--refresh-stale` 才重生 |
| `--dates` 指定 | 無條件重生 |

`fingerprint` 用**刻意粗化**的資料算（分數四捨五入到最接近的 5、REM 用布林值
而非原始 0）。粗化是關鍵——否則每次微調評分權重（這專案已改過兩次）
就會讓 46 晚全部失效重花一次錢。

`--limit` 預設 10：主要不是控成本，是**控品質**——prompt 寫錯時你在第 10 晚
發現，不是第 46 晚。
