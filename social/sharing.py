"""
social/sharing.py —— 每個人自己選要讓好友看到什麼（2026-11-15 使用者定，grill）。純函式。

⚠️ 仍是**白名單**：能分享的只有 ITEMS 裡的項目，每一項用自己的 picker 從那一晚的 `/home`
   回應裡挑出一個小值。新欄位要被分享，得有人刻意在這裡加一項——黑名單的寫法會在某天
   有人加了新欄位時安靜地把它分享出去。
⚠️ 三樣**永遠不給**、連選項都沒有（NEVER_SHARED）：攝影機片段（臥室原始畫面）、
   Move IQ 每段的時刻（會透露每天幾點出門）、睡前用了哪些 App。
⚠️ 預設：行為那幾項（放下手機、準時、連續、寵物心情、衣服、挑戰）開；其他全部關。
⚠️ 數字一律從那一晚的 `/home` 挑——跟本人自己的早晨報告**同一份**，好友看到的不會跟本人不一樣。
⚠️ 只讀。這裡不寫回評分、不給 XP（紅線 4）。
"""
import json
from datetime import datetime

GROUPS = (
    ("sleep", "Sleep"),
    ("heart", "Heart & stress"),
    ("day", "Daytime"),
    ("game", "Game"),
)

# 永遠不給（只為了說明與測試，ITEMS 裡不能出現這幾個 key）
NEVER_SHARED = (
    ("camera_clips", "Camera clips (video of your bedroom)"),
    ("move_iq_times", "When each Move IQ walk started"),
    ("prebed_apps", "Which apps you used before bed"),
)

TIME_PRECISIONS = ("exact", "on_time_only")
PET_SPECIES = ("dog", "cat")
# 動態卡的場景（2026-11-16 使用者定：每個人自己選一張，像大頭貼；不依心情或好壞換）。
# 圖是使用者生成的，在 app/assets/backgrounds/scene_<id>.jpg
SCENES = ("campfire", "rooftop", "lake", "treehouse")
DEFAULT_SCENE = "campfire"

# 「只寫準時與否」時拿掉的項目（有時刻的）
_TIME_ITEMS = ("phone_down_time", "bed_times")


def _wall(s):
    """ISO 字串 → 牆鐘 datetime（不換時區：手錶帶 +08:00、按鈕不帶，兩邊都只取牆鐘）。"""
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s)).replace(tzinfo=None)
    except ValueError:
        return None


def _hhmm(s):
    t = _wall(s)
    return None if t is None else f"{t.hour:02d}:{t.minute:02d}"


def _g(d, *path):
    for p in path:
        if not isinstance(d, dict):
            return None
        d = d.get(p)
    return d


def _num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def _compact(d):
    """全部是 None 的小字典 → None（那一項不出現，不寫成 0）。"""
    if not isinstance(d, dict):
        return d
    return d if any(v is not None for v in d.values()) else None


# ── 每一項的 picker：ctx → 值或 None ──────────────────────────────────
# ctx = {"home": /home 那一晚, "game": build_game_state, "closet": {...},
#        "prebed_minutes": 數字, "camera": camera_nightly 那一列, "behavior_mood": 行為版心情}

def _phone_down_time(c):
    return _hhmm(_g(c["home"], "behavior", "lights_out_at"))


def _on_time(c):
    late = _g(c["home"], "behavior", "is_late")
    return None if late is None else (not bool(late))


def _fell_asleep(c):
    start = _wall(_g(c["home"], "behavior", "bed_start_at"))
    end = _wall(_g(c["home"], "behavior", "bed_end_at"))
    asleep = _wall(_g(c["home"], "metrics", "sleep_start_time"))
    if start is None or asleep is None or asleep < start or (end is not None and asleep >= end):
        return None  # 手錶比按鈕早睡著（負數）不給，同報告
    return round((asleep - start).total_seconds() / 60)


def _efficiency(c):
    basis = _g(c["home"], "scoring", "composition", "efficiency_basis")
    b = _g(c["home"], "behavior") or {}
    if basis and basis == b.get("measured_efficiency_basis"):
        value = b.get("measured_efficiency")
    elif basis and basis == b.get("watch_wake_efficiency_basis"):
        value = b.get("watch_wake_efficiency")
    else:
        value = _g(c["home"], "metrics", "sleep_efficiency")
    if _num(value) is None:
        return None
    return {"value": value, "label": _g(c["home"], "scoring", "composition", "efficiency_label")}


def _stages(c):
    """
    深睡／淺睡／REM 的分鐘數，加上那一晚的階梯圖（2026-11-16：動態卡中間那張大圖）。

    ⚠️ 每一段只給「從睡著起算第幾分鐘到第幾分鐘」，**不給 ISO 時刻**；兩端的時刻另放
       start／end，選了「只寫準時與否」時由 night_card 拿掉（時間軸就只剩 Fell asleep／Woke up）。
    """
    out = {k: _num(_g(c["home"], "metrics", f"{k}_minutes")) for k in ("deep", "light", "rem")}
    stages = _g(c["home"], "metrics", "sleep_stages")
    segs = stages.get("segments") if isinstance(stages, dict) else None
    timeline = []
    t0 = None
    for seg in segs or []:
        if not isinstance(seg, dict):
            continue
        a, b = _wall(seg.get("start")), _wall(seg.get("end"))
        if a is None or b is None or b <= a or seg.get("stage") not in ("awake", "rem", "light", "deep"):
            continue
        t0 = t0 or a
        timeline.append({"stage": seg["stage"],
                         "from": round((a - t0).total_seconds() / 60, 1),
                         "to": round((b - t0).total_seconds() / 60, 1)})
    if timeline:
        out["segments"] = timeline
        out["rem_measured"] = bool(stages.get("rem_measured", True))
        out["start"] = _hhmm(_g(c["home"], "metrics", "sleep_start_time"))
        out["end"] = _hhmm(_g(c["home"], "metrics", "wake_time"))
    return _compact(out)


def _offsets(points):
    """曲線 [{t: ISO, value}] → [{m: 從第一點起算第幾分鐘, v}]。
    ⚠️ 不給 ISO 時刻（同 _stages）：兩端的時刻由 stages 的 start／end 決定要不要給。"""
    out, t0 = [], None
    for p in points or []:
        if not isinstance(p, dict):
            continue
        t, v = _wall(p.get("t")), _num(p.get("value"))
        if t is None or v is None:
            continue
        t0 = t0 or t
        out.append({"m": round((t - t0).total_seconds() / 60, 1), "v": v})
    return out


def _sleeping_hr(c):
    curve = _g(c["home"], "metrics", "heart_rate_curve")
    if isinstance(curve, dict) and _num(curve.get("avg")) is not None:
        # 完整頁的 Heart rate 區塊（2026-11-16）：整晚的線跟著同一個開關
        return {"avg": round(curve["avg"]), "min": _num(curve.get("min")),
                "curve": _offsets(curve.get("points")) or None}
    avg = _num(_g(c["home"], "metrics", "avg_heart_rate"))
    return None if avg is None else {"avg": round(avg), "min": None}


def _camera_timeline(c):
    """
    完整頁的 Movement (camera) 區塊（2026-11-16 使用者定）：整晚每 5 分鐘動多少的光柱、
    總共動幾次、動了多久、「跟他自己平常比」那一句。

    ⚠️ 自己一個開關、**預設關**：每小時幾次只是一個數字，時間軸細到「半夜幾點在動」。
    ⚠️ 片段影像永遠不給（NEVER_SHARED）。只留睡著那段（/home 的 camera_curve 已經剪好）。
    """
    curve = _g(c["home"], "metrics", "camera_curve")
    cam = c.get("camera") or {}
    moving = None
    try:
        eps = json.loads(cam["motion_episodes"]) if cam.get("motion_episodes") else None
        if isinstance(eps, list):
            moving = round(sum(_num(e.get("seconds")) or 0 for e in eps if isinstance(e, dict)))
    except (TypeError, ValueError):
        moving = None
    usual = cam.get("usual")
    return _compact({
        "points": _offsets(curve.get("points")) or None if isinstance(curve, dict) else None,
        "total": _num(cam.get("events_total")),
        "moving_sec": moving,
        "usual": usual.get("label") if isinstance(usual, dict) else None,
    })


def _devices(c):
    """
    那一晚用了哪些設備（2026-11-16 使用者要求，像 Strava 活動頁的鞋子與手錶）：
    手錶（型號照 wearable_nightly.device_brand）、有錄影就有攝影機、有就寢紀錄就有手機。
    只寫名字，不寫序號或任何識別碼。
    """
    home = c["home"]
    out = []
    if _g(home, "scoring", "source"):
        brand = _g(home, "scoring", "device_brand")
        out.append({"kind": "watch",
                     "name": brand if isinstance(brand, str) and brand and brand != "demo" else "Watch"})
    cam = c.get("camera")
    if cam:
        out.append({"kind": "camera", "name": cam.get("camera_model") or "Camera"})
    b = _g(home, "behavior") or {}
    if b.get("lights_out_at") or b.get("bed_start_at"):
        out.append({"kind": "phone", "name": c.get("phone_model") or "Phone"})
    return out or None


def _stress(c):
    s = _g(c["home"], "yesterday", "stress")
    if not isinstance(s, dict):
        return None
    return _compact({k: _num(s.get(f"{k}_sec")) for k in ("rest", "low", "medium", "high")})


def _move_iq(c):
    events = _g(c["home"], "yesterday", "move_iq")
    if not isinstance(events, list):
        return None
    # ⚠️ 騎車不算（使用者多半騎機車，同 App 的 moveIqShown）；**時刻不給**，只給段數與分鐘
    shown = [e for e in events if isinstance(e, dict) and e.get("type") != "cycling"]
    return {"count": len(shown), "minutes": sum(_num(e.get("minutes")) or 0 for e in shown)}


def _level(c):
    g = c.get("game") or {}
    lvl = g.get("level")
    if isinstance(lvl, dict):
        lvl = lvl.get("level")
    return _compact({"level": _num(lvl), "xp_total": _num(g.get("xp_total"))})


def _outfit(c):
    g = c.get("game") or {}
    badges = g.get("badges") or []
    return _compact({
        "equipped_item_id": (c.get("closet") or {}).get("equipped_item_id"),
        "badges": len(badges) if isinstance(badges, list) else None,
    })


def _challenges(c):
    out = []
    for ch in c.get("challenges") or []:
        if not isinstance(ch, dict):
            continue
        # 只給名字與完成沒：current／target 是各挑戰自己的單位（分鐘、晚數、離散度），
        # 朋友看到「26.9/0」看不懂（11-15 真資料預覽發現）
        out.append({"title": ch.get("title"), "completed": ch.get("status") == "completed"})
    return out or None


ITEMS = (
    # key, group, default_on, label, picker
    ("phone_down_time", "sleep", True, "Phone-down time", _phone_down_time),
    ("on_time", "sleep", True, "On time or late", _on_time),
    ("pet_mood", "sleep", True, "Pet mood", lambda c: c.get("behavior_mood")),
    # 即時狀態（2026-11-19 使用者定，預設關）：按了 Start Sleep 好友就看到 Asleep。
    # 不是某一晚的值，所以 picker 回 None、不進動態卡；只在好友摘要（social/friends.py）用
    ("live_status", "sleep", False, "Live status (asleep now, past bedtime)", lambda c: None),
    ("target_bedtime", "sleep", False, "Target bedtime",
     lambda c: _g(c["home"], "behavior", "target_bedtime")),
    ("phone_after_start", "sleep", False, "Phone use after Start Sleep",
     lambda c: _num(_g(c["home"], "behavior", "phone_in_bed_minutes"))),
    ("prebed_phone", "sleep", False, "Phone use in the hour before bed",
     lambda c: _num(c.get("prebed_minutes"))),
    # 動態卡上的三個大數字（睡多久、每小時動幾次、分數）預設分享、可以關（2026-11-16 使用者定）
    ("score", "sleep", True, "Sleep score",
     lambda c: _compact({"score": _num(_g(c["home"], "scoring", "final_score")),
                         "quality": _g(c["home"], "scoring", "final_quality")})),
    ("sleep_duration", "sleep", True, "Time asleep",
     lambda c: _num(_g(c["home"], "metrics", "sleep_duration_minutes"))),
    ("bed_times", "sleep", False, "Bedtime and get-up time",
     lambda c: _compact({"start": _hhmm(_g(c["home"], "behavior", "bed_start_at")),
                         "end": _hhmm(_g(c["home"], "behavior", "bed_end_at"))})),
    ("time_in_bed", "sleep", False, "Time in bed",
     lambda c: _num(_g(c["home"], "behavior", "time_in_bed_minutes"))),
    ("fell_asleep", "sleep", False, "Time to fall asleep", _fell_asleep),
    ("awake", "sleep", False, "Awake during the night",
     lambda c: _compact({"count": _num(_g(c["home"], "metrics", "awake_count")),
                         "minutes": _num(_g(c["home"], "metrics", "waso_minutes"))})),
    ("stages", "sleep", False, "Sleep stages chart (deep, light, REM)", _stages),
    ("efficiency", "sleep", False, "Sleep efficiency", _efficiency),
    ("camera_moves", "sleep", True, "Movements per hour (camera)",
     lambda c: _num((c.get("camera") or {}).get("events_per_hour"))),
    ("camera_timeline", "sleep", False, "Movement through the night (camera timeline)",
     _camera_timeline),
    ("devices", "sleep", True, "Devices used that night (watch model, camera, phone)", _devices),
    ("morning_rating", "sleep", False, "How rested you felt",
     lambda c: _compact({"rested": _num(_g(c["home"], "morning_rating", "rested")),
                         "label": _g(c["home"], "morning_rating", "label")})),
    ("sleeping_hr", "heart", False, "Sleeping heart rate", _sleeping_hr),
    ("resting_hr", "heart", False, "Resting heart rate",
     lambda c: _num(_g(c["home"], "metrics", "resting_heart_rate"))),
    ("stress", "heart", False, "Stress", _stress),
    ("awake_hr", "heart", False, "Awake heart rate",
     lambda c: _compact({"avg": _num(_g(c["home"], "yesterday", "awake_heart_rate", "avg")),
                         "max": _num(_g(c["home"], "yesterday", "awake_heart_rate", "max"))})),
    ("body_battery", "heart", False, "Body Battery",
     lambda c: _compact({"charged": _num(_g(c["home"], "yesterday", "body_battery", "charged")),
                         "drained": _num(_g(c["home"], "yesterday", "body_battery", "drained"))})),
    ("vo2max", "heart", False, "VO2 max",
     lambda c: _num(_g(c["home"], "yesterday", "vo2max", "value"))),
    ("steps", "day", False, "Steps, distance and floors",
     lambda c: _compact({"steps": _num(_g(c["home"], "yesterday", "steps")),
                         # 2026-11-19：小鎮面板的步數圓弧要目標（同早晨報告，只寫 Goal，不寫 reached）
                         "goal": _num(_g(c["home"], "yesterday", "step_goal")),
                         "distance_m": _num(_g(c["home"], "yesterday", "distance_m")),
                         "floors": _num(_g(c["home"], "yesterday", "floors_up"))})),
    ("calories", "day", False, "Calories",
     lambda c: _compact({"active": _num(_g(c["home"], "yesterday", "active_kcal")),
                         "total": _num(_g(c["home"], "yesterday", "total_kcal"))})),
    ("active_time", "day", False, "Active time",
     lambda c: _compact({k: _num(_g(c["home"], "yesterday", "activity", f"{k}_sec"))
                         for k in ("highly_active", "active", "sedentary")})),
    ("move_iq", "day", False, "Move IQ walks (count and minutes)", _move_iq),
    ("level", "game", False, "Level and XP", _level),
    ("outfit", "game", True, "Pet outfit and badges", _outfit),
    ("challenges", "game", True, "Challenge progress", _challenges),
)

ITEM_KEYS = tuple(k for k, *_ in ITEMS)
_BY_KEY = {k: (group, default, label, pick) for k, group, default, label, pick in ITEMS}
# 不是每一晚的值、是「這個人」的：連續天數與那一週的打勾（Streak 卡）
STREAK_KEY = "streak"
ALL_KEYS = ITEM_KEYS + (STREAK_KEY,)

assert not set(ALL_KEYS) & {k for k, _ in NEVER_SHARED}, "永遠不給的項目不能出現在清單裡"


def item_label(key):
    """分享項目的名字（設定頁上那個）；連續天數不在清單裡，另外給。"""
    if key == STREAK_KEY:
        return "Streak"
    return _BY_KEY[key][2] if key in _BY_KEY else key


def defaults():
    out = {k: d for k, (_, d, _, _) in _BY_KEY.items()}
    out[STREAK_KEY] = True
    return out


def effective(stored):
    """資料庫那一列（或 None）→ {"items": {key: bool}, "time_precision", "pet_species", "scene"}。
    不認得的 key 一律忽略（舊資料裡有、後來拿掉的項目不會又冒出來）。"""
    stored = stored or {}
    items = defaults()
    for k, v in (stored.get("items") or {}).items():
        if k in items and isinstance(v, bool):
            items[k] = v
    precision = stored.get("time_precision")
    species = stored.get("pet_species")
    scene = stored.get("scene")
    return {
        "items": items,
        "time_precision": precision if precision in TIME_PRECISIONS else "exact",
        "pet_species": species if species in PET_SPECIES else "dog",
        "scene": scene if scene in SCENES else DEFAULT_SCENE,
    }


def validate_patch(items=None, time_precision=None, pet_species=None, scene=None):
    """PATCH 進來的東西；不認得的 key（含永遠不給那三個）→ ValueError，回 422。"""
    for k, v in (items or {}).items():
        if k not in ALL_KEYS:
            raise ValueError(f"{k!r} cannot be shared.")
        if not isinstance(v, bool):
            raise ValueError(f"{k!r} must be true or false.")
    if time_precision is not None and time_precision not in TIME_PRECISIONS:
        raise ValueError(f"time_precision must be one of {TIME_PRECISIONS}.")
    if pet_species is not None and pet_species not in PET_SPECIES:
        raise ValueError(f"pet_species must be one of {PET_SPECIES}.")
    if scene is not None and scene not in SCENES:
        raise ValueError(f"scene must be one of {SCENES}.")


def view(settings):
    """GET /sharing 的形狀：分組、每項的開關、永遠不給的清單。"""
    items = settings["items"]
    groups = []
    for gid, glabel in GROUPS:
        rows = [{"key": k, "label": label, "enabled": items[k], "default": d}
                for k, (g, d, label, _) in _BY_KEY.items() if g == gid]
        if gid == "sleep":
            rows.insert(2, {"key": STREAK_KEY, "label": "Streak", "enabled": items[STREAK_KEY],
                            "default": True})
        groups.append({"id": gid, "label": glabel, "items": rows})
    return {
        "groups": groups,
        "time_precision": settings["time_precision"],
        "pet_species": settings["pet_species"],
        "scene": settings["scene"],
        "scenes": list(SCENES),
        "never_shared": [label for _, label in NEVER_SHARED],
    }


def night_card(ctx, settings):
    """一晚的卡：只有本人打開、而且那一晚有值的項目。沒值的不出現（不寫 0）。"""
    items = settings["items"]
    skip = _TIME_ITEMS if settings["time_precision"] == "on_time_only" else ()
    out = {}
    for k in ITEM_KEYS:
        if not items.get(k) or k in skip:
            continue
        v = _BY_KEY[k][3](ctx)
        if k == "stages" and isinstance(v, dict) and _hides_times(settings):
            # 階梯圖照給，但兩端的時刻拿掉（Fell asleep／Woke up）
            v = {kk: vv for kk, vv in v.items() if kk not in ("start", "end")}
        if v is not None:
            out[k] = v
    return out


def _hides_times(settings):
    return settings["time_precision"] == "on_time_only"


def streak_week(rows, today, achieved):
    """
    Streak 卡那一排：today 所在的那一週（週一 → 週日）每天的狀態。
    on_time / late / none（沒資料）/ future（還沒到）。achieved = challenges.night_achieved。
    """
    from datetime import date, timedelta
    d0 = today if isinstance(today, date) else date.fromisoformat(str(today))
    monday = d0 - timedelta(days=d0.weekday())
    by_date = {str(r.get("date")): r for r in rows or []}
    out = []
    for i in range(7):
        d = monday + timedelta(days=i)
        if d > d0:
            status = "future"
        else:
            row = by_date.get(d.isoformat())
            a = achieved(row) if row is not None else None
            status = "none" if a is None else ("on_time" if a else "late")
        out.append({"date": d.isoformat(), "status": status})
    return out
