"""
inspect_tapo_dump.py

清點影像組給的 `tapo/sleep_records.sql`，並輸出「哪些夜晚的日期可以信」。

⚠️ **為什麼需要這支：**`report_date` 不是可以直接拿來 merge 的鍵。
   PROJECT_STATUS.md 3.10 ① 記過：日期錯了就是把 A 晚的攝影機資料配上
   B 晚的手錶資料，而 `how='inner'` 會安靜地丟掉配不上的列，不會報錯。

判斷日期可不可信，唯一的內部證據是 `created_at`：

    現場擷取   created_at 與 report_date 同日，或差 ±1 天（夜晚跨午夜）
    事後批次補 一批列的 created_at 完全相同（同一秒）→ 日期是人工填的
    幾乎確定錯 相差超過一週

⚠️ 這支只用標準庫（專案規範：非必要不用 pandas）。它**不做任何評分**，
   只清點與比對，所以不受「遊戲化層不得回寫評分層」那條紅線影響。

執行：python inspect_tapo_dump.py
"""
import csv
import io
import json
import re
import sys
from collections import Counter
from datetime import date
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent
DUMP = ROOT / "tapo" / "sleep_records.sql"
GARMIN = ROOT / "garmin" / "data" / "garmin_sleep_quality_final.csv"
FEATURES = ROOT / "garmin" / "data" / "garmin_sleep_features.csv"

# 一列 INSERT 的形狀：(id, 'date', events, large, snore, score, '[timeline]', 'created', 'updated')
ROW_RE = re.compile(
    r"\((\d+), '(\d{4}-\d{2}-\d{2})', (\d+), (\d+), (\d+), (\d+), "
    r"'(\[.*?\])', '([\d\- :]+)', '([\d\- :]+)'\)",
    re.S,
)

# 同日或差 ±1 天都算現場擷取：夜晚跨午夜時，report_date 用哪一天是慣例問題。
LIVE_TOLERANCE_DAYS = 1


def parse_dump(path):
    """把 dump 解析成 list of dict。壞掉的 timeline 不會讓整支掛掉。"""
    sql = io.open(path, encoding="utf-8", errors="replace").read()
    out = []
    for m in ROW_RE.finditer(sql):
        rid, rdate, events, large, snore, score, timeline, created, updated = m.groups()
        try:
            tl = json.loads(timeline.replace('\\"', '"'))
        except (ValueError, TypeError):
            tl = None
        times = sorted(x["time"] for x in (tl or []) if "time" in x)
        out.append({
            "id": int(rid),
            "report_date": rdate,
            "total_events": int(events),
            "large_turn_count": int(large),
            "snore_count": int(snore),
            "score": int(score),
            "created_at": created,
            "first_event": times[0] if times else None,
            "last_event": times[-1] if times else None,
            "n_timeline": len(tl) if tl is not None else None,
        })
    return out


def classify(rows):
    """
    依 created_at 與 report_date 的關係分層。

    「事後批次補」的判準是**同一個 created_at 出現在多列**——那代表它們是
    一次寫進去的，report_date 只能是人工填的。單看一列看不出來，
    所以要先數過整批。
    """
    bulk = {c for c, n in Counter(r["created_at"] for r in rows).items() if n > 1}
    for r in rows:
        try:
            delta = (date.fromisoformat(r["created_at"][:10])
                     - date.fromisoformat(r["report_date"])).days
        except ValueError:
            r["layer"], r["delta_days"] = "日期無法解析", None
            continue
        r["delta_days"] = delta
        if r["created_at"] in bulk:
            r["layer"] = "事後批次補"
        elif abs(delta) <= LIVE_TOLERANCE_DAYS:
            r["layer"] = "現場擷取"
        else:
            r["layer"] = "幾乎確定錯"
    return rows


def load_garmin_nights():
    if not GARMIN.exists():
        return set(), {}
    with io.open(GARMIN, encoding="utf-8-sig") as f:
        nights = {r["date"] for r in csv.DictReader(f)}
    feats = {}
    if FEATURES.exists():
        with io.open(FEATURES, encoding="utf-8-sig") as f:
            feats = {r["date"]: r for r in csv.DictReader(f)}
    return nights, feats


def main():
    if not DUMP.exists():
        sys.exit(f"✗ 找不到 {DUMP}。這個檔由影像組提供。")

    rows = classify(parse_dump(DUMP))
    if not rows:
        sys.exit("✗ 解析不到任何紀錄。dump 的欄位順序可能改了，請看 ROW_RE。")

    nights, feats = load_garmin_nights()

    print("=" * 78)
    print(f"TAPO dump 清點：{DUMP.relative_to(ROOT)}")
    print("=" * 78)
    print(f"紀錄數：{len(rows)}")
    scores = sorted({r['score'] for r in rows})
    print(f"sleep_quality_score：{len(scores)} 個不同的值，{min(scores)} ~ {max(scores)}")
    if len(scores) == 1:
        print("  ⚠️ 所有紀錄同分 → 紅線 3「分數不得有人為地板」，不同夜晚彼此無法區分")

    print()
    print(f"{'id':>4} {'report_date':<12} {'層級':<12} {'created_at':<20} "
          f"{'首事件':>9} {'末事件':>9} {'事件':>6} {'分數':>5}")
    for r in sorted(rows, key=lambda x: x["report_date"]):
        mark = "★" if r["report_date"] in nights else " "
        print(f"{r['id']:>4} {r['report_date']:<12}{mark}{r['layer']:<11} "
              f"{r['created_at']:<20} {str(r['first_event'] or '—'):>9} "
              f"{str(r['last_event'] or '—'):>9} {r['total_events']:>6} {r['score']:>5}")
    print("  ★ = 這一晚 Garmin 也有計分資料")

    # ── 資料一致性：total_events 與 timeline 必須對得起來 ──
    # 對不上代表寫入端與統計端不同步，而那會讓任何以 total_events 為準的
    # 分析（含 sleep_quality_score 的扣分公式）落在一份不存在的 timeline 上。
    mismatch = [r for r in rows
                if r["n_timeline"] is None or r["n_timeline"] != r["total_events"]]
    if mismatch:
        print()
        print("⚠️ total_events 與 timeline 筆數對不上：")
        for r in mismatch:
            n = "JSON 解析失敗" if r["n_timeline"] is None else r["n_timeline"]
            print(f"    id {r['id']} ({r['report_date']})："
                  f"total_events={r['total_events']}，timeline={n}")
        print("    → 寫入端與統計端不同步，請回報影像組。")

    print()
    print("-" * 78)
    print("分層統計（★ 欄是與 Garmin 的重疊）")
    print("-" * 78)
    for layer in ("現場擷取", "事後批次補", "幾乎確定錯", "日期無法解析"):
        sel = [r for r in rows if r.get("layer") == layer]
        if not sel:
            continue
        ov = sorted(r["report_date"] for r in sel if r["report_date"] in nights)
        print(f"  {layer:<10} {len(sel):>2} 筆｜與 Garmin 重疊 {len(ov)} 晚 {ov}")

    total_ov = sorted(r["report_date"] for r in rows if r["report_date"] in nights)
    live_ov = sorted(r["report_date"] for r in rows
                     if r.get("layer") == "現場擷取" and r["report_date"] in nights)
    print()
    print(f"  → 重疊夜數：最寬鬆 {len(total_ov)} 晚，只算現場擷取 {len(live_ov)} 晚")

    # ── 上床時刻可行性：首事件 vs Garmin 入睡（見 PROJECT_STATUS 3.9）──
    if feats:
        print()
        print("-" * 78)
        print("首事件能不能當「上床時刻」（PROJECT_STATUS 3.9）")
        print("-" * 78)
        print(f"{'日期':<12}{'層級':<12}{'機:首事件':>10}{'錶:入睡':>10}{'差':>8}  判定")
        for r in sorted(rows, key=lambda x: x["report_date"]):
            g = feats.get(r["report_date"])
            if not g:
                continue
            first = r["first_event"]
            onset = g["sleep_start_time"][11:19]

            def mins(t):
                h, m, _ = t.split(":")
                return int(h) * 60 + int(m)

            if not first:
                verdict, diff = "timeline 沒有事件", None
            elif first.startswith("00:00:0"):
                verdict, diff = "❌ 時間戳壞掉", None
            else:
                d = mins(first) - mins(onset)
                if d > 720:
                    d -= 1440
                if d < -720:
                    d += 1440
                diff = d
                if -180 <= d < 0:
                    verdict = "✅ 早於入睡，合理"
                elif d >= 0:
                    verdict = "❌ 晚於入睡（監測窗沒開到）"
                else:
                    verdict = "❌ 早太多"
            ds = f"{diff:+d} 分" if diff is not None else "—"
            print(f"{r['report_date']:<12}{r['layer']:<12}{str(first or '—'):>10}"
                  f"{onset:>10}{ds:>8}  {verdict}")

        print()
        print("  ⚠️ 「晚於入睡」多半不是偵測失敗，是攝影機還沒開機——")
        print("     tapo 2.0/.env 的 SLEEP_START 決定它幾點開始錄。")

    print()
    print("=" * 78)


if __name__ == "__main__":
    main()
