"""
compare_night_sources.py — 同一晚的四個時刻擺在一起，看它們差多少。

═══════════════════════════════════════════════════════════════════
這支要回答的問題
═══════════════════════════════════════════════════════════════════
「手機推出來的就寢時刻，比真正上床晚多少？」

D2 的受測者只有手機，所以 `lights_out_at`（最後一次放下手機）是他們唯一
的就寢時刻。它是**代理值**——問題是偏多少。要量這件事，就得有一晚同時
存在「另一個獨立的來源」，而那正是攝影機錄影的夜晚。

    [開始錄影]   [按開始睡覺]      [lights_out]        [攝影機測到入睡]
        │             │                 │                     │
      自述.攝影機   自述.手機        偵測.手機              偵測.攝影機

═══════════════════════════════════════════════════════════════════
⚠️ 四個時刻不是同一種東西，比錯了會得到沒有意義的數字
═══════════════════════════════════════════════════════════════════

| 比什麼 | 量到的是 | 有用嗎 |
|---|---|---|
| 自述上床 vs **lights_out_at** | **上床後滑手機多久**（不是量測誤差） | ✅ 見下 |
| 自述上床 vs 攝影機測到的入睡 | 入睡潛伏期 SOL | ✅ |
| 開始錄影 vs 按開始睡覺 | **你自己按得一不一致** | ⚠️ 只是資料品質檢查 |

最後一列特別要小心：兩邊**都是同一個人的自述**，只是兩種按法。
拿它們互比量到的不是儀器準不準，是使用者的操作一致性。
本支會把它標成「自述 vs 自述」，不要拿去當效標。

🔴 **第一列也要小心，而且原因不一樣**（2026-09-07 實測後修正的認知）：

    自述上床 → lights_out  ==  上床後滑手機的時間  ==  phone_in_bed_minutes

三者在代數上是**同一個數字**（實測 09-07：兩邊都是 48.4 分）。所以：

  · 它**不是量測誤差**。`lights_out_at` 不是「上床時刻的雜訊估計」，
    它是另一個構念：「你停止用手機的時刻」。兩者的差是**行為**，不是誤差。
  · 因此**不能拿它當固定偏移去校正 D2 的上床時刻**——實測兩晚是
    +3.4 與 +48.4 分鐘，差一個數量級，因為那本來就是每晚不同的行為。

→ D2 那條線真正該講的是：**只有 lights_out 的人，臥床時間會少算掉
  自己睡前滑手機的那一段，而那一段每晚都不一樣。** 這是限制的陳述，
  不是可以修正的偏差。

═══════════════════════════════════════════════════════════════════
⚠️ 這支**只讀不寫**
═══════════════════════════════════════════════════════════════════
- 直接以唯讀模式開 SQLite 檔，**不走 HTTP、不需要 user_id**。
  （這個 API 沒有認證，user_id 本身就是憑證——見 CLAUDE.md。
    寫入路徑才需要它，而這支不寫。）
- **不輸出 user_id。** 使用者用暱稱指定。
- 不動攝影機的 CSV、不動資料庫。

用法
────
  python compare_night_sources.py                       # 所有對得起來的夜晚
  python compare_night_sources.py --csv tapo_metrics/xxx.csv
  python compare_night_sources.py --db  C:/.../sonnap.db --user Nathan

資料庫路徑的預設值與後端一致（SONNAP_DB 環境變數，否則 db.py 旁邊那個）。
"""
import argparse
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "tapo_metrics"

import db as sonnap_db  # noqa: E402
import tapo_sleep_onset as onset  # noqa: E402
from behavior.adherence import night_date  # noqa: E402


def open_readonly(path):
    """
    唯讀開啟。用 URI 模式而不是「小心不要寫」——後者靠紀律，前者是
    結構上做不到：連線本身就不允許寫入，寫了會拋例外。
    """
    uri = f"file:{Path(path).as_posix()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def load_behavior(db_path, display_name=None):
    """回傳 {日期字串: row}。⚠️ 不回傳也不印 user_id。"""
    conn = open_readonly(db_path)
    try:
        if display_name:
            users = [r["user_id"] for r in conn.execute(
                "SELECT user_id FROM users WHERE display_name = ?", (display_name,))]
            if not users:
                names = [r["display_name"] for r in
                         conn.execute("SELECT display_name FROM users")]
                sys.exit(f"✗ 找不到暱稱 {display_name!r}。這個 DB 裡有：{names}")
        else:
            users = [r["user_id"] for r in conn.execute("SELECT user_id FROM users")]

        rows = {}
        for uid in users:
            for r in conn.execute(
                    "SELECT * FROM nightly_behavior WHERE user_id = ?", (uid,)):
                d = dict(r)
                d.pop("user_id", None)          # ⚠️ 憑證，不往下傳
                rows.setdefault(d["date"], d)
        return rows
    finally:
        conn.close()


def parse(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def naive(t):
    """把有無時區的時刻拉到同一個基準才減得動（本專案一律 +08:00）。"""
    return t.replace(tzinfo=None) if t and t.tzinfo else t


def delta_minutes(a, b):
    """b − a，分鐘。任一個缺就回 None。"""
    a, b = naive(a), naive(b)
    if a is None or b is None:
        return None
    return (b - a).total_seconds() / 60


def is_logger_csv(path):
    """
    這份 CSV 是 tapo_metric_logger 的輸出嗎？

    ⚠️ **看欄位，不要猜檔名。** tapo_metrics/ 裡還有標註檔、片段度量檔，
       它們也叫 .csv。先前是用檔名與檔案大小過濾，結果把 2026-09-07
       那晚（只錄到 25 分鐘）整個濾掉——而那正是最需要看的一晚。
    """
    try:
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("#"):
                    continue
                cols = {c.strip() for c in line.split(",")}
                return {"t", "max_px", "warmup"} <= cols
    except OSError:
        return False
    return False


def camera_nights(csv_paths):
    """跑 tapo_sleep_onset，回傳 {日期字串: 結果}。"""
    out = {}
    for p in csv_paths:
        if not is_logger_csv(p):
            continue
        r = onset.analyse(p)
        if "error" in r:
            continue
        start = parse(r["bed_start_at"])
        if start is None:
            continue
        out[night_date(start).isoformat()] = r
    return out


def pad(text, width):
    """
    依**顯示寬度**補空白。中文在終端機佔兩格，但 f-string 的 :<14
    數的是字元數 —— 直接用會讓中文那幾欄整排歪掉。
    """
    import unicodedata
    w = sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)
    return text + " " * max(width - w, 0)


def fmt_time(t):
    return "—" if t is None else naive(t).strftime("%H:%M:%S")


def fmt_delta(m, width=9):
    return f"{'—':>{width}}" if m is None else f"{m:+{width}.1f}"


def report(nights, behavior):
    print("=" * 96)
    print("同一晚的四個時刻")
    print("=" * 96)

    biases = []          # 自述上床 → lights_out（== 上床後滑手機，不是誤差）
    sols = []            # 自述上床 → 攝影機測到的入睡
    consistency = []     # 開始錄影 → 按開始睡覺（自述 vs 自述）

    matched = 0
    for date in sorted(nights):
        cam = nights[date]
        beh = behavior.get(date)
        cam_start = parse(cam["bed_start_at"])
        cam_onset = parse(cam["sleep_onset_at"])
        btn_start = parse(beh["bed_start_at"]) if beh else None
        lights = parse(beh["lights_out_at"]) if beh else None

        print(f"\n【{date}】")
        print(f"  {pad('開始錄影', 16)}{fmt_time(cam_start)}   [自述．攝影機]")
        print(f"  {pad('按開始睡覺', 16)}{fmt_time(btn_start)}   [自述．手機按鈕]")
        print(f"  {pad('lights_out', 16)}{fmt_time(lights)}   [偵測．手機]")
        if cam["sleep_onset_below_floor"]:
            print(f"  {pad('攝影機測入睡', 16)}≤ 開錄後 "
                  f"{cam['sleep_onset_floor_minutes']} 分鐘內   [偵測．低於下限]")
        else:
            print(f"  {pad('攝影機測入睡', 16)}{fmt_time(cam_onset)}   [偵測．攝影機]")

        if beh is None:
            print("  ⚠️ 這一晚資料庫裡沒有行為紀錄（App 沒上傳過）")
            continue
        matched += 1

        # 自述上床：手機按鈕優先（它就是為了這件事做的），沒有才退回開錄時刻
        declared = btn_start or cam_start
        declared_src = "按鈕" if btn_start else "開錄"

        print("  ── 差值 ──")
        b = delta_minutes(declared, lights)
        if b is not None:
            biases.append(b)
            print(f"  {pad(f'自述上床({declared_src}) → lights_out', 34)}"
                  f"{fmt_delta(b)} 分   ← 上床後滑手機（不是量測誤差）")
        s = delta_minutes(declared, cam_onset) if cam_onset else None
        if s is not None:
            sols.append(s)
            print(f"  {pad(f'自述上床({declared_src}) → 攝影機測入睡', 34)}"
                  f"{fmt_delta(s)} 分   ← 入睡潛伏期")
        elif cam["sleep_onset_below_floor"]:
            print(f"  {pad(f'自述上床({declared_src}) → 攝影機測入睡', 34)}"
                  f"{'≤' + str(cam['sleep_onset_floor_minutes']):>9} 分"
                  f"   ← 低於偵測下限，不給點估計")
        c = delta_minutes(cam_start, btn_start)
        if c is not None:
            consistency.append(c)
            print(f"  {pad('開始錄影 → 按開始睡覺', 34)}{fmt_delta(c)} 分"
                  f"   ⚠️ 自述 vs 自述，只是操作一致性")

    print("\n" + "=" * 96)
    print(f"彙總（{matched} 晚同時有攝影機與行為紀錄）")
    print("=" * 96)

    def summarise(label, vals, note):
        if not vals:
            print(f"  {pad(label, 26)}—（沒有可用的夜晚）")
            return
        mean = sum(vals) / len(vals)
        lo, hi = min(vals), max(vals)
        print(f"  {pad(label, 26)}n={len(vals)}  平均 {mean:+.1f} 分"
              f"（{lo:+.1f} ~ {hi:+.1f}）")
        print(f"  {' ' * 26}{note}")

    summarise("上床後滑手機", biases,
              "== phone_in_bed_minutes。**不是量測誤差，是行為**——"
              "每晚不同，不能當固定偏移去校正 D2 的上床時刻")
    summarise("入睡潛伏期", sols, "← 自述上床到攝影機測到入睡")
    summarise("按法的一致性", consistency,
              "⚠️ 兩邊都是自述，不是效標")

    print("""
⚠️ n 很小的時候不要寫進報告當結論。要寫的話寫成
   「n=X 晚，平均 +Y 分鐘」，不要寫成「手機的就寢時刻準確度是 Y 分鐘」——
   後者宣稱的是一個母體參數，而這是幾晚的樣本。

⚠️ 這支不寫任何東西。它是**唯讀**開啟資料庫的（mode=ro），
   所以連寫錯的可能性都沒有。""")
    print("=" * 96)


def main():
    ap = argparse.ArgumentParser(
        description="把同一晚的攝影機時刻與手機時刻擺在一起（唯讀，不評分）")
    ap.add_argument("--csv", type=Path, action="append",
                    help="指定攝影機 CSV，可重複。預設用 tapo_metrics/ 裡全部的")
    ap.add_argument("--db", type=Path, default=sonnap_db.DB_PATH,
                    help="SQLite 檔路徑（預設與後端一致）")
    ap.add_argument("--user", help="使用者暱稱。省略就看所有使用者")
    # ⚠️ 錄影檔在跑 logger 的那個目錄，而 tapo_metrics/ 是 gitignored，
    #    所以不會跟著 worktree 走。指到實際有檔案的地方。
    ap.add_argument("--metrics-dir", type=Path, default=OUT_DIR,
                    help="tapo_metrics/ 的位置（預設是本檔旁邊那個）")
    args = ap.parse_args()

    if not Path(args.db).exists():
        sys.exit(f"✗ 找不到資料庫 {args.db}\n"
                 "   後端跑在哪個 SONNAP_DB 上，這裡就要指同一個。")

    paths = args.csv or [
        p for p in sorted(args.metrics_dir.glob("*.csv"))
        if "selftest" not in p.name and "_truth" not in p.name
    ]
    # ⚠️ 不用檔案大小過濾。先前用 >500KB 擋掉短檔，結果把 2026-09-07
    #    那晚（串流 25 分鐘後斷掉）整個濾掉了——而那正是最需要看的一晚。
    #    短不短交給 analyse() 判（它要求 ≥100 個可用樣本），
    #    那是「資料夠不夠」的判準，檔案大小不是。
    if not paths:
        sys.exit(
            "✗ " + str(args.metrics_dir) + " 裡找不到整夜錄影 CSV。 "
            "錄影檔在跑 tapo_metric_logger.py 的那個目錄，"
            "用 --metrics-dir 指過去。")

    print(f"攝影機 CSV {len(paths)} 份、資料庫 {args.db}")
    nights = camera_nights(paths)
    if not nights:
        sys.exit("✗ 沒有一份 CSV 算得出上床時刻。")
    behavior = load_behavior(args.db, args.user)
    report(nights, behavior)


if __name__ == "__main__":
    main()
