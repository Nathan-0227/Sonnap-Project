"""
tests/test_sleep_onset.py

守的是 `tapo_sleep_onset.py` 那三個**壞掉時不會報錯**的機制。

這支算出來的都是「看起來很合理的分鐘數」——量錯了不會拋例外，
只會讓入睡潛伏期差幾分鐘，而 SOL 本身可能才五分鐘。

  【1】臥床起點取自檔頭的 started=，不是第一列可用資料
      （暖機那 90 秒人已經在床上了。用錯少算 1.5 分鐘，
        而那個誤差會整個吃進 SOL）
  【2】SOL 低於偵測下限時**不給數字**，不是給 0
      （實測第 6 晚清醒 5 分鐘卻算出 0 —— 報 0 會被讀成「躺下就睡著」）
  【3】刻意不輸出睡眠效率（WASO 量不到，分子就湊不出來）

三條都用「把 bug 重新引入、確認測試會紅」驗證過。

⚠️ 這支需要 tapo_metrics/ 裡有錄影 CSV。那個目錄是 gitignored，
   所以在沒有資料的機器上會**跳過**而不是失敗。

執行：python tests/test_sleep_onset.py
"""
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import tapo_sleep_onset as onset  # noqa: E402
from tapo_metric_logger import read_started  # noqa: E402

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<50} 得到 {got!r:<24} 期望 {want!r}")
    if not ok:
        fails.append(label)


def check_true(label, got, note=""):
    print(f"  {'✓' if got else '✗'} {label}" + (f"  {note}" if note else ""))
    if not got:
        fails.append(label)


print("=" * 92)
print("tapo_sleep_onset.py")
print("=" * 92)

# ── 【1】臥床起點 —— 用合成檔頭測，不依賴真實錄影 ────────────────
print("\n【1】臥床起點取自檔頭的 started=，不是第一列可用資料")
import tempfile
tmp = Path(tempfile.mkdtemp()) / "hdr.csv"
tmp.write_text(
    "# tapo_metric_logger  started=2026-09-06T06:10:40.937763\n"
    "# size=640x360 fps=5.0\n"
    "# roi=full\n"
    "t,mean,raw_px,fg_px,blobs,max_px,max_x,max_y,max_w,max_h,illum_skip,warmup,vf\n",
    encoding="utf-8")
check("read_started 讀得出檔頭的時刻", read_started(tmp),
      datetime(2026, 9, 6, 6, 10, 40, 937763))
no_hdr = Path(tempfile.mkdtemp()) / "nohdr.csv"
no_hdr.write_text("# size=640x360\nt,mean\n", encoding="utf-8")
check("檔頭沒有 started= 時回 None（呼叫端才好退回第一列）",
      read_started(no_hdr), None)

# ── 用真實錄影驗其餘兩條 ─────────────────────────────────────────
metrics = ROOT / "tapo_metrics"
real = sorted((p for p in metrics.glob("*.csv")
               if "selftest" not in p.name and "_truth" not in p.name
               and p.stat().st_size > 500_000),
              key=lambda p: p.stat().st_mtime) if metrics.exists() else []

if not real:
    print("\n⚠️ tapo_metrics/ 裡沒有整夜錄影 CSV，跳過【2】【3】。")
    print("   （那個目錄是 gitignored，所以這在別人的機器上是正常的。）")
else:
    path = real[-1]
    print(f"\n用最新一份整夜錄影：{path.name}")
    r = onset.analyse(path)

    started = read_started(path)
    check("bed_start_at 等於檔頭的 started=", r["bed_start_at"], started.isoformat())
    # 反向對照：第一列可用資料**晚於**開始錄影（因為暖機被排除）。
    # 沒有這一條，就算 bed_start 取錯了，上面那條也可能碰巧通過。
    samples, _ = onset.load(path)
    check_true("第一列可用資料確實晚於開始錄影（證明兩者真的不同）",
               samples[0][0] > started,
               f"差 {(samples[0][0] - started).total_seconds():.0f} 秒")

    print("\n【2】低於偵測下限時不給數字")
    if r["sleep_onset_below_floor"]:
        check("低於下限 → latency 是 None 不是 0",
              r["sleep_onset_latency_minutes"], None)
        check("低於下限 → onset 時刻也是 None", r["sleep_onset_at"], None)
        check_true("但下限本身要說得出來", r["sleep_onset_floor_minutes"] > 0,
                   f"{r['sleep_onset_floor_minutes']} 分鐘")
    else:
        check_true("高於下限 → latency 有值",
                   r["sleep_onset_latency_minutes"] is not None,
                   f"{r['sleep_onset_latency_minutes']} 分鐘")
        check_true("而且必須 ≥ 下限（否則 below_floor 的判斷反了）",
                   r["sleep_onset_latency_minutes"] >= r["sleep_onset_floor_minutes"])

    print("\n【3】刻意不輸出睡眠效率")
    check("sleep_efficiency 必須是 None", r["sleep_efficiency"], None)
    check_true("而且要說得出為什麼（不是欄位忘了填）",
               "WASO" in (r["sleep_efficiency_note"] or ""))
    check_true("每個量都帶 provenance",
               r["bed_times_provenance"].startswith("SELF_REPORTED")
               and r["sleep_onset_provenance"].startswith("DETECTED"))

# ═══════════════════════════════════════════════════════════════════
print()
if fails:
    print(f"✗ {len(fails)} 條未通過：")
    for label in fails:
        print(f"    - {label}")
    sys.exit(1)
print("✓ 全部通過")
