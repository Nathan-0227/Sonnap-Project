"""
behavior/challenges.py — 挑戰引擎（Tier A）

═══════════════════════════════════════════════════════════════════
這個模組在整個架構的哪裡
═══════════════════════════════════════════════════════════════════

    nightly_behavior（Tier A：手機產生的行為資料）
        ↓  只讀
    本模組：算出每個挑戰的進度
        ↓
    App 顯示進度條、寵物解鎖狀態

⚠️ **本模組只讀 nightly_behavior，永遠不讀 wearable_nightly。**
   這不是巧合，是紅線（PROJECT_STATUS.md 8.6）：
   挑戰的標的必須是**行為**（幾點放下手機），不能是**生理結果**
   （深睡幾分鐘）。使用者控制得了前者，控制不了後者——
   拿後者當挑戰目標等於懲罰使用者的生理。

⚠️ 同時這也是 8.7 那條紅線（遊戲化層不得回寫評分層）的結構保證：
   評分器根本不在本模組的呼叫路徑上。驗收指令見 behavior/__init__.py。

═══════════════════════════════════════════════════════════════════
三個挑戰的型別
═══════════════════════════════════════════════════════════════════

    time         今晚在目標就寢時間前放下手機          窗格 1 晚
    streak       連續 N 晚達成                          窗格 14 天
    consistency  最近 7 晚的就寢時間收斂在 ±30 分鐘內   窗格 7 天

定義（標題、門檻、文獻依據）存在 db.py 的 DEFAULT_CHALLENGES，
本模組只負責「算進度」。分開的理由是定義會在 D2 期間微調文案與難度，
而計算邏輯不該跟著動。

═══════════════════════════════════════════════════════════════════
⚠️ 進度是**每次即時重算**的，不是累加上去的
═══════════════════════════════════════════════════════════════════
事實來源永遠是 nightly_behavior。challenge_progress 那張表是快取，
存下來只為了記 completed_at（「你哪一天完成的」重算不出來）。

即時重算的好處是資料修正會自動反映——受測者事後補填某一晚，
進度會跟著更正，不會留下一個當初算錯、之後再也改不掉的數字。
"""

from datetime import date, timedelta

from .adherence import bedtime_spread_minutes

# ═══════════════════════════════════════════════════════════════════
# 常數
# ═══════════════════════════════════════════════════════════════════

# 一晚要「達成」的門檻：adherence_minutes <= 0，也就是**沒有晚於目標時間**。
#
# ⚠️ 這個 0 跟 adherence.py 的 LATE_THRESHOLD_MINUTES = 30 **是兩件事**，
#    不要混淆，也不要為了「統一」而把其中一個改掉：
#
#      is_late（門檻 30）  → 診斷用的標籤。「這一晚算不算有意義的拖延」，
#                            30 分鐘是容忍量，用來算熬夜比率。
#      挑戰達成（門檻 0）  → 目標。「你有沒有做到自己設的那件事」。
#
#    所以中間有一個灰帶（遲 0–30 分鐘）：不算熬夜，但挑戰沒達成。
#    這是對的——標籤要寬容（免得把正常波動說成拖延），目標要精確
#    （免得「達成」變得沒有意義）。
ACHIEVED_MAX_ADHERENCE_MINUTES = 0.0


def _min_nights_for_window(window_days):
    """
    consistency 這類「看一段期間」的挑戰，窗格內至少要有幾晚資料才算數。

    ⚠️ **這個下限是必要的，少了它就會直接違反紅線 5**
       （獎勵必須與品質耦合，不能只與「有資料」耦合）。

       想像窗格內只有 2 晚有記錄，而它們剛好差 10 分鐘 →
       離散度 5 分鐘，遠低於 30 → 挑戰達成。
       但那個人其實 7 晚裡有 5 晚沒記錄，我們根本不知道他規不規律。
       **「資料很少」被獎勵成了「作息很穩」**，正是要防的事。

    取「窗格的過半數」而不是寫死一個數字，是為了讓它跟著 window_days 縮放——
    日後加一個 14 天的挑戰時不必再訂一個新常數。

    ⚠️ 這是**產品決定，不是文獻門檻**。之所以可以這樣訂，是因為它
       **不進任何分數**——同 LATE_THRESHOLD_MINUTES 的處理。
       但它會被一起回報（recorded_nights），讓看的人自己判斷樣本夠不夠。
    """
    return window_days // 2 + 1


# ═══════════════════════════════════════════════════════════════════
# 單晚判定
# ═══════════════════════════════════════════════════════════════════

def night_achieved(row):
    """
    這一晚算不算「達成」。回傳 True / False / **None（沒測到）**。

    ⚠️ 三態而不是兩態，是本專案一貫的堅持：「沒測到」與「沒達成」
       是完全不同的兩件事，混在一起就再也分不開了。
       手機關機的那一晚不該被當成失敗，也不該被當成成功。

    達成的定義刻意跟 challenge 定義裡的 target_value 無關——
    time 與 streak 兩種挑戰共用這一個判準，只有一個定義處。
    """
    minutes = row.get("adherence_minutes")
    if minutes is None:
        return None
    return minutes <= ACHIEVED_MAX_ADHERENCE_MINUTES


# ═══════════════════════════════════════════════════════════════════
# 窗格
# ═══════════════════════════════════════════════════════════════════

def _as_date(value):
    """把 "2026-08-26" 或 date 轉成 date；空值回 None。"""
    if value is None:
        return None
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value)[:10])


def window_rows(rows, window_days, as_of=None):
    """
    取出窗格內的資料列。回傳 (窗格內的列, as_of)。

    ⚠️ 窗格是用**日曆日**界定的，不是「最後 N 筆」。
       這個區別很重要：如果只取最後 N 筆，一個三個月沒用 App 的人
       重新打開時，會拿到橫跨三個月的 7 筆資料，然後被當成
       「最近 7 晚」來算收斂度——那個數字毫無意義。

    as_of 預設是**最新一筆有記錄的日期**，不是今天。
    這是一個顯示上的取捨，講清楚比較好：
      - 用「最新記錄日」→ 三天沒開 App 的人，連續紀錄會停在原地不動
      - 用「今天」      → 同一個人的連續紀錄會歸零

    選前者的理由是 App 可能延遲上傳（早上 10 點打開時昨晚的資料
    還沒送上來），用今天當基準會讓同一個人在上午看到「中斷了」、
    下午又看到「還在」。呼叫端要嚴格的話可以自己傳 as_of=今天。
    **一併回傳 as_of，讓 UI 有辦法標示「截至某日」。**
    """
    dated = [(d, r) for r in rows if (d := _as_date(r.get("date"))) is not None]
    if not dated:
        return [], None

    dated.sort(key=lambda pair: pair[0])
    anchor = _as_date(as_of) or dated[-1][0]

    # 含 anchor 當天往回數 window_days 天。window_days=1 → 只有 anchor 當天。
    start = anchor - timedelta(days=window_days - 1)
    return [r for d, r in dated if start <= d <= anchor], anchor


def current_streak(rows, as_of=None):
    """
    到 as_of 為止連續達成的夜數。回傳 (連續夜數, as_of)。

    ⚠️ **必須沿日曆日往回走，不能只走 rows 的順序。** 這是這個函式
       唯一容易寫錯的地方，而且錯了不會報錯：

           rows 裡只有「有記錄的夜晚」。直接走清單的話，
           08-10 達成、08-11 沒資料、08-12 達成
           會被算成「連續 2 晚」——但中間那晚根本沒發生過。

       沿日曆日走的話，08-11 查不到資料就停下來，得到正確的 1 晚。

    ⚠️ **缺資料的夜晚會中斷連續紀錄**，這是刻意的，理由同樣是紅線 5：
       若把缺資料當成「跳過不算」，那麼只在自己表現好的日子開 App 的人
       就能靠「選擇性記錄」累積連續紀錄——獎勵就變成跟「有沒有資料」
       耦合，而不是跟行為耦合。當成「達成」更糟，那是憑空捏造。
    """
    by_date = {}
    for r in rows:
        d = _as_date(r.get("date"))
        if d is not None:
            by_date[d] = r

    if not by_date:
        return 0, None

    anchor = _as_date(as_of) or max(by_date)

    streak = 0
    cursor = anchor
    while True:
        row = by_date.get(cursor)
        if row is None:                  # 缺資料 → 中斷
            break
        if night_achieved(row) is not True:   # 沒達成、或沒測到 → 中斷
            break
        streak += 1
        cursor -= timedelta(days=1)

    return streak, anchor


# ═══════════════════════════════════════════════════════════════════
# 各型別的進度計算
# ═══════════════════════════════════════════════════════════════════
#
# 三個函式的回傳格式一致，讓 evaluate_challenge() 可以無差別組裝：
#     (current_value, achieved_days, recorded_nights, completed, detail)
#
# current_value 的**單位每種挑戰都不一樣**（分鐘 / 夜數 / 分鐘），
# 所以一定要搭配 detail 那句人看得懂的說明一起顯示，
# 不要讓 UI 自己猜這個數字是什麼意思。

def _progress_time(rows, challenge, as_of):
    """
    time：今晚（窗格內最新一晚）有沒有在目標時間前放下手機。

    current_value 回的是 **adherence_minutes 本身**（正值＝遲了幾分鐘），
    不是 0/1。理由：進度條顯示「達成 / 未達成」就夠了，但使用者真正
    想知道的是「差多少」——「遲了 12 分鐘」遠比「未達成」有用，
    而且它指向一個具體可改的行為。
    """
    scoped, _ = window_rows(rows, challenge["window_days"], as_of)
    measured = [r for r in scoped if night_achieved(r) is not None]

    if not measured:
        return None, 0, 0, False, "今晚還沒有記錄。"

    latest = measured[-1]
    minutes = latest["adherence_minutes"]
    achieved = night_achieved(latest)

    if achieved:
        detail = (
            f"提早 {abs(minutes):.0f} 分鐘放下手機。"
            if minutes < 0 else "正好在目標時間放下手機。"
        )
    else:
        detail = f"比目標時間晚了 {minutes:.0f} 分鐘。"

    return minutes, (1 if achieved else 0), len(measured), bool(achieved), detail


def _progress_streak(rows, challenge, as_of):
    """
    streak：連續達成幾晚。

    ⚠️ 連續紀錄**不受 window_days 限制**——一個連續 20 晚的人不該因為
       挑戰定義寫 14 天就被截斷成 14。window_days 在這裡只用來界定
       recorded_nights（分母），讓 UI 能說「最近 14 天裡有 9 晚有記錄」。
    """
    streak, _ = current_streak(rows, as_of)
    scoped, _ = window_rows(rows, challenge["window_days"], as_of)
    measured = [r for r in scoped if night_achieved(r) is not None]

    # ⚠️ 窗格內**完全沒有記錄**時要回 None（insufficient_data），不是 0。
    #    「連續 0 晚」與「我們沒有你的資料」是兩件不同的事：
    #    前者代表你昨晚沒達成（可以今晚重新開始），
    #    後者代表 App 還沒收到任何東西。兩者給使用者的訊息完全不同，
    #    而且回 0 會讓進度條顯示 0%，看起來像「你表現很差」。
    if not measured:
        return None, 0, 0, False, "還沒有任何記錄，今晚開始就能累積。"

    target = challenge["target_value"]
    completed = streak >= target

    if streak == 0:
        detail = "目前沒有連續紀錄，今晚就可以重新開始。"
    elif completed:
        detail = f"已連續 {streak} 晚達成。"
    else:
        detail = f"已連續 {streak} 晚，再 {int(target - streak)} 晚就完成。"

    return float(streak), streak, len(measured), completed, detail


def _progress_consistency(rows, challenge, as_of):
    """
    consistency：最近幾晚的就寢時間有多收斂。

    ⚠️ **這一項的方向是相反的：數字越小越好。** current_value 是離散度
       （分鐘），target_value 是允許的上限。UI 畫進度條時要注意這件事，
       所以 evaluate_challenge() 會另外回一個 lower_is_better 旗標。

    ⚠️ 這是對 PROJECT_STATUS.md 8.6 的必要修正。8.6 寫「挑戰標的用 SRI」，
       但那是在「單使用者、有手錶」的前提下寫的——**SRI 需要 Garmin 的
       睡眠時間軸，而 D2 的受測者沒有錶**。改用 lights_out_at 的收斂程度：
       同一個構念（作息規律性）、同樣是**個人內比較**，因此同樣繞開
       6.5 的顧慮（不同計算方法算出的 SRI 不能對照外部常模）；
       但資料來源換成每個人都有的手機。
    """
    scoped, _ = window_rows(rows, challenge["window_days"], as_of)
    spread, n = bedtime_spread_minutes(scoped)

    need = _min_nights_for_window(challenge["window_days"])
    if spread is None or n < need:
        return None, 0, n, False, (
            f"最近 {challenge['window_days']} 晚只有 {n} 晚有記錄，"
            f"至少要 {need} 晚才算得出收斂程度。"
        )

    target = challenge["target_value"]
    completed = spread <= target

    if completed:
        detail = f"最近 {n} 晚的就寢時間都落在平均的 ±{spread:.0f} 分鐘內。"
    else:
        detail = (
            f"最近 {n} 晚的就寢時間最多偏離平均 {spread:.0f} 分鐘，"
            f"目標是 {target:.0f} 分鐘內。"
        )

    return spread, n, n, completed, detail


# 型別 → 計算函式。用查表而不是 if/elif 串，是為了讓「新增一種挑戰型別」
# 變成「加一列」而不是「改一段控制流程」。
PROGRESS_FUNCS = {
    "time": _progress_time,
    "streak": _progress_streak,
    "consistency": _progress_consistency,
}

# 哪些型別是「數字越小越好」。UI 畫進度條要用。
LOWER_IS_BETTER = {"consistency"}


# ═══════════════════════════════════════════════════════════════════
# 對外主函式
# ═══════════════════════════════════════════════════════════════════

def _progress_ratio(kind, current_value, target_value, completed):
    """
    給 UI 進度條用的 0–1 數值。**算不出來時回 None，不回 0。**

    ⚠️ 回 None 而不是 0 是重要的：0 的意思是「完全沒進展」，
       None 的意思是「還不知道」。前者會讓沒資料的使用者看到一條空進度條，
       誤以為自己表現很差——而事實是我們根本沒測到。

    三種型別的換算方式不同，各自的理由：

      time         二元。要嘛在目標前放下手機、要嘛沒有，沒有中間值。
      streak       連續夜數 ÷ 目標夜數，最高 1.0。線性、直觀。
      consistency  目標 ÷ 實際離散度，最高 1.0。**用比值而不是線性遞減**，
                   因為線性遞減需要再訂一個「幾分鐘算 0%」的常數，
                   而比值不用：離散 30 分鐘（達標）→ 1.0、60 分鐘 → 0.5、
                   120 分鐘 → 0.25。永遠不會歸零也是刻意的——
                   作息再亂的人也看得到自己有在往目標靠近。
    """
    if current_value is None:
        return None
    if kind == "time":
        return 1.0 if completed else 0.0
    if kind == "streak":
        if target_value <= 0:
            return None
        return round(min(current_value / target_value, 1.0), 3)
    if kind == "consistency":
        if current_value <= 0:
            return 1.0            # 離散度 0（只可能是所有夜晚同一時刻）
        return round(min(target_value / current_value, 1.0), 3)
    return None


def evaluate_challenge(challenge, rows, as_of=None):
    """
    算出單一挑戰的進度。

    challenge 是 db.get_challenges() 回的其中一列；
    rows 是 db.get_nightly_behavior() 回的行為資料（由舊到新）。

    回傳的 dict 直接就是 API 要吐給 App 的格式。
    """
    kind = challenge["kind"]
    func = PROGRESS_FUNCS.get(kind)
    if func is None:
        # 未知型別不要靜靜地回 0——那會讓「有人加了新型別卻忘了寫計算函式」
        # 看起來跟「這個人還沒開始做」一模一樣。
        raise ValueError(
            f"未知的挑戰型別 {kind!r}（challenge_id={challenge['challenge_id']}）。"
            f"支援的型別：{sorted(PROGRESS_FUNCS)}"
        )

    current, achieved_days, recorded, completed, detail = func(rows, challenge, as_of)

    # 三種狀態要分清楚，尤其是 insufficient_data——它不是「失敗」。
    if current is None:
        status = "insufficient_data"
    elif completed:
        status = "completed"
    else:
        status = "in_progress"

    return {
        "challenge_id": challenge["challenge_id"],
        "kind": kind,
        "title": challenge["title"],
        "description": challenge["description"],
        "target_value": challenge["target_value"],
        "window_days": challenge["window_days"],
        "literature_ref": challenge.get("literature_ref"),
        # ── 進度 ──
        "current_value": current,
        "achieved_days": achieved_days,
        # ⚠️ recorded_nights 一定要一起回。它是分母——沒有它的話
        #    「達成 3 晚」看不出是 3/3 還是 3/14。
        "recorded_nights": recorded,
        "progress": _progress_ratio(
            kind, current, challenge["target_value"], completed
        ),
        "lower_is_better": kind in LOWER_IS_BETTER,
        "completed": completed,
        "status": status,
        "detail": detail,
    }


def evaluate_all(challenges, rows, as_of=None):
    """
    算出所有挑戰的進度，順序照 challenges 傳進來的順序
    （db.get_challenges() 已按 window_days 由近到遠排好）。
    """
    return [evaluate_challenge(c, rows, as_of) for c in challenges]
