"""
evaluate_sleep_quality.py

讀取 extract_sleep_features.py 產生的 garmin_sleep_features.csv，
以 rule-based 方式計算每晚的睡眠品質分數（0–100）、分級與建議，輸出：
- garmin_sleep_quality.csv
- garmin_sleep_quality.json

═══════════════════════════════════════════════════════════════════
評分架構（V1）
═══════════════════════════════════════════════════════════════════
權重設計依 Research-Background/Garmin手錶分數.md 的 PSQI 式原則：
「核心指標主導、輔助指標修正」(Buysse et al., 1989 的 component-to-global score 架構)。

核心指標（高權重，直接反映睡眠本體與連續性）：
  睡眠時長 30 分 / 睡眠效率 25 分 / WASO 夜間清醒 25 分
輔助指標（低權重，補充睡眠結構資訊）：
  深層睡眠比例 10 分 / REM 比例 10 分

分級：80–100 Good ／ 65–79 Normal ／ 50–64 Poor ／ <50 Bad

═══════════════════════════════════════════════════════════════════
⚠️ V1 已知限制（報告中須誠實說明）
═══════════════════════════════════════════════════════════════════
1. 睡眠效率並非臨床真效率：因缺「上床時間」，分母為（起床−入睡），不含入睡潛伏期，
   數值會偏高，鑑別力有限。待 TAPO 攝影機提供上床時間後才能改為臨床定義。
2. 裝置限制：Vivoactive 3 部分夜晚 REM = 0（已實測確認 Garmin 官方也顯示無 REM）。
   為避免因裝置偵測限制而懲罰使用者，當 REM = 0 時視為「未測得」，
   將其權重按比例重新分配給其他可用指標（見 normalize 邏輯）。
3. 心率／壓力／活動量未納入 V1：文獻要求以「個人 baseline + 趨勢」判讀
   (Kerkering et al., 2022)，而非固定門檻，留待 V2 實作。
4. Vivoactive 3 不支援 HRV（已實測 get_hrv_data 回傳空值），
   故以 Garmin 壓力分數（其內部由 HRV 推算）作為替代，同樣留待 V2。
"""

import argparse
import csv
import json
from pathlib import Path


# 【2026-08-11】生成的資料檔集中放在 garmin/data/，用 Path(__file__).parent 定位，
# 不管從哪個工作目錄執行都能正確找到（見 garmin/README.md）。
DATA_DIR = Path(__file__).parent / "data"

DEFAULT_INPUT_CSV = DATA_DIR / "garmin_sleep_features.csv"
DEFAULT_OUTPUT_CSV = DATA_DIR / "garmin_sleep_quality.csv"
DEFAULT_OUTPUT_JSON = DATA_DIR / "garmin_sleep_quality.json"


# ═══════════════════════════════════════════════════════════════════
# 分齡參考區間（門檻皆有文獻依據）
# ═══════════════════════════════════════════════════════════════════

# 【睡眠時長】單位：小時，(理想下限, 理想上限)
# 文獻：Hirshkowitz M, et al. National Sleep Foundation's sleep time duration
#       recommendations: methodology and results summary. Sleep Health. 2015;1(1):40-43.
#       doi:10.1016/j.sleh.2014.12.010
#       （青少年 8–10h、年輕成人與成人 7–9h、老年人 7–8h）
DURATION_RANGE = {
    "child_teen": (8.0, 10.0),
    "young_adult": (7.0, 9.0),
    "middle_adult": (7.0, 9.0),
    "older_adult": (7.0, 8.0),
    "very_old_adult": (7.0, 8.0),
}

# 【REM 比例】單位：%，(理想下限, 理想上限)
# 文獻：Ohayon MM, Carskadon MA, Guilleminault C, Vitiello MV. Meta-analysis of
#       quantitative sleep parameters from childhood to old age in healthy individuals.
#       SLEEP. 2004;27(7):1255-1273. doi:10.1093/sleep/27.7.1255
#       REM 比例隨年齡下降，故採五段分齡參考區間（非臨床診斷切點）
REM_RANGE = {
    "child_teen": (22.0, 27.0),
    "young_adult": (20.0, 25.0),
    "middle_adult": (18.0, 22.0),
    "older_adult": (16.0, 20.0),
    "very_old_adult": (14.0, 18.0),
}

# 【WASO 入睡後清醒時間】單位：分鐘，(佳的上限, 尚可的上限)；超過第二值視為偏高
# 文獻：Ohayon MM, et al. SLEEP. 2004;27(7):1255-1273.（WASO 隨年齡明顯增加）
#       Harrison EI, et al. Sleep time and efficiency in patients undergoing
#       laboratory-based polysomnography. J Clin Sleep Med. 2021;17(8):1591-1598.
#       doi:10.5664/jcsm.9252
#       採分齡三段式判讀，避免將正常老化造成的 WASO 增加誤判為異常
WASO_THRESHOLD = {
    "child_teen": (10.0, 20.0),
    "young_adult": (15.0, 30.0),
    "middle_adult": (20.0, 40.0),
    "older_adult": (30.0, 50.0),
    "very_old_adult": (40.0, 60.0),
}

# 【深層睡眠比例】單位：%，(參考下限, 參考上限)
# 文獻：Boulos MI, et al. Normal polysomnography parameters in healthy adults:
#       a systematic review and meta-analysis. Lancet Respir Med. 2019;7(6):533-543.
#       doi:10.1016/S2213-2600(19)30057-8
#       Hertenstein M, et al. Reference data for polysomnography-measured and
#       subjective sleep in healthy adults. J Clin Sleep Med. 2018;14(4):523-532.
#       doi:10.5664/jcsm.7036
# 註：文獻明確指出深睡比例個體差異大、無單一臨床切點，故此為「操作性參考區間」
DEEP_RANGE = (13.0, 23.0)

# 【睡眠效率】單位：%
# 文獻：Hertenstein M, et al. J Clin Sleep Med. 2018;14(4):523-532.
#       健康成人 SE 分布變異大（±1SD 可達 71–93%），臨床常以 <80% 為偏低參考，
#       但不宜視為嚴格病理切點，故採保守三段式分級
EFFICIENCY_GOOD = 85.0   # ≥85% 良好
EFFICIENCY_FAIR = 80.0   # 80–84.9% 尚可；<80% 偏低

# 各指標配分（核心 80 分 + 輔助 20 分 = 100）
WEIGHTS = {
    "duration": 30,
    "efficiency": 25,
    "waso": 25,
    "deep": 10,
    "rem": 10,
}

# 分級門檻
GRADE_THRESHOLDS = [
    (80, "Good"),
    (65, "Normal"),
    (50, "Poor"),
    (0, "Bad"),
]


def parse_args():
    parser = argparse.ArgumentParser(description="Compute a rule-based sleep quality score for each night.")
    parser.add_argument("--input", default=DEFAULT_INPUT_CSV, help="Input features CSV.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT_CSV, help="Output scoring CSV.")
    parser.add_argument("--output-json", default=DEFAULT_OUTPUT_JSON, help="Output scoring JSON.")
    return parser.parse_args()


def to_float(value):
    """安全轉浮點數；空字串/None/無法解析 -> None。"""
    try:
        if value is None or str(value).strip() == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def score_range(value, low, high, full_points, decay_per_unit):
    """
    區間式評分：落在 [low, high] 內給滿分，偏離時依距離線性扣分（最低 0 分）。

    這種「參考區間 + 漸進扣分」的設計，是為了呼應文獻反覆強調的一點：
    睡眠參數的健康範圍具有高度個體差異，不應以單一硬切點判定正常/異常。
    """
    if value is None:
        return None
    if low <= value <= high:
        return float(full_points)
    distance = (low - value) if value < low else (value - high)
    return max(0.0, full_points - distance * decay_per_unit)


def score_duration(hours, band):
    """睡眠時長評分（30 分）。每偏離理想區間 1 小時扣 10 分。"""
    low, high = DURATION_RANGE[band]
    return score_range(hours, low, high, WEIGHTS["duration"], decay_per_unit=10.0)


def score_efficiency(efficiency):
    """
    睡眠效率評分（25 分）。依 Hertenstein (2018) 的三段式分級。
    ⚠️ V1 的效率因缺上床時間而偏高，鑑別力有限（見檔案開頭限制說明）。
    """
    if efficiency is None:
        return None
    if efficiency >= EFFICIENCY_GOOD:
        return float(WEIGHTS["efficiency"])          # 良好：滿分
    if efficiency >= EFFICIENCY_FAIR:
        return WEIGHTS["efficiency"] * 0.68          # 尚可：約 17 分
    # 偏低：自 40% 分數起，每低於 80% 一個百分點再扣分
    base = WEIGHTS["efficiency"] * 0.40              # 10 分
    return max(0.0, base - (EFFICIENCY_FAIR - efficiency) * 0.5)


def score_waso(waso_minutes, band):
    """
    WASO 夜間清醒評分（25 分）。依分齡三段式：佳=滿分、尚可=六成、偏高=依超出程度遞減。
    """
    if waso_minutes is None:
        return None
    good_limit, fair_limit = WASO_THRESHOLD[band]
    if waso_minutes <= good_limit:
        return float(WEIGHTS["waso"])                # 佳：滿分
    if waso_minutes <= fair_limit:
        return WEIGHTS["waso"] * 0.60                # 尚可：15 分
    # 偏高：自 40% 分數起，每超出 fair_limit 一分鐘扣 0.5 分
    base = WEIGHTS["waso"] * 0.40                    # 10 分
    return max(0.0, base - (waso_minutes - fair_limit) * 0.5)


def score_deep(deep_ratio_pct):
    """深層睡眠比例評分（10 分）。偏離 13–23% 參考區間時，每 1 個百分點扣 0.8 分。"""
    low, high = DEEP_RANGE
    return score_range(deep_ratio_pct, low, high, WEIGHTS["deep"], decay_per_unit=0.8)


def score_rem(rem_ratio_pct, band):
    """REM 比例評分（10 分）。偏離分齡區間時，每 1 個百分點扣 0.6 分。"""
    low, high = REM_RANGE[band]
    return score_range(rem_ratio_pct, low, high, WEIGHTS["rem"], decay_per_unit=0.6)


def grade_for(score):
    """依總分給出分級標籤。"""
    for threshold, label in GRADE_THRESHOLDS:
        if score >= threshold:
            return label
    return "Bad"


def build_recommendation(grade, component_scores, band, feats):
    """
    依「失分最多的指標」產生針對性建議（rule-based）。
    未來可替換為 Gemini AI 生成更自然的文字。
    """
    # 找出相對失分最嚴重的指標（失分比例 = 失去的分 / 該指標權重）
    losses = {}
    for name, earned in component_scores.items():
        if earned is None:
            continue
        weight = WEIGHTS[name]
        losses[name] = (weight - earned) / weight

    advice = []
    if grade == "Good":
        advice.append("Sleep quality was good. Keep your current routine. ")
    elif grade == "Normal":
        advice.append("Sleep quality was acceptable, with room to improve. ")
    elif grade == "Poor":
        advice.append("Sleep quality was below average; consider adjusting your routine. ")
    else:
        advice.append("Sleep quality was poor; this is worth addressing. ")

    # Good 等級不再給「改進建議」：整晚已經判定良好，若還指出某指標
    # 「失分最多」並建議改動作息，會跟前面「請維持目前的作息」自相矛盾。
    if losses and grade != "Good":
        worst = max(losses, key=losses.get)
        # 只有在該指標確實有明顯失分時才給針對性建議
        if losses[worst] > 0.15:
            if worst == "duration":
                low, high = DURATION_RANGE[band]
                # 從 CSV 讀進來的是字串，需先轉成數字才能比較
                hours = to_float(feats.get("sleep_duration_hours"))
                if hours is not None and hours < low:
                    advice.append(f"Sleep was short ({hours} h). Try going to bed earlier; aim for {low}–{high} h.")
                else:
                    advice.append(f"Sleep ran long. Keep a regular schedule; aim for {low}–{high} h.")
            elif worst == "efficiency":
                advice.append("Sleep efficiency was low, meaning a fair amount of time in bed was spent awake. Avoid using your phone in bed.")
            elif worst == "waso":
                advice.append("Time awake during the night was high. Check your sleep environment (light, noise, temperature) and avoid caffeine before bed.")
            elif worst == "deep":
                advice.append("Deep sleep share fell outside the usual range. Regular exercise and a consistent bedtime help raise deep sleep.")
            elif worst == "rem":
                advice.append("REM share fell outside the age-based norm. Keep a regular schedule and reduce pre-sleep stress.")

    return "".join(advice)


def evaluate_night(row):
    """對一晚的特徵計算各指標分數與總分。"""
    band = row.get("age_band", "young_adult")
    if band not in DURATION_RANGE:
        band = "young_adult"

    duration_h = to_float(row.get("sleep_duration_hours"))
    efficiency = to_float(row.get("sleep_efficiency"))
    waso_min = to_float(row.get("waso_minutes"))
    # 特徵檔中的比例是 0–1，評分門檻用百分比，故乘 100
    deep_ratio = to_float(row.get("deep_ratio"))
    rem_ratio = to_float(row.get("rem_ratio"))
    deep_pct = deep_ratio * 100 if deep_ratio is not None else None
    rem_pct = rem_ratio * 100 if rem_ratio is not None else None

    # 裝置限制處理：REM = 0 視為「未測得」而非「REM 極差」，
    # 避免因 Vivoactive 3 偵測不到 REM 而懲罰使用者（已實測 Garmin 官方同樣顯示無 REM）
    rem_unavailable = (rem_pct is None or rem_pct == 0.0)

    component_scores = {
        "duration": score_duration(duration_h, band),
        "efficiency": score_efficiency(efficiency),
        "waso": score_waso(waso_min, band),
        "deep": score_deep(deep_pct),
        "rem": None if rem_unavailable else score_rem(rem_pct, band),
    }

    # 只計算「有資料」的指標，並把總分正規化回 100 分制
    # （等於把未測得指標的權重按比例分配給其他指標）
    available_weight = sum(WEIGHTS[k] for k, v in component_scores.items() if v is not None)
    earned = sum(v for v in component_scores.values() if v is not None)
    score = round(earned / available_weight * 100, 1) if available_weight > 0 else 0.0

    grade = grade_for(score)

    return {
        "date": row.get("date", ""),
        "score": score,
        "quality": grade,
        "age_band": band,
        # 各指標得分（None 代表該指標未測得、已排除計分）
        "duration_score": _round(component_scores["duration"]),
        "efficiency_score": _round(component_scores["efficiency"]),
        "waso_score": _round(component_scores["waso"]),
        "deep_score": _round(component_scores["deep"]),
        "rem_score": _round(component_scores["rem"]),
        "rem_measured": not rem_unavailable,
        "recommendation": build_recommendation(grade, component_scores, band, row),
    }


def _round(value):
    return None if value is None else round(value, 1)


def main():
    args = parse_args()

    with open(args.input, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))

    if not rows:
        raise SystemExit(f"{args.input} has no rows. Run extract_sleep_features.py first.")

    results = [evaluate_night(row) for row in rows]

    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    with open(args.output, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)

    # 統計分級分布，方便快速檢視結果是否合理
    distribution = {}
    for r in results:
        distribution[r["quality"]] = distribution.get(r["quality"], 0) + 1
    rem_missing = sum(1 for r in results if not r["rem_measured"])
    avg_score = round(sum(r["score"] for r in results) / len(results), 1)

    print("Sleep quality evaluation complete.")
    print(f"- Input: {args.input} ({len(rows)} nights)")
    print(f"- Output: {args.output} / {args.output_json}")
    print(f"- Mean score: {avg_score}")
    print(f"- Grade distribution: {distribution}")
    print(f"- Nights excluded from REM scoring (not measured): {rem_missing}")


if __name__ == "__main__":
    main()
