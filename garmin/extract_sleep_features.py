"""
extract_sleep_features.py

讀取 analyze_garmin_sleep.py 產生的每日睡眠彙整 (garmin_sleep_summary.csv)，
為每一個「有效的睡眠夜晚」抽取可供評分的特徵，輸出：
- garmin_sleep_features.csv
- garmin_sleep_features.json

本腳本只負責「資料準備」，不含評分規則；評分門檻與權重在 evaluate_sleep_quality.py。

使用方式：
    python extract_sleep_features.py              # 預設年齡 22（年輕成人）
    python extract_sleep_features.py --age 45     # 指定年齡

年齡的用途：
睡眠時長、REM 比例、WASO 的正常範圍都會隨年齡改變（見 Research-Background/Garmin手錶分數.md），
因此需要年齡才能套用正確的參考區間。年齡未來由使用者註冊時輸入，這裡先以參數提供。
本腳本只負責「判斷年齡屬於哪個年齡層」並記錄下來，實際門檻由評分腳本套用。

⚠️ 重要限制（報告中須誠實說明）：
本腳本算出的 sleep_efficiency 並非臨床定義的睡眠效率。
臨床定義的分母是「臥床時間」(time in bed，自上床躺下起算)，但 Garmin 只提供「入睡時間」，
沒有「上床時間」，因此這裡的分母是（起床時間 − 入睡時間），實為「睡眠期間效率」，
不包含入睡潛伏期。待 TAPO 攝影機提供上床時間後，才能計算真正的臨床睡眠效率。
"""

import argparse
import csv
import json
from datetime import datetime
from pathlib import Path


# 【2026-08-11】生成的資料檔集中放在 garmin/data/，用 Path(__file__).parent 定位，
# 不管從哪個工作目錄執行都能正確找到（見 garmin/README.md）。
DATA_DIR = Path(__file__).parent / "data"

DEFAULT_INPUT_CSV = DATA_DIR / "garmin_sleep_summary.csv"
DEFAULT_OUTPUT_CSV = DATA_DIR / "garmin_sleep_features.csv"
DEFAULT_OUTPUT_JSON = DATA_DIR / "garmin_sleep_features.json"

# 預設年齡：以大學生使用者為主要對象，落在「年輕成人」區間
DEFAULT_AGE = 22


def parse_args():
    parser = argparse.ArgumentParser(
        description="Extract sleep quality features from the Garmin daily sleep summary."
    )
    parser.add_argument(
        "--age",
        type=int,
        default=DEFAULT_AGE,
        help=f"User age, used to pick the age-band reference range (default {DEFAULT_AGE}).",
    )
    parser.add_argument("--input", default=DEFAULT_INPUT_CSV, help="Input sleep summary CSV.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT_CSV, help="Output features CSV.")
    parser.add_argument("--output-json", default=DEFAULT_OUTPUT_JSON, help="Output features JSON.")
    return parser.parse_args()


def age_band_for(age):
    """
    依年齡判斷所屬年齡層，供評分時套用對應的參考區間。

    年齡層劃分依據 Research-Background/Garmin手錶分數.md 中的分齡設計：
    - 睡眠時長參考 Hirshkowitz et al. (2015) 的分齡建議
    - REM 比例與 WASO 參考 Ohayon et al. (2004) 的全生命週期常模

    回傳：'child_teen' / 'young_adult' / 'middle_adult' / 'older_adult' / 'very_old_adult'
    """
    if age < 18:
        return "child_teen"
    if age <= 25:
        return "young_adult"
    if age <= 64:
        return "middle_adult"
    if age <= 79:
        return "older_adult"
    return "very_old_adult"


def parse_iso(ts):
    """把 ISO8601 字串（含 +08:00）轉成 datetime；失敗回 None。"""
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts)
    except (TypeError, ValueError):
        return None


def to_int(value):
    """安全轉整數；空字串/None/無法解析 -> None。"""
    try:
        if value is None or str(value).strip() == "":
            return None
        return int(float(value))
    except (TypeError, ValueError):
        return None


def to_float(value):
    """安全轉浮點數；空字串/None/無法解析 -> None。"""
    try:
        if value is None or str(value).strip() == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def ratio(part, whole):
    """安全比例計算（回傳 0–1，四捨五入到小數點後 4 位）；分母 <= 0 回 None。"""
    if whole is None or whole <= 0 or part is None:
        return None
    return round(part / whole, 4)


def is_valid_night(row):
    """
    判斷這一列是否為「有效的睡眠夜晚」。回傳 (是否有效, 略過原因)。

    採通用邏輯而非寫死日期，可自動處理：
    - 手錶沒戴著睡的日子（入睡/起床時間為空）
    - 入睡時間 == 起床時間 的異常資料（例如 2026-06-02）
    - 沒有任何睡眠時長的日子
    """
    start = parse_iso(row.get("sleep_start_time"))
    wake = parse_iso(row.get("wake_time"))
    total_sleep = to_int(row.get("total_sleep_minutes"))

    if start is None or wake is None:
        return False, "missing sleep-onset or wake time (the watch may not have been worn)"

    sleep_period_min = (wake - start).total_seconds() / 60.0
    if sleep_period_min <= 0:
        return False, "sleep interval <= 0 (onset and wake identical or reversed - bad row)"

    if not total_sleep or total_sleep <= 0:
        return False, "total sleep time is 0"

    return True, ""


def extract_features(row, age, band):
    """
    從一列有效的 summary 資料計算特徵。

    ── 輸出欄位的三種用途（供後續接手者參考）──────────────────────────
    輸出欄位刻意多於評分所需，因為它們服務三種不同目的：

    【1】餵給評分 (evaluate_sleep_quality.py 實際讀取的欄位)
        sleep_duration_hours、sleep_efficiency、waso_minutes、deep_ratio、rem_ratio、age_band

    【2】供 App 顯示與對帳 Garmin 使用，不進評分
        total_sleep_minutes、deep_minutes、light_minutes、rem_minutes、sleep_period_hours
            → 這些分鐘數是我們與 Garmin App 對帳的依據（Garmin 官方就是以分鐘顯示）
        light_ratio、awake_ratio
            → 供 App 畫睡眠結構圖（深/淺/REM 三段）與跨使用者比較
            → 註：light_ratio 不納入評分是刻意的設計，因為已實測驗證
              deep_ratio + light_ratio + rem_ratio = 1（誤差僅來自四捨五入），
              淺層比例並非獨立資訊；若深層與 REM 皆已計分，再對淺層計分會造成重複計算。
            → 註：awake_ratio 與 waso_minutes 是同一份資料的兩種表示法。
              評分採用 waso_minutes（絕對分鐘），因為文獻的 WASO 門檻是以分鐘定義的。

    【3】生理與行為指標
        avg_heart_rate、resting_heart_rate、avg_stress_score、total_steps

        ⚠️ 這一段的說明在 2026-08-12 修正過。原本寫「V2 預留（目前未計分）」，
           那是 Tier3 上線（2026-07-31）之前的舊敘述，**已經不正確**。

        現況要分兩層講，混在一起就會誤解：

        (a) 【這個檔案輸出的這幾欄】確實沒有任何程式讀取。
            evaluate_sleep_quality.py 雖然讀 features.csv，但它只用
            時長/效率/WASO/深睡/REM 五項算 Tier1/2 基礎分數。

        (b) 【同樣的數值】**有進計分**，只是走另一條路：
            apply_recovery_modifier.py 讀的是 garmin_sleep_summary.csv
            （analyze 的輸出，不是這個檔），拿來算 Tier3 修正值——
            靜止心率 ±2、睡眠期間平均心率 ±2、壓力 ±4、步數 0~+2，
            合計上限 ±12。文獻依據見 Research-Background/Garmin手錶分數.md F–I 節。

        所以這幾欄留在這裡是**冗餘**而非「預留」。保留它們是為了讓
        features.csv 單獨拿出去分析時資訊完整，不是因為之後要拿來計分。

    【4】動作指標（2026-08-12 新增，永不計分）
        movement_sample_minutes、movement_level_mean / max、movement_active_minutes
            → 舊的 movement_count 已證明是「取樣分鐘數」而非動作量：46 晚實測
              與睡眠時長相關 r = +0.929、與夜間清醒 r = −0.138，且 43/48 天
              等於錄製跨距分鐘數（誤差 0）。它測的是時鐘不是身體。
            → 真訊號是 Garmin sleepMovement 的 activityLevel（0–7.64 連續值），
              原本被 `+= 1` 丟掉，現已改為保留平均、峰值與超過門檻的分鐘數。
            → 與【3】不同，這幾欄**不是**「等文獻到位就計分」，而是**永不計分**：
              active 的門檻是人為選的，不像心率／壓力那樣有 baseline 方法學支持。
    ────────────────────────────────────────────────────────────
    """
    start = parse_iso(row.get("sleep_start_time"))
    wake = parse_iso(row.get("wake_time"))

    total_sleep_min = to_int(row.get("total_sleep_minutes")) or 0
    deep_min = to_int(row.get("deep_minutes")) or 0
    light_min = to_int(row.get("light_minutes")) or 0
    rem_min = to_int(row.get("rem_minutes")) or 0
    # awake_minutes 來自 Garmin awakeSleepSeconds，即入睡後的清醒時間，
    # 對應文獻中的 WASO (Wake After Sleep Onset)
    waso_min = to_int(row.get("awake_minutes")) or 0

    # 睡眠區間 = 起床 − 入睡（注意：非臨床「臥床時間」，見檔案開頭說明）
    sleep_period_min = (wake - start).total_seconds() / 60.0

    return {
        "date": row.get("date", ""),
        "sleep_start_time": row.get("sleep_start_time", ""),
        "wake_time": row.get("wake_time", ""),
        # 年齡資訊：供評分階段套用分齡參考區間
        "age": age,
        "age_band": band,
        # --- 睡眠量 ---
        "sleep_duration_hours": round(total_sleep_min / 60.0, 2),
        "total_sleep_minutes": total_sleep_min,
        "sleep_period_hours": round(sleep_period_min / 60.0, 2),
        # --- 睡眠效率（睡眠期間效率，非臨床真效率，見檔案開頭限制說明）---
        "sleep_efficiency": min(round(total_sleep_min / sleep_period_min * 100, 2), 100.0),
        # --- 睡眠結構（絕對分鐘）---
        "deep_minutes": deep_min,
        "light_minutes": light_min,
        "rem_minutes": rem_min,
        # WASO 絕對分鐘數：文獻的 WASO 門檻是以「分鐘」分齡設定，故需保留絕對值
        "waso_minutes": waso_min,
        # --- 睡眠結構（占總睡眠的比例，0–1）---
        "deep_ratio": ratio(deep_min, total_sleep_min),
        "rem_ratio": ratio(rem_min, total_sleep_min),
        "light_ratio": ratio(light_min, total_sleep_min),
        # 清醒比例分母用「睡眠+清醒」，因為清醒不計入總睡眠
        "awake_ratio": ratio(waso_min, total_sleep_min + waso_min),
        # --- 生理與行為指標（V2 評分才會使用，V1 先保留供後續分析）---
        "avg_heart_rate": to_float(row.get("avg_heart_rate")),
        "resting_heart_rate": to_int(row.get("resting_heart_rate")),
        "avg_stress_score": to_float(row.get("avg_stress_score")),
        # ── 動作相關（2026-08-12 改版）────────────────────────────
        # ⚠️ 這四欄一律**不進評分**。movement_active_* 的門檻是我們自己訂的、
        #    沒有文獻依據，只供 App 呈現與 AI 敘事。
        #
        # ⚠️ 注意這裡沒有用 `or 0`。上游 analyze 端在「沒戴錶」的夜晚
        #    刻意輸出 None，這裡若寫 `or 0` 就會把 None 轉成 0，
        #    等於謊稱「那晚完全沒動」——那是資料，不是事實。
        #    （對照上面 total_steps 用了 `or 0`：步數的 0 確實代表沒走，語意不同。）
        "movement_sample_minutes": to_int(row.get("movement_sample_minutes")) or 0,
        "movement_level_mean": to_float(row.get("movement_level_mean")),
        "movement_level_max": to_float(row.get("movement_level_max")),
        "movement_active_minutes": to_int(row.get("movement_active_minutes")),
        "total_steps": to_int(row.get("steps_total")) or 0,
    }


def main():
    args = parse_args()
    band = age_band_for(args.age)

    with open(args.input, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))

    features = []
    skipped = []
    for row in rows:
        valid, reason = is_valid_night(row)
        if valid:
            features.append(extract_features(row, args.age, band))
        else:
            skipped.append((row.get("date", "?"), reason))

    if not features:
        raise SystemExit("No valid sleep nights found. Check garmin_sleep_summary.csv first.")

    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(features, f, ensure_ascii=False, indent=2)

    with open(args.output, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=features[0].keys())
        writer.writeheader()
        writer.writerows(features)

    print("Sleep feature extraction complete.")
    print(f"- User age: {args.age}")
    print(f"- Input: {args.input}")
    print(f"- Output: {args.output} / {args.output_json}")
    print(f"- Valid sleep nights: {len(features)}")
    print(f"- Skipped: {len(skipped)}")
    for date, reason in skipped:
        print(f"    [skipped] {date}: {reason}")


if __name__ == "__main__":
    main()
