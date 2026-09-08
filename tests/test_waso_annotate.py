"""
守 `tapo_waso_annotate.py` 那幾個**壞掉時不會報錯**的地方。

這支工具的失敗全是安靜的：一份只有 proposed 列的工作單照樣算得出
一個 WASO 數字，看起來完全合理——只是它系統性地漏掉「醒著但不動」，
而那正是整件事要量的東西。

每一條都用「把 bug 重新引入、確認測試會紅」驗證過。
"""
import csv
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import tapo_waso_annotate as W  # noqa: E402

PASS = FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✓ {name}")
    else:
        FAIL += 1
        print(f"  ✗ {name}  {detail}")


def make_csv(dir_, name, minutes, fps=5.0, with_video_until=None):
    """造一份最小的 logger CSV。with_video_until = 幾分鐘之後 vf 變空。"""
    path = dir_ / f"{name}.csv"
    t0 = datetime(2026, 9, 9, 2, 0, 0)
    with path.open("w", encoding="utf-8", newline="") as fh:
        fh.write(f"# tapo_metric_logger  started={t0.isoformat()}\n")
        fh.write("# size=640x360 fps=5.0\n")
        w = csv.writer(fh)
        w.writerow(["t", "mean", "raw_px", "fg_px", "blobs", "max_px",
                    "max_x", "max_y", "max_w", "max_h", "illum_skip",
                    "warmup", "vf"])
        n = int(minutes * 60 * fps)
        for i in range(n):
            t = t0 + timedelta(seconds=i / fps)
            elapsed_min = i / fps / 60
            vf = "" if (with_video_until is not None
                        and elapsed_min >= with_video_until) else str(i)
            w.writerow([t.isoformat(timespec="milliseconds"), 92.0, 50, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, vf])
    return path


def run(*args):
    return subprocess.run(
        [sys.executable, str(ROOT / "tapo_waso_annotate.py"), *map(str, args)],
        capture_output=True, text=True, encoding="utf-8",
        env={**__import__("os").environ, "PYTHONIOENCODING": "utf-8"})


def read_worksheet(path):
    with path.open(encoding="utf-8") as fh:
        return list(csv.DictReader(l for l in fh if not l.startswith("#")))


def fill(path, state_for):
    rows = read_worksheet(path)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["at", "video_at_seconds", "source", "state", "note"])
        for r in rows:
            w.writerow([r["at"], r["video_at_seconds"], r["source"],
                        state_for(r), r["note"]])


def main():
    print("=" * 70)
    print("tapo_waso_annotate 守門測試")
    print("=" * 70)

    with tempfile.TemporaryDirectory() as td:
        d = Path(td)

        print("\n【1】工作單一定要有均勻抽樣的列")
        src = make_csv(d, "20260909_020000", minutes=70)
        r = run("--plan", src)
        ws = src.with_name(src.stem + "_waso.csv")
        check("--plan 產出工作單", ws.exists(), r.stdout + r.stderr)
        rows = read_worksheet(ws)
        check("有 grid 列", any(x["source"] in ("grid", "both") for x in rows))
        check("70 分鐘 / 每 10 分鐘 → 7 列",
              len(rows) == 7, f"實際 {len(rows)}")

        print("\n【2】⚠️ 只有 proposed 的工作單必須被拒收")
        # 這是這支工具最重要的一條守門：只看偵測器提示的時段，
        # 會系統性漏掉「醒著但不動」——而那正是要量的東西。
        only_proposed = d / "only_proposed_waso.csv"
        with only_proposed.open("w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["at", "video_at_seconds", "source", "state", "note"])
            w.writerow(["2026-09-09T02:00:00", "0", "proposed", "awake", ""])
            w.writerow(["2026-09-09T02:30:00", "9000", "proposed", "asleep", ""])
        r = run("--score", src, "--worksheet", only_proposed)
        check("退回並說明原因", r.returncode != 0 and "grid" in (r.stdout + r.stderr))

        print("\n【3】沒填完不准算")
        fill(ws, lambda x: "asleep" if x["at"].endswith("00:00") else "")
        r = run("--score", src, "--worksheet", ws)
        check("有空白就退回", r.returncode != 0 and "沒填" in (r.stdout + r.stderr))

        print("\n【4】亂填的 state 不准算")
        fill(ws, lambda x: "sleeping")     # 不是三個合法值
        r = run("--score", src, "--worksheet", ws)
        check("退回", r.returncode != 0 and "state" in (r.stdout + r.stderr))

        print("\n【5】WASO 的分鐘數算對")
        # 7 列 × 10 分鐘，把第 2、3 列標成 awake → 20 分鐘
        order = {x["at"]: i for i, x in enumerate(read_worksheet(ws))}
        fill(ws, lambda x: "awake" if order[x["at"]] in (1, 2) else "asleep")
        r = run("--score", src, "--worksheet", ws)
        out = r.stdout + r.stderr
        check("跑得完", r.returncode == 0, out)
        check("醒著的時間 = 20 分", "20.0 分" in out, out)

        print("\n【6】⚠️ 影片沒錄到的時段要標出來，不能默默當成睡著")
        src2 = make_csv(d, "20260909_030000", minutes=70, with_video_until=20)
        (d / "20260909_030000.mp4").write_bytes(b"")   # 只要存在就好
        r = run("--plan", src2)
        ws2 = src2.with_name(src2.stem + "_waso.csv")
        rows2 = read_worksheet(ws2)
        no_frame = [x for x in rows2 if not x["video_at_seconds"]]
        check("後面那幾列的 video_at 是空的", len(no_frame) >= 4,
              f"實際 {len(no_frame)}")
        check("而且每一列都標了原因",
              all("沒有畫面" in x["note"] for x in no_frame))
        # ⚠️ 反向對照：前面有畫面的列**不可以**被標成沒畫面。
        #    少了這一條，把每一列都標成「沒畫面」也會讓上面兩條通過。
        has_frame = [x for x in rows2 if x["video_at_seconds"]]
        check("反向對照：有畫面的列沒被誤標",
              len(has_frame) >= 2 and all("沒有畫面" not in x["note"]
                                          for x in has_frame),
              f"有畫面的 {len(has_frame)} 列")

        print("\n【8】⚠️ proposed 的列不可以影響 WASO 估計")
        # 這是 2026-09-08 修掉的統計錯誤：第一版把每個標記外推成
        # 「到下一個標記為止」，於是 proposed 的列（挑事件率高的地方放的）
        # 會在容易醒著的時段多放權重，WASO 系統性高估。
        # 正確做法是只拿 grid 當系統抽樣。
        #
        # ⚠️ 均勻抽樣覆蓋整段時，兩種算法會給出**同一個答案**——所以
        #    【5】那條抓不到這個 bug。要抓到就必須多放幾個非 grid 的點。
        def write_ws(path, with_proposed):
            with path.open("w", encoding="utf-8", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(["at", "video_at_seconds", "source", "state", "note"])
                for i in range(7):
                    t = datetime(2026, 9, 9, 2, 0) + timedelta(minutes=10 * i)
                    w.writerow([t.isoformat(), i * 3000, "grid",
                                "awake" if i in (1, 2) else "asleep", ""])
                    if with_proposed and i < 3:
                        t2 = t + timedelta(minutes=3)
                        w.writerow([t2.isoformat(), i * 3000 + 900,
                                    "proposed", "awake", ""])

        base = d / "prop_base_waso.csv"
        biased = d / "prop_biased_waso.csv"
        write_ws(base, False)
        write_ws(biased, True)
        r1 = run("--score", src, "--worksheet", base)
        r2 = run("--score", src, "--worksheet", biased)

        def waso_line(out):
            # ⚠️ 不能只認開頭的 "WASO"——標題列是「WASO 人工標註 <檔名>」，
            #    兩份的檔名不同，就會永遠不相等而讓這條假性失敗。
            #    2026-09-09 那個量改名成「臥床期間醒著的時間」（它含入睡
            #    潛伏期，不是臨床 WASO），這裡跟著改。
            for ln in out.splitlines():
                t = ln.strip()
                if t.startswith("醒著的時間") and "信賴區間" in t:
                    return t
            return ""

        check("同一份 grid 標註，多了 proposed 的點也不會改變估計",
              waso_line(r1.stdout) == waso_line(r2.stdout) != "",
              f"只有 grid：{waso_line(r1.stdout)} / "
              f"多了提示點：{waso_line(r2.stdout)}")
        check("提示點另外列出來（定性佐證，不進估計）",
              "不進上面的估計" in r2.stdout, r2.stdout[-400:])

        print("\n【9】估計要附信賴區間與解析度下限")
        # 40 個取樣點估出來的比例，區間寬得值得寫出來。不附區間的話
        # 「39 分鐘」會被當成量到的數字引用。
        check("有 95% 信賴區間", "95% 信賴區間" in r1.stdout, r1.stdout[-400:])
        # ⚠️ 這兩句要分開講：總時數不偏，但「醒了幾次」答不出來。
        #    只講「解析度下限」會讓人推論成「總時數被低估」——不會。
        check("有講抽樣間隔造成的限制", "抽樣間隔" in r1.stdout)
        check("有講總時數仍然不偏", "不偏" in r1.stdout, r1.stdout[-500:])
        check("有講醒了幾次答不出來", "醒了幾次" in r1.stdout)

        print("\n【10】⚠️ recall 欄不可以影響估計")
        # 2026-09-09 定案：state 只填影片看得到的，記憶填 recall。
        # recall 是第二個獨立的量測，不是效標——混進估計就不再是影片量測，
        # 而且會變成「知道答案再去看畫面」的非盲標。
        rec = d / "with_recall_waso.csv"
        with rec.open("w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["at", "video_at_seconds", "source", "state",
                        "recall", "note"])
            for i in range(7):
                t = datetime(2026, 9, 9, 2, 0) + timedelta(minutes=10 * i)
                # 影片看到 2 格醒著；記憶說 5 格醒著
                w.writerow([t.isoformat(), i * 3000, "grid",
                            "awake" if i in (1, 2) else "asleep",
                            "awake" if i in (1, 2, 3, 4, 5) else "asleep", ""])
        r3 = run("--score", src, "--worksheet", rec)
        base_line = waso_line(r1.stdout)
        check("填了 recall，估計仍然只看 state",
              waso_line(r3.stdout) == base_line != "",
              f"有 recall：{waso_line(r3.stdout)} / 沒有：{base_line}")
        check("記得醒著但影片看不出來的，要單獨列出來",
              "記得醒著、影片看不出來" in r3.stdout, r3.stdout[-600:])
        check("⚠️ 有講兩邊一致也不構成互相驗證",
              "不構成互相驗證" in r3.stdout)

        print("\n【7】不覆寫已經標好的工作單")
        r = run("--plan", src2)
        check("第二次 --plan 退回", r.returncode != 0)

    print()
    print("=" * 70)
    print(f"通過 {PASS} / 失敗 {FAIL}")
    print("=" * 70)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
