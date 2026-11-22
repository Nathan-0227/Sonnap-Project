"""
export_teammate.py — 把手機帳號整份複製成一個可以帶走的 SQLite 檔，給隊友在她自己的電腦上跑後端。

    # 第一次：產生新的帳號 id
    SONNAP_DB_URL=mysql://root@localhost/sonnap  python export_teammate.py --out <資料夾>

    # 之後更新資料：沿用同一個 id，她手上那支 APK 就不用重建
    SONNAP_DB_URL=mysql://root@localhost/sonnap  python export_teammate.py --out <新資料夾> \
        --user-id-file <上次的資料夾>/NEW_USER_ID.txt

產出：
    <out>/sonnap.db            放到她那份 repo 的 data/sonnap.db（後端預設就讀這裡，不用設環境變數）
    <out>/camera_clips/*.gif   放到她那份 repo 的上一層 sonnap-data/camera_clips/（camera_clips.CLIPS_DIR 的預設）
    <out>/NEW_USER_ID.txt      建 APK 用：--dart-define=SONNAP_USER_ID=<這個>

═══════════════════════════════════════════════════════════════════
為什麼要換 id，而不是直接給她你的
═══════════════════════════════════════════════════════════════════
1. **user_id 本身就是憑證**（免註冊、無密碼），換掉就不會離開這台電腦。
2. App 沒有唯讀模式：她的手機一打開就會上傳**她的**放下手機時刻、Health Connect、
   起床自評。用你的 id 的話，同一晚會被整列覆寫（upsert_nightly_behavior），
   按鈕時刻是攝影機上床偵測的標準答案，蓋掉救不回來，而且不會有任何錯誤訊息。
   換成新 id、寫進她自己電腦上的檔案，兩邊結構上就碰不到。

複製的範圍：手機帳號（`db.resolve_phone_account()`，同早晨匯入的判準）＋它的好友
（多半是示範帳號，好友頁才會一樣）。好友的 id 也換新的。沒有 user_id 欄位的表
（挑戰定義）整張照抄。其他帳號（wearer_a、研究者帳號）一列都不帶。

⚠️ **只讀來源資料庫**，一筆都不寫。
⚠️ 不印任何 user_id（裝了這支的終端機紀錄、截圖都可能外流）。
⚠️ 產出物裡有真實睡眠資料與臥室畫面：放在所有 worktree 之外（例如 sonnap-data/），
   **不要進 repo、不要用 GitHub 網頁上傳**。
⚠️ 片段的 clip_id 不換：它是隨機碼不是憑證，換了就要連檔名一起改。
"""

import argparse
import shutil
import sqlite3
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import camera_clips  # noqa: E402
import db  # noqa: E402

# 每張表裡指向帳號的欄位。新加了指向帳號的欄位而沒列在這裡，
# 那一欄會原封不動帶著你真正的 id 出去——tests/test_export_teammate.py 掃整個檔案守著。
ID_COLUMNS = ("user_id", "friend_id")

# 整張不帶的表。🔴 user_logins 有 email 與密碼雜湊：副本是給隊友用的，
# 帶過去等於把你的登入名稱與雜湊交出去（雜湊也能拿去離線猜）。測試【6】守著。
EXCLUDED_TABLES = ("user_logins",)


def export(out_dir, *, source_db=None, clips_dir=None, new_user_id=None):
    """
    回傳 dict：new_user_id、tables（表名 → 複製幾列）、friends、clips、clips_missing、fk_errors。
    source_db=None 時走 db.connect() 的預設（SONNAP_DB_URL 或 SONNAP_DB）；測試給 SQLite 路徑。
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    dst_path = out_dir / "sonnap.db"
    if dst_path.exists():
        raise SystemExit(f"{dst_path} 已經存在。換一個資料夾，或先刪掉它。")

    phone, info = db.resolve_phone_account(source_db)
    if not phone:
        raise SystemExit(f"認不出手機帳號（{info['reason']}），停下來，什麼都沒寫。")

    src = db.connect(source_db)
    try:
        friends = [r["friend_id"] for r in src.execute(
            "SELECT friend_id FROM friendships WHERE user_id = ?", (phone,)).fetchall()]
        idmap = {phone: new_user_id or str(uuid.uuid4())}
        for f in friends:
            idmap[f] = str(uuid.uuid4())

        db.init_db(dst_path)
        dst = db.connect(dst_path)
        dst.execute("PRAGMA foreign_keys = OFF")   # 整批倒進去，表的順序不重要；倒完再檢查
        tables = [r[0] for r in dst.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        counts = {}
        for t in tables:
            if t in EXCLUDED_TABLES:
                counts[t] = 0
                continue
            cols = [r[1] for r in dst.execute(f"PRAGMA table_info({t})")]
            try:
                rows = src.execute(f"SELECT * FROM {t}").fetchall()
            except Exception:                       # 來源比較舊、還沒有這張表
                counts[t] = None
                continue
            dst.execute(f"DELETE FROM {t}")         # init 可能已經灌了東西（挑戰），改用來源那份
            kept = 0
            for r in rows:
                d = {c: r[c] if c in r.keys() else None for c in cols}
                if any(c in d and d[c] not in idmap for c in ID_COLUMNS):
                    continue
                for c in ID_COLUMNS:
                    if c in d:
                        d[c] = idmap[d[c]]
                dst.execute(
                    f"INSERT INTO {t} ({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                    tuple(d.values()))
                kept += 1
            counts[t] = kept
        dst.commit()
        dst.execute("PRAGMA foreign_keys = ON")
        fk_errors = len(dst.execute("PRAGMA foreign_key_check").fetchall())
        # 只留一個檔：WAL 模式會多出 -wal／-shm，少帶一個就是舊資料
        dst.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        dst.execute("PRAGMA journal_mode = DELETE")
        dst.close()

        clip_ids = [r["clip_id"] for r in src.execute(
            "SELECT clip_id FROM camera_clips WHERE user_id = ?", (phone,)).fetchall()]
    finally:
        src.close()

    clips_src = Path(clips_dir) if clips_dir else camera_clips.CLIPS_DIR
    clips_out = out_dir / "camera_clips"
    clips_out.mkdir(exist_ok=True)
    missing = 0
    for c in clip_ids:
        p = clips_src / f"{c}.gif"
        if p.exists():
            shutil.copy2(p, clips_out / p.name)
        else:
            missing += 1

    (out_dir / "NEW_USER_ID.txt").write_text(idmap[phone], encoding="utf-8")
    return {"new_user_id": idmap[phone], "tables": counts, "friends": len(friends),
            "clips": len(clip_ids) - missing, "clips_missing": missing, "fk_errors": fk_errors}


def main():
    ap = argparse.ArgumentParser(description="把手機帳號複製成一個帶得走的 SQLite 檔（換新 id）")
    ap.add_argument("--out", required=True, help="輸出資料夾（放在 repo 外面）")
    ap.add_argument("--user-id-file", help="沿用上次的 NEW_USER_ID.txt，APK 就不用重建")
    ap.add_argument("--clips-dir", help="片段資料夾，預設 camera_clips.CLIPS_DIR")
    args = ap.parse_args()

    reuse = None
    if args.user_id_file:
        reuse = Path(args.user_id_file).read_text(encoding="utf-8").strip()
        if not reuse:
            raise SystemExit(f"{args.user_id_file} 是空的")

    r = export(args.out, clips_dir=args.clips_dir, new_user_id=reuse)
    for t, n in r["tables"].items():
        print(f"  {t:22} {'來源沒有這張表' if n is None else n}")
    print(f"好友 {r['friends']} 個、片段 {r['clips']} 個（找不到 {r['clips_missing']} 個）、"
          f"外鍵錯誤 {r['fk_errors']} 筆")
    print(f"帳號 id：{'沿用上次的' if reuse else '新產生的'}，寫在 NEW_USER_ID.txt")
    if r["fk_errors"] or r["clips_missing"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
