"""
tapo_sleep_onset.py — 從一晚的錄影度量算出：臥床時間、入睡時刻、入睡潛伏期。

═══════════════════════════════════════════════════════════════════
這支要回答的問題
═══════════════════════════════════════════════════════════════════
「躺下之後多久才睡著？」

這是本專案目前**完全缺席**的構念，而且是攝影機唯一能提供、手錶在原理上
提供不了的東西（手錶偵測「睡著」，量不到「上床」）。

    [開始錄影]                    [入睡]                    [收工]
         │                          │                          │
         ├──── 入睡潛伏期 SOL ──────┤                          │
         └────────────────── 臥床時間 TIB ──────────────────────┘

═══════════════════════════════════════════════════════════════════
⚠️ 兩端的可信度完全不同，所以每個欄位都標了來源
═══════════════════════════════════════════════════════════════════

| 欄位 | 來源 | 可信度 |
|---|---|---|
| 臥床起訖 | **自述**（開始錄影＝宣告上床） | 取決於使用者習慣 |
| 入睡時刻 | **偵測**（動作密度轉折） | ⚠️ n=2，未驗證 |

**臥床時刻不是攝影機量出來的。** 使用者是打算睡覺才去開攝影機，
所以「開始錄影」這個動作本身就是上床時刻的標記——不需要影像偵測，
但它的效度取決於習慣（開了錄影才去刷牙 → 高估；躺半小時才想起來開 → 低估）。
這等同臨床睡眠日誌（sleep diary），**寫進報告要標成自述，不能寫成「攝影機偵測」**。

入睡時刻則是真的偵測得到的。實測（2026-09-06，兩晚）：

    醒著躺在床上滑手機   40–96 次/小時
    睡著之後             12 次/小時      → 差 3.3~7.6 倍

實測對照（自述 = 使用者逐幀標註時說的「在此之前還沒睡著」）：

| | 自述 | 本支算出 | 差 |
|---|---|---|---|
| 第 3 晚 | 11.3 分 | **11.5 分** | **+0.2 分** |
| 第 6 晚 | 5.0 分 | ≤10 分（低於偵測下限，見 detect_onset） | — |

⚠️ 但**這不算驗證過**，三個理由：
   ① n=2，而且只有一晚的 SOL 高於偵測下限；
   ② 對照本身不精確 —— 「在此之前還沒睡著」是**上界**不是點估計；
   ③ 兩晚都是同一個人、同一個房間。
   真正的效標是同一晚 Garmin 的 sleep_start_time —— 見
   Research-Background/攝影機分數.md F 節第 3 關（目前只有 09-01 重疊，
   而那一晚是壞掉的偵測器錄的）。

═══════════════════════════════════════════════════════════════════
🔴 這支**刻意不輸出睡眠效率**
═══════════════════════════════════════════════════════════════════
效率 = 總睡眠 ÷ 臥床。分母有了（TIB），分子沒有——
總睡眠 = TIB − SOL − **WASO** − 最後醒來後躺著的時間，而 WASO 量不到。

實測（2026-09-06，第 6 晚）試過用同一套動作密度判準抓夜間清醒，
掃出來的三段全部**剛好卡在門檻上**（36 次/小時），而「醒著」的參考值
本身也才 40 —— margin 太小，分不開。

沒有 WASO 的話，同一晚可以是：

    WASO = 0  → 效率 98.6%（判讀「極佳」）
    WASO = 60 → 效率 81.3%（判讀「尚可」）

兩者與我們觀測到的東西**完全一致**，而 Ohayon 2017 的共識切點
（≥85% 良好、<75% 不良）正好落在這個範圍中間。給任何一個數字都是瞎猜。

→ 要行為版的效率（自述臥床 + lights_out，WASO 假定為 0）看
  `behavior/sleep_efficiency.py`。那一支有它自己的限制說明，
  **不要把這兩支的輸出混在一起**。

用法
────
  python tapo_sleep_onset.py                       # 用最新一份 CSV
  python tapo_sleep_onset.py tapo_metrics/xxx.csv
  python tapo_sleep_onset.py <csv> --json          # 只印 JSON，給程式吃
"""
import argparse
import csv
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "tapo_metrics"

from tapo_metric_logger import read_roi, row_frac, read_started  # noqa: E402
from tapo_scan_threshold import episodes  # noqa: E402

# ─── 偵測參數 ────────────────────────────────────────────────────
# 動作門檻：三晚人工標註定案的值（見 docs/TAPO_HANDOFF.md 那張表）。
MOTION_THRESHOLD = 0.0075          # 佔 ROI（沒有 ROI 時是佔畫面）

# 入睡判定：滑動 WINDOW 分鐘的事件率，第一次連續 HOLD 分鐘低於 RATE。
#
# ⚠️ 這三個數字是**偵測參數**不是計分門檻，靠效標校準、不受紅線 2 約束。
#    但它們現在只用 n=2 掃過（W/H/R 各試過 2–3 組），只能算試作。
#    掃過的組合（誤差 = 算出來 − 自述）：
#        W=10 H=10 R=20 → 第 3 晚 +0.2 分  ← 用這組
#        W=10 H=10 R=25 → 差不多
#        W=5  H=10 R=25 → 第 6 晚整個歪掉（視窗太短，單一空檔就騙得過去）
#    → 視窗不要縮。縮了會換來一個更糟的失敗模式：不是量不到，是量錯。
ONSET_WINDOW_MINUTES = 10
ONSET_HOLD_MINUTES = 10
ONSET_RATE_PER_HOUR = 20

# 「醒著」的參考線，只用來印診斷、不參與判定。
# 實測醒著躺床上滑手機是 40–96 次/小時。
AWAKE_RATE_HINT = 36


def load(path):
    """回傳 (samples, roi)。samples = [(時刻, 佔比, 可用嗎)]，暖機已排除。"""
    roi, _ = read_roi(path)
    with path.open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(l for l in fh if not l.startswith("#")))
    out = []
    for r in rows:
        if r.get("warmup") == "1":
            continue
        t = datetime.fromisoformat(r["t"])
        frac = row_frac(r, roi)
        out.append((t, 0.0, False) if frac is None else (t, frac, True))
    return out, roi


def event_starts(samples):
    """整夜的動作事件起點（datetime 列表）。"""
    return [e[0] for e in episodes(samples, MOTION_THRESHOLD)]


def rate_in(starts, begin, minutes):
    """[begin, begin+minutes) 這段的事件率（次/小時）。"""
    end = begin + timedelta(minutes=minutes)
    n = sum(1 for s in starts if begin <= s < end)
    return n / (minutes / 60)


def detect_onset(samples, starts):
    """
    找入睡時刻：第一次連續 HOLD 分鐘，滑動視窗的事件率都低於門檻。

    找不到就回 None —— 那代表整夜都很吵（可能根本沒睡，或偵測器有問題），
    **不要退回一個猜測值**。

    ⚠️ **這個方法有一個結構性的偵測下限：SOL 短於視窗長度就量不出來。**
       清醒期的事件會被攤進整個視窗。實測第 6 晚清醒 5 分鐘、3 個事件，
       攤進 10 分鐘視窗就是 18 次/小時 —— 壓不過 20 的門檻，於是判定
       在第 0 分鐘就成立，算出 SOL = 0。
       那個 0 **是假的**，真值是 5。所以呼叫端一定要看 below_floor
       （見 analyse()）：落在下限內時不給數字，只說「≤ 下限」。

       縮短視窗不是解法：實測 W=5 在第 6 晚會歪到 +9.7 分鐘
       （單一空檔就騙得過去）。這是取捨不是 bug。
    """
    if not samples:
        return None
    t0, t1 = samples[0][0], samples[-1][0]
    step = timedelta(minutes=2)
    hold = timedelta(minutes=ONSET_HOLD_MINUTES)
    cur = t0
    while cur + hold <= t1:
        probe = cur
        ok = True
        while probe <= cur + hold:
            if rate_in(starts, probe, ONSET_WINDOW_MINUTES) > ONSET_RATE_PER_HOUR:
                ok = False
                break
            probe += step
        if ok:
            return cur
        cur += step
    return None


def analyse(path):
    """回傳一個 dict —— 每個量都帶 provenance。"""
    samples, roi = load(path)
    if len(samples) < 100:
        return {"error": "not enough usable samples", "csv": path.name}

    # ⚠️ 臥床起點是**開始錄影**的時刻，不是第一列可用資料的時刻。
    #    暖機那 90 秒人已經躺在床上了，算掉的話 SOL 會少 1.5 分鐘 ——
    #    而 SOL 本身可能才幾分鐘，那個誤差不是小數點後的問題。
    t0 = read_started(path) or samples[0][0]
    t1 = samples[-1][0]
    tib_min = (t1 - t0).total_seconds() / 60
    starts = event_starts(samples)
    onset = detect_onset(samples, starts)

    # 落在偵測下限內 → 不給數字。報一個 0 會被當成「躺下就睡著」，
    # 而真值可能是 5 分鐘（實測第 6 晚就是這樣）。
    sol = (onset - t0).total_seconds() / 60 if onset else None
    below_floor = sol is not None and sol < ONSET_HOLD_MINUTES

    result = {
        "csv": path.name,
        "roi": list(roi) if roi else None,
        "motion_threshold_pct_of_roi" if roi else "motion_threshold_pct_of_frame":
            MOTION_THRESHOLD * 100,

        "bed_start_at": t0.isoformat(),
        "bed_end_at": t1.isoformat(),
        "time_in_bed_minutes": round(tib_min, 1),
        # ⚠️ provenance 必須跟著數字走。少了它，讀的人會以為臥床時刻
        #    也是攝影機量出來的。
        "bed_times_provenance": "SELF_REPORTED_recording_start_stop",

        "sleep_onset_at": None if (onset is None or below_floor) else onset.isoformat(),
        # ⚠️ 落在下限內時這裡是 None **不是 0** —— 見 detect_onset() 的說明。
        "sleep_onset_latency_minutes": (
            None if (sol is None or below_floor) else round(sol, 1)),
        "sleep_onset_below_floor": below_floor,
        "sleep_onset_floor_minutes": ONSET_HOLD_MINUTES,
        "sleep_onset_provenance": "DETECTED_motion_density__n2_unvalidated",

        # 這一行是刻意的，不是遺漏。理由見檔頭。
        "sleep_efficiency": None,
        "sleep_efficiency_note": (
            "Deliberately not computed: WASO is not measurable, so total sleep "
            "time is unknown. See the module docstring."
        ),
        "events_total": len(starts),
        "events_per_hour": round(len(starts) / (tib_min / 60), 1) if tib_min else None,
    }
    if onset and not below_floor:
        pre = (onset - t0).total_seconds() / 60
        post = (t1 - onset).total_seconds() / 60
        result["rate_before_onset"] = (
            round(sum(1 for s in starts if s < onset) / (pre / 60), 1) if pre >= 2 else None)
        result["rate_after_onset"] = (
            round(sum(1 for s in starts if s >= onset) / (post / 60), 1) if post >= 2 else None)
    return result


def report(r):
    def line(label, value, prov=None):
        v = "—" if value is None else value
        print(f"  {label:<22}{v}" + (f"    [{prov}]" if prov else ""))

    print("=" * 88)
    print(f"入睡潛伏期：{r['csv']}")
    print("=" * 88)
    if "error" in r:
        print(f"✗ {r['error']}")
        return

    if r["roi"]:
        print(f"  ROI {tuple(r['roi'])}，動作門檻 "
              f"{r['motion_threshold_pct_of_roi']:.2f}% 佔 ROI")
    else:
        print(f"  沒有 ROI，動作門檻 {r['motion_threshold_pct_of_frame']:.2f}% 佔畫面")
    print()
    line("上床（開始錄影）", r["bed_start_at"], "自述")
    line("下床（收工）", r["bed_end_at"], "自述")
    line("臥床時間", f"{r['time_in_bed_minutes']:.0f} 分鐘 "
                    f"（{r['time_in_bed_minutes'] / 60:.2f} 小時）", "自述")
    print()
    if r["sleep_onset_below_floor"]:
        line("入睡時刻", f"≤ 開始後 {r['sleep_onset_floor_minutes']} 分鐘內",
             "偵測．低於下限")
        line("入睡潛伏期 SOL", f"≤ {r['sleep_onset_floor_minutes']} 分鐘（不是 0）",
             "偵測．低於下限")
    else:
        line("入睡時刻", r["sleep_onset_at"], "偵測．n=2 未驗證")
        line("入睡潛伏期 SOL", (f"{r['sleep_onset_latency_minutes']:.0f} 分鐘"
                              if r["sleep_onset_latency_minutes"] is not None else None),
             "偵測．n=2 未驗證")
    print()
    line("整夜事件數", r["events_total"])
    line("事件率", f"{r['events_per_hour']} 次/小時")

    if r.get("rate_before_onset") is not None:
        print()
        print("  【診斷】入睡前後的事件率對比 —— 這是判定站不站得住的唯一內部證據")
        print(f"    入睡前 {r['rate_before_onset']:>6.1f} 次/小時"
              f"（醒著躺床上滑手機實測 40–96）")
        print(f"    入睡後 {r['rate_after_onset']:>6.1f} 次/小時（睡著實測約 12）")
        if r["rate_after_onset"]:
            ratio = r["rate_before_onset"] / r["rate_after_onset"]
            print(f"    比值   {ratio:>6.1f}x", end="  ")
            if ratio >= 2.5:
                print("✓ 分得開，這個判定看起來站得住")
            else:
                print("⚠️ **分不開** —— 這一晚的入睡時刻不可信，不要引用")

    if r["sleep_onset_below_floor"]:
        print()
        print(f"  ⚠️ **SOL 低於偵測下限（{ONSET_HOLD_MINUTES} 分鐘），所以不給數字。**")
        print("     清醒期比判定視窗短的時候，那幾個事件會被攤進整個視窗、")
        print("     壓不過門檻，判定就會在第 0 分鐘成立。實測第 6 晚清醒 5 分鐘")
        print("     卻算出 0 —— 那個 0 是假的。縮短視窗會讓別的夜晚歪掉，")
        print("     所以這是取捨不是 bug。")
    elif r["sleep_onset_at"] is None:
        print()
        print("  ⚠️ 找不到入睡時刻：整夜都沒有出現連續 "
              f"{ONSET_HOLD_MINUTES} 分鐘的安靜期。")
        print("     可能是這一晚根本沒睡，或門檻／ROI 不適用於這一晚。")

    print()
    print("  ⚠️ **沒有睡眠效率**，那是刻意的：WASO 量不到，所以總睡眠時間未知。")
    print("     同一晚 WASO=0 給 98.6%、WASO=60 給 81.3%，而共識切點就在中間。")
    print("     行為版的效率（假定 WASO=0）在 behavior/sleep_efficiency.py，")
    print("     兩者不要混用。")
    print("=" * 88)


def main():
    ap = argparse.ArgumentParser(description="從錄影度量算入睡潛伏期（不評分）")
    ap.add_argument("csv", nargs="?", type=Path)
    ap.add_argument("--json", action="store_true", help="只印 JSON")
    args = ap.parse_args()

    path = args.csv
    if path is None:
        files = sorted(OUT_DIR.glob("*.csv"), key=lambda p: p.stat().st_mtime)
        files = [f for f in files if "selftest" not in f.name
                 and "_truth" not in f.name] or files
        if not files:
            sys.exit("✗ tapo_metrics/ 裡沒有 CSV。先跑 tapo_metric_logger.py。")
        path = files[-1]
    if not path.exists():
        sys.exit(f"✗ 找不到 {path}")

    r = analyse(path)
    if args.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
    else:
        report(r)


if __name__ == "__main__":
    main()
