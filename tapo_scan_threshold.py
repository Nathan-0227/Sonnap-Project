"""
tapo_scan_threshold.py — 拿 tapo_metric_logger 的 CSV 掃門檻，不評分。

═══════════════════════════════════════════════════════════════════
這支要回答的問題
═══════════════════════════════════════════════════════════════════
「動作門檻該設多少？」

舊做法是拍腦袋訂一個像素數（350000、250000、150000…），每晚還不一樣。
這支反過來：把門檻當自變數掃過去，看哪一個會讓**每小時事件數**落進
文獻常模。這是用資料校準，不是猜。

⚠️ 這是**偵測門檻**不是計分門檻。偵測門檻靠效標校準（文獻常模、
   影片人工標註），不受「每一項計分都必須有文獻門檻」那條紅線約束；
   紅線管的是「一小時動幾次算睡得差」那一類。兩者不要混。
   → 見 TAPO_HANDOFF「偵測門檻 ≠ 計分門檻」。

⚠️ 這支**不評分、不寫任何檔案**，只讀 CSV 印表。

═══════════════════════════════════════════════════════════════════
一次動作怎麼算（TAPO_HANDOFF「一次動作 = 一段」那一節）
═══════════════════════════════════════════════════════════════════
不是「這一幀有沒有超過門檻」，而是：

    連續 START_FRAMES 幀超過門檻   → 一段動作開始
    連續 END_FRAMES  幀低於門檻   → 這一段結束

一段 = 一個事件，帶起訖與持續時間。舊程式數的是「有多少幀在動」，
所以一晚會數出 7000 多筆；文獻數的是「動了幾次」。

用法
────
  python tapo_scan_threshold.py                      # 用最新一份 CSV
  python tapo_scan_threshold.py tapo_metrics/xxx.csv
"""
import csv
import statistics
import sys
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "tapo_metrics"

# ─── 文獻常模（只當基準線，不是門檻）────────────────────────────────
# Montini A, Loddo G, Zenesini C, Mainieri G, Baldelli L, Mignani F,
# Mondini S, Provini F. Physiological movements during sleep in healthy
# adults across all ages. Sleep. 2024;47(9):zsae138. doi:10.1093/sleep/zsae138
# 50 名健康成人的**錄影** PSG —— 模態與我們相同。
MONTINI_MEDIAN = 11            # 次/小時
MONTINI_IQR = (8, 15)
MONTINI_DURATION_MEDIAN = 4.0  # 秒
#
# De Koninck J, Lorrain D, Gagnon P. Sleep positions and position shifts in
# five age groups. Sleep. 1992;15(2):143-149. 18-24 歲：3.6 次/小時。
DEKONINCK_SHIFTS = 3.6

# ─── 事件聚合參數 ───────────────────────────────────────────────────
START_FRAMES = 3     # 連續幾幀超過門檻才算開始（濾掉瞬間閃動）
END_FRAMES = 15      # 連續幾幀安靜才算結束（同一次翻身不被切成兩段）

FRAME_AREA = 640 * 360


def load(path):
    """讀 CSV，回傳按時間排序的 (時刻, 最大區塊佔比, 可用嗎)。"""
    with path.open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(l for l in fh if not l.startswith("#")))
    out = []
    for r in rows:
        if r["warmup"] == "1":
            continue                      # 背景模型還沒建好，整段丟掉
        t = datetime.fromisoformat(r["t"])
        if r["illum_skip"] == "1" or not r["max_px"]:
            out.append((t, 0.0, False))   # 照明否決：保留時間軸，但不算在動
        else:
            out.append((t, int(r["max_px"]) / FRAME_AREA, True))
    return out


def episodes(samples, threshold, start_frames=START_FRAMES, end_frames=END_FRAMES):
    """把逐幀的「有沒有超過門檻」聚合成一段一段的動作。"""
    found = []
    motion_run = quiet_run = 0
    in_ep = False
    ep_start = ep_peak = None
    last_moving_t = None

    for t, frac, usable in samples:
        moving = usable and frac >= threshold
        if moving:
            quiet_run = 0
            last_moving_t = t
            if in_ep:
                ep_peak = max(ep_peak, frac)
            else:
                motion_run += 1
                if motion_run >= start_frames:
                    in_ep, ep_start, ep_peak = True, t, frac
        else:
            motion_run = 0
            if in_ep:
                quiet_run += 1
                if quiet_run >= end_frames:
                    found.append((ep_start,
                                  (last_moving_t - ep_start).total_seconds(),
                                  ep_peak))
                    in_ep = False
    if in_ep:
        found.append((ep_start, (last_moving_t - ep_start).total_seconds(), ep_peak))
    return found


def rule(ch="-", n=92):
    print(ch * n)


def main():
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    else:
        files = sorted(OUT_DIR.glob("*.csv"), key=lambda p: p.stat().st_mtime)
        files = [f for f in files if "selftest" not in f.name] or files
        if not files:
            sys.exit("✗ tapo_metrics/ 裡沒有 CSV。先跑 tapo_metric_logger.py。")
        path = files[-1]

    samples = load(path)
    if len(samples) < 100:
        sys.exit("✗ 有效樣本太少。")
    hours = (samples[-1][0] - samples[0][0]).total_seconds() / 3600
    fps = len(samples) / max((samples[-1][0] - samples[0][0]).total_seconds(), 1)

    print("=" * 92)
    print(f"門檻掃描：{path.name}")
    print(f"樣本 {len(samples)} 幀 / {hours:.2f} 小時（實際 {fps:.2f} 幀/秒）")
    print(f"事件定義：連續 {START_FRAMES} 幀超過門檻開始、"
          f"連續 {END_FRAMES} 幀（≈{END_FRAMES / fps:.1f} 秒）安靜結束")
    print("=" * 92)

    print(f"\n基準線① Montini 2024（video-PSG）：{MONTINI_MEDIAN} 次/小時"
          f"（IQR {MONTINI_IQR[0]}–{MONTINI_IQR[1]}），持續時間中位數 "
          f"{MONTINI_DURATION_MEDIAN} 秒")
    print(f"基準線② De Koninck 1992（18–24 歲體位改變）：{DEKONINCK_SHIFTS} 次/小時")

    print(f"\n{'門檻(佔畫面)':<14}{'事件數':>7}{'次/小時':>9}{'vs Montini':>12}"
          f"{'時長中位數':>11}{'時長p90':>9}{'峰值中位數':>11}  判讀")
    rule()

    grid = [0.2, 0.3, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.5, 10.0, 15.0, 20.0]
    hits = []
    for pct in grid:
        eps = episodes(samples, pct / 100)
        rate = len(eps) / hours
        if not eps:
            print(f"{pct:>6.2f}%{'':<7}{0:>7}{0:>9.1f}{'—':>12}{'—':>11}{'—':>9}{'—':>11}")
            continue
        durs = sorted(e[1] for e in eps)
        peaks = sorted(e[2] for e in eps)
        med = statistics.median(durs)
        p90 = durs[int(len(durs) * 0.9)]
        in_band = MONTINI_IQR[0] <= rate <= MONTINI_IQR[1]
        if in_band:
            hits.append((pct, rate, med, len(eps)))
        verdict = "★ 落在 IQR 內" if in_band else (
            "偏高" if rate > MONTINI_IQR[1] else "偏低")
        print(f"{pct:>6.2f}%{'':<7}{len(eps):>7}{rate:>9.1f}"
              f"{rate / MONTINI_MEDIAN:>11.2f}x{med:>10.1f}s{p90:>8.1f}s"
              f"{statistics.median(peaks) * 100:>10.2f}%  {verdict}")

    rule()
    if hits:
        print(f"\n★ 落在 Montini IQR（{MONTINI_IQR[0]}–{MONTINI_IQR[1]} 次/小時）"
              f"的門檻有 {len(hits)} 個：")
        for pct, rate, med, n in hits:
            dur_ok = "✓" if 2 <= med <= 8 else "✗"
            print(f"    {pct:>5.2f}% 畫面 → {rate:>5.1f} 次/小時、{n} 個事件、"
                  f"時長中位數 {med:.1f} 秒 {dur_ok}（Montini 是 "
                  f"{MONTINI_DURATION_MEDIAN} 秒）")
        print("""
  ⚠️ 「落在 IQR」只是**必要條件不是充分條件**。時長中位數也要對得上
     （Montini 是 4 秒）——兩個獨立的量同時吻合，才比較像是真的量到動作，
     而不是剛好湊出一個數字。
  ⚠️ 而且這是 n=1 晚。要定案至少要幾晚都落在同一區間，
     再用影片人工標註驗一次準確率。""")
    else:
        print("\n⚠️ 沒有任何門檻落進 Montini 的 IQR。可能的原因：")
        print("   - 相機視野裡床佔太小（現在分母是整個畫面，還沒有 ROI）")
        print("   - END_FRAMES 太長或太短，把動作黏成一段或切成好幾段")
        print("   - 這一晚本身不典型")

    # ── END_FRAMES 的敏感度：它對事件數的影響往往比門檻還大 ──
    print(f"\n\n【敏感度】END_FRAMES 對事件數的影響（固定門檻）")
    rule()
    anchor = hits[len(hits) // 2][0] / 100 if hits else 0.02
    print(f"門檻固定在 {anchor * 100:.2f}% 畫面")
    print(f"\n{'END_FRAMES':<12}{'≈秒':>7}{'事件數':>8}{'次/小時':>9}{'時長中位數':>12}")
    rule()
    for ef in (5, 10, 15, 20, 30, 45, 60):
        eps = episodes(samples, anchor, end_frames=ef)
        if not eps:
            continue
        rate = len(eps) / hours
        med = statistics.median(e[1] for e in eps)
        mark = " ★" if MONTINI_IQR[0] <= rate <= MONTINI_IQR[1] else ""
        print(f"{ef:<12}{ef / fps:>7.1f}{len(eps):>8}{rate:>9.1f}{med:>11.1f}s{mark}")
    print("""
  → END_FRAMES 決定「隔多久算兩次動作」。太短會把一次翻身切成好幾段，
    太長會把兩次併成一次。它和門檻是**兩個獨立的旋鈕**，
    調的時候要一起看，不能只調門檻。""")

    print("\n" + "=" * 92)
    print("""下一步

  1. 再錄幾晚，看落進 IQR 的門檻穩不穩定（現在 n=1）
  2. 推 ROI（tapo_derive_roi.py），把分母從整個畫面換成床
     —— 現在的百分比會被「床只佔畫面一部分」稀釋
  3. 用 tapo 2.0/sleep_videos/ 的片段人工標註，驗準確率
  4. 三者都過了，才談要不要計分 —— 而計分門檻要另外找文獻
     （Research-Background/攝影機分數.md，還沒寫）""")
    print("=" * 92)


if __name__ == "__main__":
    main()
