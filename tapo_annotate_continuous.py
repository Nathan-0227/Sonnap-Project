"""
tapo_annotate_continuous.py — 用連續錄影 + 時間戳標註真正校準門檻。

═══════════════════════════════════════════════════════════════════
跟 tapo_annotate_clips.py 的差異，以及為什麼需要這一支
═══════════════════════════════════════════════════════════════════
tapo_annotate_clips.py 標的是 tapo 2.0/sleep_videos/ 的 126 個片段，
但那些片段由**舊偵測器自己挑選、自己決定長度**——片長與人工標註次數
r=0.84，是選擇偏誤，無法用來校準門檻（見該檔案檔頭 2026-09-03 的結論）。

這一支改標 `tapo_metric_logger.py --save-video` 存的**連續影片**：
它涵蓋整個錄影窗格內的每一秒，沒有被任何演算法篩選過。標註者按下
標記鍵的那一刻，只跟真實動作有沒有發生有關，跟偵測器怎麼想無關。

而且影片與 CSV 是逐幀對齊的（影片第 N 幀 == CSV 裡 vf==N 那一列），
**演算法的度量已經在 CSV 裡了，不需要重新跑一次**——直接拿 max_px
對照人工標記就好。這也是第一次能算出真正的假陽性率：片段版量不到
「偵測器完全沒反應的時刻」，因為那些時刻根本沒有影片。

⚠️ 這支**不評分**。它定的是偵測門檻，靠效標校準、不受紅線 2 約束
   （見 TAPO_HANDOFF「偵測門檻 ≠ 計分門檻」）。

用法
────
  python tapo_annotate_continuous.py <csv>              # 標註（可中斷續標）
  python tapo_annotate_continuous.py <csv> --compare    # 對照找門檻

標註時的按鍵：
  空白（space）  暫停 / 播放
  a / d          暫停時單幀後退 / 前進；方向鍵 ←/→ 也可以
  w / s          加快 /放慢播放速度；方向鍵 ↑/↓ 也可以
  m              標記「這一刻正在發生動作」
  u              撤銷最後一個標記
  g              輸入要跳到的幀號（terminal 視窗輸入，Enter 確認）
  q / Esc        存檔離開（下次接著標，已看過的範圍會記住）
"""
import argparse
import csv
import json
import sys
from pathlib import Path

import os
os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")

import cv2
import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

FRAME_AREA = 640 * 360
DEFAULT_DELAY_MS = 60      # 播放間隔；越小越快
MIN_DELAY_MS, MAX_DELAY_MS = 10, 400
STEP_DELAY_MS = 15

# 與 tapo_scan_threshold.py 對齊的預設聚合參數與文獻常模
START_FRAMES = 3
END_FRAMES = 15
GRID = [0.2, 0.3, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.5, 10.0, 15.0, 20.0]
MONTINI_MI_MEDIAN = 11
MONTINI_MI_IQR = (8, 15)
TOLERANCE_SECONDS = 3.0    # 人工標記與演算法事件視為同一次的容許誤差


def video_path_for(csv_path: Path) -> Path:
    return csv_path.with_suffix(".mp4")


def truth_path_for(csv_path: Path) -> Path:
    return csv_path.with_name(csv_path.stem + "_truth.csv")


def load_vf_fracs(csv_path: Path):
    """
    回傳 dict：vf(int) -> (timestamp_str, frac 或 None)。

    分母跟著檔頭走：用 --roi 錄的就是 ROI 面積。解讀在 tapo_metric_logger，
    這裡不自己判斷（判準只有一份，漂移時才有人發現）。
    """
    from tapo_metric_logger import read_roi, row_frac
    if not csv_path.exists():
        return {}          # 只有影片也要能標註，見 main()
    roi, _ = read_roi(csv_path)
    out = {}
    with csv_path.open(encoding="utf-8") as fh:
        for row in csv.DictReader(l for l in fh if not l.startswith("#")):
            if row.get("vf", "") == "":
                continue
            try:
                vf = int(row["vf"])
            except ValueError:
                continue
            out[vf] = (row.get("t", ""), row_frac(row, roi))
    return out


def merge_ranges(ranges):
    """[(s,e), ...] → 合併重疊/相鄰區間，回傳排序後的 list。"""
    if not ranges:
        return []
    rs = sorted(ranges)
    merged = [list(rs[0])]
    for s, e in rs[1:]:
        if s <= merged[-1][1] + 1:
            merged[-1][1] = max(merged[-1][1], e)
        else:
            merged.append([s, e])
    return [(s, e) for s, e in merged]


def seen_to_ranges(seen: np.ndarray):
    """布林陣列 → run-length 區間。"""
    idx = np.flatnonzero(seen)
    if len(idx) == 0:
        return []
    ranges = []
    s = idx[0]
    prev = idx[0]
    for i in idx[1:]:
        if i != prev + 1:
            ranges.append((int(s), int(prev)))
            s = i
        prev = i
    ranges.append((int(s), int(prev)))
    return ranges


# ═══════════════════════════════════════════════════════════════════
# 讀 / 寫標註檔
# ═══════════════════════════════════════════════════════════════════

def load_truth(truth_path: Path):
    """回傳 (marks: list[int], reviewed: list[(s,e)])。檔案不存在就回空的。"""
    if not truth_path.exists():
        return [], []
    reviewed = []
    marks = []
    with truth_path.open(encoding="utf-8") as fh:
        lines = fh.readlines()
    for line in lines:
        if line.startswith("# reviewed="):
            try:
                reviewed = [tuple(p) for p in json.loads(line.split("=", 1)[1])]
            except (ValueError, json.JSONDecodeError):
                reviewed = []
            break
    body = [l for l in lines if not l.startswith("#")]
    for row in csv.DictReader(body):
        try:
            marks.append(int(row["vf"]))
        except (KeyError, ValueError):
            continue
    return marks, reviewed


def save_truth(truth_path: Path, marks, reviewed, vf_map):
    truth_path.parent.mkdir(parents=True, exist_ok=True)
    with truth_path.open("w", newline="", encoding="utf-8") as fh:
        fh.write(f"# reviewed={json.dumps([list(r) for r in reviewed])}\n")
        w = csv.writer(fh)
        w.writerow(["vf", "t", "note"])
        for vf in sorted(set(marks)):
            t = vf_map.get(vf, ("", None))[0]
            w.writerow([vf, t, ""])


# ═══════════════════════════════════════════════════════════════════
# ① 標註 UI
# ═══════════════════════════════════════════════════════════════════

WIN = "TAPO continuous annotation"

# OpenCV 在 Windows 上 waitKeyEx 回傳的方向鍵碼
LEFT, UP, RIGHT, DOWN = 2424832, 2490368, 2555904, 2621440


def render(frame, idx, total, marks, delay_ms, paused, flash, vf_map):
    fr = cv2.resize(frame, (960, 540))
    if fr.ndim == 2:
        fr = cv2.cvtColor(fr, cv2.COLOR_GRAY2BGR)
    bar = int(960 * idx / max(total - 1, 1))
    cv2.rectangle(fr, (0, 528), (960, 540), (60, 60, 60), -1)
    cv2.rectangle(fr, (0, 528), (bar, 540), (0, 200, 255), -1)
    for m in marks:
        x = int(960 * m / max(total - 1, 1))
        cv2.line(fr, (x, 528), (x, 540), (0, 0, 255), 2)

    t, frac = vf_map.get(idx, ("", None))
    speed = f"{200 / delay_ms:.1f}x" if delay_ms else "?"
    status = "PAUSED" if paused else f"PLAY {speed}"
    lines = [
        f"frame {idx}/{total - 1}   {t[11:19] if len(t) > 19 else t}   {status}",
        f"marks: {len(marks)}" + ("   *** MARKED ***" if flash else ""),
        "space pause | a/d step | w/s speed | m mark | u undo | g goto | q save+quit",
    ]
    for i, text in enumerate(lines):
        y = 24 + i * 24
        cv2.putText(fr, text, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 4)
        color = (0, 0, 255) if (i == 1 and flash) else (255, 255, 255)
        cv2.putText(fr, text, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1)
    cv2.imshow(WIN, fr)


def cmd_annotate(csv_path: Path):
    video_path = video_path_for(csv_path)
    truth_path = truth_path_for(csv_path)
    if not video_path.exists():
        sys.exit(f"✗ 找不到 {video_path}（這份 CSV 錄影時沒有加 --save-video 嗎？）")

    vf_map = load_vf_fracs(csv_path)
    marks, reviewed = load_truth(truth_path)
    marks = list(marks)

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        sys.exit(f"✗ 影片開不起來：{video_path}")
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if total <= 0:
        sys.exit("✗ 讀不到幀數，檔案可能壞了。")

    seen = np.zeros(total, dtype=bool)
    for s, e in reviewed:
        seen[s:e + 1] = True

    print(f"共 {total} 幀（{total / 5 / 60:.1f} 分鐘 @ 5fps）。"
          f"已標記 {len(marks)} 次，已看過 {seen.sum()}/{total} 幀（{seen.mean() * 100:.0f}%）。")
    print("""
規則（請一致，這是標準答案）：
  身體真的在動（翻身、抬手、調整姿勢）就按 m —— 每一次獨立動作按一次。
  光線變化、雜訊、完全靜止不要按。
  不確定就繼續看，寧可少按也不要亂猜。
  可以隨時暫停（space）、單幀核對（a/d）、倒回重看。
""")

    cv2.namedWindow(WIN, cv2.WINDOW_AUTOSIZE)

    pos = 0            # cap 下一次 read() 會回傳的幀號
    last_idx = -1
    frame = None
    paused = False
    delay = DEFAULT_DELAY_MS
    flash_until = 0

    def seek(i):
        nonlocal pos
        i = max(0, min(total - 1, i))
        cap.set(cv2.CAP_PROP_POS_FRAMES, i)
        pos = i

    def read_next():
        nonlocal pos, last_idx, frame
        ok, fr = cap.read()
        if ok:
            frame = fr
            last_idx = pos
            seen[pos] = True
            pos += 1
        return ok

    if not read_next():
        sys.exit("✗ 讀不到第一幀。")

    import time as _time
    quitting = False
    while not quitting:
        flash = _time.time() < flash_until
        render(frame, last_idx, total, marks, delay, paused, flash, vf_map)
        k = cv2.waitKeyEx(0 if paused else delay)

        if k in (27, ord("q"), ord("Q")):
            quitting = True
        elif k == ord(" "):
            paused = not paused
        elif k == ord("m") or k == ord("M"):
            marks.append(last_idx)
            flash_until = _time.time() + 0.4
        elif k == ord("u") or k == ord("U"):
            if marks:
                marks.pop()
                flash_until = _time.time() + 0.4
        elif k in (ord("g"), ord("G")):
            paused = True
            try:
                raw = input(f"\n跳到第幾幀？(0-{total - 1}): ").strip()
                target = int(raw)
                seek(target)
                read_next()
            except (ValueError, EOFError):
                pass
        elif k in (ord("w"), ord("W"), UP):
            delay = max(MIN_DELAY_MS, delay - STEP_DELAY_MS)
        elif k in (ord("s"), ord("S"), DOWN):
            delay = min(MAX_DELAY_MS, delay + STEP_DELAY_MS)
        elif paused and k in (ord("a"), ord("A"), LEFT):
            seek(last_idx - 1)
            if not read_next():
                seek(last_idx)
                read_next()
        elif paused and k in (ord("d"), ord("D"), RIGHT):
            if not read_next():
                seek(last_idx)  # 已到底，留在原地
                read_next()
        elif not paused:
            if not read_next():
                paused = True   # 播到底了，自動暫停
                seek(last_idx)
                read_next()
        # 其他鍵：忽略，重畫同一幀

    cap.release()
    cv2.destroyAllWindows()

    reviewed_now = merge_ranges(seen_to_ranges(seen))
    save_truth(truth_path, marks, reviewed_now, vf_map)
    print(f"\n✓ 已標記 {len(marks)} 次，看過 {seen.sum()}/{total} 幀"
          f"（{seen.mean() * 100:.0f}%），寫入 {truth_path}")
    print("  隨時可以再跑一次接著標；標夠了跑 --compare。")


# ═══════════════════════════════════════════════════════════════════
# ② 對照：CSV 裡的 max_px 已經是演算法度量，直接比對，不必重跑
# ═══════════════════════════════════════════════════════════════════

def detect_episodes(vf_frac_pairs, threshold,
                    start_frames=START_FRAMES, end_frames=END_FRAMES):
    """
    vf_frac_pairs：按 vf 遞增排序、屬於同一段已審視範圍的 (vf, frac)。
    回傳 [(start_vf, end_vf), ...]。
    """
    eps = []
    motion_run = quiet_run = 0
    in_ep = False
    ep_start = last_moving = None
    for vf, frac in vf_frac_pairs:
        moving = frac is not None and frac >= threshold
        if moving:
            quiet_run = 0
            last_moving = vf
            if not in_ep:
                motion_run += 1
                if motion_run >= start_frames:
                    in_ep, ep_start = True, vf
        else:
            motion_run = 0
            if in_ep:
                quiet_run += 1
                if quiet_run >= end_frames:
                    eps.append((ep_start, last_moving))
                    in_ep = False
    if in_ep:
        eps.append((ep_start, last_moving))
    return eps


def match_sets(episodes, marks, tolerance_frames):
    """回傳 (matched_mark_indices, matched_episode_indices) 兩個集合。"""
    matched_marks = set()
    matched_eps = set()
    for ei, (s, e) in enumerate(episodes):
        for mi, m in enumerate(marks):
            if s - tolerance_frames <= m <= e + tolerance_frames:
                matched_eps.add(ei)
                matched_marks.add(mi)
    return matched_marks, matched_eps


def match(episodes, marks, tolerance_frames):
    """回傳 (matched_marks, matched_eps)：各自的個數。"""
    mm, me = match_sets(episodes, marks, tolerance_frames)
    return len(mm), len(me)


def rule(ch="-", n=92):
    print(ch * n)


def cmd_compare(csv_path: Path):
    truth_path = truth_path_for(csv_path)
    marks, reviewed = load_truth(truth_path)
    if not reviewed:
        sys.exit(f"✗ {truth_path} 沒有已審視的範圍。先跑標註（不加 --compare）。")

    vf_map = load_vf_fracs(csv_path)
    # 分母跟著檔頭走，表格的單位標籤也要跟著 —— 標錯的話「0.5%」會被當成
    # 佔畫面 0.5%，而這份其實是佔 ROI 0.5%（差 3.5 倍）。
    from tapo_metric_logger import read_roi
    roi, _ = read_roi(csv_path)
    unit = "佔 ROI" if roi else "佔畫面"
    fps = 5.0
    tol = int(TOLERANCE_SECONDS * fps)
    reviewed_frames = sum(e - s + 1 for s, e in reviewed)
    reviewed_hours = reviewed_frames / fps / 3600

    print("=" * 92)
    print(f"連續標註對照：{csv_path.name}")
    print(f"已審視 {reviewed_frames} 幀（{reviewed_hours * 60:.1f} 分鐘），"
          f"人工標記 {len(marks)} 次，容許誤差 ±{TOLERANCE_SECONDS:.0f} 秒")
    print("=" * 92)

    if len(marks) < 3:
        print("\n⚠️ 標記數太少（<3），統計沒有意義。多標一些再來。")
        return

    print(f"\n人工事件率：{len(marks) / reviewed_hours:.1f} 次/小時"
          f"（Montini 2024 常模：{MONTINI_MI_MEDIAN} 次/小時，"
          f"IQR {MONTINI_MI_IQR[0]}–{MONTINI_MI_IQR[1]}）")

    if roi:
        print(f"\n⚠️ 這份是用 ROI {roi} 錄的 —— 門檻是**佔 ROI**"
              f"（{roi[2] * roi[3]} px）的比例，不是佔整個畫面。")
    print(f"\n{'門檻(' + unit + ')':>13}{'演算法事件':>11}{'次/小時':>9}{'召回率':>8}{'精確率':>8}"
          f"{'F1':>7}{'誤報/小時':>10}  判讀")
    rule()

    rows = []
    for p in GRID:
        eps = []
        for s, e in reviewed:
            pairs = [(vf, vf_map[vf][1]) for vf in range(s, e + 1) if vf in vf_map]
            eps.extend(detect_episodes(pairs, p / 100))
        tp_marks, tp_eps = match(eps, marks, tol)
        recall = tp_marks / len(marks) if marks else 0
        precision = tp_eps / len(eps) if eps else 0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0
        fp_per_hour = (len(eps) - tp_eps) / reviewed_hours if reviewed_hours else 0
        rows.append((p, eps, recall, precision, f1, fp_per_hour))
        verdict = ""
        print(f"{p:>7.2f}%{len(eps):>11}{len(eps) / reviewed_hours:>9.1f}"
              f"{recall * 100:>7.0f}%{precision * 100:>7.0f}%{f1:>7.2f}"
              f"{fp_per_hour:>10.1f}  {verdict}")

    rule()
    best = max(rows, key=lambda r: r[4])
    edge = best[0] in (GRID[0], GRID[-1])
    print(f"\nF1 最高：{best[0]}% 畫面（召回率 {best[2] * 100:.0f}%、"
          f"精確率 {best[3] * 100:.0f}%、F1 {best[4]:.2f}）")
    if edge:
        print("  ⚠️ 這是掃描格點的端點，真正的最佳值可能在格點之外，"
              "不要直接採用，先擴大格點範圍重跑。")
    print("""
  ⚠️ 精確率/召回率是這裡才算得出來的東西（片段版量不到假陰性，
     因為偵測器完全沒反應的時刻根本沒有影片）。
     召回率低 = 偵測器漏掉真的動作；精確率低 = 偵測器在雜訊上誤報。
     兩者都要看，只看其中一個會選到偏頗的門檻。

  ⚠️ 這仍然只是一晚（或審視範圍內）的樣本。要定案，
     多錄幾晚、每晚都標一段，看最佳門檻是否穩定在同一區間。""")
    print("=" * 92)


def vf_to_clock(vf, fps=5.0):
    """
    vf → 影片內的位置 mm:ss。

    ⚠️ 這是**播放器要拖到的地方**，不是牆鐘時刻。兩者都要給：
       牆鐘時刻用來對照別的紀錄（Garmin、手機），影片位置才能真的跳過去。
       影片存的是降取樣後實際分析的那些幀，所以 vf 就是影片的幀序號，
       而影片的宣告幀率固定是 TARGET_FPS —— 實測第 6 晚 21801 幀 @ 5.0fps
       對上 CSV 的 vf 0~21800，逐幀對齊。
    """
    total = vf / fps
    return f"{int(total // 60)}:{total % 60:04.1f}"


def cmd_list_fp(csv_path: Path, threshold: float):
    """
    把「偵測到但沒有對應人工標記」的事件逐一列出來，附影片幀號。

    ⚠️ 為什麼需要這支：`--compare` 只給精確率一個數字，但那個數字
       **同時混著兩種完全不同的東西**——真的誤報（那時候沒人在動），
       與人工標註漏標的真動作（有動，只是標的時候沒看到）。
       兩者的處置相反：前者要調偵測、後者要補標註。
       數字分不出來，只有回頭看影片分得出來。

    ⚠️ 這支**不下判斷**，只列出要看哪幾段。判斷要人眼做。
    """
    truth_path = truth_path_for(csv_path)
    marks, reviewed = load_truth(truth_path)
    if not reviewed:
        sys.exit(f"✗ {truth_path} 沒有已審視的範圍。先跑標註（不加旗標）。")

    vf_map = load_vf_fracs(csv_path)
    from tapo_metric_logger import read_roi
    roi, _ = read_roi(csv_path)
    unit = "佔 ROI" if roi else "佔畫面"
    fps = 5.0
    tol = int(TOLERANCE_SECONDS * fps)

    eps = []
    for s0, e0 in reviewed:
        pairs = [(vf, vf_map[vf][1]) for vf in range(s0, e0 + 1) if vf in vf_map]
        eps.extend(detect_episodes(pairs, threshold / 100))
    matched_marks, matched_eps = match_sets(eps, marks, tol)

    fp = [(i, eps[i]) for i in range(len(eps)) if i not in matched_eps]
    fn = [(i, marks[i]) for i in range(len(marks)) if i not in matched_marks]

    print("=" * 92)
    print(f"要回頭看影片的片段：{csv_path.name}   門檻 {threshold}% {unit}")
    print(f"演算法 {len(eps)} 個事件、人工 {len(marks)} 個標記、容許誤差 ±{TOLERANCE_SECONDS:.0f} 秒")
    print("=" * 92)
    print(f"\n影片檔：{video_path_for(csv_path).name}")
    print("⚠️ 影片的第 N 幀 == CSV 裡 vf==N 的那一列，逐幀對齊。")
    print("   「影片位置」是拖進度條要到的地方（vf ÷ fps）；「牆鐘」是那一刻的真實時間。")
    print(f"   ⚠️ 配對的容許誤差是 ±{TOLERANCE_SECONDS:.0f} 秒，所以**前後各多看幾秒**再判斷，")
    print("      不要只看區間內那一瞬間。")

    print(f"\n【A】偵測到但沒有標記 —— {len(fp)} 段（這就是那 1.4 倍的來源）")
    rule()
    if fp:
        print(f"{'#':>3}  {'影片位置（拖到這裡）':<22}{'牆鐘':>10}{'長度':>7}{'峰值':>8}  {'vf 範圍':>14}   判斷（你來填）")
        rule()
        for n, (i, (s0, e0)) in enumerate(fp, 1):
            t = vf_map.get(s0, (None, None))[0]
            hhmmss = t[11:19] if isinstance(t, str) and len(t) > 18 else "?"
            peak = max((vf_map[v][1] or 0) for v in range(s0, e0 + 1) if v in vf_map)
            span = f"{vf_to_clock(s0, fps)} → {vf_to_clock(e0, fps)}"
            print(f"{n:>3}  {span:<22}{hhmmss:>10}"
                  f"{(e0 - s0) / fps:>6.1f}s{peak * 100:>7.2f}%  {f'{s0}–{e0}':>14}"
                  f"   [ ] 真的沒動  [ ] 有動但沒標")
    else:
        print("  （沒有）")

    print(f"\n【B】有標記但沒偵測到 —— {len(fn)} 段（漏掉的真動作）")
    rule()
    if fn:
        print(f"{'#':>3}  {'影片位置':<12}{'牆鐘':>10}{'vf':>10}")
        rule()
        for n, (i, m) in enumerate(fn, 1):
            t = vf_map.get(m, (None, None))[0]
            hhmmss = t[11:19] if isinstance(t, str) and len(t) > 18 else "?"
            print(f"{n:>3}  {vf_to_clock(m, fps):<12}{hhmmss:>10}{m:>10}")
    else:
        print("  （沒有）")

    print(f"""
怎麼判讀 A 那張表（**這是這支工具存在的唯一理由**）：

  多數是「真的沒動」 → 偵測器在雜訊上誤報，門檻或形態學要調
  多數是「有動但沒標」 → **標註才是偏低的那一方**，那麼事件率高於文獻
                          就不是偵測器的問題，而是我們與文獻數的不是同一種東西

⚠️ 不要先看數字再判斷。逐段看完再統計，否則會看到自己想看的。
""")
    print("=" * 92)


def main():
    ap = argparse.ArgumentParser(description="用連續錄影 + 時間戳標註校準偵測門檻（不評分）")
    ap.add_argument("csv", type=Path, help="tapo_metric_logger.py --save-video 產生的 CSV")
    ap.add_argument("--compare", action="store_true", help="對照人工標記與 CSV 裡的演算法度量")
    ap.add_argument("--list-fp", type=float, metavar="門檻%",
                    help="列出「偵測到但沒被標記」的片段與影片幀號，供回頭看影片分類")
    args = ap.parse_args()

    # CSV 不在也要能標註 —— 標註只需要影片。2026-09-06 第 4 晚的 CSV 被
    # 誤刪（worktree 收掉時連未追蹤檔一起帶走），影片還在卻標不了，
    # 那個限制是這支自己加的、沒有必要。
    if not args.csv.exists():
        if not video_path_for(args.csv).exists():
            sys.exit(f"✗ 找不到 {args.csv}，也找不到 {video_path_for(args.csv)}")
        if args.compare:
            sys.exit(f"✗ 找不到 {args.csv} —— --compare 要讀 CSV 裡的演算法度量。\n"
                     "   影片還在的話改用 tapo_roi_experiment.py，"
                     "它從影片重跑管線，不需要 CSV。")
        print(f"⚠ 找不到 {args.csv.name}，只用影片標註。")
        print("  影響：標記存下來時沒有 t 欄（時刻），vf 照舊 —— 對照分析用的是 vf，不受影響。")

    if args.list_fp is not None:
        cmd_list_fp(args.csv, args.list_fp)
    elif args.compare:
        cmd_compare(args.csv)
    else:
        cmd_annotate(args.csv)


if __name__ == "__main__":
    main()

