# tests/ — 後端驗收測試

```bash
pip install -r requirements.txt          # 含測試用的 httpx
python tests/test_healthconnect_adapter.py
python tests/test_api.py
python tests/test_scoring_guards.py
python tests/test_tapo_index.py
python tests/test_history_mood.py
```

五支都是**獨立可執行的腳本**（不需要 pytest），跑完印出逐項結果，
全過回傳 exit code 0、有失敗回 1。刻意不引入 pytest，沿用專案
「優先用標準庫、非必要不加依賴」的既有規範。

⚠️ `test_api.py` 全程使用**暫存資料庫**，不會碰到 `data/sonnap.db`。

> Flutter 端的測試在 `app/` 底下：`flutter test`（目前 **72 個**）與 `flutter analyze`。
> 測什麼見 [`../app/README.md`](../app/README.md)。

## 它們在驗什麼

| 檔案 | 驗收重點 |
|---|---|
| `test_healthconnect_adapter.py` | Health Connect 的資料走**既有評分器**算出的 Tier1/2 與手算相符；WASO 只算睡眠區間內；壞資料明確失敗而非安靜算錯 |
| `test_api.py` | 多使用者隔離；紅線 5（差的夜晚回饋明顯較少）；紅線 4（`behavior/` 不 import 評分層）；缺資料會中斷連續紀錄；`DELETE /users` 真的 CASCADE；舊端點 `/get-sleep-data` 行為不變 |
| `test_scoring_guards.py` | 四個評分層的機制（見下） |
| `test_tapo_index.py` | 五個攝影機資料的機制（見下） |
| `test_history_mood.py` | history 每晚的 `pet_mood` 在兩條路徑上一致（見下） |

## 為什麼這幾項值得寫成測試

這些不是「一般的單元測試」。**每一條守的都是「壞掉時不會報錯」的機制**——
會拋例外的 bug 跑一次就發現了，不需要測試來守；安靜地算出錯誤答案的才需要。

後三支的每一條，都用「把 bug 重新引入、確認測試會紅」驗證過。

### `test_scoring_guards.py`（4 條）

1. **`has_measured_sleep()` 與 `extract_sleep_features.is_valid_night()` 的判準不得漂移**
   —— 兩支刻意不互相 import，所以漂移沒有任何錯誤訊息
2. **沒量到睡眠的夜晚，睡眠衍生的量不得進 baseline**
   —— 含反向對照，確認那些欄位真的有被讀，否則這條會**假性通過**
3. **baseline 窗格是日曆天不是筆數**（`MAX_BASELINE_DAYS`）
4. **`MOTIF_FAMILIES` 與夢境調色盤選項一對一**，且沒有兩個家族共用關鍵字

### `test_tapo_index.py`（5 條）

日期取自 `video_clip` 檔名而非 `report_date`、壞掉的時間戳要能還原、
橫跨兩夜的紀錄要切開、重複檔要去重、每個欄位都要有 provenance 標籤。
這五件事錯了都不會拋例外，只會讓 A 晚的攝影機資料配上 B 晚的手錶資料。

### `test_history_mood.py`（3 條）

`/insights`（讀 SQLite）與打包的 asset（讀 JSON）走**不同資料來源、不同函式**
（asset 用 `map_pet_mood`、API 用 `resolve_mood`）。任何一邊改了規則而另一邊沒改，
都不會有錯誤訊息，只會讓使用者在首頁與 Insights 對同一晚看到**兩隻不同的寵物**。

⚠️ 裡面有一條**反向對照**（確認樣本裡真的有 anxious 的夜晚）——
沒有它的話，把 anxious 覆寫整個拿掉，測試仍然全綠。

### 其他幾條的來歷

- **分數與手算相符** —— 若哪天有人為 Health Connect 另寫一套評分，這裡會立刻爆掉。
  本專案最難複製的資產是「每一項計分都有文獻引文」，兩套標準就毀了它。
- **紅線 4 用 grep 驗 import 行** —— ⚠️ 不能單純搜關鍵字，
  那樣會抓到規則自己的說明文字（實際踩過）。
- **`DELETE /users` 的 CASCADE** —— SQLite 預設**不啟用**外鍵約束。
  忘了 `PRAGMA foreign_keys = ON` 的話刪除照樣回成功，只是留下孤兒資料，
  而我們已經對受測者承諾「退出即刪除」。失敗時沒有任何錯誤訊息。
- **舊端點行為不變** —— 新增多使用者路徑時最容易順手改壞的東西。
