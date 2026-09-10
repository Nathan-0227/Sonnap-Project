"""
資料庫方言層 —— 讓 `db.py` 同時跑得動 SQLite 與 MySQL/MariaDB。

═══════════════════════════════════════════════════════════════════════
為什麼是「方言層」而不是直接把 db.py 改成 MySQL
═══════════════════════════════════════════════════════════════════════
`db.py` 的 SCHEMA 有 275 行，其中大半是**註解**——「為什麼存快照不要
join」「為什麼這個 efficiency 絕不進 final_score」「為什麼 block_events
現在沒資料也要先建表」。那些是這個專案最難重建的資產。

抄一份 MySQL 版的 SCHEMA，等於讓那些註解有兩個定義處。改一邊忘另一邊
不會有任何錯誤訊息，只會讓兩個環境的資料庫結構默默地不一樣——而那正是
`COLUMN_MIGRATIONS` 那一整段在防的事。

→ 所以 MySQL 的 DDL 是**從 SQLite 的 SCHEMA 自動產生的**：先在記憶體裡
  用 SCHEMA 建一個 SQLite 庫，再把它的結構讀出來翻成 MySQL。
  欄位集合因此在結構上不可能漂移，而不是靠人記得同步。
  `tests/test_db_backends.py` 有一條在守這件事。

═══════════════════════════════════════════════════════════════════════
怎麼選後端
═══════════════════════════════════════════════════════════════════════
    （不設）                        → SQLite，路徑看 SONNAP_DB
    SONNAP_DB_URL=mysql://root@localhost/sonnap
    SONNAP_DB_URL=mysql://user:pw@127.0.0.1:3306/sonnap

⚠️ **測試一律用 SQLite。** 測試要能隨時跑、不依賴外部服務——這個專案的
   驗收指令是「獨立腳本、不需 pytest」，要求先開 XAMPP 才跑得動就破壞了
   那個性質。兩個後端的一致性由 `test_db_backends.py` 對照驗證，
   不是靠「反正都跑 MySQL」。
"""
import os
import re
import sqlite3
from urllib.parse import unquote, urlparse

# MySQL 不能對 TEXT 建索引（要給長度），所以進 PK / 索引 / 外鍵的字串欄位
# 要用 VARCHAR。191 是 utf8mb4 下 191×4=764 bytes，在最保守的 767 bytes
# 索引長度限制底下也安全。
KEYED_TEXT = "VARCHAR(191)"


# ═══════════════════════════════════════════════════════════════════
# 後端選擇
# ═══════════════════════════════════════════════════════════════════

def mysql_config(url=None):
    """把 SONNAP_DB_URL 解析成 mysql-connector 的參數。不是 MySQL 就回 None。"""
    url = url if url is not None else os.environ.get("SONNAP_DB_URL", "")
    if not url:
        return None
    p = urlparse(url)
    if p.scheme not in ("mysql", "mariadb"):
        return None
    if not (p.path or "").strip("/"):
        raise ValueError(f"SONNAP_DB_URL 少了資料庫名稱：{url}")
    return {
        "host": p.hostname or "127.0.0.1",
        "port": p.port or 3306,
        "user": unquote(p.username or "root"),
        # ⚠️ 密碼可能是空的（XAMPP 的 root 預設就是），那與「沒給」不同。
        "password": unquote(p.password) if p.password is not None else "",
        "database": (p.path or "").strip("/"),
    }


# ═══════════════════════════════════════════════════════════════════
# SQL 翻譯
# ═══════════════════════════════════════════════════════════════════

_ON_CONFLICT = re.compile(
    r"ON\s+CONFLICT\s*\([^)]*\)\s*DO\s+UPDATE\s+SET", re.IGNORECASE)
_EXCLUDED = re.compile(r"\bexcluded\.(\w+)", re.IGNORECASE)


def translate(sql):
    """
    SQLite 的 SQL → MySQL。

    只處理這個專案真的用到的兩件事：

      ?                      → %s
      ON CONFLICT(...) DO UPDATE SET x = excluded.x
                             → ON DUPLICATE KEY UPDATE x = VALUES(x)

    ⚠️ **刻意不做通用的 SQL 轉譯。** 通用轉譯需要一個真正的 parser，
       而半吊子的正則式會在某天安靜地翻錯一句——那比不支援還糟。
       db.py 只有 4 個 ON CONFLICT，全部是同一個機械式的形狀。
       新增別種語法時，這裡會翻不動而不是翻錯（MySQL 直接報語法錯誤）。
    """
    sql = _ON_CONFLICT.sub("ON DUPLICATE KEY UPDATE", sql)
    sql = _EXCLUDED.sub(r"VALUES(\1)", sql)
    # ⚠️ 只換不在字串字面值裡的 `?`。這個專案的 SQL 沒有任何字串字面值
    #    含問號，但還是掃一次比較保險——換錯的話症狀是參數對不上，
    #    而 mysql-connector 會丟出來，不會安靜錯。
    out, in_str, quote = [], False, ""
    for ch in sql:
        if in_str:
            out.append(ch)
            if ch == quote:
                in_str = False
            continue
        if ch in ("'", '"'):
            in_str, quote = True, ch
            out.append(ch)
        elif ch == "?":
            out.append("%s")
        else:
            out.append(ch)
    return "".join(out)


# ═══════════════════════════════════════════════════════════════════
# SQLite SCHEMA → MySQL DDL
# ═══════════════════════════════════════════════════════════════════

def _sqlite_structure(schema_sql):
    """在記憶體裡建一次，把結構讀出來。這樣欄位集合不可能跟 SCHEMA 漂移。"""
    conn = sqlite3.connect(":memory:")
    conn.executescript(schema_sql)
    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY rowid")]
    info = {}
    for t in tables:
        cols = [dict(cid=r[0], name=r[1], type=r[2], notnull=r[3],
                     default=r[4], pk=r[5])
                for r in conn.execute(f'PRAGMA table_info("{t}")')]
        fks = [dict(table=r[2], frm=r[3], to=r[4], on_delete=r[6])
               for r in conn.execute(f'PRAGMA foreign_key_list("{t}")')]
        idxs = []
        for r in conn.execute(f'PRAGMA index_list("{t}")'):
            name, unique, origin = r[1], r[2], r[3]
            if origin != "c":          # 只要明確建立的索引，PK/UNIQUE 另外處理
                continue
            icols = [x[2] for x in conn.execute(f'PRAGMA index_info("{name}")')]
            idxs.append(dict(name=name, unique=unique, cols=icols))
        info[t] = dict(cols=cols, fks=fks, indexes=idxs)
    conn.close()
    return info


def _keyed_columns(spec):
    """哪些欄位進了 PK / 索引 / 外鍵 —— 這些字串欄位必須是 VARCHAR。"""
    keyed = {c["name"] for c in spec["cols"] if c["pk"]}
    keyed |= {f["frm"] for f in spec["fks"]}
    for idx in spec["indexes"]:
        keyed |= set(idx["cols"])
    return keyed


def _mysql_type(col, keyed, autoinc):
    t = (col["type"] or "TEXT").upper()
    if autoinc:
        return "INT AUTO_INCREMENT"
    if t.startswith("INT"):
        return "INT"
    if t in ("REAL", "DOUBLE", "FLOAT"):
        return "DOUBLE"
    # TEXT 及其他一律當字串
    return KEYED_TEXT if col["name"] in keyed else "TEXT"


def mysql_ddl(schema_sql):
    """
    回傳一串 MySQL 的 CREATE TABLE / CREATE INDEX。

    ⚠️ 表的順序沿用 SCHEMA 裡的順序。外鍵要求父表先建，而 SCHEMA 的
       順序本來就是對的（users 在最前面）。改 SCHEMA 順序時要留意。
    """
    info = _sqlite_structure(schema_sql)
    out = []
    for table, spec in info.items():
        keyed = _keyed_columns(spec)
        pk_cols = [c["name"] for c in sorted(
            (c for c in spec["cols"] if c["pk"]), key=lambda c: c["pk"])]
        # SQLite 的 `INTEGER PRIMARY KEY AUTOINCREMENT` 是單欄整數主鍵
        single_int_pk = (
            len(pk_cols) == 1
            and any(c["name"] == pk_cols[0] and (c["type"] or "").upper().startswith("INT")
                    for c in spec["cols"]))

        lines = []
        for c in spec["cols"]:
            autoinc = single_int_pk and c["name"] == pk_cols[0]
            piece = f'  `{c["name"]}` {_mysql_type(c, keyed, autoinc)}'
            # ⚠️ SQLite 的 `TEXT PRIMARY KEY` 其 notnull 是 0（SQLite 的老
            #    毛病：只有 INTEGER PRIMARY KEY 才隱含 NOT NULL）。MySQL 會
            #    自己把 PK 欄位變成 NOT NULL，但寫明比較不會有人誤會。
            if c["notnull"] or autoinc or c["name"] in pk_cols:
                piece += " NOT NULL"
            if c["default"] is not None and not autoinc:
                piece += f' DEFAULT {c["default"]}'
            lines.append(piece)
        if pk_cols:
            lines.append("  PRIMARY KEY (" +
                         ", ".join(f"`{c}`" for c in pk_cols) + ")")
        for f in spec["fks"]:
            lines.append(
                f'  FOREIGN KEY (`{f["frm"]}`) '
                f'REFERENCES `{f["table"]}` (`{f["to"]}`) '
                f'ON DELETE {f["on_delete"] or "NO ACTION"}')
        out.append(
            f"CREATE TABLE IF NOT EXISTS `{table}` (\n"
            + ",\n".join(lines)
            + "\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 "
              "COLLATE=utf8mb4_unicode_ci")

    # 索引分開建：MySQL 沒有 CREATE INDEX IF NOT EXISTS，所以由呼叫端
    # 吞掉「已經存在」的錯誤（見 MySQLConn.ensure_index）。
    for table, spec in info.items():
        for idx in spec["indexes"]:
            cols = ", ".join(f"`{c}`" for c in idx["cols"])
            out.append(f'CREATE INDEX `{idx["name"]}` ON `{table}` ({cols})')
    return out


# ═══════════════════════════════════════════════════════════════════
# 連線包裝：對外的介面跟 sqlite3.Connection 一樣
# ═══════════════════════════════════════════════════════════════════

class Row:
    """既能 row["col"] 也能 row[0]。

    ⚠️ sqlite3.Row 兩種都支援，而 mysql-connector 的 dict cursor 只支援
       前者。db.py 兩種都有用到（`SELECT COUNT(*)` 那幾處是位置存取），
       所以這裡補齊——不補的話症狀是 KeyError: 0，而且只在特定查詢出現。
    """

    __slots__ = ("_d", "_t")

    def __init__(self, d):
        self._d = d
        self._t = tuple(d.values())

    def __getitem__(self, k):
        return self._t[k] if isinstance(k, int) else self._d[k]

    def keys(self):
        return list(self._d.keys())

    def get(self, k, default=None):
        return self._d.get(k, default)

    def __iter__(self):
        return iter(self._t)

    def __len__(self):
        return len(self._t)

    def __repr__(self):
        return f"Row({self._d!r})"


class _Result:
    """execute() 的回傳值。可以疊代、可以 fetchone/fetchall。"""

    def __init__(self, rows, lastrowid=0, rowcount=-1):
        self._rows = rows
        self.lastrowid = lastrowid
        self.rowcount = rowcount

    def fetchone(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return list(self._rows)

    def __iter__(self):
        return iter(self._rows)


class MySQLConn:
    """把 mysql-connector 包成 sqlite3.Connection 的樣子。"""

    def __init__(self, config):
        import mysql.connector          # noqa: PLC0415  只有 MySQL 後端才需要
        self._mysql = mysql.connector
        self._conn = mysql.connector.connect(**config, autocommit=False)

    def execute(self, sql, params=()):
        cur = self._conn.cursor(dictionary=True)
        try:
            cur.execute(translate(sql), tuple(params))
            rows = [Row(r) for r in cur.fetchall()] if cur.with_rows else []
            return _Result(rows, cur.lastrowid or 0, cur.rowcount)
        finally:
            cur.close()

    def executescript(self, script):
        """⚠️ 只給 DDL 用。MySQL 的 DDL 各自是一句，不能整段送。"""
        for stmt in [s.strip() for s in script.split(";") if s.strip()]:
            self.execute(stmt)

    def ensure_index(self, stmt):
        """建索引，已經存在就當作成功（MySQL 沒有 IF NOT EXISTS）。"""
        try:
            self.execute(stmt)
        except self._mysql.Error as exc:
            # 1061 = Duplicate key name
            if getattr(exc, "errno", None) != 1061:
                raise

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        self._conn.close()
