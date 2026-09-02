"""
tapo_index.py — 「攝影機那一晚看到什麼」的單一事實來源

═══════════════════════════════════════════════════════════════════
為什麼需要這一支
═══════════════════════════════════════════════════════════════════
TAPO 的資料散在兩個來源、三種日期、兩種時間戳，而且**沒有一個是可以直接信的**：

  來源 A  tapo/sleep_records.sql              影像組的 MySQL dump
  來源 B  tapo/sleep_reports/<日期>/*.json    每夜一份的原始報告

  ⚠️ `report_date` 會錯。實例：sleep_reports/2026-08-04/sleep_report_003653.json
     的 report_date 寫 08-04，但裡面 106 個 video_clip 全是 turn_20260803_*
     ——那是 08-03 那一夜。另一筆是 sql#48（宣稱 06-11，實際 06-12 凌晨）。

  ⚠️ `time` 欄位會壞。08-06 / 08-07 / 08-18 三晚整串都是 00:00:00~00:00:05。

**唯一可信的時間來源是 `video_clip` 的檔名**：`turn_YYYYMMDD_HHMMSS_*.mp4`，
日期與時間都在裡面，而且是錄影當下由檔案系統寫的，不經過那兩層會出錯的邏輯。
上面三個壞掉的夜晚全部可以從檔名還原（實測 08-06 → 01:06:09~06:04:34）。

═══════════════════════════════════════════════════════════════════
這一支不做取捨
═══════════════════════════════════════════════════════════════════
它**不丟資料、不做評分、不判斷好壞**，只做四件事：解析、依檔名定日期、
依間隔切夜、把同一晚的紀錄聚在一起（含彼此矛盾的部分）。

「這個值可不可信」由 `provenance()` 標成等級，交給下游決定怎麼用——
`ai/night_profile.py` 會把標籤一起寫進 prompt，讓模型看得到全部的量測值，
同時知道哪些是量出來的、哪些是 np.random 生的。

⚠️ 紅線 4：這裡的任何值都**不得**進入 garmin/evaluate_sleep_quality.py
   或 garmin/apply_recovery_modifier.py 的計算。攝影機只進敘事層與 payload。
"""
import glob
import hashlib
import io
import json
import re
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
# 影像組的 MySQL dump 有兩個落點，因為他們的程式有兩代。
#
# ⚠️ **兩個都要讀。** 2026-09-02 實測：新版 `tapo 2.0/` 那份是舊份的嚴格超集
#    （共同的 15 筆逐欄相同，另外多 5 晚 08-28~09-01）。但下次不一定——
#    影像組更新哪一個是他們的習慣問題，不是我們能假設的。
#    只讀其中一個的話，新資料會**安靜地**從所有分析裡消失，沒有任何錯誤訊息。
#
#    重複的紀錄由 build_index() 的內容指紋擋掉，多讀一個檔不會重複計算。
DUMPS = [
    ROOT / "tapo" / "sleep_records.sql",        # 第一代
    ROOT / "tapo 2.0" / "sleep_records.sql",    # 第二代（目前較新）
]
REPORT_GLOB = str(ROOT / "tapo" / "sleep_reports" / "*" / "sleep_report_*.json")

# 一列 INSERT 的形狀：
# (id, 'date', events, large, snore, score, '[timeline]', 'created', 'updated')
SQL_ROW_RE = re.compile(
    r"\((\d+), '(\d{4}-\d{2}-\d{2})', (\d+), (\d+), (\d+), (\d+), "
    r"'(\[.*?\])', '([\d\- :]+)', '([\d\- :]+)'\)",
    re.S,
)

# turn_20260803_014145_474_370.mp4 → 20260803 + 014145
CLIP_STAMP_RE = re.compile(r"_(\d{8})_(\d{6})_")

# 同一列紀錄裡，超過這個間隔就視為兩個不同的夜晚。
# 實測依據：sql#51 有 32 筆在 08-18、2 筆在 08-19，中間空了 15.2 小時。
# 一夜之內的最大自然間隔遠小於此。
SESSION_GAP_HOURS = 6

# 事件落在中午前 → 屬於當天早上結束的那一夜；中午後 → 屬於隔天早上結束的那一夜。
# 這是為了對齊 Garmin：它按「起床日」分組（見 CLAUDE.md）。
NIGHT_BOUNDARY_HOUR = 12


# ═══════════════════════════════════════════════════════════════════
# 解析：兩個來源 → 同一種形狀
# ═══════════════════════════════════════════════════════════════════

def _clip_events(timeline):
    """
    從 video_clip 檔名取出每個事件的真實時刻，附上該事件的 motion_intensity，
    依時間排序回傳 [(時刻, intensity), ...]。

    intensity 帶著走是為了認出**暖機假影**，見 _is_warmup_artifact()。
    """
    out = []
    for event in timeline or []:
        match = CLIP_STAMP_RE.search(event.get("video_clip") or "")
        if match:
            out.append((datetime.strptime(match.group(1) + match.group(2),
                                          "%Y%m%d%H%M%S"),
                        event.get("motion_intensity")))
    return sorted(out, key=lambda pair: pair[0])




def _count_levels(timeline):
    """數出三種事件。欄位名稱沿用影像組的原始命名，不改寫。"""
    large = micro = snore = 0
    decibels = []
    for event in timeline or []:
        level = event.get("motion_level")
        if level == "large_turn":
            large += 1
        elif level == "micro_motion":
            micro += 1
        if event.get("sound_level") == "snoring_or_noise":
            snore += 1
        if isinstance(event.get("decibel"), int):
            decibels.append(event["decibel"])
    return large, micro, snore, decibels


# 1920×1080：整個畫面都被判定成前景。
FULL_FRAME_INTENSITY = 1920 * 1080


def _is_warmup_artifact(clip_events):
    """
    這串事件的第一筆是不是**背景模型的暖機假影**？

    ═══════════════════════════════════════════════════════════════
    為什麼要認它出來（2026-09-02 追到的根因）
    ═══════════════════════════════════════════════════════════════
    影像組用 `cv2.createBackgroundSubtractorMOG2()` 做背景相減
    （`tapo 2.0/sleep_monitor.py:1026-1028`）：程式先記住「沒有人的時候
    房間長什麼樣」，再比對每一幀有什麼不同。

    但那個背景模型是**在連上攝影機的當下才建立的**，所以第一次比對根本
    沒有背景可比 → 整個畫面都被判成前景 → 記下一筆 intensity 恰好等於
    1920×1080 的「超大動作」。

    **實測 15 / 15**（去重後）：所有含整畫面事件的紀錄裡，那一筆永遠排在
    第一個。真的動作不可能每次都剛好排第一。
    ⚠️ 兩份 dump 有大量重複，不去重會把同一筆算兩次而虛報成 25/25。

    ⚠️ **後果**：那一筆的時刻不是使用者的動作，是**監測程式被打開的時刻**。
       先前把它讀成「上床時刻」並算出「比入睡早 30–48 分鐘」——那個數字
       描述的是操作者幾點啟動程式，不是使用者幾點躺上床。

    ⚠️ 這不代表那個時刻沒有用。`SLEEP_START` 是每次執行時由操作者輸入的
       （`sleep_monitor.py:138-162`），如果他是「準備睡了才啟動」，那它就
       等同於一顆「我要睡了」按鈕——但那是**自我回報**，不是攝影機量到的。

    ✅ 未來錄的資料不受影響：`tapo_metric_logger.py` 已經把暖機期標成
       `warmup` 並在事後排除。這個函式處理的是**既有的歷史資料**。
    """
    return bool(clip_events) and clip_events[0][1] == FULL_FRAME_INTENSITY


def _record(source_id, kind, report_date, stored_score, timeline):
    large, micro, snore, decibels = _count_levels(timeline)
    clip_events = _clip_events(timeline)
    return {
        "first_is_warmup": _is_warmup_artifact(clip_events),
        "source_id": source_id,
        "source_kind": kind,             # "sql" | "json"
        "report_date": report_date,      # ⚠️ 已證實會錯，只留著做對照
        "stored_score": stored_score,    # 影像組寫進來的 sleep_quality_score
        "total_events": len(timeline or []),
        "large_turn_count": large,
        "micro_motion_count": micro,
        "snore_count": snore,
        "decibels": decibels,
        "stamps": [t for t, _ in clip_events],   # ← 唯一可信的時間
        "timeline": timeline or [],
    }


def parse_dump(path):
    """
    解析一份 MySQL dump。壞掉的 timeline 不會讓整支掛掉。

    ⚠️ `source_id` 要帶上是哪一份檔案。兩代 dump 的紀錄 id 會撞
       （兩邊都有 `sql#1`），不帶檔名的話，跨來源落差那張表會出現
       兩個同名的來源，看的人分不出誰是誰。
    """
    path = Path(path)
    if not path.exists():
        return []
    sql = io.open(path, encoding="utf-8", errors="replace").read()
    out = []
    for m in SQL_ROW_RE.finditer(sql):
        rid, rdate, _events, _large, _snore, score, raw, _c, _u = m.groups()
        try:
            timeline = json.loads(raw.replace('\\"', '"'))
        except (ValueError, TypeError):
            timeline = []
        out.append(_record(f"{path.parent.name}/sql#{rid}", "sql",
                           rdate, int(score), timeline))
    return out


def parse_reports(pattern=REPORT_GLOB):
    """解析 tapo/sleep_reports/<日期>/sleep_report_*.json（每夜一份的原始報告）。"""
    out = []
    for path in sorted(glob.glob(pattern)):
        try:
            data = json.load(io.open(path, encoding="utf-8"))
        except (ValueError, OSError):
            continue
        summary = data.get("summary") or {}
        rel = Path(path).relative_to(ROOT).as_posix()
        out.append(_record(rel, "json", data.get("report_date"),
                           summary.get("sleep_quality_score"),
                           data.get("timeline")))
    return out


def iter_raw_records():
    """
    兩個來源的原始紀錄，**未去重、未合併**。

    inspect_tapo_score.py 要的是這一層——它要證明的正是
    「同一晚在兩個來源會得到不同的分數」，合併掉就看不到了。
    """
    records = []
    for dump in DUMPS:
        records += parse_dump(dump)
    return records + parse_reports()


# ═══════════════════════════════════════════════════════════════════
# 切夜：一列紀錄可能橫跨兩夜，一夜也可能散在多列
# ═══════════════════════════════════════════════════════════════════

def night_key(stamp):
    """事件時刻 → 它屬於哪一夜（用 Garmin 的「起床日」慣例）。"""
    day = stamp.date()
    if stamp.hour >= NIGHT_BOUNDARY_HOUR:
        day += timedelta(days=1)
    return day.isoformat()


def split_sessions(stamps, gap_hours=SESSION_GAP_HOURS):
    """依間隔把一串時刻切成數段。回傳 list of list。"""
    if not stamps:
        return []
    gap = timedelta(hours=gap_hours)
    sessions = [[stamps[0]]]
    for prev, cur in zip(stamps, stamps[1:]):
        if cur - prev > gap:
            sessions.append([])
        sessions[-1].append(cur)
    return sessions


def _content_hash(record):
    """
    去重用的內容指紋。

    08-07 那三份 `_recovered` 檔是同一份資料被存了三次
    （sleep_report_114346 / 114556 / 114920，內容逐筆相同）。
    用時刻序列 + 三個計數當指紋，比檔名可靠。
    """
    blob = json.dumps({
        "stamps": [s.isoformat() for s in record["stamps"]],
        "large": record["large_turn_count"],
        "micro": record["micro_motion_count"],
        "snore": record["snore_count"],
    }, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


# ═══════════════════════════════════════════════════════════════════
# 對外介面
# ═══════════════════════════════════════════════════════════════════

def build_index(records=None):
    """
    回傳 {夜晚(YYYY-MM-DD): 那一夜攝影機看到的東西}。

    ⚠️ **同一夜的多筆紀錄不會被合成一個「正確答案」**。
       兩個來源對同一夜可以給出差 80 分的結果（08-02：SQL 80 分 / JSON 0 分），
       硬選一個就是在沒有依據的情況下替影像組做決定。
       所以 `scores` 是一個 list，`score_disagreement` 直接把落差攤開。
    """
    records = iter_raw_records() if records is None else records

    seen = set()
    nights = {}
    for record in records:
        digest = _content_hash(record)
        if digest in seen:
            continue          # 08-07 的三份重複檔在這裡被擋掉
        seen.add(digest)

        for session in split_sessions(record["stamps"]):
            key = night_key(session[0])
            night = nights.setdefault(key, {
                "date": key,
                "camera_first": session[0],
                "camera_last": session[-1],
                "total_events": 0,
                "large_turn_count": 0,
                "micro_motion_count": 0,
                "snore_count": 0,
                "decibel_min": None,
                "decibel_max": None,
                "scores": [],
                "sources": [],
                "report_dates": set(),
                "first_is_warmup": False,
            })
            # first_is_warmup 描述的是**現在這個 camera_first 那一筆**，不是整晚。
            # 所以只有在這一段成為新的（或並列的）最早時刻時才更新。
            # 而且只有紀錄的**第一段**可能是暖機——背景模型在連線當下建一次，
            # 之後的段落是同一次連線裡的後續事件。
            if session[0] <= night["camera_first"]:
                night["first_is_warmup"] = (record["first_is_warmup"]
                                            and session[0] == record["stamps"][0])
            night["camera_first"] = min(night["camera_first"], session[0])
            night["camera_last"] = max(night["camera_last"], session[-1])
            night["sources"].append(record["source_id"])
            night["report_dates"].add(record["report_date"])

            # 一列橫跨兩夜時，計數只能按事件比例分攤——影像組的 summary
            # 是整列的總數，沒有逐夜拆開。用比例是近似，所以標在 provenance 裡。
            share = len(session) / max(len(record["stamps"]), 1)
            night["total_events"] += round(record["total_events"] * share)
            night["large_turn_count"] += round(record["large_turn_count"] * share)
            night["micro_motion_count"] += round(record["micro_motion_count"] * share)
            night["snore_count"] += round(record["snore_count"] * share)
            if record["stored_score"] is not None:
                night["scores"].append((record["source_id"], record["stored_score"]))
            if record["decibels"]:
                lo, hi = min(record["decibels"]), max(record["decibels"])
                night["decibel_min"] = lo if night["decibel_min"] is None \
                    else min(night["decibel_min"], lo)
                night["decibel_max"] = hi if night["decibel_max"] is None \
                    else max(night["decibel_max"], hi)

    for night in nights.values():
        values = [s for _, s in night["scores"]]
        night["score_disagreement"] = (max(values) - min(values)) if len(values) > 1 else 0
        night["report_dates"] = sorted(x for x in night["report_dates"] if x)
        night["date_mismatch"] = [d for d in night["report_dates"] if d != night["date"]]
    return nights


# 整段錄影都落在這個時段且不到一小時 → 是測試錄影不是整夜睡眠。
DAYTIME_START, DAYTIME_END = 6, 20
MIN_NIGHT_HOURS = 1
# 人一整晚翻身約 10–40 次；每小時超過這個數不合生理，代表偵測器在抓畫面變化。
MAX_TURNS_PER_HOUR = 30


def sleep_recording_problem(night):
    """
    這一夜的錄影能不能當「一夜的睡眠」看？可以回傳 None，不行回傳原因（英文）。

    ⚠️ 這個判準**只有一份**，三個呼叫端共用（build_app_payload、
       itegration/if_integrate、ai/night_profile）。
       各自抄一份的話會漂移，而漂移沒有任何錯誤訊息——某一支開始把
       29 秒的白天測試錄影當成一夜，另一支不會，兩邊的數字就對不起來。

    ⚠️ 這**不是評分**，是資料有效性檢查，所以不受紅線 4 影響。
    """
    first, last = night["camera_first"], night["camera_last"]
    span_hours = (last - first).total_seconds() / 3600

    if span_hours < MIN_NIGHT_HOURS and \
            all(DAYTIME_START <= h < DAYTIME_END for h in (first.hour, last.hour)):
        return (f"the clip runs {first:%H:%M}-{last:%H:%M} in daytime hours and "
                f"lasts under an hour; it is a test recording, not a night's sleep")

    turns_per_hour = night["large_turn_count"] / max(span_hours, 1)
    if turns_per_hour > MAX_TURNS_PER_HOUR:
        return (f"the recording reports roughly {turns_per_hour:.0f} large turns "
                f"per hour, outside the physiologically plausible range; the motion "
                f"detector is picking up frame-wide changes rather than body movement")
    return None


_INDEX_CACHE = None


def get_index(refresh=False):
    """
    快取版的 build_index()。

    ai/night_profile.py 會對 51 晚各查一次，每次重讀 244KB 的 dump
    要多花約 3.5 秒。索引在一次執行內不會變，所以只建一次。
    """
    global _INDEX_CACHE
    if _INDEX_CACHE is None or refresh:
        _INDEX_CACHE = build_index()
    return _INDEX_CACHE


def provenance():
    """
    每個欄位是什麼等級的證據。**下游必須照著標，不可以自己判斷。**

    這張表是 2026-08-30 用 23552 筆事件實測出來的，不是抄來的：
      - decibel 直方圖 35–41 dB 七個值各佔 13.4–14.2% → np.random 的均勻分布
      - sound_level 由 decibel 門檻推導，所以 snore_count 是亂數的計數
      - sleep_quality_score 與 timeline 長度綁死，同一晚跨來源差 80 分
      - motion_intensity 只有 213/23552 筆是整畫面值，整畫面誤判是局部問題

    重跑方式：python inspect_tapo_score.py
    """
    return {
        # ⚠️ camera_first **不是**單純的量測值。當 first_is_warmup 為真時，
        #    它記錄的是「監測程式連上攝影機的那一刻」，不是使用者的動作
        #    （見 _is_warmup_artifact()，實測 15/15）。呼叫端必須看那個旗標，
        #    不可以無條件當成上床時刻用。
        "camera_first": "MEASURED_SESSION_START",
        "first_is_warmup": "MEASURED",
        "camera_last": "MEASURED",
        "total_events": "MEASURED_NOT_COMPARABLE",
        "large_turn_count": "MEASURED_NOT_COMPARABLE",
        "micro_motion_count": "MEASURED_NOT_COMPARABLE",
        "stored_score": "NOT_MEASUREMENT_GRADE",
        "snore_count": "SIMULATED",
        "decibel_min": "SIMULATED",
        "decibel_max": "SIMULATED",
    }
