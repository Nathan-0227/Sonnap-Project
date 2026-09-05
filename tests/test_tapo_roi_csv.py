"""
tests/test_tapo_roi_csv.py

守的是 `tapo_metric_logger` 的 ROI 欄位那四個**壞掉時不會報錯**的機制。

`--roi` 換掉的是「佔比」的**分母**。分母錯了不會拋例外，也不會有空值——
只會讓門檻整個差一個數量級，而數字看起來完全正常。實測第 4 晚的 ROI
只佔畫面 28.9%，用錯分母的話「0.75%」會變成「2.6%」，事件數差三倍。

  【1】檔頭有 `# roi=` 時，read_roi 必須讀出那個框；分母是 ROI 面積
  【2】舊 CSV（沒有那一行）必須照舊用整個畫面當分母 —— 不能拋例外
  【3】暖機與照明否決的列一律回 None，不得當成「沒有動作」的 0
  【4】有 ROI 時 row_frac 讀的是 roi_px，**不是** max_px
       （反向對照：兩者故意給不同的值，讀錯就會被抓到）

四條都用「把 bug 重新引入、確認測試會紅」驗證過。

執行：python tests/test_tapo_roi_csv.py
"""
import sys
import tempfile
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tapo_metric_logger import read_roi, row_frac, WIDTH, HEIGHT  # noqa: E402

FRAME_AREA = WIDTH * HEIGHT
fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<54} 得到 {got!r:<20} 期望 {want!r}")
    if not ok:
        fails.append(label)


def write_csv(lines):
    fh = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False,
                                     encoding="utf-8", newline="")
    fh.write("\n".join(lines) + "\n")
    fh.close()
    return Path(fh.name)


HEADER_COLS = ("t,mean,raw_px,fg_px,blobs,max_px,max_x,max_y,max_w,max_h,"
               "illum_skip,warmup,vf,roi_px,roi_x,roi_y,roi_w,roi_h")

ROI = (34, 129, 288, 231)
ROI_AREA = ROI[2] * ROI[3]          # 66528

print("=" * 92)
print("tapo_metric_logger 的 ROI 欄位")
print("=" * 92)

# ── 【1】檔頭有 ROI ────────────────────────────────────────────────
print("\n【1】檔頭寫了 ROI 就要讀得出來，而且分母是 ROI 面積")
p = write_csv([
    "# tapo_metric_logger  started=2026-09-06T02:00:00",
    "# size=640x360 fps=5.0",
    f"# roi={ROI[0]},{ROI[1]},{ROI[2]},{ROI[3]} roi_area={ROI_AREA}",
    "# source=hidden",
    HEADER_COLS,
])
roi, area = read_roi(p)
check("read_roi 讀出的框", roi, ROI)
check("read_roi 讀出的分母面積", area, ROI_AREA)
p.unlink()

# ── 【2】舊 CSV 沒有那一行 ────────────────────────────────────────
print("\n【2】--roi 之前錄的 CSV：沒有 `# roi=` 那一行，要退回整個畫面")
p = write_csv([
    "# tapo_metric_logger  started=2026-09-03T02:06:31",
    "# size=640x360 fps=5.0",
    "# source=hidden",
    "t,mean,raw_px,fg_px,blobs,max_px,max_x,max_y,max_w,max_h,illum_skip,warmup,vf",
])
roi, area = read_roi(p)
check("舊 CSV 的框", roi, None)
check("舊 CSV 的分母面積", area, FRAME_AREA)
# 舊 CSV 連 roi_px 這一欄都沒有，row_frac 不能因此壞掉
old_row = {"max_px": "2304", "illum_skip": "0", "warmup": "0"}
check("舊 CSV 的一列仍算得出佔比（2304/230400）", row_frac(old_row, roi), 0.01)
p.unlink()

# `# roi=full` 是新版在沒給 --roi 時寫的，要與「沒有那一行」等價
p = write_csv([
    "# tapo_metric_logger  started=2026-09-06T02:00:00",
    "# roi=full",
    HEADER_COLS,
])
check("`# roi=full` 等同於整個畫面", read_roi(p), (None, FRAME_AREA))
p.unlink()

# ── 【3】不可用的列要回 None，不是 0 ──────────────────────────────
print("\n【3】暖機與照明否決的列回 None —— 回 0 會被下游當成「安靜」")
warm = {"max_px": "230400", "roi_px": "66528", "illum_skip": "0", "warmup": "1"}
illum = {"max_px": "", "roi_px": "", "illum_skip": "1", "warmup": "0"}
check("暖機的列（整畫面）", row_frac(warm, None), None)
check("暖機的列（有 ROI）", row_frac(warm, ROI), None)
check("照明否決的列（整畫面）", row_frac(illum, None), None)
check("照明否決的列（有 ROI）", row_frac(illum, ROI), None)

# ── 【4】有 ROI 就要讀 roi_px，不是 max_px ────────────────────────
print("\n【4】有 ROI 時讀的是 roi_px。兩欄故意給不同的值，讀錯就會被抓到")
# max_px 佔畫面 10%，roi_px 佔 ROI 1% —— 四種讀法各自會得到不同的數字，
# 所以這一條同時排除「用對欄位但用錯分母」與「用錯欄位」。
row = {"max_px": str(int(FRAME_AREA * 0.10)),
       "roi_px": str(int(ROI_AREA * 0.01)),
       "illum_skip": "0", "warmup": "0"}
got_roi = row_frac(row, ROI)
got_full = row_frac(row, None)
check("有 ROI → roi_px / ROI 面積 ≈ 1%", round(got_roi * 100, 2), 1.0)
check("沒有 ROI → max_px / 畫面面積 ≈ 10%", round(got_full * 100, 2), 10.0)
check("兩者不相等（否則這條測試沒有鑑別力）", got_roi != got_full, True)

# 反向對照：如果 row_frac 忘了換分母（roi_px / FRAME_AREA），
# 會得到 0.29% 而不是 1%。明寫出來，免得有人「修」成那樣。
wrong = int(ROI_AREA * 0.01) / FRAME_AREA
check("用錯分母會得到的值（不得等於正解）", round(wrong * 100, 2) == round(got_roi * 100, 2), False)

# ═══════════════════════════════════════════════════════════════════
print()
if fails:
    print(f"✗ {len(fails)} 條未通過：")
    for label in fails:
        print(f"    - {label}")
    sys.exit(1)
print("✓ 全部通過")
