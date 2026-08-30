"""
inspect_tapo_score.py — TAPO `sleep_quality_score` 到底在量什麼？

═══════════════════════════════════════════════════════════════════
這一支要回答的問題
═══════════════════════════════════════════════════════════════════
「為什麼攝影機的分數是 0？」

答案不是「因為使用者睡得很差」，也不只是「因為分數撞到地板」。
實測結論是：**這個分數量的是 timeline 有多長，不是睡得好不好。**

⚠️ 這支**不做任何評分**，只重現影像組的公式並把扣分逐項拆開，
   所以不受「遊戲化層不得回寫評分層」那條紅線影響。

⚠️ 它也**不修改任何檔案**。影像組送新 dump 之後直接再跑一次即可，
   不要照抄輸出的數字——那是跑的當下那份檔的結果。

執行：python inspect_tapo_score.py
"""
import sys
from collections import Counter, defaultdict

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
LARGE_WEIGHT = 2.0
MICRO_WEIGHT = 0.1
SNORE_WEIGHT = 0.4
RESCUE_EVENT_THRESHOLD = 20
RESCUE_LARGE_WEIGHT = 3

FULL_FRAME_INTENSITY = 1920 * 1080   # 2073600：整個畫面都在動 = 偵測器誤判


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
     **尺度才是**——見表二。""")
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
     現在是同一晚可以是 80 也可以是 0，取決於你讀哪個檔。""")


# ═══════════════════════════════════════════════════════════════════
# 表三：decibel 是不是量出來的？
# ═══════════════════════════════════════════════════════════════════

def table_decibel(records):
    print("\n\n【表三】decibel 直方圖 —— 均勻分布是 np.random 的指紋")
    rule("=")

    hist = Counter()
    by_level = defaultdict(Counter)
    for record in records:
        for event in record["timeline"]:
            db = event.get("decibel")
            if isinstance(db, int):
                hist[db] += 1
                by_level[event.get("sound_level")][db] += 1

    total = sum(hist.values())
    if not total:
        print("  （沒有 decibel 資料）")
        return

    for db in sorted(hist):
        pct = hist[db] / total * 100
        print(f"  {db:>3} dB  {hist[db]:>6}  {pct:>5.2f}%  {'█' * int(pct * 1.5)}")

    rule()
    print(f"  總計 {total} 筆事件\n")
    print("  sound_level 對應到的 decibel 範圍：")
    for level, counts in sorted(by_level.items(), key=lambda kv: -sum(kv[1].values())):
        keys = [k for k in counts if k is not None]
        if keys:
            print(f"    {str(level):<20} n={sum(counts.values()):>6}  decibel {min(keys)}–{max(keys)}")
    print("""
  ⚠️ 這些範圍**彼此重疊**（quiet 與 snoring_or_noise 有共同的 dB 值），
     所以 sound_level 不是同一組門檻算出來的 —— 兩個來源用的是不同版本的
     音訊邏輯。這本身就是 3.3「六份版本」的證據。""")

    quiet_band = [hist[db] for db in range(35, 42) if db in hist]
    if len(quiet_band) >= 5:
        share = [c / sum(quiet_band) * 100 for c in quiet_band]
        print(f"\n  ★ 關鍵證據：35–41 dB 這 {len(quiet_band)} 個值")
        print(f"     筆數 {min(quiet_band)}–{max(quiet_band)}，"
              f"band 內佔比 {min(share):.1f}%–{max(share):.1f}%"
              f"（理想均勻是 {100 / len(quiet_band):.1f}%）")
        print(f"     最多與最少只差 {max(quiet_band) / min(quiet_band):.3f} 倍。")
        print("     → 這是 np.random.randint 的形狀。真實環境音是連續且有結構的，")
        print("       不會在 7 個整數值上等機率落點、也不會在 34 dB 與 35 dB 之間斷崖。")
    print("""
  → snore_count 數的是 sound_level == "snoring_or_noise" 的次數，
    而該欄位建立在這組亂數之上。所以 snore×0.4 這一項扣的不是打鼾。

  ⚠️ 現行程式根本不會產生 "snoring_or_noise" 這個字串
     （sleep_monitor.py:881-885 只產生 quiet / medium / LOUD）
     → 資料是舊版程式寫的，與現行程式對不上。""")


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

    print("\n" + "=" * 100)
    print("""結論（給報告用）

  1. sleep_quality_score 不可用於任何比較。它是 timeline 長度的函數，
     同一晚跨來源最大差 80 分。
  2. snore_count / decibel 是 np.random 產生的，不是量測值。
  3. large_turn / micro_motion 是真的偵測結果，但**跨夜不可比較**
     ——事件數取決於偵測門檻與清理設定，那些在不同錄影之間變過。
  4. 攝影機唯一可直接用的量測值是**事件的時刻**（來自 video_clip 檔名），
     它讓「上床時刻」變得可算 —— 而那正是手錶量不到的東西。

  → 修法在影像組那一端：micro_motion 的偵測門檻（MOTION_MICRO）。
    一晚 7000+ 個 micro_motion 不是生理現象。""")
    print("=" * 100)


if __name__ == "__main__":
    main()
