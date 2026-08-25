# tests/ — 後端驗收測試

```bash
pip install -r requirements.txt          # 含測試用的 httpx
python tests/test_healthconnect_adapter.py
python tests/test_api.py
```

兩支都是**獨立可執行的腳本**（不需要 pytest），跑完印出逐項結果，
全過回傳 exit code 0、有失敗回 1。刻意不引入 pytest，沿用專案
「優先用標準庫、非必要不加依賴」的既有規範。

⚠️ `test_api.py` 全程使用**暫存資料庫**，不會碰到 `data/sonnap.db`。

## 它們在驗什麼

| 檔案 | 驗收重點 |
|---|---|
| `test_healthconnect_adapter.py` | Health Connect 的資料走**既有評分器**算出的 Tier1/2 與手算相符；WASO 只算睡眠區間內（不含入睡潛伏期與醒後賴床）；壞資料明確失敗而非安靜算錯 |
| `test_api.py` | 多使用者隔離；紅線 5（差的夜晚回饋明顯較少）；紅線 4（`behavior/` 不 import 評分層）；缺資料會中斷連續紀錄；`DELETE /users` 真的 CASCADE；舊端點 `/get-sleep-data` 行為不變 |

## 為什麼這幾項值得寫成測試

這些不是「一般的單元測試」，每一條都對應一個**曾經或可能安靜失效**的地方：

- **分數與手算相符** —— 若哪天有人為 Health Connect 另寫一套評分，
  這裡會立刻爆掉。本專案最難複製的資產是「每一項計分都有文獻引文」，
  兩套標準就毀了它。
- **紅線 4 用 grep 驗 import 行** —— ⚠️ 不能單純搜關鍵字，
  那樣會抓到規則自己的說明文字（實際踩過）。
- **`DELETE /users` 的 CASCADE** —— SQLite 預設**不啟用**外鍵約束。
  忘了 `PRAGMA foreign_keys = ON` 的話刪除照樣回成功，只是留下孤兒資料，
  而我們已經對受測者承諾「退出即刪除」。失敗時沒有任何錯誤訊息。
- **舊端點行為不變** —— 新增多使用者路徑時最容易順手改壞的東西。
