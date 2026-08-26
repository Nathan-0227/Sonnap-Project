"""
migrate_garmin_to_db.py — 把研究者的 46 晚 Garmin 資料灌進資料庫

═══════════════════════════════════════════════════════════════════
這支腳本要做什麼
═══════════════════════════════════════════════════════════════════

在此之前，那 46 晚只存在於 garmin/data/*.json 與打包進 App 的
app_payload.json 裡——**沒有使用者概念**，所以十個同學裝了 APK
會看到同一個人的睡眠分數。

這支腳本把它們搬進 wearable_nightly，掛在一個明確的 user_id 底下，
讓研究者本人變成「使用者之一」而不是「唯一的那個」。

    garmin/data/garmin_sleep_quality_final.json   ← Tier1/2 + Tier3 + 最終分數
    garmin/data/garmin_sleep_quality.json         ← rem_measured（上面那份沒有）
    garmin/data/garmin_sleep_features.json        ← 原始生理量測
                          ↓
                  wearable_nightly（46 列）

═══════════════════════════════════════════════════════════════════
⚠️ 這支腳本**不寫入 nightly_behavior**（Tier A）
═══════════════════════════════════════════════════════════════════
很容易想「Garmin 有 sleep_start_time，拿來當 lights_out_at 不就好了」。
**不行，那是兩個不同的構念：**

    sleep_start_time  = 手錶偵測到你**睡著**的時刻      （生理）
    lights_out_at     = 手機最後一次被操作的時刻        （行為）

兩者可能差半小時以上（躺床上滑手機），而整個 Tier A 的意義正是
「量得到使用者控制得了的那件事」。把生理值塞進行為欄位，
等於讓 46 晚的假行為資料混進真實的受測者資料裡，之後再也分不開。

→ 挑戰難度的驗證改用**離線模擬**（見 --simulate-challenges），
  算完就印出來，不寫進資料庫。

═══════════════════════════════════════════════════════════════════
使用方式
═══════════════════════════════════════════════════════════════════
    python migrate_garmin_to_db.py                  # 灌資料（可重複執行）
    python migrate_garmin_to_db.py --verify         # 只驗證，不寫入
    python migrate_garmin_to_db.py --simulate-challenges
                                                    # 用 46 晚模擬挑戰難度
"""

import argparse
import csv
import json
import sys
from pathlib import Path

import db

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
GARMIN_DATA = ROOT / "garmin" / "data"

# ═══════════════════════════════════════════════════════════════════
# 研究者的固定 user_id
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️ **寫死一個固定 UUID 是刻意的**，讓這支腳本可以重複執行：
#    每次都 create_user() 產生新 uuid4 的話，跑三次就會有三個研究者，
#    每個各自掛著 46 晚重複資料——而且不會有任何錯誤訊息。
#
#    這個值是隨機產生後寫死的，不是從任何個資推出來的
#    （不要改成 uuid5(email) 之類，那會讓 id 本身帶有個資）。
RESEARCHER_USER_ID = "00000000-5017-4e01-9a30-000000000001"

# 裝置型號要記錄，理由見 db.py 的 wearable_nightly schema：
# 跨品牌的睡眠分期演算法不互通，source 與 device_brand 是方法學上的
# 必要資訊，不是備註。
RESEARCHER_DEVICE = "Garmin Vivoactive 3"

# ⚠️ 年齡層要跟當初跑 pipeline 時用的一致，否則等於用不同的參考區間
#    去解讀同一批分數。extract_sleep_features.py 的 DEFAULT_AGE = 22
#    → young_adult。features.json 每一列都帶著 age_band，
#    下面會實際讀出來核對，不是照抄這個預設值。
RESEARCHER_AGE_BAND = "young_adult"


def load(name):
    """讀 garmin/data/ 底下的 JSON。缺檔時給出可以直接照做的指示。"""
    path = GARMIN_DATA / name
    if not path.exists():
        sys.exit(
            f"\u2717 {path} not found\n"
            f"  Run this first: python garmin/run_pipeline.py"
        )
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def index_by_date(rows):
    """[{date: ...}, ...] → {date: row}。"""
    return {r["date"]: r for r in rows or []}


def build_rows():
    """
    把三個 JSON 對齊成每晚一筆 (date, metrics)。

    ⚠️ 三個檔的夜數**應該相同**（都是 46）。不同的話代表有人只重跑了
       pipeline 的一部分——那正是 2026-08-10 踩過的坑（漏跑中間步驟
       不會報錯，後面的步驟會安靜地用上次留下的舊檔案算）。
       所以這裡明確檢查並中止，而不是取交集繼續跑。
    """
    final = load("garmin_sleep_quality_final.json")
    base = load("garmin_sleep_quality.json")      # 只為了 rem_measured
    feats = load("garmin_sleep_features.json")

    by_base = index_by_date(base)
    by_feat = index_by_date(feats)

    if not (len(final) == len(base) == len(feats)):
        sys.exit(
            f"\u2717 The three files disagree on night counts: "
            f"quality_final={len(final)}, quality={len(base)}, features={len(feats)}.\n"
            f"  Most likely only part of the pipeline was re-run.\n"
            f"  Run the whole thing: python garmin/run_pipeline.py"
        )

    rows = []
    for q in final:
        date = q["date"]
        f = by_feat.get(date)
        b = by_base.get(date)
        if f is None or b is None:
            sys.exit(f"\u2717 {date} does not line up across the three files; re-run the pipeline.")

        rows.append((date, {
            "device_brand": RESEARCHER_DEVICE,
            # ── 原始生理量測 ──
            "duration_min": f.get("total_sleep_minutes"),
            "efficiency": f.get("sleep_efficiency"),
            "waso_min": f.get("waso_minutes"),
            "deep_min": f.get("deep_minutes"),
            "rem_min": f.get("rem_minutes"),
            "avg_hr": f.get("avg_heart_rate"),
            "resting_hr": f.get("resting_heart_rate"),
            # ── 臥床時間：Garmin **給不出來** ──
            # ⚠️ 一律 None 而不是拿 sleep_period 充數。Garmin 只知道
            #    你什麼時候睡著，不知道你什麼時候躺下——這正是
            #    PROJECT_STATUS.md 3.9 記錄的限制。填一個近似值進去，
            #    就再也沒有人會記得這一欄其實是假的。
            "time_in_bed_min": None,
            "clinical_efficiency": None,
            # ── Tier1/2 ──
            "base_score": q.get("base_score"),
            "base_quality": q.get("base_quality"),
            # rem_measured 只有 Tier1/2 那份輸出有，final 那份沒帶過來
            "rem_measured": 1 if b.get("rem_measured") else 0,
            # ── Tier3 與 SRI（只有 Garmin 來源會有值）──
            "total_modifier": q.get("total_modifier"),
            "sri": q.get("sri"),
            "modifier_note": q.get("modifier_note"),
            # 自律神經三分項。pet_mood 的 anxious 覆寫是定義在這三個上的，
            # 用 total_modifier 代替會算錯——總和可能被別項的加分抵銷掉。
            "rhr_modifier": q.get("rhr_modifier"),
            "avg_hr_modifier": q.get("avg_hr_modifier"),
            "stress_modifier": q.get("stress_modifier"),
            # ── 最終分數：存實際值，不讓讀取端自己 base + modifier ──
            "final_score": q.get("final_score"),
            "final_quality": q.get("final_quality"),
        }))

    return rows, feats


def ensure_user(db_path=None):
    """
    確保研究者這個使用者存在。已存在就直接用，不重建。

    回傳 (user_id, 是否為新建)。
    """
    existing = db.get_user(RESEARCHER_USER_ID, db_path)
    if existing:
        return RESEARCHER_USER_ID, False

    db.create_user(
        display_name="Researcher (self)",
        target_bedtime="23:30",
        age_band=RESEARCHER_AGE_BAND,
        # L2 = 研究者本人：全部資料 + Tier3 + SRI + 攝影機
        study_cohort="L2",
        wearable_brand=RESEARCHER_DEVICE,
        db_path=db_path,
        user_id=RESEARCHER_USER_ID,
    )
    return RESEARCHER_USER_ID, True


def verify(user_id, db_path=None):
    """
    驗收第 4 項：wearable_nightly 有 46 列，且 final_score 與
    garmin_sleep_quality_final.csv **逐列相符**。

    ⚠️ 刻意拿 **CSV** 而不是 JSON 來比對。JSON 正是灌資料時讀的那份，
       拿它比對等於自己跟自己比，任何搬運過程的錯誤都驗不出來。
       CSV 是 pipeline 的另一份獨立輸出，比對它才有意義。
    """
    csv_path = GARMIN_DATA / "garmin_sleep_quality_final.csv"
    if not csv_path.exists():
        return False, f"Comparison file {csv_path.name} not found"

    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        expected = {r["date"]: r for r in csv.DictReader(f)}

    stored = {r["date"]: r for r in db.get_wearable_nightly(
        user_id, days=10_000, db_path=db_path)}

    problems = []
    if len(stored) != len(expected):
        problems.append(
            f"Row count mismatch: database has {len(stored)}, CSV has {len(expected)}"
        )

    for date, exp in expected.items():
        got = stored.get(date)
        if got is None:
            problems.append(f"{date} is not in the database")
            continue
        # CSV 全是字串，轉成 float 再比。用 != 直接比字串會因為
        # "85.0" vs "85" 這種格式差異而誤報。
        exp_score = float(exp["final_score"])
        if abs((got["final_score"] or -1) - exp_score) > 1e-9:
            problems.append(
                f"{date} final_score mismatch: database {got['final_score']}, "
                f"CSV {exp_score}"
            )
        if got["final_quality"] != exp["final_quality"]:
            problems.append(
                f"{date} final_quality mismatch: database {got['final_quality']}, "
                f"CSV {exp['final_quality']}"
            )

    return (not problems), problems


# 模擬時要試哪些目標就寢時間。
#
# ⚠️ **必須掃過多個目標，不能只用一個。** time 與 streak 兩種挑戰的難度
#    **完全由使用者自己設的目標決定**——只用預設值 23:30 去跑，
#    對一個平均 02:34 才睡的人來說達成率必然接近 0，
#    然後就會誤判成「挑戰設計壞了」。第一次跑就是這樣被騙到的。
SIM_TARGETS = ("23:30", "01:00", "02:00", "02:30", "03:00")


def _simulate_rows(starts, target, collapse_gaps=False):
    """
    把入睡時刻列表轉成模擬的 nightly_behavior。

    collapse_gaps=True 時把日期重新編號成**連續的日曆日**。
    ⚠️ 這個選項是必要的，理由見 simulate_challenges 的說明：
       手錶配戴的斷點會吃掉連續紀錄，而 Tier A 的資料來源是手機，
       不會有那種斷點。不拿掉的話會把 streak 的門檻訂得過低。
    """
    from datetime import date as _date, timedelta as _td

    from behavior import adherence

    rows = []
    base = _date(2026, 1, 1)
    for i, s in enumerate(sorted(starts)):
        night = adherence.evaluate_night(s, target, source="simulated")
        if collapse_gaps:
            night["date"] = (base + _td(days=i)).isoformat()
        rows.append(night)
    rows.sort(key=lambda r: r["date"])
    return rows


def _rate(challenge, rows):
    """
    逐日重跑這個挑戰，回傳 (達成的日子, 可評估的日子)。

    ⚠️ 逐日重跑而不是只看最後一晚。只看最後一晚等於 n=1，
       那個數字完全取決於最後那天剛好如何，沒有參考價值。
    """
    from behavior import challenges

    done = evaluable = 0
    for r in rows:
        result = challenges.evaluate_challenge(challenge, rows, as_of=r["date"])
        if result["status"] == "insufficient_data":
            continue
        evaluable += 1
        if result["completed"]:
            done += 1
    return done, evaluable


def simulate_challenges(feats):
    """
    用 46 晚的 sleep_start_time 模擬 lights_out_at，跑一次挑戰引擎，
    看看難度合不合理。**結果只印出來，不寫進資料庫。**

    ⚠️ 這是**模擬，不是量測**，有兩個已知的偏誤方向，都要講清楚：

    1. **構念代換**：sleep_start_time 是「睡著」，lights_out_at 是
       「放下手機」，兩者差一段入睡潛伏期（躺床上滑手機的時間）。
       真實的 lights_out_at 一定**早於** sleep_start_time，
       所以真實的 adherence_minutes 會比這裡算的小、比較容易達成。
       → 這個模擬**偏悲觀**。

    2. **配戴斷點**：46 晚散在 74 個日曆日裡（手錶配戴率問題），
       只有 1 段連續 ≥5 天。而「連續達成」的定義是缺資料就中斷，
       所以斷點會吃掉大部分的連續紀錄。
       → 但 Tier A 的資料來源是**手機**，天天都在，不會有這種斷點。
       → 所以 streak 那一項要看「去掉斷點」那一欄才有意義。

    這個模擬能回答的問題只有一個：**難度是不是荒謬到沒有意義**
    （全部達成或全部失敗）。它回答不了「真實達成率會是多少」。
    """
    from behavior import adherence, challenges

    starts = [f["sleep_start_time"] for f in feats if f.get("sleep_start_time")]
    if not starts:
        print("features.json has no sleep_start_time; cannot simulate.")
        return

    ref = _simulate_rows(starts, "23:30")
    print(f"\nSimulation sample: {len(ref)} nights ({ref[0]['date']} ~ {ref[-1]['date']})")
    print("\u26a0 Uses sleep-onset time as a stand-in for phone-down time: simulated, not measured.\n")

    by_kind = {c["kind"]: c for c in db.DEFAULT_CHALLENGES}

    # ── time 與 streak：難度由使用者自己的目標決定，所以掃過多個目標 ──
    time_c = by_kind.get("time")
    streak_c = by_kind.get("streak")

    print("[1] On time / streak - difficulty is set entirely by the user's own target")
    print(f"{'Target':<9}{'On-time':>10}{'Streak(raw)':>14}{'Streak(no gaps)':>18}"
          f"   <- the no-gaps column is what phone data looks like")
    print("-" * 66)
    for target in SIM_TARGETS:
        raw = _simulate_rows(starts, target)
        flat = _simulate_rows(starts, target, collapse_gaps=True)

        on_time = sum(1 for r in raw if r["adherence_minutes"] <= 0)
        d_raw, e_raw = _rate(streak_c, raw) if streak_c else (0, 0)
        d_flat, e_flat = _rate(streak_c, flat) if streak_c else (0, 0)

        print(f"{target:<9}{on_time / len(raw):>7.0%}"
              f"{(d_raw / e_raw if e_raw else 0):>11.0%}"
              f"{(d_flat / e_flat if e_flat else 0):>13.0%}")

    print(f"\n  This user falls asleep at 02:34 on average. With a target near their own "
          f"\n  rhythm (02:00-03:00) the streak challenge forms a sensible gradient; "
          f"a 23:30 target is necessarily close to 0 - "
          f"\n  that is not the challenge being broken, it is the target being unrealistic for this person.")
    print(f"\n  \u26a0 Product implication: a new user who keeps the 23:30 default while "
          f"\n     actually sleeping at 2-3am WILL SEE 0% ON DAY ONE AND QUIT. Registration "
          f"\n     must ask when they usually sleep and suggest a target from that.")

    # ── consistency：與目標時間完全無關，只看就寢時間的離散度 ──
    cons_c = by_kind.get("consistency")
    if cons_c:
        rows = ref
        done, evaluable = _rate(cons_c, rows)
        print(f"\n[2] {cons_c['title']} - independent of the target time; only spread matters")
        print(f"  Threshold \u00b1{cons_c['target_value']:.0f} min: "
              f"{done}/{evaluable} = {done / evaluable if evaluable else 0:.0%}")

        # 各門檻的敏感度，讓看的人自己判斷這個門檻訂得對不對
        spreads = []
        for r in rows:
            scoped, _ = challenges.window_rows(rows, cons_c["window_days"],
                                               as_of=r["date"])
            sp, n = adherence.bedtime_spread_minutes(scoped)
            if sp is not None and n >= (cons_c["window_days"] // 2 + 1):
                spreads.append(sp)
        if spreads:
            spreads.sort()
            mid = spreads[len(spreads) // 2]
            print(f"  Median spread {mid:.0f} min"
                  f" (min {spreads[0]:.0f}, max {spreads[-1]:.0f})")
            print("  Attainment by threshold: ", end="")
            for th in (30, 45, 60, 90, 120):
                n = sum(1 for s in spreads if s <= th)
                print(f"  ±{th}→{n / len(spreads):.0%}", end="")
            print()

    print(f"\n\u26a0 Calibration sample is n=1, and this person is unusually irregular "
          f"(bedtime SD 84 min).\n   These thresholds are provisional; re-run once D2 supplies real data.")


def main():
    parser = argparse.ArgumentParser(
        description="Load the researcher's Garmin data into wearable_nightly."
    )
    parser.add_argument("--verify", action="store_true",
                        help="Only verify that the database matches the CSV; do not write.")
    parser.add_argument("--simulate-challenges", action="store_true",
                        help="Simulate challenge difficulty over the 46 nights (no database writes).")
    parser.add_argument("--db", default=None, help="Database path (for tests).")
    args = parser.parse_args()

    rows, feats = build_rows()

    if args.simulate_challenges:
        simulate_challenges(feats)
        return

    # 年齡層核對：features.json 每一列都帶 age_band，
    # 跟預期不同的話代表 pipeline 是用別的年齡跑的。
    bands = {f.get("age_band") for f in feats}
    if bands != {RESEARCHER_AGE_BAND}:
        print(f"\u26a0 features.json age_band is {bands}, "
              f"which differs from the expected {RESEARCHER_AGE_BAND!r}. "
              f"Scores were computed with the former; the user record will reflect it as-is.")

    if not args.verify:
        db.init_db(args.db)
        user_id, created = ensure_user(args.db)
        print(f"{'Created' if created else 'Reusing existing'} user {user_id}")

        for date, metrics in rows:
            db.upsert_wearable_nightly(
                user_id, date, source="garmin", metrics=metrics,
                db_path=args.db,
            )
        print(f"Wrote {len(rows)} nights into wearable_nightly")
    else:
        user_id = RESEARCHER_USER_ID

    ok, problems = verify(user_id, args.db)
    if ok:
        print(f"\u2713 Verified: final_score / final_quality for {len(rows)} nights "
              f"match garmin_sleep_quality_final.csv row for row")
    else:
        print("\u2717 Verification failed:")
        for p in (problems if isinstance(problems, list) else [problems]):
            print(f"    {p}")
        sys.exit(1)


if __name__ == "__main__":
    main()
