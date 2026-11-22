"""
game/badges.py —— 徽章：13 個系列、每個系列 5 級。純函式。

2026-11-22 使用者 grill 後定（獎勵頁「獎盃架」）。

═══════════════════════════════════════════════════════════════════
規則
═══════════════════════════════════════════════════════════════════

- 每個系列數一種「做到了」的次數，跨過門檻就拿到那一級。
- **「做到了」一律照用既有的判定，這裡不另訂**：
    準時放下手機   behavior.challenges.night_achieved
    連續準時       behavior.challenges.current_streak
    上床少滑手機   phone_in_bed 那個挑戰本身（evaluate_challenge，門檻是挑戰定義裡的）
    作息收斂       consistency 那個挑戰本身（同上）
    準時起床       behavior/wake.py 併進來的 up_on_time
    熬夜           POST /nightly 存的 is_late（跨午夜只在 behavior/adherence.py 算）
  在這裡另寫一份判準，就是第二個定義處。
- 拿到的那一級**永遠留著**（db.badges_earned），日期是**跨過門檻那一晚**，不是寫入那天。
  資料改正（例如 11-16 那種就寢時刻被後端改正）之後，即時算的次數可能變少，
  但已經記下的那一級不收回。
- 每一級給 XP（TIER_XP），透過 POST /game/claim 領，同挑戰獎勵——拿徽章與拿 XP 是同一刻。
  achievement_id 是 `badge:<系列>:<級>`，每一級只能領一次。

⚠️ 門檻（5、15、30、60…）與 XP 都是**設計決策、沒有文獻**。它們只決定什麼時候給徽章，
   不進分數、不改心情（紅線 4），所以不受紅線 2 約束——但不要把它們寫成有出處。

⚠️ 紅線 5：睡眠那幾個系列，只有**做到了**的晚上會前進；差的晚上、沒資料的晚上都不算。
   「有資料就給」的系列（戴錶天數、按按鈕次數、填自評）刻意沒有（使用者 11-22 同意）。

🔴 三個使用者知情的例外（11-22 grill Q19、Q21、Q22）：
   Good friend（拜訪）、Habits（自己勾、沒有證據）、Assistant（每問一次花一次 API 額度）
   跟睡得好不好無關，但使用者決定照樣給徽章與 XP。灌得到的有上限：最多 5 級、150 XP。
   Assistant 數的是**天數**不是題數，一天問十題也只算一天。
"""
from datetime import date as date_cls, timedelta

from behavior.challenges import current_streak, evaluate_challenge, night_achieved

# 每一級給多少 XP（第 1 級 → 第 5 級）。一個系列全拿 150。
TIER_XP = (10, 20, 30, 40, 50)

GROUPS = (
    ("sleep", "Sleep"),
    ("friends", "Friends"),
    ("habits", "Habits & buddy"),
)

# 順序就是架子上的順序。thresholds 一定是 5 個、由小到大。
# unit 只用來寫進度（"12 / 15 nights"）。
SERIES = (
    {"series_id": "lights_out", "group": "sleep", "title": "Lights out",
     "how": "Put your phone down by your target bedtime.",
     "unit": "nights", "thresholds": (1, 5, 15, 30, 60)},
    {"series_id": "on_a_roll", "group": "sleep", "title": "On a roll",
     "how": "Put your phone down on time several nights in a row.",
     "unit": "nights in a row", "thresholds": (3, 7, 14, 21, 30)},
    {"series_id": "good_night", "group": "sleep", "title": "Good night",
     "how": "Your watch rates a night as Good.",
     "unit": "nights", "thresholds": (1, 5, 15, 30, 60)},
    {"series_id": "early_bird", "group": "sleep", "title": "Early bird",
     "how": "Get up within an hour of your wake time.",
     "unit": "mornings", "thresholds": (1, 5, 15, 30, 60)},
    {"series_id": "phone_down", "group": "sleep", "title": "Phone down",
     "how": "After you tap Start Sleep, keep phone use within the target.",
     "unit": "nights", "thresholds": (1, 5, 15, 30, 60)},
    {"series_id": "steady_week", "group": "sleep", "title": "Steady week",
     "how": "Keep your bedtimes close together for a whole week.",
     "unit": "weeks", "thresholds": (1, 2, 4, 8, 12)},
    {"series_id": "traveller", "group": "sleep", "title": "Traveller",
     "how": "Move forward one stop on a Journey.",
     "unit": "stops", "thresholds": (1, 3, 6, 10, 15)},
    {"series_id": "full_circle", "group": "sleep", "title": "Full circle",
     "how": "On the same night, put your phone down on time and get up on time.",
     "unit": "nights", "thresholds": (1, 5, 15, 30, 60)},
    {"series_id": "bounce_back", "group": "sleep", "title": "Bounce back",
     "how": "After a late night, be on time the very next night.",
     "unit": "times", "thresholds": (1, 3, 6, 10, 15)},
    {"series_id": "good_friend", "group": "friends", "title": "Good friend",
     "how": "Visit a friend in town.",
     "unit": "visits", "thresholds": (1, 10, 30, 60, 100)},
    {"series_id": "podium", "group": "friends", "title": "Podium",
     "how": "Finish a week in the top 3 for On time, Streak or Steady "
            "(the board needs at least 3 people).",
     "unit": "weeks", "thresholds": (1, 3, 6, 10, 15)},
    {"series_id": "habits", "group": "habits", "title": "Habits",
     "how": "Tick every habit in your plan for the day.",
     "unit": "days", "thresholds": (1, 5, 15, 30, 60)},
    {"series_id": "assistant", "group": "habits", "title": "Ask your buddy",
     "how": "Ask your sleep assistant a question.",
     "unit": "days", "thresholds": (1, 5, 15, 30, 60)},
)
SERIES_BY_ID = {s["series_id"]: s for s in SERIES}

# Podium 只看這三個排行榜（跟睡眠作息有關的）；那張榜至少要有幾個人上榜才算。
PODIUM_METRICS = ("on_time", "streak", "steady")
PODIUM_MIN_PEOPLE = 3
PODIUM_TOP = 3


def achievement_id(series_id, tier):
    return f"badge:{series_id}:{int(tier)}"


def _d(value):
    return str(value)[:10] if value else None


# ═══════════════════════════════════════════════════════════════════
# 每個系列：「做到了」的日期清單（由舊到新，可重複）
# ═══════════════════════════════════════════════════════════════════
#
# 每個函式回傳 hits：第 k 次做到的那一天是 hits[k-1]。
# 第 t 級的門檻是 n → 第 n 次做到的那一天就是拿到的日期。
# On a roll 例外：它數的是「最長連續」，回傳的是「連續長度第一次到 n 的那一晚」，
# 所以另外處理（_streak_reached）。

def _behavior_sorted(rows):
    return sorted((r for r in rows or [] if r.get("date")), key=lambda r: str(r["date"]))


def hits_lights_out(behavior_rows):
    return [_d(r["date"]) for r in _behavior_sorted(behavior_rows) if night_achieved(r) is True]


def streak_reached(behavior_rows):
    """
    {連續長度 n: 第一次連續到 n 的那一晚}。
    連續的定義照用 current_streak（沿日曆日走、缺資料就中斷）。
    """
    rows = _behavior_sorted(behavior_rows)
    reached = {}
    for r in rows:
        if night_achieved(r) is not True:
            continue
        n, _ = current_streak(rows, as_of=_d(r["date"]))
        for k in range(1, n + 1):
            reached.setdefault(k, _d(r["date"]))
    return reached


def hits_good_night(wearable_rows):
    return sorted(_d(w["date"]) for w in wearable_rows or []
                  if w.get("date") and w.get("final_quality") == "Good")


def hits_early_bird(behavior_rows):
    return [_d(r["date"]) for r in _behavior_sorted(behavior_rows) if r.get("up_on_time") is True]


def hits_phone_down(behavior_rows, challenge_def):
    """照用 phone_in_bed 挑戰本身判每一晚（門檻在挑戰定義裡，不在這裡）。"""
    if not challenge_def:
        return []
    rows = _behavior_sorted(behavior_rows)
    out = []
    for r in rows:
        if r.get("phone_in_bed_minutes") is None:
            continue
        res = evaluate_challenge(challenge_def, rows, as_of=_d(r["date"]))
        if res.get("status") == "completed":
            out.append(_d(r["date"]))
    return out


def hits_steady_week(behavior_rows, challenge_def, today):
    """
    照用 consistency 挑戰本身判每一週。週＝不重疊的 window_days 天窗格
    （同 game/rewards.claim_period 的切法），只判已經結束的窗格，日期記在窗格最後一天。
    """
    if not challenge_def:
        return []
    rows = _behavior_sorted(behavior_rows)
    if not rows:
        return []
    span = max(1, int(challenge_def["window_days"]))
    first = date_cls.fromisoformat(_d(rows[0]["date"]))
    last_day = date_cls.fromisoformat(str(today)[:10]) - timedelta(days=1)
    out = []
    period = first.toordinal() // span
    while True:
        end = date_cls.fromordinal((period + 1) * span - 1)
        if end > last_day:
            break
        res = evaluate_challenge(challenge_def, rows, as_of=end.isoformat())
        if res.get("status") == "completed":
            out.append(end.isoformat())
        period += 1
    return out


def hits_full_circle(behavior_rows):
    return [_d(r["date"]) for r in _behavior_sorted(behavior_rows)
            if night_achieved(r) is True and r.get("up_on_time") is True]


def hits_bounce_back(behavior_rows):
    """前一個日曆晚上熬夜（is_late 為真），這一晚就準時。前一晚沒資料不算。"""
    rows = _behavior_sorted(behavior_rows)
    by_date = {_d(r["date"]): r for r in rows}
    out = []
    for r in rows:
        if night_achieved(r) is not True:
            continue
        prev = (date_cls.fromisoformat(_d(r["date"])) - timedelta(days=1)).isoformat()
        p = by_date.get(prev)
        if p is not None and p.get("is_late") is not None and bool(p.get("is_late")):
            out.append(_d(r["date"]))
    return out


def hits_from_counts(activity_rows):
    """game_activity 每天的次數 → 每一次各一個日期（拜訪、Journey 站數）。"""
    out = []
    for a in sorted(activity_rows or [], key=lambda a: str(a["date"])):
        out.extend([_d(a["date"])] * max(0, int(a.get("count") or 0)))
    return out


def hits_days(activity_rows):
    """有做的天數（助理：一天問十題也只算一天；Podium：那週有進前三）。"""
    return sorted(_d(a["date"]) for a in activity_rows or [] if int(a.get("count") or 0) > 0)


def hits_habits(habit_rows):
    return sorted(_d(h["date"]) for h in habit_rows or []
                  if int(h.get("total") or 0) > 0 and int(h.get("checked") or 0) >= int(h["total"]))


# ═══════════════════════════════════════════════════════════════════
# 組起來
# ═══════════════════════════════════════════════════════════════════

def compute(ctx):
    """
    ctx：{
      behavior: _behavior_rows_with_wake() 的輸出, wearable: [...],
      challenges: {kind: 挑戰定義}, today: 'YYYY-MM-DD',
      visits / assistant / journey / podium: game_activity 的列, habits: habit_days 的列,
    }
    → {series_id: {"value": 現在的次數, "reached": {門檻: 那一天}}}
    """
    b = ctx.get("behavior") or []
    defs = ctx.get("challenges") or {}
    hits = {
        "lights_out": hits_lights_out(b),
        "good_night": hits_good_night(ctx.get("wearable")),
        "early_bird": hits_early_bird(b),
        "phone_down": hits_phone_down(b, defs.get("phone_in_bed")),
        "steady_week": hits_steady_week(b, defs.get("consistency"), ctx.get("today")),
        "traveller": hits_from_counts(ctx.get("journey")),
        "full_circle": hits_full_circle(b),
        "bounce_back": hits_bounce_back(b),
        "good_friend": hits_from_counts(ctx.get("visits")),
        "podium": hits_days(ctx.get("podium")),
        "habits": hits_habits(ctx.get("habits")),
        "assistant": hits_days(ctx.get("assistant")),
    }
    out = {}
    for s in SERIES:
        sid = s["series_id"]
        if sid == "on_a_roll":
            reached_all = streak_reached(b)
            value = max(reached_all) if reached_all else 0
            reached = {n: reached_all[n] for n in s["thresholds"] if n in reached_all}
        else:
            h = hits[sid]
            value = len(h)
            reached = {n: h[n - 1] for n in s["thresholds"] if n <= len(h)}
        out[sid] = {"value": value, "reached": reached}
    return out


def newly_earned(computed, stored_rows):
    """這次算出來達成、但還沒記下來的那幾級 → 要寫進 badges_earned 的列。"""
    have = {(r["series_id"], int(r["tier"])) for r in stored_rows or []}
    rows = []
    for s in SERIES:
        c = computed.get(s["series_id"]) or {"reached": {}}
        for tier, n in enumerate(s["thresholds"], start=1):
            when = c["reached"].get(n)
            if when and (s["series_id"], tier) not in have:
                rows.append({"series_id": s["series_id"], "tier": tier, "earned_on": when})
    return rows


def view(computed, stored_rows, claimed_ids):
    """
    畫面要的樣子：每個系列的 5 級、拿到了沒、哪一晚、領過 XP 沒、下一級的進度。

    「拿到了沒」以**記下來的**為準（永遠留著），再加上這次剛算出來、還沒寫進去的。
    """
    stored = {(r["series_id"], int(r["tier"])): _d(r["earned_on"]) for r in stored_rows or []}
    for r in newly_earned(computed, stored_rows):
        stored[(r["series_id"], r["tier"])] = r["earned_on"]
    claimed = set(claimed_ids or ())
    series = []
    for s in SERIES:
        sid = s["series_id"]
        value = (computed.get(sid) or {}).get("value", 0)
        tiers = []
        for tier, n in enumerate(s["thresholds"], start=1):
            when = stored.get((sid, tier))
            tiers.append({
                "tier": tier,
                "threshold": n,
                "earned": when is not None,
                "earned_on": when,
                "xp": TIER_XP[tier - 1],
                "claimed": achievement_id(sid, tier) in claimed,
            })
        level = max([t["tier"] for t in tiers if t["earned"]], default=0)
        nxt = next((t for t in tiers if not t["earned"]), None)
        series.append({
            "series_id": sid,
            "group": s["group"],
            "title": s["title"],
            "how": s["how"],
            "unit": s["unit"],
            "level": level,
            "max_level": len(s["thresholds"]),
            "value": value,
            # 下一級還差多少：照實寫現在的次數，不夾到門檻（已經記下的級數可能比現在的次數高）
            "next": None if nxt is None else {"tier": nxt["tier"], "threshold": nxt["threshold"],
                                              "value": min(value, nxt["threshold"])},
            "tiers": tiers,
        })
    return series


def claimable(series_view):
    """拿到了、還沒領 XP 的那幾級。"""
    out = []
    for s in series_view:
        for t in s["tiers"]:
            if t["earned"] and not t["claimed"]:
                out.append({
                    "series_id": s["series_id"],
                    "tier": t["tier"],
                    "title": f"{s['title']} · level {t['tier']}",
                    "achievement_id": achievement_id(s["series_id"], t["tier"]),
                    "xp": t["xp"],
                })
    return out


def legacy_badges(series_view):
    """
    舊版 App 讀的三個徽章（`badges`），改由新系列推出來，不再自己判一次：
      first_on_time = Lights out 第 1 級；on_time_x5 = Lights out 第 2 級；good_sleep = Good night 第 1 級。
    """
    by_id = {s["series_id"]: s for s in series_view}

    def earned(sid, tier):
        s = by_id.get(sid)
        return bool(s and s["tiers"][tier - 1]["earned"])

    return [
        {"badge_id": "first_on_time", "title": "First on-time night",
         "description": "Put your phone down before your target bedtime.",
         "earned": earned("lights_out", 1)},
        {"badge_id": "on_time_x5", "title": "Five on-time nights",
         "description": "Five nights on time, not necessarily in a row.",
         "earned": earned("lights_out", 2)},
        {"badge_id": "good_sleep", "title": "A good night",
         "description": "Your watch rated a night as Good.",
         "earned": earned("good_night", 1)},
    ]


# ═══════════════════════════════════════════════════════════════════
# Podium：某個週日的 7 天榜
# ═══════════════════════════════════════════════════════════════════

def sundays_between(first, last):
    """first 之後（含）到 last（含）的每個週日，ISO 字串。"""
    if not first or not last:
        return []
    d = date_cls.fromisoformat(str(first)[:10])
    end = date_cls.fromisoformat(str(last)[:10])
    d += timedelta(days=(6 - d.weekday()) % 7)
    out = []
    while d <= end:
        out.append(d.isoformat())
        d += timedelta(days=7)
    return out


def on_podium(people, me_key, sunday):
    """
    那個週日結束時，我有沒有在任何一張（準時／連續／作息）7 天榜的前三名。
    people：[{"key", "shares_by": {metric: 有沒有公開那一項}, "behavior": [...]}]。
    名次照用 social.leaderboard.rank()（同排行榜：沒公開的不上榜、並列同名次）；
    streak 一項換成「到那個週日為止」的連續晚數（排行榜本身只有「現在」）。
    榜上（有名次的）不到 PODIUM_MIN_PEOPLE 人的那一張不算。
    """
    from social import leaderboard  # 只在這裡用，避免 game ↔ social 互相 import

    end = date_cls.fromisoformat(sunday)
    lo = (end - timedelta(days=6)).isoformat()
    for metric in PODIUM_METRICS:
        ppl = []
        for p in people:
            q = {**p, "shares": bool((p.get("shares_by") or {}).get(metric))}
            if metric == "streak":
                n, _ = current_streak(p.get("behavior") or [], as_of=sunday)
                q["streak"] = (n, n)
            ppl.append(q)
        period = "now" if metric == "streak" else "week"
        ranked, _below, _hidden = leaderboard.rank(ppl, metric, period, lo, sunday)
        if len(ranked) < PODIUM_MIN_PEOPLE:
            continue
        if any(k == me_key and r <= PODIUM_TOP for k, r, *_ in ranked):
            return True
    return False
