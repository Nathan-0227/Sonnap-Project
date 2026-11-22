"""
管理員重設密碼：發一組臨時密碼給忘了密碼的人。

    SONNAP_DB_URL=mysql://root@localhost/sonnap python reset_password.py someone@example.com

- 印出臨時密碼（只印這一次，資料庫裡只有雜湊）。當面或私訊交給對方，
  請他登入後到設定頁 Change password 換掉。
- 同時清掉連錯次數與鎖。
- 🔴 密碼**看不到**：資料庫存的是 scrypt 雜湊，連管理員也還原不出原文——
  所以只能重設，不能「查」。
- 不印 user_id（它就是憑證）。
"""

import argparse
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import auth
import db


def reset(email, db_path=None):
    """回傳 (臨時密碼, 暱稱)；沒有這個 email 回 (None, None)。"""
    email = auth.normalize_email(email)
    found = db.get_login_by_email(email, db_path)
    if found is None:
        return None, None
    temp = auth.temp_password()
    db.set_login_password(found["user_id"], auth.hash_password(temp), db_path)
    user = db.get_user(found["user_id"], db_path)
    return temp, (user or {}).get("display_name")


def main():
    ap = argparse.ArgumentParser(description="Reset a user's password to a temporary one.")
    ap.add_argument("email")
    args = ap.parse_args()
    temp, name = reset(args.email)
    if temp is None:
        print(f"No login with email {auth.normalize_email(args.email)!r}.")
        return 1
    print(f"Reset the password for {name!r}.")
    print(f"Temporary password: {temp}")
    print("Ask them to log in with it and change it in Settings → Change password.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
