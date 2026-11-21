# 每晚睡前／起床的步驟（攝影機自動錄影）

照順序做。每一步後面寫了「看到什麼才算對」。哪一步不對，就看最下面的「出問題時」。

> 為什麼要這麼多步：按 Start Sleep 會叫電腦上的後端去開攝影機錄影（`camera_auto.py`）。
> 所以**筆電、後端、攝影機、手機四個都要在、都要連得到彼此**，少一個就沒有錄影。

---

## 睡前

| # | 做什麼 | 看到什麼才算對 |
|---|---|---|
| 1 | 筆電**插電**，螢幕**不要闔上** | 右下角電池圖示有插頭。⚠️ 防待機擋得住「放著不動自己睡」，**擋不住闔上螢幕**——闔上的話錄影跟後端一起停 |
| 2 | 筆電、手機、攝影機都連**同一個網路**（現在是手機熱點「Nathan S24+」） | Tapo App 打得開攝影機畫面 |
| 3 | 熱點重開過的話，在 Tapo App 看攝影機的 IP（設定 → Network Connection → Static IP 那頁） | 跟 `tapo 2.0/.env` 裡的一樣（2026-11-21 是 `10.202.54.253`）。不一樣就請 Claude 只改 IP 那段 |
| 4 | XAMPP 裡 MySQL 是開的（沒開就按**一次** Start） | MySQL 那列是綠的。⚠️ 不要連按 |
| 5 | 開後端（終端機貼這三行，視窗開著不要關） | 最後出現 `Uvicorn running on http://0.0.0.0:8000` |
| 6 | 手機打開 Sonnap | 首頁寫 **Hi, Nathan!**（寫 Sleeper ＝手機連不到後端，見下面） |
| 7 | 按導覽列中間的狗頭 → **Start Sleep** | 睡覺畫面副標底下出現 **Camera recording**（約 10 秒內） |
| 8 | 30 秒後在電腦跑 `--status`（指令在下面） | 印出 **● 錄影中** |
| 9 | 去睡 | — |

第 5 步的指令：

```powershell
cd C:\Users\user\Projects\Sonnap-Project
$env:SONNAP_DB_URL="mysql://root@localhost/sonnap"
.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

第 8 步的指令（另開一個終端機）：

```powershell
cd C:\Users\user\Projects\Sonnap-Project
.venv\Scripts\python.exe camera_auto.py --status
```

⚠️ 錄影程式在**背景**跑，電腦上**不會有視窗**。看不到視窗不代表沒在錄——以第 7、8 步為準。
⚠️ 筆電 IP 變了（不是 `10.202.54.92`）的話，手機 App 要重建才連得到——請 Claude 用新的 IP 重建。

---

## 起床

| # | 做什麼 | 看到什麼才算對 |
|---|---|---|
| 1 | 睡覺畫面按中間那顆外框的大按鈕 **Out of bed**（⚠️ 不是底下的小字 Cancel） | 進到起床動畫、起床自評 |
| 2 | 跑一次 `--status` | 印出 **○ 沒在錄**，最近一次是昨晚那份 |
| 3 | 跟 Claude 說「跑早晨匯入」 | 匯入檢查全過（錄影沒斷、攝影機沒被移動） |

- 按錯成 Cancel：那晚的錄影沒被刪，只是搬到 `tapo_metrics/cancelled/`，跟 Claude 說就好。
- 忘了按 Out of bed：錄影最多 14 小時會自己停。

---

## 出問題時

| 症狀 | 多半是 | 怎麼辦 |
|---|---|---|
| 首頁寫 Hi, Sleeper! | 手機連不到後端 | 確認第 2、5 步；筆電 IP 變了就要重建 App |
| 按了 Start Sleep 沒出現 Camera recording | 電腦連不到攝影機（多半是熱點換了攝影機 IP） | 看 `tapo_metrics/auto_logger.log` 最後幾行有沒有「連不上」→ 做第 3 步 |
| `--status` 寫「已經 N 秒沒寫入」 | 串流斷了，錄影程式會自己重連 | 等一分鐘再看；一直這樣就看 `auto_logger.log` |
| `--status` 寫「筆電沒插電」 | 第 1 步 | 插電 |
| 後端啟動時 `[Errno 10048]` | 8000 埠已經有一個後端在跑 | 不用再開；或請 Claude 找出來停掉 |
| XAMPP 的 MySQL 按 Start 起不來 | 資料庫上次沒正常關 | **不要連按**，請 Claude 照記憶裡的修法處理 |

（規則與理由見 CLAUDE.md「按 Start Sleep 自動開攝影機」那一節。）
