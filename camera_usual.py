"""
camera_usual.py — 攝影機動作率的「跟你平常比」（呈現用，不進任何分數）。

這裡算的是一句可驗證的事實：今晚的 events_per_hour 跟**你自己**最近幾晚的
中位數差多少。它**不主張動得多是好還是壞**。

═══════════════════════════════════════════════════════════════════
為什麼只能做到這樣（不要把它改成計分）
═══════════════════════════════════════════════════════════════════
1. **Montini 2024 給的是常模不是切點。** 它說健康成人每小時約動 11 次
   （IQR 8–15），但**沒有**說「動得多睡得比較差」。拿它當扣分門檻等於
   自己補上一句文獻沒有授權的話（紅線 2）。
2. **我們自己的資料也不支持那句話。** F 節第 3 關（2026-11-09，n=31）：
   事件率 vs 同一晚 Garmin 的 WASO（Pearson −0.197／Spearman +0.050）、
   awake_count（+0.154／+0.200）、final_score（−0.181／−0.235）——全部
   接近零，WASO 兩種算法連正負號都相反。只數大振幅事件（峰值 ≥10／20／40%）
   四個切點也一樣沒有相關，所以不能用「我們量不準」解釋。
3. **個人內比較不需要常模**，所以這一支不欠文獻債；但它也因此只能描述，
   不能評價——一旦變成加分或扣分，就必須假設一個方向，而方向沒有驗出來。

→ 詳見 Research-Background/攝影機分數.md A 節與 F 節。

═══════════════════════════════════════════════════════════════════
🔴 基線只取「同一把尺」量出來的夜晚
═══════════════════════════════════════════════════════════════════
`motion_threshold_basis` 是 'roi'（分母＝床鋪範圍）或 'frame'（分母＝整個畫面）。
同一個 0.75% 在兩種分母下差一個數量級，而**數字看起來都很正常**。
實例：09-01、09-03 錄於 ROI 之前，basis='frame'。
→ 基線要求 basis 與 roi **都**相同，不同的一律不取。
   tests/test_tapo_roi_csv.py 守的是同一件事（換分母不會拋例外也不會有空值）。

═══════════════════════════════════════════════════════════════════
⚠️ 兩個常數沒有文獻依據，是設計決策
═══════════════════════════════════════════════════════════════════
BASELINE_MIN_NIGHTS = 5   32 晚實測覆蓋 84%。不用手錶那邊的
                          MIN_BASELINE_NIGHTS = 14——攝影機夜晚稀疏
                          （32 晚分布在 63 天、最大空檔 18 天），14 晚只剩 12%。
SAME_AS_USUAL_PCT = 25    事件率跨夜不穩 3.1 倍且原因未知（已排除錄影長度
                          r=+0.049、照明否決率只有 0.1–0.6% 的幀、攝影機位置），
                          所以小幅偏離很可能是雜訊，門檻以內一律講「差不多」。

⚠️ 這兩個數字一改，驗收數字就會變，`tests/test_camera_usual.py` 會紅。
"""

BASELINE_WINDOW_DAYS = 28          # 沿用 apply_recovery_modifier.MAX_BASELINE_DAYS 的約定
BASELINE_MIN_NIGHTS = 5
SAME_AS_USUAL_PCT = 25.0

# ⚠️ 這幾句話會原封不動顯示在手機上，**只在這裡定義**。
#    Dart 端照抄（app/test/camera_card_test.dart 用哨兵字串守著）——
#    在 Dart 重寫一份的話，兩邊漂移不會有任何錯誤訊息。
SAME_AS_USUAL = "About the same as usual"
BASIS = "within_person__median_of_recent_nights"

NOTE = (
    "Movement is compared with your own recent nights, not with other people. "
    "It never enters any score, and more movement is NOT read as worse sleep: "
    "the reference study reports a norm, not a cut-point, and in 31 nights of our "
    "own data the event rate did not track the watch's wake measures. "
    "Night-to-night spread is wide (3.1x) and not yet explained, so small "
    "differences are reported as 'about the same'."
)


def _label(delta_pct):
    """把偏離百分比變成那句話。門檻以內一律講「差不多」。"""
    if abs(delta_pct) < SAME_AS_USUAL_PCT:
        return SAME_AS_USUAL
    word = "more" if delta_pct > 0 else "less"
    return f"{abs(delta_pct):.0f}% {word} movement than usual"


def _needs_label(short_by):
    night = "night" if short_by == 1 else "nights"
    return f"Needs {short_by} more recorded {night} to compare with your usual"


def _median(values):
    s = sorted(values)
    n = len(s)
    if not n:
        return None
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2


def _same_ruler(night, other):
    """同一把尺量的嗎？分母（basis）與框（roi）都要一樣。"""
    return (other.get("motion_threshold_basis") == night.get("motion_threshold_basis")
            and other.get("roi") == night.get("roi"))


def _days_between(a, b):
    """a、b 是 'YYYY-MM-DD'。回傳相差幾天（a 較新時為正）。"""
    from datetime import date
    ya, ma, da = (int(x) for x in a.split("-"))
    yb, mb, db_ = (int(x) for x in b.split("-"))
    return (date(ya, ma, da) - date(yb, mb, db_)).days


def compare_to_usual(night, history):
    """
    這一晚的動作率跟「自己平常」差多少。

    night    ：這一晚的 camera_nightly 列（dict）
    history  ：**這一晚之前**的 camera_nightly 列（dict 的 list，順序不拘）

    回傳 dict，或 None（這一晚本身沒有 events_per_hour，沒得比）。

    ⚠️ 回傳的 label 一定有值——基線不足時是「還需要幾晚」，不是 None、
       也不是 0%。給 0% 會被讀成「跟平常一模一樣」，那是假話。
    """
    rate = night.get("events_per_hour")
    if rate is None:
        return None

    usable = [
        h["events_per_hour"] for h in history
        if h.get("events_per_hour") is not None
        and h.get("date") and night.get("date")
        and 0 < _days_between(night["date"], h["date"]) <= BASELINE_WINDOW_DAYS
        and _same_ruler(night, h)
    ]

    out = {
        "events_per_hour": rate,
        "baseline_nights": len(usable),
        "baseline_window_days": BASELINE_WINDOW_DAYS,
        "basis": BASIS,
    }
    if len(usable) < BASELINE_MIN_NIGHTS:
        out.update({
            "usual_events_per_hour": None,
            "delta_pct": None,
            "label": _needs_label(BASELINE_MIN_NIGHTS - len(usable)),
        })
        return out

    usual = _median(usable)
    delta = 100.0 * (rate - usual) / usual if usual else 0.0
    out.update({
        "usual_events_per_hour": round(usual, 1),
        "delta_pct": round(delta, 1),
        "label": _label(delta),
    })
    return out


def annotate(rows):
    """
    一次算完一串夜晚（由舊到新）。每一列掛上 'usual' 欄位。

    ⚠️ 呼叫端要**多給一段歷史**：基線看的是這一晚之前的夜晚，只給要顯示的
       那幾晚的話，最舊的幾晚會誤報「還需要幾晚」。見 main.py 那裡的註解。
    """
    for i, r in enumerate(rows):
        r["usual"] = compare_to_usual(r, rows[:i])
    return rows
