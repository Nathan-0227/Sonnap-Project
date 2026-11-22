"""
email＋密碼登入（2026-11-22 grill，記憶 settings-redesign-and-login 的 A'）。

只做一件事：讓換了手機、重裝 App 的人拿回**原本那個 user_id**。

⚠️ **API 仍然用 user_id 認人，沒有 token。** 登入成功回傳的就是 user_id，
   之後每個請求照舊帶它——拿到 id 的人照樣讀寫得到那個帳號。
   密碼保護的是「怎麼找回 id」，不是每一個請求。上架前要補真正的認證（token／session）。

規則（設計決策，沒有文獻）：
  - email 只當登入名稱：不寄信、不驗證、不能「忘記密碼」——忘了找管理員跑
    `python reset_password.py <email>` 發一組臨時密碼
  - 密碼至少 8 個字元
  - 連錯 5 次鎖 15 分鐘（鎖的是那個帳號，不是那支手機）
  - 🔴 密碼只存 scrypt 雜湊（標準庫 hashlib.scrypt），**誰都看不到原文**，管理員也一樣

只用標準庫。
"""

import base64
import hashlib
import hmac
import re
import secrets
from datetime import datetime, timedelta

MIN_PASSWORD_LENGTH = 8
MAX_PASSWORD_LENGTH = 128       # scrypt 吃任意長度，上限只為了擋惡意的超大請求
MAX_FAILED_ATTEMPTS = 5
LOCK_MINUTES = 15

# scrypt 參數：N=2^14、r=8、p=1（約 16 MB 記憶體、幾十毫秒）。
# 存進雜湊字串裡，之後要調高也認得出舊的。
_N, _R, _P = 2 ** 14, 8, 1
_SALT_BYTES = 16
_KEY_BYTES = 32
_PREFIX = "scrypt"

# 只擋明顯打錯的（沒有 @、沒有點）。不寄信，所以不需要更嚴格。
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
MAX_EMAIL_LENGTH = 191          # MariaDB 那邊 VARCHAR(191)（db_backend.KEYED_TEXT）

# 臨時密碼：去掉 0/O/1/l/I 這種看錯的字
_TEMP_ALPHABET = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
TEMP_PASSWORD_LENGTH = 10


def normalize_email(email):
    """去掉前後空白、轉小寫。登入與設定都走這一支，不然 A@x.com 跟 a@x.com 是兩個帳號。"""
    return (email or "").strip().lower()


def email_problem(email):
    """回傳給人讀的問題；沒問題回 None。email 要先 normalize。"""
    if not email:
        return "Enter your email."
    if len(email) > MAX_EMAIL_LENGTH or not _EMAIL.match(email):
        return "That doesn't look like an email address."
    return None


def password_problem(password):
    if password is None or len(password) < MIN_PASSWORD_LENGTH:
        return f"Use at least {MIN_PASSWORD_LENGTH} characters."
    if len(password) > MAX_PASSWORD_LENGTH:
        return f"Use at most {MAX_PASSWORD_LENGTH} characters."
    return None


def _b64(b):
    return base64.b64encode(b).decode("ascii")


def hash_password(password):
    """回傳 "scrypt$N$r$p$salt$key"。每次 salt 不同，同一個密碼兩次雜湊不會一樣。"""
    salt = secrets.token_bytes(_SALT_BYTES)
    key = hashlib.scrypt(password.encode("utf-8"), salt=salt,
                         n=_N, r=_R, p=_P, dklen=_KEY_BYTES)
    return f"{_PREFIX}${_N}${_R}${_P}${_b64(salt)}${_b64(key)}"


def verify_password(password, stored):
    """對得上回 True。格式壞掉一律 False（不丟例外：壞資料不該讓登入端點 500）。"""
    try:
        prefix, n, r, p, salt, key = stored.split("$")
        if prefix != _PREFIX:
            return False
        salt, key = base64.b64decode(salt), base64.b64decode(key)
        got = hashlib.scrypt(password.encode("utf-8"), salt=salt,
                             n=int(n), r=int(r), p=int(p), dklen=len(key))
    except (ValueError, AttributeError, TypeError):
        return False
    return hmac.compare_digest(got, key)


# 找不到 email 時也算一次雜湊，讓「沒這個帳號」跟「密碼錯」花一樣久，
# 不能從回應時間猜出哪些 email 有帳號。
_DUMMY_HASH = None


def burn_time(password):
    global _DUMMY_HASH
    if _DUMMY_HASH is None:
        _DUMMY_HASH = hash_password("not-a-real-password")
    verify_password(password or "", _DUMMY_HASH)


def temp_password():
    return "".join(secrets.choice(_TEMP_ALPHABET) for _ in range(TEMP_PASSWORD_LENGTH))


def _parse(ts):
    return datetime.fromisoformat(ts) if ts else None


def locked_minutes_left(login, now):
    """還要鎖幾分鐘（無條件進位）；沒鎖回 0。now 要帶時區（同 db.now_iso）。"""
    until = _parse(login.get("locked_until"))
    if until is None or until <= now:
        return 0
    return max(1, -(-int((until - now).total_seconds()) // 60))


def after_failure(login, now):
    """
    錯一次之後的 (failed_attempts, locked_until)。

    鎖過期之後重新數：鎖 15 分鐘到了，再錯 1 次不會馬上又鎖。
    """
    count = login.get("failed_attempts") or 0
    if _parse(login.get("locked_until")) is not None:
        count = 0           # 走到這裡代表鎖已過期（還在鎖的不會進來驗密碼）
    count += 1
    if count >= MAX_FAILED_ATTEMPTS:
        return count, (now + timedelta(minutes=LOCK_MINUTES)).isoformat(timespec="seconds")
    return count, None
