"""
inspect_tapo_score.py — TAPO `sleep_quality_score` 到底在量什麼？

═══════════════════════════════════════════════════════════════════
這一支要回答的問題
═══════════════════════════════════════════════════════════════════
「為什麼攝影機的分數是 0？」

答案不是「因為使用者睡得很差」，也不只是「因為分數撞到地板」。
實測結論是：**這個分數量的是 timeline 有多長，不是睡得好不好。**
再往下一層，timeline 有多長取決於**當晚的偵測門檻設多少**，
而那個門檻逐晚在變、且沒有記在任何一筆資料裡（表五）。

⚠️ 這支**不做任何評分**，只重現影像組的公式並把扣分逐項拆開，
   所以不受「遊戲化層不得回寫評分層」那條紅線影響。

⚠️ 它也**不修改任何檔案**。影像組送新 dump 之後直接再跑一次即可，
   不要照抄輸出的數字——那是跑的當下那份檔的結果。

執行：python inspect_tapo_score.py
"""
import sys
from collections import Counter, defaultdict
from datetime import datetime

import tapo_index

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════
# 影像組的公式（抄過來只為了重現，不是我們的評分）
# ═══════════════════════════════════════════════════════════════════
# 出處：tapo/tapo_detector.py:486 與 tapo 2.0/sleep_monitor.py:760，兩版相同。
#
#     deduction = large*2.0 + micro*0.1 + snore*0.4
#     score     = max(0, 100 - deduction)
#     if total_events < 20 and score < 100:      # 少事件的救援條款
#         score = max(0, 100 - large*3)
#
# ⚠️ 這三個係數沒有註解、沒有引用、沒有用資料校準過（PROJECT_STATUS 3.8 ④）。
#
# ⚠️ 這不是唯一的一代。repo 裡總共有四代公式，其中三支都會寫進
#    `sleep_records.sleep_quality_score` 這同一個欄位，而且欄位沒有版本標記：
#      V1   tapo/tapo_detector.py:486、tapo 2.0/sleep_monitor.py:760（就是下面這組）
#      V2   tapo/sleep_anylzer.py:96           翻身率 + 打呼 + 事件數分段
#      V2.5 tapo 2.0/tapo_detector.py:399      翻身間隔 <5min/-10、5-15/-5、15-30/-2
#      V3   tapo/newsleep score count.py       翻身總數定基礎分 95/85/70/50/30
#    表一的「符合」欄實測出現有 dump 是 V1 寫的（V3 寫好了但沒套用）。
LARGE_WEIGHT = 2.0
MICRO_WEIGHT = 0.1
SNORE_WEIGHT = 0.4
RESCUE_EVENT_THRESHOLD = 20
RESCUE_LARGE_WEIGHT = 3

FULL_FRAME_INTENSITY = 1920 * 1080   # 2073600：整個畫面都在動 = 偵測器誤判

# repo 現行的偵測門檻（tapo 2.0/tapo_detector.py:24-26 的 default_config）。
# 表五會拿它跟每一筆資料裡**實際生效過**的門檻比對。
REPO_MIN_MOTION_AREA = 50000
REPO_MOTION_MICRO = 250000
REPO_MOTION_LARGE = 350000


# ═══════════════════════════════════════════════════════════════════
# 文獻基準線（表六用）
# ═══════════════════════════════════════════════════════════════════
# ⚠️ 這裡只放**常模**，不放門檻，也不拿來計分——這支不評分。
#    它的用途是健全性檢查：偵測器吐出來的事件率，跟人類實際會動的次數
#    差幾個數量級？差幾十倍就不必再討論係數了。
#
# 要把這些數字變成計分門檻，必須先寫 Research-Background/攝影機分數.md
# （紅線 2：每一項計分都必須有文獻門檻）。在那份文件寫好之前不要動評分。
#
# ① Montini A, Loddo G, Zenesini C, Mainieri G, Baldelli L, Mignani F,
#    Mondini S, Provini F. Physiological movements during sleep in healthy
#    adults across all ages: a video-polysomnographic analysis of non-codified
#    movements reveals sex differences and distinct motor patterns.
#    Sleep. 2024;47(9):zsae138. doi:10.1093/sleep/zsae138
#    50 名健康成人（20-70 歲）的**錄影** PSG——模態與我們相同。
MONTINI_MI_MEDIAN = 11        # 次/小時
MONTINI_MI_IQR = (8, 15)
#
# ② De Koninck J, Lorrain D, Gagnon P. Sleep positions and position shifts in
#    five age groups: an ontogenetic picture. Sleep. 1992;15(2):143-149.
#    體位改變次數：3-5 歲 4.4、8-12 歲 4.7、18-24 歲 3.6、35-45 歲 2.7、
#    65-80 歲 2.1 次/小時。本專案的使用者是大學生 → 取 18-24 那一格。
DEKONINCK_SHIFTS_PER_HOUR = 3.6

# 跨度短於這個值就算不出有意義的「率」。
# 實測有幾筆的 `time` 欄位壞到讓上百個事件擠在幾秒內（跨度 0.00 小時），
# 不擋掉的話會算出 154800 次/小時，把整張表的統計毀掉。
MIN_SPAN_HOURS = 0.5


def recompute(record):
    """用影像組的公式重算，回傳 (三項扣分, 總扣分, 分數)。"""
    large = record["large_turn_count"] * LARGE_WEIGHT
    micro = record["micro_motion_count"] * MICRO_WEIGHT
    snore = record["snore_count"] * SNORE_WEIGHT
    deduction = large + micro + snore
    score = int(max(0, 100 - deduction))
    if record["total_events"] < RESCUE_EVENT_THRESHOLD and score < 100:
        score = int(max(0, 100 - record["large_turn_count"] * RESCUE_LARGE_WEIGHT))
    return (large, micro, snore), deduction, score


def rule(char="-", width=100):
    print(char * width)


def short(source_id):
    """把來源 id 縮成能排進表格的寬度。"""
    return source_id.replace("\\", "/").split("/")[-1][:44]


def timeline_span_hours(timeline):
    """
    用事件的 `time` 欄位算跨度（小時），跨午夜自動 +24。

    ⚠️ `time` 是已知會壞的欄位（tapo_index 的檔頭有說明，所以那邊改用
       video_clip 檔名）。但 micro_motion 沒有 video_clip，要算事件**率**
       就只剩這個欄位可用。→ 表六的跨度是**近似值**，
       不要拿去當上床時刻，那件事請用 tapo_index。
    """
    times = []
    for event in timeline:
        try:
            times.append(datetime.strptime(event.get("time", ""), "%H:%M:%S"))
        except ValueError:
            continue
    if len(times) < 2:
        return 0.0
    span = (times[-1] - times[0]).total_seconds() / 3600
    return span + 24 if span < 0 else span


def zero_gap_share(timeline):
    """相鄰事件間隔正好 0 秒的比例。偵測器每一幀都在觸發時會接近 1。"""
    times = []
    for event in timeline:
        try:
            times.append(datetime.strptime(event.get("time", ""), "%H:%M:%S"))
        except ValueError:
            continue
    if len(times) < 2:
        return None
    zero = sum(1 for i in range(1, len(times)) if times[i] == times[i - 1])
    return zero / (len(times) - 1)


def observed_thresholds(timeline):
    """
    從 motion_intensity 反推**這筆資料實際生效過**的門檻。

    下限   = 最小的非零強度（低於它的事件根本沒被記錄）
    分界   = max(micro 的強度) 與 min(large 的強度) 之間

    回傳 (下限, micro最大, large最小)，取不到的用 None。
    """
    micro, large, nonzero = [], [], []
    for event in timeline:
        value = event.get("motion_intensity") or 0
        if value:
            nonzero.append(value)
        level = event.get("motion_level")
        if level == "micro_motion":
            micro.append(value)
        elif level == "large_turn":
            large.append(value)
    return (
        min(nonzero) if nonzero else None,
        max(micro) if micro else None,
        min(large) if large else None,
    )


# ═══════════════════════════════════════════════════════════════════
# 表一：逐筆扣分拆解
# ═══════════════════════════════════════════════════════════════════

def table_breakdown(records):
    print("\n【表一】扣分逐項拆解 —— 哪一項把分數打到 0？")
    rule("=")
    print(f"{'紀錄':<46}{'事件':>6}{'large×2':>9}{'micro×.1':>10}"
          f"{'snore×.4':>10}{'總扣分':>9}{'重算':>6}{'存檔':>6}{'符合':>5}")
    rule()

    dominant = defaultdict(Counter)
    deductions = []
    mismatches = []
    for record in sorted(records, key=lambda r: (r["source_kind"], r["source_id"])):
        (large, micro, snore), deduction, score = recompute(record)
        stored = record["stored_score"]
        agree = "✓" if stored == score else "✗"
        if stored != score:
            mismatches.append((record["source_id"], stored, score, record["total_events"]))
        if deduction > 0:
            deductions.append(deduction)
            bucket = "撞到地板（0 分）" if score == 0 else "沒撞地板"
            dominant[bucket][max((large, "large_turn"), (micro, "micro_motion"),
                                 (snore, "snore"))[1]] += 1
        print(f"{record['source_id']:<46}{record['total_events']:>6}"
              f"{large:>9.0f}{micro:>10.1f}{snore:>10.1f}"
              f"{deduction:>9.1f}{score:>6}{stored if stored is not None else '—':>6}{agree:>5}")

    rule()
    if deductions:
        lo, hi = min(deductions), max(deductions)
        print(f"總扣分範圍：{lo:.1f} ~ {hi:.1f}（相差 {hi / lo:.0f} 倍），"
              f"滿分只有 100 分可以扣。")
    print("\n主導項統計（哪一項在該筆貢獻最多扣分）：")
    for bucket in ("撞到地板（0 分）", "沒撞地板"):
        if dominant[bucket]:
            parts = "、".join(f"{k} {v} 筆" for k, v in dominant[bucket].most_common())
            print(f"    {bucket:<18} {parts}")
    print("""
  ⚠️ 沒有單一的「元兇項」，這正是問題所在：公式是事件數的線性函數，
     既不除以錄影時長、也不隨偵測靈敏度調整。偵測器吐幾千筆時 micro
     主導，timeline 被清理過只剩數十筆時 large 主導——**兩種情況下
     扣分都遠超過 100**，差別只在有沒有撞到地板。

  ⚠️ PROJECT_STATUS 3.8 ⑤ 寫「50 次大翻身就扣完 100 分」只描述了後一種情況，
     會讓人以為調整 large_turn 的係數就能修好。實際上係數不是問題，
     **尺度才是**——見表二與表五。

  ★ 「符合」欄幾乎全部打勾，本身就是一個結論：**現有 dump 是 V1 寫的**。
     V3（tapo/newsleep score count.py，08-27）寫好了但沒有套用到這份資料。""")
    if mismatches:
        print("\n  ⚠️ 重算與存檔不符：")
        for sid, stored, calc, events in mismatches:
            note = "（timeline 是空的，但 total_events 不是 0 —— " \
                   "就是 id 117 那個寫入端與統計端不同步的 bug）" if events == 0 else ""
            print(f"     {sid}：存檔 {stored}，重算 {calc} {note}")


# ═══════════════════════════════════════════════════════════════════
# 表二：同一晚、不同來源，分數差多少
# ═══════════════════════════════════════════════════════════════════

def table_divergence(index):
    print("\n\n【表二】同一晚在兩個來源會得到不同的分數")
    rule("=")
    print(f"{'夜晚':<12}{'落差':>6}  來源與分數（事件數）")
    rule()

    conflicts = [n for n in index.values() if n["score_disagreement"] > 0]
    for night in sorted(index.values(), key=lambda n: n["date"]):
        if night["score_disagreement"] == 0:
            continue
        parts = ", ".join(f"{sid.split('/')[-1]}={score}" for sid, score in night["scores"])
        print(f"{night['date']:<12}{night['score_disagreement']:>6}  {parts}")

    rule()
    if conflicts:
        worst = max(conflicts, key=lambda n: n["score_disagreement"])
        print(f"  最大落差：{worst['date']} 差 {worst['score_disagreement']} 分。")
    print("""
  為什麼會這樣：SQL dump 的 timeline 被 clean_timeline_data() 與
  MAX_TIMELINE_EVENTS 上限削過，每列只剩數十筆；per-night JSON 是原始的，
  動輒數千筆。扣分與事件數成正比，所以削過的沒撞地板、原始的一律歸零。

  → 這個分數是「timeline 有多長」的函數，而 timeline 長度取決於
    清理設定與哪一版程式寫的，**與睡眠無關**。

  ⚠️ 這比「分數恆為 0」嚴重：恆為 0 至少是誠實的無資訊；
     現在是同一晚可以是 80 也可以是 0，取決於你讀哪個檔。

  → 「削過」具體是怎麼削的，見表五。""")


# ═══════════════════════════════════════════════════════════════════
# 表三：decibel 是不是量出來的？（分世代看）
# ═══════════════════════════════════════════════════════════════════

def _decibel_stats(records):
    hist = Counter()
    by_level = defaultdict(Counter)
    for record in records:
        for event in record["timeline"]:
            db = event.get("decibel")
            if isinstance(db, int):
                hist[db] += 1
                by_level[event.get("sound_level")][db] += 1
    return hist, by_level


def table_decibel(records):
    print("\n\n【表三】decibel：一個世代是量出來的，另一個世代是亂數")
    rule("=")

    generations = [
        ("json", "JSON 世代（per-night 原始報告）"),
        ("sql", "SQL 世代（dump 裡的 timeline）"),
    ]

    for kind, label in generations:
        subset = [r for r in records if r["source_kind"] == kind]
        hist, by_level = _decibel_stats(subset)
        total = sum(hist.values())
        if not total:
            continue

        print(f"\n  ── {label}：{total} 筆事件，**{len(hist)} 個相異 dB 值**")
        for db in sorted(hist):
            pct = hist[db] / total * 100
            print(f"     {db:>3} dB  {hist[db]:>6}  {pct:>5.2f}%  {'█' * int(pct * 1.2)}")

        print("     sound_level 對應到的 decibel 範圍：")
        for level, counts in sorted(by_level.items(), key=lambda kv: -sum(kv[1].values())):
            keys = [k for k in counts if k is not None]
            if keys:
                print(f"       {str(level):<20} n={sum(counts.values()):>6}  "
                      f"decibel {min(keys)}–{max(keys)}")

        band = [hist[db] for db in range(35, 42) if db in hist]
        if len(band) >= 5 and sum(band) / total > 0.5:
            share = [c / sum(band) * 100 for c in band]
            print(f"\n     ★ 35–41 dB 這 {len(band)} 個值：筆數 {min(band)}–{max(band)}，"
                  f"band 內佔比 {min(share):.1f}%–{max(share):.1f}%"
                  f"（理想均勻 {100 / len(band):.1f}%），最多與最少只差 "
                  f"{max(band) / min(band):.3f} 倍。")
            print("       → 這是 np.random.randint(35, 42) 的形狀。真實環境音是連續且")
            print("         有結構的，不會在 7 個整數上等機率落點、也不會在 34 與 35 之間斷崖。")

    print("""
  → 兩個世代的形狀完全不同：JSON 世代只有十幾個相異值、`quiet` 等機率落在
    35–41、`breathing_heavy` 是一個常數；SQL 世代是連續遞減的分布。
    **前者是合成的，後者是真的量測。**
    所以 snore×0.4 這一項，在 JSON 世代扣的是亂數產生器。

  ⚠️ 就算在「真的有量」的世代，量的也不是聲壓：
     `db = 20*log10(rms)`（tapo 2.0/tapo_detector.py:779）是相對 int16
     最小刻度的 **dBFS**，天花板 20·log10(32768) = 90.3。
     門檻 30/40 看起來像 SPL 的「安靜圖書館」，實際上是 −60/−50 dBFS，
     完全取決於這台相機的麥克風增益。
     → 文獻對打呼的操作型定義是 **A 加權聲壓級（dBA）、麥克風固定床頭上方
       1 公尺**，常用門檻 ≥40 dBA。我們的數字與任何 dBA 門檻之間**沒有可
       建立的對應關係**，除非拿聲級計做校準。**校準之前，打呼不可計分。**

  ⚠️ 兩版的門檻還不一樣（tapo/ 是 20/30，tapo 2.0/ 是 30/40）——這就是
     SQL 世代裡 quiet 與 breathing_heavy 的 dB 區間會重疊的原因。

  ⚠️ 更正一則舊註解：先前這裡寫「現行程式根本不會產生 snoring_or_noise
     （sleep_monitor.py:881-885 只產生 quiet / medium / LOUD）」。**那是錯的。**
     881-885 那三行是 console 狀態列裡的區域變數 `sound_level`，不進 timeline。
     真正寫進事件的是 `current_sound_type`，設在
     tapo 2.0/tapo_detector.py:841-846 與 sleep_monitor.py:931-935，
     產生的正是 snoring_or_noise / breathing_heavy / quiet。""")


# ═══════════════════════════════════════════════════════════════════
# 表四：整畫面誤判到底佔多少
# ═══════════════════════════════════════════════════════════════════

def table_intensity(records):
    print("\n\n【表四】motion_intensity：整畫面誤判是局部問題，不是主因")
    rule("=")

    hist = Counter()
    full_by_level = Counter()
    level_total = Counter()
    for record in records:
        for event in record["timeline"]:
            value = event.get("motion_intensity")
            hist[value] += 1
            level = event.get("motion_level")
            level_total[level] += 1
            if value == FULL_FRAME_INTENSITY:
                full_by_level[level] += 1

    total = sum(hist.values())
    full = hist.get(FULL_FRAME_INTENSITY, 0)
    print(f"  相異值：{len(hist)} 個")
    print(f"  整畫面值 {FULL_FRAME_INTENSITY}（=1920×1080）：{full} / {total} 筆"
          f"（{full / total * 100:.2f}%）" if total else "  （無資料）")
    print(f"  零強度 0：{hist.get(0, 0)} 筆")
    print("\n  依 motion_level 拆：")
    for level, count in level_total.most_common():
        hit = full_by_level.get(level, 0)
        print(f"    {str(level):<16} {count:>6} 筆，其中整畫面 {hit:>4} 筆"
              f"（{hit / count * 100:>5.1f}%）")
    micro = level_total.get("micro_motion", 0)
    if total:
        print(f"\n  micro_motion 佔全部事件的 {micro / total * 100:.1f}%")
    print("""
  ⚠️ PROJECT_STATUS 目前寫「motion_intensity: 2073600 = 整畫面誤判」，
     讀起來像是所有事件都這樣。實測不是——整畫面誤判只出現在 large_turn，
     而且是其中的少數；佔全部事件不到 1%。

  → 真正撐起事件量的是 micro_motion（九成以上）。這才是要調的地方：
    它決定 timeline 有多長，而 timeline 長度決定分數（見表二）。
    整畫面誤判是另一個獨立的問題，值得修，但修了不會改變分數的行為。""")


# ═══════════════════════════════════════════════════════════════════
# 表五：偵測門檻逐晚在變，而且沒有記在資料裡
# ═══════════════════════════════════════════════════════════════════

def table_thresholds(records):
    print("\n\n【表五】偵測門檻逐晚漂移 —— 這才是「跨夜不可比較」的根因")
    rule("=")
    print(f"{'紀錄':<46}{'事件':>6}{'下限':>10}{'micro最大':>11}"
          f"{'large最小':>11}  推得的 micro/large 分界")
    rule()

    floors, boundaries = [], []
    for record in sorted(records, key=lambda r: (r["source_kind"], r["source_id"])):
        floor, micro_max, large_min = observed_thresholds(record["timeline"])
        if floor is None:
            continue
        floors.append(floor)
        if micro_max and large_min:
            bracket = f"{micro_max:,} ~ {large_min:,}"
            # ⚠️ large_min 若是整畫面值，那是偵測器誤判（表四），
            #    不是門檻，拿它估分界會把上界拉到 100 萬以上。
            if large_min != FULL_FRAME_INTENSITY:
                boundaries.append((micro_max + large_min) / 2)
        elif large_min:
            bracket = f"≤ {large_min:,}（沒有 micro 事件）"
        else:
            bracket = "—（沒有 large 事件）"
        print(f"{short(record['source_id']):<46}{record['total_events']:>6}"
              f"{floor:>10,}{(micro_max or 0):>11,}{(large_min or 0):>11,}  {bracket}")

    rule()
    print(f"  repo 現行預設（tapo 2.0/tapo_detector.py:24-26）："
          f"下限 {REPO_MIN_MOTION_AREA:,}、micro {REPO_MOTION_MICRO:,}、"
          f"large {REPO_MOTION_LARGE:,}")
    if floors:
        print(f"  資料裡實際出現過的下限：{min(floors):,} ~ {max(floors):,}"
              f"（相差 {max(floors) / min(floors):.1f} 倍）")
    if boundaries:
        print(f"  推得的分界：約 {min(boundaries):,.0f} ~ {max(boundaries):,.0f}")
    print("""
  ⚠️ 沒有任何一晚是用現在程式裡的設定錄的，而且門檻在夜與夜之間變過好幾組。
     **資料裡沒有任何欄位記著當晚用的是哪一組。**

  → 「一個事件」不是固定的單位。分數是事件數的線性函數，
    單位會變 → 分數跨夜不可比較，**這在原理上就不成立，不是調係數能修的**。""")

    _table_relabel_evidence(records)


def _table_relabel_evidence(records):
    """
    最直接的證據：SQL 那幾列不是重錄，是同一批事件被新門檻重貼標籤。

    做法：拿每一筆 SQL 列的下限，回頭去數同一晚的 JSON 原始報告裡
    有幾個事件的強度 ≥ 這個下限。數字相等 = 同一批事件。
    """
    sql_records = [r for r in records if r["source_kind"] == "sql"]
    json_records = [r for r in records if r["source_kind"] == "json"]
    if not sql_records or not json_records:
        return

    by_date = defaultdict(list)
    for record in json_records:
        by_date[str(record["report_date"])].append(record)

    rows = []
    for record in sql_records:
        floor, _, _ = observed_thresholds(record["timeline"])
        if floor is None:
            continue
        for source in by_date.get(str(record["report_date"]), []):
            above = sum(1 for e in source["timeline"]
                        if (e.get("motion_intensity") or 0) >= floor)
            rows.append((record["source_id"], record["total_events"],
                         short(source["source_id"]), source["total_events"],
                         floor, above))
    if not rows:
        return

    print("\n  ── 佐證：SQL 那幾列不是重錄，是同一批事件被新門檻重貼標籤")
    rule()
    print(f"  {'SQL 列':<10}{'其筆數':>7}   {'同夜的 JSON 報告':<44}"
          f"{'原始筆數':>9}{'≥下限':>7}{'吻合':>5}")
    rule()
    exact = 0
    for sid, sql_n, jid, json_n, floor, above in rows:
        agree = "✓" if above == sql_n else "✗"
        exact += above == sql_n
        print(f"  {sid:<10}{sql_n:>7}   {jid:<44}{json_n:>9}{above:>7}{agree:>5}")
    rule()
    print(f"  {exact} / {len(rows)} 組逐筆吻合。")
    print("""
  → 吻合表示：SQL 列裡的，正好就是 JSON 裡強度過得了新下限的那些事件。
    同一個物理夜晚，事後用哪一組門檻重跑 clean_timeline_data()，
    就得到不同的 motion_level 組成、因而不同的分數。
    這就是表二那 80 分落差的機制。

  ⚠️ 對不上的那幾組不是反證——那幾晚有多份錄影，配對是照 report_date 做的，
     而 report_date 本身已知會錯（所以 tapo_index 改用 video_clip 檔名）。""")


# ═══════════════════════════════════════════════════════════════════
# 表六：事件節奏 vs 文獻常模
# ═══════════════════════════════════════════════════════════════════

def table_cadence(records):
    print("\n\n【表六】事件節奏 vs 文獻常模 —— 偵測器吐出來的是不是生理訊號？")
    rule("=")
    print(f"  基準線① Montini 2024（video-PSG，50 名健康成人）："
          f"movement index 中位數 {MONTINI_MI_MEDIAN} 次/小時"
          f"（IQR {MONTINI_MI_IQR[0]}–{MONTINI_MI_IQR[1]}）")
    print(f"  基準線② De Koninck 1992（18–24 歲）："
          f"體位改變 {DEKONINCK_SHIFTS_PER_HOUR} 次/小時")
    rule()
    print(f"{'紀錄':<46}{'跨度h':>7}{'事件/h':>9}{'vs 常模':>9}"
          f"{'0秒間隔':>9}{'翻身/h':>8}{'vs 常模':>9}")
    rule()

    ratios = []
    excluded = []
    for record in sorted(records, key=lambda r: (r["source_kind"], r["source_id"])):
        span = timeline_span_hours(record["timeline"])
        if span < MIN_SPAN_HOURS:
            excluded.append((record, span))
            continue
        rate = record["total_events"] / span
        turn_rate = record["large_turn_count"] / span
        zero = zero_gap_share(record["timeline"])
        ratio = rate / MONTINI_MI_MEDIAN
        turn_ratio = turn_rate / DEKONINCK_SHIFTS_PER_HOUR
        ratios.append(rate)
        print(f"{short(record['source_id']):<46}{span:>7.2f}{rate:>9.1f}"
              f"{ratio:>8.1f}x{(zero * 100 if zero is not None else 0):>8.1f}%"
              f"{turn_rate:>8.1f}{turn_ratio:>8.1f}x")

    rule()
    if ratios:
        lo, hi = min(ratios), max(ratios)
        print(f"  事件率：{lo:.1f} ~ {hi:.1f} 次/小時"
              f"（= Montini 中位數的 {lo / MONTINI_MI_MEDIAN:.1f}x ~ "
              f"{hi / MONTINI_MI_MEDIAN:.1f}x）")
        inside = sum(1 for r in ratios if MONTINI_MI_IQR[0] <= r <= MONTINI_MI_IQR[1])
        print(f"  落在 IQR {MONTINI_MI_IQR[0]}–{MONTINI_MI_IQR[1]} 次/小時之內的："
              f"{inside} / {len(ratios)} 筆")
    if excluded:
        print(f"\n  排除 {len(excluded)} 筆（跨度 < {MIN_SPAN_HOURS} 小時，算不出有意義的率）。"
              f"排除的理由不只一種，分開標：")
        for record, span in excluded:
            events = record["total_events"]
            seconds = span * 3600
            if events == 0:
                reason = "timeline 是空的（total_events 卻不是 0 → 寫入端 bug）"
            elif seconds < events:
                # 平均每秒超過一個事件，物理上不可能是真的時刻
                reason = "`time` 欄位壞掉，不是真的只錄了那麼短"
            else:
                reason = "錄影本身就很短（tapo_index 的 sleep_recording_problem 也會擋）"
            print(f"    {short(record['source_id']):<46}"
                  f"{events:>6} 筆事件 / {seconds:>6.0f} 秒 → {reason}")
    print("""
  ⚠️ 「vs 常模」不是分數，也不是門檻——這支不評分。它是健全性檢查：
     人一小時動 11 次（中位數），偵測器一小時吐幾百次，
     那就不是在量身體。「0秒間隔」欄接近 100% 更直接：
     同一秒內多筆事件 = 偵測器幾乎每一幀都在觸發。

  ★ 值得注意的對比：**翻身率（large_turn）的量級是對的**，
     跟 De Koninck 的 3.6 次/小時同一個數量級。
     → micro_motion 是雜訊，large_turn 是訊號。要救的是後者。

  ⚠️ 跨度是用事件的 `time` 欄位算的，是**近似值**（`time` 已知會壞，
     所以 tapo_index 改用 video_clip 檔名）。要精確的時刻請用 tapo_index。

  ⚠️ 要把這兩條常模變成計分門檻，**必須先寫 Research-Background/攝影機分數.md**
     （紅線 2）。常模不等於門檻：文獻數的是人工判讀的動作，
     我們數的是像素面積過門檻的幀，兩者不是同一個東西，
     中間還缺一次效標驗證。""")


def main():
    records = tapo_index.iter_raw_records()
    if not records:
        sys.exit("✗ 找不到 TAPO 資料（tapo/sleep_records.sql 或 "
                 "tapo/sleep_reports/）。這些檔由影像組提供。")

    print("=" * 100)
    print("TAPO sleep_quality_score 根因分析")
    print(f"資料來源：{sum(1 for r in records if r['source_kind'] == 'sql')} 筆 SQL 列"
          f" + {sum(1 for r in records if r['source_kind'] == 'json')} 份 JSON 報告")
    print("=" * 100)

    table_breakdown(records)
    table_divergence(tapo_index.build_index(records))
    table_decibel(records)
    table_intensity(records)
    table_thresholds(records)
    table_cadence(records)

    print("\n" + "=" * 100)
    print("""結論（給報告用）

  1. sleep_quality_score 不可用於任何比較。它是 timeline 長度的函數，
     同一晚跨來源最大差 80 分。
  2. 再往下一層：timeline 長度取決於**當晚的偵測門檻**，而門檻逐晚變過
     好幾組、且沒有記在任何欄位裡（表五）。所以跨夜比較在原理上不成立——
     這不是調係數能修的。
  3. snore_count / decibel 在 JSON 世代是亂數；即使在有真的量測的世代，
     量的也是 dBFS 不是 dBA，與文獻的 ≥40 dBA 門檻無法對應。
  4. micro_motion 的事件率是文獻常模的數十倍，量的是感光雜訊不是身體；
     **large_turn 的量級則與 De Koninck 1992 相符**——那是唯一有救的訊號。
  5. 攝影機唯一可直接用的量測值是**事件的時刻**（來自 video_clip 檔名），
     它讓「上床時刻」變得可算 —— 而那正是手錶量不到的東西。

  → 修法在影像組那一端：micro_motion 的偵測門檻（MOTION_MICRO），
    外加把當晚的門檻與程式版本寫進每一筆紀錄。
  → 我們這一端：在 Research-Background/攝影機分數.md 寫好之前，
    不寫任何攝影機評分公式，也不調既有係數（紅線 2）。""")
    print("=" * 100)


if __name__ == "__main__":
    main()
