"""
09-17 簡報用的圖表產生器。

目前產出 Slide 4 那張：**9 晚的就寢時刻 vs 目標 23:30**。

⚠️ 資料一律從 `nightly_behavior` 讀，不寫死在程式裡——簡報前一天資料還會長，
   寫死的話圖會跟投影片上的數字對不起來。讀不到資料時會**停下來報錯**而不是
   偷偷畫一張空圖。

⚠️ 要帶 `SONNAP_DB_URL` 執行，否則會連到空的 SQLite、畫出 0 晚：

    SONNAP_DB_URL=mysql://root@localhost/sonnap python make_ppt_charts.py

配色取自 dataviz 規範的參考調色盤（已跑過驗證器：淺底對比 PASS）。
淺色與深色兩版都產出，投影片是白底或深底都有得用。
"""

import sys
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import db
from behavior.adherence import LATE_THRESHOLD_MINUTES as TOLERANCE_MINUTES

sys.stdout.reconfigure(encoding="utf-8")

OUT_DIR = Path(__file__).parent / "docs" / "images"

# ── 配色（dataviz 參考調色盤）────────────────────────────────────
# 單一系列用 categorical slot 1（藍）。參考線與文字一律用 ink token，
# 不用系列色——系列色只負責「這是資料」，文字不該搶走那個角色。
THEMES = {
    "light": {
        "surface": "#fcfcfb",
        "series": "#2a78d6",
        "text_primary": "#0b0b0b",
        "text_secondary": "#52514e",
        "muted": "#898781",
        "grid": "#e1e0d9",
        "baseline": "#c3c2b7",
    },
    "dark": {
        "surface": "#1a1a19",
        "series": "#3987e5",
        "text_primary": "#ffffff",
        "text_secondary": "#c3c2b7",
        "muted": "#898781",
        "grid": "#2c2c2a",
        "baseline": "#383835",
    },
}

FONT_STACK = ["Segoe UI", "DejaVu Sans"]   # matplotlib 不認 system-ui，留著只會洗版警告


def fetch_nights(user_id=None):
    """讀 nightly_behavior。回傳 [(date, target_bedtime, adherence_minutes, lights_out_at)]。"""
    conn = db.connect()
    try:
        if user_id is None:
            user_id, info = db.resolve_phone_account()
            if user_id is None:
                raise SystemExit(
                    f"Cannot identify the phone account (reason={info.get('reason')}). "
                    "Pass a user id explicitly."
                )
        rows = conn.execute(
            "SELECT date, target_bedtime, adherence_minutes, lights_out_at "
            "FROM nightly_behavior WHERE user_id = ? AND lights_out_at IS NOT NULL "
            "ORDER BY date",
            (user_id,),
        ).fetchall()
    finally:
        conn.close()
    return [tuple(r) for r in rows]


def fmt_delay(minutes):
    """404.1 → '+6 h 44 m'，1.2 → '+1 min'。投影片上的標籤，整數就夠了。"""
    total = int(round(minutes))
    if total < 60:
        return f"+{total} min"
    return f"+{total // 60} h {total % 60:02d} m"


def hour_ticks(max_delay):
    """
    x 軸刻度：0 = 那一晚自己的目標時刻，往右每小時一格。

    ⚠️ **刻意不標成時鐘時間**（23:30、00:00…）。目標就寢時間 09-13 從 23:30
       改成 23:00，各晚的基準點不同，標成時鐘時間會讓後面幾晚的刻度是錯的。
       `adherence_minutes` 本來就是後端相對**各自目標**算好的（含跨午夜正規化），
       直接照用才不會產生第二個定義處。
    """
    ticks, labels = [0], ["target"]
    hour = 1
    while hour * 60 <= max_delay + 55:
        ticks.append(hour * 60)
        labels.append(f"+{hour} h")
        hour += 1
    return ticks, labels


def draw(nights, theme_name, out_path, bare=False):
    """bare=True 產給投影片內嵌用：不畫大標題（投影片自己有），畫面壓扁一點。"""
    c = THEMES[theme_name]
    plt.rcParams["font.family"] = FONT_STACK

    dates = [n[0] for n in nights]
    delays = [float(n[2]) for n in nights]

    fig, ax = plt.subplots(figsize=(10, 4.6) if bare else (10, 5.6), dpi=200)
    fig.patch.set_facecolor(c["surface"])
    ax.set_facecolor(c["surface"])

    y = list(range(len(nights)))

    # 垂直格線在資料底下，hairline
    ax.set_axisbelow(True)
    ticks, labels = hour_ticks(max(delays))
    ax.set_xticks(ticks)
    ax.set_xticklabels(labels)
    ax.grid(axis="x", color=c["grid"], linewidth=1, zorder=0)

    # 容許帶（0 ~ 30 分鐘）。畫出來是為了讓圖自己解釋「為什麼晚 1 分鐘仍算達標」，
    # 不用旁白補充。
    ax.axvspan(0, TOLERANCE_MINUTES, color=c["grid"], zorder=1, linewidth=0)

    # 每晚一條：從目標時刻延伸到實際放下手機的時刻。
    # 兩端都是資料端（起點＝目標、終點＝實際），所以用圓頭。
    for yi, delay in zip(y, delays):
        ax.plot(
            [0, delay], [yi, yi],
            color=c["series"], linewidth=13, solid_capstyle="round", zorder=3,
        )

    # 目標線：整張圖的對照基準，用 ink 色虛線而不是另一個系列色
    ax.axvline(0, color=c["text_secondary"], linewidth=2, linestyle=(0, (5, 4)), zorder=4)

    # 直接標籤只給兩條：最晚的那一晚，以及最後一晚（那是唯一落在容許帶內的一晚，
    # 也是這張圖的重點）。其餘靠 x 軸讀，不要每條都掛數字。
    highlights = {delays.index(max(delays)), len(delays) - 1}
    for yi in sorted(highlights):
        label = fmt_delay(delays[yi])
        if yi == len(delays) - 1 and delays[yi] <= TOLERANCE_MINUTES:
            label += "  · first night inside the window"
        ax.text(
            delays[yi] + 11, yi, label,
            va="center", ha="left", fontsize=11, color=c["text_secondary"], zorder=5,
        )

    ax.set_yticks(y)
    ax.set_yticklabels([datetime.strptime(d, "%Y-%m-%d").strftime("%b %-d")
                        if sys.platform != "win32"
                        else datetime.strptime(d, "%Y-%m-%d").strftime("%b %d").replace(" 0", " ")
                        for d in dates])
    ax.invert_yaxis()                      # 最早的一晚放最上面
    ax.set_xlim(-28, max(delays) + 78)     # 右邊留白給標籤
    ax.set_ylim(len(nights) - 0.4, -0.9)

    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(c["baseline"])
    ax.tick_params(colors=c["muted"], labelsize=11, length=0)
    for lbl in ax.get_yticklabels():
        lbl.set_color(c["text_secondary"])

    # ⚠️ 「晚睡」的判準照 behavior/adherence.py 的門檻，不要在這裡另外定一個
    late = sum(1 for d in delays if d > TOLERANCE_MINUTES)
    avg = sum(delays) / len(delays)
    targets = list(dict.fromkeys(n[1][:5] for n in nights))   # 依出現順序去重
    target_note = " → ".join(targets)

    if not bare:
        ax.set_title(
            f"{late} of {len(nights)} nights, the phone went down late",
            fontsize=17, color=c["text_primary"], loc="left", pad=40, fontweight="bold",
        )
    ax.text(
        0, 1.10 if bare else 1.055,
        f"Target bedtime {target_note} · shaded band = {TOLERANCE_MINUTES}-minute "
        f"tolerance · average {fmt_delay(avg).lstrip('+')} late · "
        "measured on the researcher's own phone",
        transform=ax.transAxes, fontsize=11.5, color=c["muted"], va="bottom",
    )

    fig.tight_layout()
    fig.savefig(out_path, facecolor=c["surface"], bbox_inches="tight", pad_inches=0.3)
    plt.close(fig)
    print(f"  wrote {out_path.name}")


def main():
    nights = fetch_nights()
    if not nights:
        raise SystemExit(
            "No nights with a lights-out time found. Is SONNAP_DB_URL set to the "
            "database the phone actually uploads to?"
        )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Slide 4 chart: {len(nights)} nights, {nights[0][0]} to {nights[-1][0]}")
    for theme in ("light", "dark"):
        draw(nights, theme, OUT_DIR / f"slide4_bedtime_vs_target_{theme}.png")
        # 投影片內嵌版：投影片自己有標題，圖裡不要再來一個
        draw(nights, theme, OUT_DIR / f"slide4_bedtime_vs_target_{theme}_bare.png", bare=True)


if __name__ == "__main__":
    main()
