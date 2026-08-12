# Sonnap 專案現況報告

> 更新日期：2026-08-12｜撰寫者：陳泰銘（AI 與數據處理）
>
> 這份文件的目的是讓團隊與指導老師一眼看出**哪些能動、哪些不能動、
> 哪些需要決策**。裡面點名的問題都附上可驗證的證據（檔案與行號），
> 不是印象或猜測。

---

## 一、目前能動的東西

| 子系統 | 狀態 | 怎麼驗證 |
|---|---|---|
| Garmin 資料 pipeline | ✅ 完整可跑，約 2.3 秒 | `python garmin/run_pipeline.py` |
| 睡眠品質評分 | ✅ 46 晚實測（2026-05-29 ~ 08-09） | `garmin/data/garmin_sleep_quality_final.csv` |
| App 資料檔 | ✅ 每次跑 pipeline 自動產生 | `app/assets/data/app_payload.json` |
| 後端 API | ✅ 回傳真實資料 | `uvicorn main:app` → `GET /get-sleep-data` |
| Flutter 首頁 | ✅ 顯示真實分數與寵物心情 | `cd app && flutter run` |
| AI 睡眠顧問 | ✅ 46 晚全數由 Claude API 生成 | `ai/data/ai_advice.json` |

### 資料流現況

```
Garmin 手錶
    ↓  garmin/run_pipeline.py（5 步驟）
garmin/data/garmin_sleep_quality_final.json
    ↓  build_app_payload.py（＋ ai/ 的建議，有才用）
app/assets/data/app_payload.json  ← 只有這一份檔案
    ├─→ Flutter 打包成 asset，App 直接讀
    └─→ main.py 對外服務 GET /get-sleep-data
```

**刻意只產一份檔案**：兩份就會出現「App 顯示的跟 API 回傳的對不上」這種
最難查的 bug。同一個檔案兩種讀法，結構上不可能不一致。

---

## 二、需要團隊決策的事（**這一節最重要**）

以下每一項都已經有可運作的預設值，但**預設值是我單方面決定的，需要 PM 核可**。

### 2.1 分數 → 寵物心情的映射（`mapping_version: 1`）

README 的 data contract 定義 `pet_mood` 只有四種合法值。目前的映射：

| 條件 | `pet_mood` |
|---|---|
| `final_quality == Good` | `happy` |
| `final_quality == Normal` | `bored` |
| `final_quality ∈ {Poor, Bad}` | `tired` |
| **覆寫**：壓力或心率明顯高於個人 baseline | `anxious` |

`energy_level = round(final_score)`。

46 晚實測分布：happy 26、anxious 10、bored 8、tired 2。
定義在 `build_app_payload.py` 的 `QUALITY_TO_MOOD`，只有一個定義處。

**要決策的**：這個對應關係 UI/UX 組認不認同？`anxious` 用生理訊號觸發（而非分數）
是我的判斷，因為總分看不出「睡得夠久但自律神經緊繃」這種狀態。

### 2.2 `metrics.motion_count` 由誰提供

README 定義它是「翻身次數，由影像組提供之偵測數據」。
Garmin 也有一個 `movement_count`，但那是**我們自訂的翻動取樣筆數**，語意不同。

**目前 payload 裡 `motion_count` 是 `null`**，Garmin 的值另外放在
`garmin_movement_samples`。這是刻意的——硬對映會讓兩個不同的東西被當成同一個，
而且從此再也沒人發現。

**要決策的**：這個欄位最終由 TAPO 提供，還是改成用 Garmin 的值並改寫定義？

### 2.3 `metrics.ambient_noise_db` 由誰提供

**Garmin 手錶沒有這個數據。TAPO 目前的分貝是模擬值（見 3.2）。**
兩個來源都給不出真值，所以 payload 裡是 `null`。

**要決策的**：這個欄位要保留、移除，還是等到真的接上麥克風再說？

### 2.4 兩套睡眠分數要顯示哪一個

| | Garmin `final_score` | TAPO `sleep_quality_score` |
|---|---|---|
| 依據 | 文獻加權（Hirshkowitz/Hertenstein/Ohayon 等）+ 個人化修正 | 翻身次數扣分算術 |
| 範圍 | 0–100 | 有地板值，跑不到低分 |
| 穩定性 | 確定性——同樣輸入必得同樣結果 | **部分由亂數驅動**（見 3.2） |

**要決策的**：App 顯示哪一個？還是合併？這不該由任何一方自己決定。

### 2.5 `status.current_activity` 的即時狀態來源

contract 定義三種值（`sleeping`/`dreaming`/`waking_up`）用來驅動動畫。
但這需要「此刻」的狀態，而目前的 pipeline 是**隔日批次**產出的，給不出來。
payload 裡是 `null`，App 走 idle 動畫。

**要決策的**：要不要在 contract 裡加一個 `idle` 值？還是之後做即時串流？

### 2.6 contract 擴充欄位是否採納

為了讓 App 能運作，我在原 contract 頂層之外加了
`scoring` / `display` / `streak` / `history` 四個區塊，並在 `ai_content`
加了 `is_ai_generated` / `content_type` / `source`。

**沒有改動也沒有移除任何原有欄位。** 需要 PM 確認這個擴充可以寫回 README。

---

## 三、TAPO 側需要處理的問題

> 這一節點名的是隊友負責的部分。我用中性描述並附上可驗證的行號，
> **目的是讓問題被看見，不是評價任何人。** 這些都是很常見的開發中狀態。

### 3.1 時段判斷在真實睡眠時段永遠不會觸發

`tapo/motion_detector.py:50`：

```python
if now_str >= START_TIME and now_str < END_TIME and ...
```

這是**字串比較**。若把時間設成跨午夜的 `23:00:00` → `07:00:00`，
凌晨 01:30 的 `"01:30:00"` 不 `>= "23:00:00"`，條件**永遠是 false**。

目前設定是 `17:26:00`–`17:28:00`（第 12–13 行）的兩分鐘下午測試窗——
也就是說**它從來沒有真正監測過一整晚**。

修法：跨午夜時改成 `now_str >= START or now_str < END`。

### 3.2 分貝與打鼾是模擬值，不是量測值

`tapo/motion_detector.py:92, 94, 97` 用 `np.random` 產生 `sound_db`。
程式裡沒有麥克風、沒有音訊擷取。

這個模擬值往下流進 `snore_events`（第 195 行），再流進扣分公式
（第 199 行），最後影響它自己算出來的 `sleep_quality_score`。
**同一段影片跑兩次會得到不同分數。**

因為這樣，AI 顧問那邊已經明確擋掉這兩個欄位（`ai/README.md` 有說明）。

### 3.3 同一支程式有兩份不同版本

| | `tapo/motion_detector.py` | `app/sleep_monitor.py` |
|---|---|---|
| 行數 | 262 | 175 |
| 監測時段 | 17:26–17:28 | 15:10–15:11 |
| 扣分公式 | `large*2.0 + micro*0.1 + snore*0.4` | `100 - large*5 - snore*2`，地板 50 |
| 輸出 | MySQL | JSON 檔 |

**兩份的分數算法不一樣。** 需要 Elvira 決定留哪一份、刪哪一份。

### 3.4 `app/sleep_report.json` 的內容是下午測試資料

這個檔案（179 KB）已經進版控，內容是 2026-06-11 的測試：

| 證據 | 代表什麼 |
|---|---|
| timeline 從 `15:47` 開始 | 下午的錄影，不是整晚睡眠 |
| `motion_intensity: 2073600` | 正好 = 1920×1080，整個畫面都在動 |
| 15 分鐘內 `large_turn_count: 301` | 平均每 3 秒翻身一次 |
| `sleep_quality_score: 50` | 撞到公式的地板值 |

AI 顧問的有效性門檻會自動擋掉這種資料，隊友修好後不用改程式就會自動納入。

### 3.5 次要問題

- **RTSP 帳號密碼明碼寫死**在 `tapo/motion_detector.py:10` 與
  `app/sleep_monitor.py:9`，且都已進版控。建議改成讀環境變數，
  並考慮修改攝影機密碼。
- `sleep_records` 資料表**沒有任何建表 SQL**（只有 `INSERT INTO`，第 234 行），
  換一台電腦跑會直接失敗。
- `cv2.imshow`（第 172 行）讓它無法在無桌面環境（伺服器、排程）執行。
- **沒有偵測「上床時間」**——那是解鎖「入睡潛伏期」與「真實睡眠效率」
  這兩個文獻指標的關鍵，也是 TAPO 對本專案最大的潛在價值。

### 3.6 ⚠️ 臥室影片會進版控的風險（已處理，但請注意）

兩支 TAPO 程式都會在自己的目錄下產生 `turn_YYYYmmdd_HHMMSS.mp4`
——**臥室錄影片段**。原本 `.gitignore` 沒有擋，只要有人跑一次再 `git add .`
就會上傳到 GitHub。

已在根目錄 `.gitignore` 加上 `turn_*.mp4`（遞迴套用到所有子資料夾）。
目前沒有影片被提交過。

---

## 四、App 側現況

`app/` 是完整的 Flutter 專案（`lib/` 底下 24 支 dart 檔，5 個分頁）。

### 已接上真實資料

- **首頁**：睡眠分數、寵物心情、連續天數、所有文案都來自 `app_payload.json`
- 讀不到資料時顯示明確的錯誤狀態與解法，不是白畫面
- 夢境日記按鈕：有 AI 內容時顯示，並標明是**寵物的夢**與免責聲明

### ⚠️ 我多動了三個 widget 檔（原本計劃只碰 `home_screen.dart`）

接上真實資料後，`flutter test` 抓到三個 **RenderFlex overflow**（畫面會出現
黃黑斜線）。我用「隊友原本寫死的值」跑基準測試分離出責任歸屬：

| widget | overflow | 原因 | 誰造成的 |
|---|---|---|---|
| `header_card.dart` | 9 px | 倒數字串 `timeLeft` 在 30px 字級下會換行，撐破 150×150 的圓環 | **既有問題**——用隊友自己的值也會發生 |
| `sleep_score_card.dart` | 15 px | `message` 超過約 10 字就換行 | 我的字串太長 |
| `pet_mood_card.dart` | 11 px | `mood` 是 `"Anxious"`（7 字）時放不下 | 我的資料 |

三張卡都是固定 `height: 150`。處理方式：

- **`header_card.dart`**：`timeLeft` 包一層 `FittedBox(scaleDown)`，長字串縮小
  而不是換行。⚠️ **這個 bug 是時間相依的**——倒數字串的長度隨當下時間變化，
  所以只在某些時段出現，這也是為什麼一直沒被發現。
- **`sleep_score_card.dart` / `pet_mood_card.dart`**：固定 `height: 150` 改成
  `BoxConstraints(minHeight: 150)`。短字維持原樣，只有放不下時才長高。
  `home_screen.dart` 用 `IntrinsicHeight` + `stretch` 讓兩張卡一起長、保持等高。

**三個檔案的建構子都沒有改動**，呼叫端完全不受影響。
`build_app_payload.py` 那邊也加了 `MAX_SCORE_MESSAGE_CHARS = 10` 的檢查，
字串太長會在產生 payload 時就報錯，而不是等到有人打開 App 才看到斜線。

> Jeremy：這三個改動如果你不同意，還原它們不會影響資料層——
> 但還原後 `flutter test` 會失敗，而且畫面在部分情況下會出現黃黑斜線。

### 尚未接上（待處理）

| 項目 | 狀況 |
|---|---|
| **Insights 頁**（`report_screen.dart`） | 34 KB，資料寫死在 `CustomPainter` 內部。趨勢圖的 30 個數值、週心情、Top Sleep Distractions 都是假的 |
| **Top Sleep Distractions** | 顯示 YouTube/Instagram 用了幾分鐘——**這個資料完全沒有來源**，需要手機用量 API |
| **Sleep Tracking Sources** | 寫死顯示三個來源都「Active」，實際上 Camera 與 Phone 都沒有真實資料 |
| Assistant 頁 | `_getMockAiResponse()` 是關鍵字比對的假回覆 |
| Friends / Closet / Rewards | 全部是 coming-soon |

`history` 欄位已經在 payload 裡帶了最近 30 晚，Insights 頁要接的時候
不需要改後端。

### 語言不一致

App UI 是英文，但 `scoring.recommendation` 是中文（規則式評分的原文，
刻意不翻譯以保持事實來源單一）。目前後端額外提供英文短句給 UI 用。
`intl` 套件已經在 `pubspec.yaml` 裡，之後要做 i18n 有基礎。

---

## 五、設計文件裡零實作的功能

以下在 Figma 或設計文件中存在，但目前**完全沒有實作**：

目標就寢時間（有 UI 但不會存）、任務系統、寵物成長、好友睡眠狀態、
好友比較、成就徽章、Closet、Rewards。

⚠️ **所有社交功能都被同一件事擋住**：它們需要 `user_id`，
但目前所有資料輸出**只有 `date`，沒有任何多使用者支援**。
這是整條路徑的前置條件，不是可以最後再補的東西。

---

## 六、已知的資料品質限制（誠實揭露）

這些不是 bug，是必須在報告裡誠實標註的限制：

1. **手錶不支援 Garmin 官方睡眠分數**（Vivoactive 3 沒有 `sleepScores` 欄位），
   所以無法用官方分數驗證我們的評分。
2. **46 晚裡有 11 晚 REM = 0**，那是舊錶的偵測限制，**不代表沒有 REM 睡眠**。
   程式與 AI 都把這種情況標成「未測得」而不是 0。
3. **`sleep_efficiency` 不是臨床真效率**。因為缺「上床時間」，分母用的是
   （起床 − 入睡），實為「睡眠期間效率」，不含入睡潛伏期。
4. **配戴率偏低**：74 個日曆日裡只有 46 晚有記錄（約 62%），
   而且起床後會取下手錶，所以白天步數（中位數 185 步）無法反映真實活動量。
   活動量修正因此自動停用。這也讓 App 的「連續天數」數字偏小——那是誠實的結果。
5. **作息規律指數（SRI）刻意不計分**，只呈現數值。理由：不同計算方法算出的
   SRI 差異大到足以改變研究結論，拿去對照外部常模沒有意義。

6. **AI 文案是生成內容，不是量測值**（2026-08-12 起 46 晚全數由 `claude-sonnet-5` 生成）。
   `ai_content.content_type` 標成 `fiction+advice`：`dream_summary` 是**寵物自己的夢**，
   **不是使用者的夢**——手錶完全沒有量測夢境內容，宣稱知道使用者夢到什麼就是誤述資料。

   數值面有四道確定性防線（全部在 `ai/generate_advice.py` 的 `validate()`，
   通不過就重試，兩次都不過才退回規則式文字）：
   - 夢境**不得出現任何數字**（正規表示式擋阿拉伯與全形數字）
   - 建議裡出現的每個數字**必須逐字存在於事實區塊**
   - 禁詞表擋掉醫療宣稱（診斷／治療／藥物…）
   - 「日記中間有幾頁是空白的」這類**「這段沒有記錄」的意象，只有 REM 真的
     沒測到的夜晚才准用**

   最後一條是這輪最值得記的教訓。2026-08-12 第一次真實呼叫，2026-08-09 那晚
   REM 明明測到 29 分鐘，模型仍寫了空白頁——**等於對使用者謊稱這段沒有資料**，
   跟本專案堅持三個誠實 `null` 是同一件事。根因是 few-shot 把「評級 Bad」與
   「REM 未測得」兩個獨立條件綁在同一個範例裡，模型在 Bad 的夜晚就照抄。
   已改成依當晚事實動態組裝 prompt，並加上驗證層——而驗證層真的救到了：
   修好 prompt 之後模型仍會再犯，是被擋下重試才過的。

---

## 七、建議的下一步

| 優先度 | 事項 | 負責 |
|---|---|---|
| 高 | 決策第二節的六個問題 | PM |
| 高 | 修 TAPO 的時段邏輯（3.1），讓它能真的錄一整晚 | 影像組 |
| 高 | 決定兩份 TAPO 程式留哪一份（3.3） | 影像組 |
| 中 | 移除明碼帳密、改讀環境變數（3.5） | 影像組 |
| 中 | 人工抽查 46 晚的 AI 文案（已全數生成，見 6.6） | 我／PM |
| 中 | Insights 頁接上 `history` 資料 | 前端 |
| 中 | TAPO 加上「上床時間」偵測（解鎖兩個文獻指標） | 影像組 |
| 低 | 多使用者支援（所有社交功能的前置條件） | 全隊討論 |
