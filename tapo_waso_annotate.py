"""
整夜影片的 WASO（入睡後清醒時間）人工標註 —— 出工作單、收工作單、算誤差。

═══════════════════════════════════════════════════════════════════════
為什麼需要這支
═══════════════════════════════════════════════════════════════════════
`behavior/sleep_efficiency.py` 算的「睡眠效率」有一個寫死的假設：
`WASO_MINUTES_ASSUMED = 0`——**假定半夜完全沒醒**。那是使用者知情之後
決定沿用的（沒有錶的受測者量不到 WASO），但它有一個方向相反的誤判：

    半夜醒著兩小時但沒碰手機 → 算出 99% 「良好」

這支是**唯一**能知道那個誤差有多大的路：拿整夜影片人工標出真正醒著的
時段，再回頭跟演算法算的比。沒有這個，我們只能說「可能有偏差」，
不能說偏差是 5 分鐘還是 120 分鐘——而報告裡那兩句話的份量完全不同。

═══════════════════════════════════════════════════════════════════════
⚠️ 標註規程：只看「動作提示」會系統性漏掉安靜的清醒
═══════════════════════════════════════════════════════════════════════
最省事的做法是「把偵測器覺得有動作的時段挑出來看」。那有兩個問題：

  ① **循環論證。** 拿偵測器的輸出去標註，再拿標註去驗偵測器，
     等於自己驗自己。
  ② **漏掉的正好是最重要的那一種。** 醒著躺著不動（想事情、失眠）
     不會觸發動作事件，永遠不會被提示到——而那正是手機那條路
     （lights_out）也量不到的同一種清醒。只看提示的話，兩邊會
     **一起錯、而且錯得一致**，看起來反而像互相驗證。

→ 所以工作單一定同時包含兩種列：
     proposed  偵測器提示的時段（省時間用）
     grid      每 N 分鐘一格的**均勻抽樣**（抓安靜的清醒用）
  只有 proposed 的工作單，`--score` 會拒收。

═══════════════════════════════════════════════════════════════════════
用法
═══════════════════════════════════════════════════════════════════════
  # ① 出工作單（看完影片之前先跑這個）
  python tapo_waso_annotate.py --plan tapo_metrics/20260909_0230.csv

  # ② 人工填 state 欄（asleep / awake / unclear），存檔

  # ③ 收工作單，算 WASO 與誤差
  python tapo_waso_annotate.py --score tapo_metrics/20260909_0230.csv \
      --worksheet tapo_metrics/20260909_0230_waso.csv

工作單的 `video_at` 是影片裡的秒數（不是牆鐘），可以直接拖到那個位置。
"""
import argparse
import csv
import sys
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

from tapo_metric_logger import read_roi, read_started            # noqa: E402
from tapo_scan_threshold import episodes                         # noqa: E402
from tapo_sleep_onset import MOTION_THRESHOLD                    # noqa: E402

FRAME_AREA = 640 * 360
CALIBRATION_ROI = (34, 129, 288, 231)

# 均勻抽樣的間隔。10 分鐘是取捨：整夜 8 小時 = 48 格，一格看 10 秒
# 約 8 分鐘看完；再密下去人會放棄，再疏下去 10 分鐘以下的清醒會漏掉。
# ⚠️ 這個間隔決定了 WASO 的**解析度下限**：抽樣間隔 10 分鐘，就不要宣稱
#    量得到 5 分鐘的清醒。
GRID_MINUTES = 10

# 提示用的門檻：連續這麼久的高事件率當成「可能醒著」。
# ⚠️ 這只是**導覽**，不是判定。判定一律以人看到的畫面為準。
PROPOSE_RATE_PER_HOUR = 36      # 與 tapo_sleep_onset 的 AWAKE_RATE_HINT 同源
PROPOSE_WINDOW_MINUTES = 10

STATES = ("asleep", "awake", "unclear")


def load_rows(path):
    """回傳 [(時刻, 佔比, 可用嗎, vf)]，暖機已排除。"""
    roi, _ = read_roi(path)
    scale = 1.0 if roi else (CALIBRATION_ROI[2] * CALIBRATION_ROI[3]) / FRAME_AREA
    out = []
    with path.open(encoding="utf-8") as fh:
        rows = csv.DictReader(l for l in fh if not l.startswith("#"))
        if not rows.fieldnames or "t" not in rows.fieldnames:
            return [], MOTION_THRESHOLD * scale
        for r in rows:
            if r.get("warmup") == "1":
                continue
            t = datetime.fromisoformat(r["t"])
            vf = int(r.get("vf") or -1)
            if r.get("illum_skip") == "1":
                out.append((t, 0.0, False, vf))
                continue
            px = int(r["roi_px"]) if roi else int(r["max_px"])
            area = roi[2] * roi[3] if roi else FRAME_AREA
            out.append((t, px / area, True, vf))
    return out, MOTION_THRESHOLD * scale


def video_path(csv_path):
    """同名的 .mp4。⚠️ 不能用 CSV 的 vf 欄判斷有沒有影片——**它照樣遞增**，
    不管當初有沒有加 --save-video。用檔案存不存在判斷才是事實。"""
    mp4 = csv_path.with_suffix(".mp4")
    return mp4 if mp4.exists() else None


def video_frames(mp4):
    """影片有幾幀。讀不到就回 None（不要因為這個讓整支掛掉）。"""
    try:
        import cv2
        cap = cv2.VideoCapture(str(mp4))
        n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()
        return n if n > 0 else None
    except Exception:
        return None


def video_seconds(rows, at, fps=5.0):
    """牆鐘時刻 → 影片裡的秒數。"""
    best = min(rows, key=lambda r: abs((r[0] - at).total_seconds()), default=None)
    if best is None or best[3] < 0:
        return None, None
    return best[3] / fps, best[3]


def propose(rows, threshold):
    """事件率持續偏高的時段——**只當導覽**，不是判定。"""
    starts = [e[0] for e in episodes([(t, f, u) for t, f, u, _ in rows], threshold)]
    if not rows:
        return []
    out, cur = [], None
    step = timedelta(minutes=PROPOSE_WINDOW_MINUTES)
    t = rows[0][0]
    end = rows[-1][0]
    while t < end:
        n = sum(1 for s in starts if t <= s < t + step)
        hot = n / (PROPOSE_WINDOW_MINUTES / 60) >= PROPOSE_RATE_PER_HOUR
        if hot and cur is None:
            cur = t
        elif not hot and cur is not None:
            out.append((cur, t))
            cur = None
        t += step
    if cur is not None:
        out.append((cur, end))
    return out


def plan(path):
    rows, threshold = load_rows(path)
    if not rows:
        sys.exit(f"✗ {path.name} 不是 logger 產的 CSV（沒有 t 欄）")

    started = read_started(path) or rows[0][0]
    end = rows[-1][0]
    hours = (end - rows[0][0]).total_seconds() / 3600
    hot = propose(rows, threshold)

    # 同一個時刻同時被提示與抽樣到時，只留一列（標成 both）——
    # 留兩列的話那一刻會被算兩次，而且人會以為要看兩遍。
    seen = {}
    for a, b in hot:
        seen[a] = ["proposed", f"事件率 >= {PROPOSE_RATE_PER_HOUR}/h，到 {b:%H:%M}"]
    t = rows[0][0]
    while t < end:
        if t in seen:
            seen[t][0] = "both"
        else:
            seen[t] = ["grid", ""]
        t += timedelta(minutes=GRID_MINUTES)
    checks = sorted((at, src, note) for at, (src, note) in seen.items())

    mp4 = video_path(path)
    frames = video_frames(mp4) if mp4 else None

    out = path.with_name(path.stem + "_waso.csv")
    if out.exists():
        sys.exit(f"✗ {out.name} 已經存在——不覆寫（裡面可能已經有人標好的東西）")
    no_frame = 0
    with out.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["# 每一列看影片的那個位置，填 state：" + " / ".join(STATES)])
        w.writerow(["# ⚠️ 先填完再跑 --score。看不清楚就填 unclear，不要猜"])
        w.writerow(["# ⚠️ grid 那些列**不可以跳過**——安靜的清醒只有它們抓得到"])
        w.writerow(["at", "video_at_seconds", "source", "state", "note"])
        for at, src, note in checks:
            vs, _ = video_seconds(rows, at)
            # ⚠️ 影片停了之後，CSV 的 vf 欄是**空字串**（不是超出範圍的數字）。
            #    用「vf >= 總幀數」判斷永遠是 False，會安靜地報 0 列沒畫面。
            if vs is None:
                no_frame += 1  # noqa: F823
                note = (note + "  " if note else "") + "⚠️ 沒有畫面（影片沒錄到這段）"
            w.writerow([at.isoformat(timespec="seconds"),
                        f"{vs:.0f}" if vs is not None else "", src, "", note])

    print(f"錄影   {started:%Y-%m-%d %H:%M} → {end:%H:%M}（{hours:.2f} 小時）")
    print(f"提示   {len(hot)} 段事件率偏高")
    print(f"均勻   每 {GRID_MINUTES} 分鐘一格")
    print(f"共     {len(checks)} 列要看")
    print()
    print(f"✓ 工作單 → {out}")
    print("  填完 state 欄之後跑：")
    print(f"    python {Path(__file__).name} --score {path} --worksheet {out}")
    print()
    if mp4 is None:
        print("⚠️ 這一晚**沒有影片**（找不到同名的 .mp4）。")
        print("   工作單照出，但沒有東西可以看——WASO 標註需要影片。")
        print("   錄的時候要加 --save-video <分鐘>，整夜就給足（例如 600）。")
    elif frames is None:
        print(f"影片   {mp4.name}（讀不到長度，自己確認涵蓋整夜）")
    else:
        covered = frames / 5.0 / 3600
        print(f"影片   {mp4.name}  {covered:.2f} 小時")
        if no_frame:
            print(f"⚠️ 影片只涵蓋 {covered:.2f} 小時，度量卻有 {hours:.2f} 小時——"
                  f"{len(checks)} 列裡有 {no_frame} 列沒有畫面可看。")
            print("   那些列已標註。WASO 只能算影片涵蓋的那一段，"
                  "不要把沒畫面的時間當成「睡著」。")


def score(csv_path, worksheet):
    rows, _ = load_rows(csv_path)
    if not rows:
        sys.exit(f"✗ {csv_path.name} 不是 logger 產的 CSV")

    marks = []
    with worksheet.open(encoding="utf-8") as fh:
        for r in csv.DictReader(l for l in fh if not l.startswith("#")):
            if not r.get("at"):
                continue
            marks.append((datetime.fromisoformat(r["at"]),
                          (r.get("source") or "").strip(),
                          (r.get("state") or "").strip().lower()))
    if not marks:
        sys.exit(f"✗ {worksheet.name} 裡沒有任何列")

    marks.sort(key=lambda m: m[0])
    blank = [m for m in marks if not m[2]]
    bad = [m for m in marks if m[2] and m[2] not in STATES]
    grid = [m for m in marks if m[1] == "grid"]

    print("=" * 74)
    print(f"WASO 人工標註  {worksheet.name}")
    print("=" * 74)
    print()
    if bad:
        sys.exit(f"✗ {len(bad)} 列的 state 不是 {STATES}，第一筆：{bad[0]}")
    if blank:
        sys.exit(f"✗ 還有 {len(blank)} 列沒填（共 {len(marks)} 列）。"
                 f"第一筆未填：{blank[0][0]:%H:%M}")
    if not grid:
        sys.exit("✗ 這份工作單沒有任何 grid 列。\n"
                 "   只看偵測器提示的時段會系統性漏掉『醒著但不動』——\n"
                 "   而那正是手機那條路也漏掉的同一種清醒，兩邊會一起錯。\n"
                 "   請用 --plan 重出工作單。")

    # 每一個標記代表它到下一個標記之間那段時間。
    total = timedelta()
    awake = timedelta()
    unclear = timedelta()
    awake_grid = timedelta()
    end = rows[-1][0]
    for i, (at, src, st) in enumerate(marks):
        nxt = marks[i + 1][0] if i + 1 < len(marks) else end
        span = nxt - at
        if span.total_seconds() <= 0:
            continue
        total += span
        if st == "awake":
            awake += span
            if src == "grid":
                awake_grid += span
        elif st == "unclear":
            unclear += span

    mins = lambda d: d.total_seconds() / 60
    print(f"標註涵蓋      {mins(total):7.1f} 分（{mins(total)/60:.2f} 小時）")
    print(f"標成 awake    {mins(awake):7.1f} 分  ← 這就是 WASO")
    print(f"標成 unclear  {mins(unclear):7.1f} 分")
    print()
    print(f"其中由**均勻抽樣**（不是偵測器提示）抓到的 awake：{mins(awake_grid):7.1f} 分")
    if awake.total_seconds() > 0:
        share = awake_grid / awake
        print(f"  佔全部 WASO 的 {share:.0%}")
        if share > 0.3:
            print("  → 偵測器提示漏掉的清醒佔比不小，"
                  "『用動作找清醒』這條路本身就有系統性偏誤")
    print()
    print("─" * 74)
    print("對 behavior/sleep_efficiency.py 的 WASO=0 假設，誤差有多大")
    print("─" * 74)
    if total.total_seconds() > 0:
        err = mins(awake) / mins(total) * 100
        print(f"  假設 WASO=0 會把睡眠效率**高估 {err:.1f} 個百分點**")
        print(f"  （臥床 {mins(total):.0f} 分裡有 {mins(awake):.0f} 分是醒著的）")
        if unclear.total_seconds() > 0:
            hi = (mins(awake) + mins(unclear)) / mins(total) * 100
            print(f"  把 unclear 全算成醒著的話是 {hi:.1f} 個百分點（上界）")
    print()
    print("  ⚠️ 這是**一晚**的誤差，不是常態。要寫進報告需要多晚。")
    print("  ⚠️ 這個數字不進任何評分，也不用來『修正』睡眠效率——")
    print("     WASO=0 是使用者知情後的決定，這裡量的是那個決定的代價。")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--plan", metavar="CSV", help="出工作單")
    ap.add_argument("--score", metavar="CSV", help="收工作單")
    ap.add_argument("--worksheet", metavar="CSV", help="--score 用：填好的工作單")
    args = ap.parse_args()

    if args.plan:
        plan(Path(args.plan))
    elif args.score:
        if not args.worksheet:
            sys.exit("✗ --score 要配 --worksheet")
        score(Path(args.score), Path(args.worksheet))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
