# Garmin 手動匯出匯入指南

本專案已提供 `garmin_importer.py`，可將 Garmin 手動匯出的 CSV 檔轉成：
- `garmin_standard_data.json`（標準化事件流）
- `garmin_project_payload.json`（可直接對接目前 Sonnap data contract）

## 1) 準備資料

1. 將 Garmin 手動匯出的 CSV 放到 `garmin_export/`。
2. 檔名不限，程式會自動讀取該資料夾下所有 `*.csv`。
3. 可先用 `garmin_export/sample_sleep.csv` 驗證流程。

## 2) 執行匯入

```bash
python garmin_importer.py
```

可選參數：

```bash
python garmin_importer.py --input-dir garmin_export --output garmin_standard_data.json --project-output garmin_project_payload.json --tz +08:00
```

## 3) 欄位對照（常用）

程式會嘗試多組常見欄位名稱：

- 時間：`timestamp` / `datetime` / `time` / `start_time`
- 心率：`heart_rate` / `hr` / `bpm`
- 壓力：`stress_score` / `stress`
- 步數：`steps` / `step_count`
- 睡眠階段：`sleep_stage` / `stage`（支援 `rem/deep/light/awake`）
- 動作：`movement` / `restlessness` / `motion`
- 入睡時間：`sleep_start_time` / `sleep_start` / `bed_time`
- 醒來時間：`wake_time` / `sleep_end_time` / `wake_up_time`

## 4) 你的需求欄位對應

你提出的欄位皆已支援轉換：
- 入睡時間 -> `sleep_start_time`
- 醒來時間 -> `wake_time`
- 心率（HR） -> `heart_rate`（bpm）
- 壓力分數 -> `stress_score`
- REM / DEEP / LIGHT / AWAKE -> `sleep_stage`
- Movement -> `movement`
- 步數 -> `steps`

## 5) 自動同步難度說明（簡版）

- 現階段建議先用手動匯出（最穩、最快可用）。
- 若要全自動同步，通常需：
  - 非官方方式（可做 PoC，但維護風險高）
  - 或 Garmin 官方合作 API（穩定但導入成本高）

## 6) Garmin Connect 直連抓取（路線二 PoC）

專案已新增 `garmin_connect_fetch.py`，可透過 Python 套件抓取資料後直接輸出：
- `garmin_standard_data.json`
- `garmin_project_payload.json`

先安裝套件：

```bash
pip install garminconnect
```

執行方式（建議使用環境變數）：

```bash
# Windows PowerShell
$env:GARMIN_EMAIL="your_email@example.com"
$env:GARMIN_PASSWORD="your_password"
python garmin_connect_fetch.py --days 3 --tz +08:00
```

或直接帶參數：

```bash
python garmin_connect_fetch.py --email your_email@example.com --password your_password --days 3
```

建議除錯模式（看每個 API 是否真的有抓到）：

```bash
python garmin_connect_fetch.py --start-date 2026-05-19 --end-date 2026-05-21 --tz +08:00 --raw-debug-output garmin_raw_debug.json
```

`garmin_raw_debug.json` 會列出每一天 sleep/hr/stress/steps 的：
- 是否成功呼叫
- 實際使用的方法名
- 回傳資料形狀（list/dict 與 key）
- 轉換後新增筆數
- 失敗嘗試（若有）

注意：
- 此做法屬社群套件 PoC，介面可能隨 Garmin 變動。
- 若沒有明確 movement 欄位，程式會使用 awake stage 生成 movement proxy。
