"""
tests/test_morning_import.py — 早上那支匯入腳本的檢查有沒有真的擋住

⚠️ 全程用暫存資料夾與假的子程式：**不會真的抓 Garmin、不會呼叫 Claude API、
   不會連資料庫**。錄影檔是照 tapo_metric_logger 的格式造出來的，
   但臥床時間走的是真的 tapo_sleep_onset.analyse()。

這支守的是四個**壞掉時不會報錯**的地方：

1. **攝影機沒過時，手錶根本不能開始抓。** 順序寫反的話，檢查照樣會擋下來，
   但手錶資料已經被覆寫、備份也建了——使用者看到「停下來了」會以為什麼都沒動。
2. **手錶少了夜晚時要還原，而且一筆都不寫。** 只停不還原的話，
   App 讀的資料檔已經是少了歷史的那一份，後端會照樣對外服務它。
3. **抓資料一定帶完整區間，不帶 --fetch。** 少一個參數就是整份歷史被換掉。
4. **正常的夜晚不能被擋。** 門檻訂太嚴的話，使用者每天早上都得加
   --skip-camera，那這個檢查很快就會被習慣性地繞過。
   （09-12 那晚是 0.91，是真實存在的「正常但不完美」。）

執行：python tests/test_morning_import.py
"""
import argparse
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import morning_import as mi  # noqa: E402

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


# ─── 造假資料 ─────────────────────────────────────────────────────

COLUMNS = ("t,mean,raw_px,fg_px,blobs,max_px,max_x,max_y,max_w,max_h,"
           "illum_skip,warmup,vf,roi_px,roi_x,roi_y,roi_w,roi_h")


def write_recording(path, started, usable_minutes, dead_minutes=0, step_s=5):
    """
    照 tapo_metric_logger 的格式寫一份錄影 CSV。

    usable_minutes：有畫面的時間（沒有動作，max_px = 0）
    dead_minutes  ：接在後面、串流斷掉的時間——logger 只寫空值標記列
    """
    lines = [
        f"# tapo_metric_logger  started={started.isoformat()}",
        "# size=640x360 fps=5.0 blur=7 mog2_history=500 var=16 lr=0.002000 open=5",
        "# roi=full",
        "# source=rtsp://…@test/stream2",
        COLUMNS,
    ]
    t = started
    end_usable = started + timedelta(minutes=usable_minutes)
    while t <= end_usable:
        warm = 1 if (t - started).total_seconds() < 90 else 0
        lines.append(f"{t.isoformat(timespec='milliseconds')},50.00,0,0,0,0,0,0,0,0,0,{warm},,,,,,")
        t += timedelta(seconds=step_s)
    end_dead = end_usable + timedelta(minutes=dead_minutes)
    t = end_usable + timedelta(minutes=10)
    while t <= end_dead:
        lines.append(f"{t.isoformat(timespec='milliseconds')},,,,,,,,,,1,1,")
        t += timedelta(minutes=10)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    old = time.time() - 3600          # 一小時前寫完的，不算「還在錄」
    os.utime(path, (old, old))
    return path


def nights_json(dates):
    return [{"date": d, "final_score": 70.0 + i} for i, d in enumerate(dates)]


def make_project(tmp, dates):
    root = tmp / "project"
    (root / "garmin" / "data").mkdir(parents=True)
    (root / "app" / "assets" / "data").mkdir(parents=True)
    (root / "tapo_metrics").mkdir()
    (root / "garmin" / "data" / "garmin_sleep_quality_final.json").write_text(
        json.dumps(nights_json(dates)), encoding="utf-8")
    (root / "garmin" / "data" / "garmin_standard_data.json").write_text(
        '{"original": true}', encoding="utf-8")
    (root / "app" / "assets" / "data" / "app_payload.json").write_text(
        '{"payload": "original"}', encoding="utf-8")
    return mi.Paths(root=root, backup_root=tmp / "backups")


class FakeRunner:
    """記下每一次呼叫；抓取與評分那兩步照指定的方式改檔。"""

    def __init__(self, paths, after_dates, fetch_rc=0, pipeline_rc=0, ai_rc=0):
        self.paths = paths
        self.after_dates = after_dates
        self.rc = {"garmin/garmin_connect_fetch.py": fetch_rc,
                   "garmin/run_pipeline.py": pipeline_rc,
                   "ai/generate_advice.py": ai_rc}
        self.calls = []

    def __call__(self, argv):
        self.calls.append(list(argv))
        script = argv[0]
        if script == "garmin/garmin_connect_fetch.py":
            (self.paths.garmin_data / "garmin_standard_data.json").write_text(
                '{"refetched": true}', encoding="utf-8")
        if script == "garmin/run_pipeline.py":
            self.paths.final_json.write_text(json.dumps(nights_json(self.after_dates)),
                                             encoding="utf-8")
            self.paths.payload.write_text('{"payload": "rebuilt"}', encoding="utf-8")
        return self.rc.get(script, 0)

    def scripts(self):
        return [c[0] for c in self.calls]


def args(**kw):
    base = {"skip_camera": False, "camera_csv": None, "no_ai": False}
    base.update(kw)
    return argparse.Namespace(**base)


def db_ok(env):
    return True, ""


BEFORE = ["2026-09-12", "2026-09-13"]
AFTER = BEFORE + ["2026-09-14"]
NOW = datetime(2026, 9, 14, 10, 0, 0)
DB_ENV = {"SONNAP_DB_URL": "mysql://root@localhost/sonnap"}


def quiet(fn, *a, **kw):
    """主流程會印一大段，測試輸出只留結論。"""
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        result = fn(*a, **kw)
    return result, buf.getvalue()


# ═══════════════════════════════════════════════════════════════════
print("\n【1】攝影機檢查：擋得住壞的，放得過正常的")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    start = datetime(2026, 9, 14, 4, 13, 55)

    v = mi.check_camera(write_recording(d / "20260914_041355.csv", start, 260))
    ok("整晚都有資料 → 通過", v.ok, f"{v.time_in_bed_minutes:.0f}/{v.recorded_minutes:.0f}")

    # 09-12 的形狀：有資料 610 分，起床後串流斷了一小時才按停
    v = mi.check_camera(write_recording(d / "20260912_011758.csv", start, 610, dead_minutes=60))
    ok("起床後斷了一小時（09-12，比例 0.91）→ 通過", v.ok,
       f"{v.time_in_bed_minutes / v.recorded_minutes:.2f}")

    # 09-13 的形狀：有資料 124 分，後面斷了三小時
    v = mi.check_camera(write_recording(d / "20260913_045549.csv", start, 124, dead_minutes=180))
    ok("後半夜斷線（09-13，比例 0.41）→ 擋下", not v.ok,
       f"{v.time_in_bed_minutes:.0f}/{v.recorded_minutes:.0f}")
    ok("  擋下的理由有講出兩個數字", "錄了" in v.reason and "臥床" in v.reason)
    ok("  而且它確實過了 120 分鐘（證明擋下它的是比例，不是長度）",
       v.time_in_bed_minutes >= mi.migrate_camera_to_db.MIN_NIGHT_MINUTES)

    v = mi.check_camera(write_recording(d / "20260909_021654.csv", start, 60))
    ok("只錄到 60 分鐘 → 擋下", not v.ok)

    live = write_recording(d / "20260914_230000.csv", start, 260)
    os.utime(live, None)                      # 剛剛才寫過
    v = mi.check_camera(live)
    ok("錄影還在寫入 → 擋下", not v.ok and "Ctrl+C" in v.reason)

print("\n【2】挑昨晚的錄影：挑最長的那份，前幾天的不拿出來重匯")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    write_recording(d / "20260912_011758.csv", datetime(2026, 9, 12, 1, 17, 58), 300)
    write_recording(d / "20260914_041339.csv", datetime(2026, 9, 14, 4, 13, 39), 1)     # 誤開的
    write_recording(d / "20260914_041355.csv", datetime(2026, 9, 14, 4, 13, 55), 260)
    # 起床後又誤開一次：檔名比正式那份**新**，挑「最新的」就會挑到它
    write_recording(d / "20260914_083500.csv", datetime(2026, 9, 14, 8, 35, 0), 1)
    write_recording(d / "20260914_041135_selftest.csv", datetime(2026, 9, 14, 4, 11, 35), 2)

    night, chosen, skipped = mi.last_night_recording(d, datetime(2026, 9, 14, 10, 0))
    ok("早上 10 點：挑到 09-14 那晚", str(night) == "2026-09-14", str(night))
    ok("  挑的是錄得最久的那份，不是最新的那份", chosen and chosen.name == "20260914_041355.csv",
       chosen.name if chosen else "None")
    ok("  兩份誤開檔都列為略過",
       sorted(p.name for p in skipped) == ["20260914_041339.csv", "20260914_083500.csv"],
       str([p.name for p in skipped]))
    ok("  自測檔不列入", all("selftest" not in p.name for p in [chosen, *skipped]))

    night, chosen, _ = mi.last_night_recording(d, datetime(2026, 9, 14, 21, 0))
    ok("晚上 9 點跑：昨晚仍然是 09-14", str(night) == "2026-09-14", str(night))

    night, chosen, _ = mi.last_night_recording(d, datetime(2026, 9, 17, 10, 0))
    ok("三天沒錄：找不到，而不是把 09-14 拿出來重匯", chosen is None, str(chosen))

print("\n【3】攝影機沒過 → 手錶根本不抓、不備份、不寫")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    paths = make_project(d, BEFORE)
    write_recording(paths.metrics_dir / "20260914_045549.csv",
                    datetime(2026, 9, 14, 4, 55, 49), 124, dead_minutes=180)
    runner = FakeRunner(paths, AFTER)
    rc, out = quiet(mi.run, args(), paths, NOW, DB_ENV, runner=runner, db_check=db_ok)
    ok("exit code 不是 0", rc != 0, str(rc))
    ok("一支子程式都沒跑（沒抓手錶、沒寫資料庫）", runner.calls == [], str(runner.scripts()))
    ok("沒有建備份資料夾", not paths.backup_root.exists())
    ok("有告訴使用者 --skip-camera 怎麼用", "--skip-camera" in out)

print("\n【4】手錶少了夜晚 → 還原檔案，一筆都不寫")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    paths = make_project(d, BEFORE)
    original_final = paths.final_json.read_bytes()
    runner = FakeRunner(paths, after_dates=["2026-09-14"])        # 只剩最近一天
    rc, out = quiet(mi.run, args(skip_camera=True), paths, NOW, DB_ENV, runner=runner, db_check=db_ok)
    ok("exit code 不是 0", rc != 0, str(rc))
    ok("沒有跑任何寫入", not {"migrate_garmin_to_db.py", "migrate_camera_to_db.py",
                          "ai/generate_advice.py", "build_app_payload.py"} & set(runner.scripts()),
       str(runner.scripts()))
    ok("評分結果還原成跑之前的", paths.final_json.read_bytes() == original_final)
    ok("手錶原始資料也還原了",
       (paths.garmin_data / "garmin_standard_data.json").read_text(encoding="utf-8") == '{"original": true}')
    ok("App 資料檔也還原了", paths.payload.read_text(encoding="utf-8") == '{"payload": "original"}')
    ok("有講出是哪幾晚不見", "2026-09-12" in out and "2026-09-13" in out)

print("\n【5】抓資料或評分失敗 → 同樣還原、不寫")
for label, kw in (("抓資料失敗", {"fetch_rc": 1}), ("評分失敗", {"pipeline_rc": 1})):
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        paths = make_project(d, BEFORE)
        runner = FakeRunner(paths, AFTER, **kw)
        rc, _ = quiet(mi.run, args(skip_camera=True), paths, NOW, DB_ENV, runner=runner, db_check=db_ok)
        ok(f"{label} → exit code 不是 0、沒有寫入",
           rc != 0 and "migrate_garmin_to_db.py" not in runner.scripts(), str(runner.scripts()))
        ok(f"  {label} → 原始資料還原",
           (paths.garmin_data / "garmin_standard_data.json").read_text(encoding="utf-8") == '{"original": true}')

print("\n【6】全部通過 → 照順序寫入；抓資料帶完整區間、不用 --fetch")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    paths = make_project(d, BEFORE)
    csv_path = write_recording(paths.metrics_dir / "20260914_041355.csv",
                               datetime(2026, 9, 14, 4, 13, 55), 260)
    runner = FakeRunner(paths, AFTER)
    rc, out = quiet(mi.run, args(), paths, NOW, DB_ENV, runner=runner, db_check=db_ok)
    ok("exit code 0", rc == 0, str(rc))
    ok("順序：抓 → 評分 → 手錶入庫 → 攝影機入庫 → 夢境 → App 資料檔",
       runner.scripts() == ["garmin/garmin_connect_fetch.py", "garmin/run_pipeline.py",
                            "migrate_garmin_to_db.py", "migrate_camera_to_db.py",
                            "ai/generate_advice.py", "build_app_payload.py"],
       str(runner.scripts()))
    fetch = runner.calls[0]
    ok("抓資料帶 --start-date 第一個戴錶者分段的起日",
       fetch[fetch.index("--start-date") + 1] == "2026-05-28" if "--start-date" in fetch else False,
       str(fetch))
    ok("  --end-date 是今天", "--end-date" in fetch and fetch[fetch.index("--end-date") + 1] == "2026-09-14")
    ok("  沒有用 --days（那是覆寫成最近幾天）", "--days" not in fetch)
    ok("任何一步都沒有 --fetch", all("--fetch" not in c for c in runner.calls))
    cam = runner.calls[3]
    ok("攝影機只匯入挑中的那一份", cam == ["migrate_camera_to_db.py", "--csv", str(csv_path)], str(cam))
    ok("有列出新增的夜晚", "2026-09-14" in out)

print("\n【7】不擋的狀況：分數變了、沒有新夜晚、夢境失敗")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    paths = make_project(d, BEFORE)
    runner = FakeRunner(paths, after_dates=BEFORE, ai_rc=1)       # 沒新夜晚、夢境失敗
    # 讓 09-12 的分數變掉
    orig = runner.__call__

    def rescoring(argv, _orig=orig):
        rc = _orig(argv)
        if argv[0] == "garmin/run_pipeline.py":
            rows = json.loads(paths.final_json.read_text(encoding="utf-8"))
            rows[0]["final_score"] = 12.3
            paths.final_json.write_text(json.dumps(rows), encoding="utf-8")
        return rc

    rc, out = quiet(mi.run, args(skip_camera=True), paths, NOW, DB_ENV, runner=rescoring, db_check=db_ok)
    ok("exit code 0（這三件事都只警告）", rc == 0, str(rc))
    ok("  有警告分數變了", "分數和上次不同" in out)
    ok("  有提醒手錶可能沒同步", "同步" in out)
    ok("  夢境失敗之後 App 資料檔照樣重建", runner.scripts()[-1] == "build_app_payload.py",
       str(runner.scripts()))

print("\n【8】--skip-camera、--no-ai")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    paths = make_project(d, BEFORE)
    write_recording(paths.metrics_dir / "20260914_041355.csv", datetime(2026, 9, 14, 4, 13, 55), 260)
    runner = FakeRunner(paths, AFTER)
    rc, _ = quiet(mi.run, args(skip_camera=True, no_ai=True), paths, NOW, DB_ENV,
                  runner=runner, db_check=db_ok)
    ok("不跑攝影機入庫、不跑夢境",
       rc == 0 and "migrate_camera_to_db.py" not in runner.scripts()
       and "ai/generate_advice.py" not in runner.scripts(), str(runner.scripts()))

print("\n【9】資料庫：沒設或連不上 → 什麼都不跑；訊息裡沒有密碼")
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    paths = make_project(d, BEFORE)
    runner = FakeRunner(paths, AFTER)
    rc, out = quiet(mi.run, args(skip_camera=True), paths, NOW, {}, runner=runner)
    ok("沒設 SONNAP_DB_URL → 停、一支都沒跑", rc != 0 and runner.calls == [])
    ok("  有教怎麼設", "$env:SONNAP_DB_URL" in out)

    # 1 號埠沒有東西在聽，連線會被拒絕（真的連，但不會連到任何資料庫）
    secret = "s3cr3t-pw"
    good, msg = mi.check_database({"SONNAP_DB_URL": f"mysql://root:{secret}@127.0.0.1:1/sonnap"})
    ok("連不上 → 回報失敗", not good)
    ok("  訊息裡沒有密碼", secret not in msg, msg.splitlines()[0] if msg else "")
    good, msg = mi.check_database({"SONNAP_DB_URL": f"mysql://root:{secret}@127.0.0.1:1/"})
    ok("URL 少了資料庫名稱 → 回報失敗，而且訊息裡沒有密碼", not good and secret not in msg)

print("\n【10】備份只留最近幾份，而且只刪自己建的")
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    for i in range(10):
        (root / f"202609{i + 1:02d}_080000").mkdir()
    (root / "手動放的").mkdir()
    mi.prune_backups(root, keep=7)
    kept = sorted(p.name for p in root.iterdir())
    ok("時間戳記資料夾剩 7 份，留的是最新的",
       [k for k in kept if k[0].isdigit()] == [f"202609{i:02d}_080000" for i in range(4, 11)])
    ok("別的資料夾不動", "手動放的" in kept)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過")
    sys.exit(1)
print("✓ 全部通過")
