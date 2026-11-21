"""
好友小鎮（2026-11-17 使用者定，共識摘要見對話；照 Finch 的做法：朋友之間只看到寵物）。**純函式**。

規則：
- 發光＝**昨晚準時放下手機**，判準只有一處：behavior.challenges.night_achieved（同連續晚數、挑戰）。
  只有他有分享「On time」才會亮（自己看自己照亮）。
- 沒發光的三種情況（晚了、沒資料、沒分享）**看起來完全一樣**：回應裡只有 glow: false，
  不給原因——給了 App 就有機會畫出不一樣的樣子。
- 拜訪：同一個朋友一天一次（以起床日算），不給 XP、不影響分數、**不推播**。
  九種動作的字（按鈕、對方看到的、送禮頁的泡泡）只在這裡定義，App 照抄。
- 拜訪紀錄存 VISIT_KEEP_DAYS 天；刪好友、刪帳號時一起刪（db.py）。
"""
from datetime import timedelta

from behavior.adherence import NIGHT_ROLLOVER_HOURS
from behavior.challenges import night_achieved

VISIT_KEEP_DAYS = 14

# key → (按鈕上的字, 對方看到的那一句, 送禮頁上你的寵物說的那句)。
# {name}＝送的人、{pet}＝收的人的寵物、{friend}＝要送給的朋友（App 只代換名字）。
# 2026-11-22 使用者定（照 Finch 的送禮頁）：4 → 9 種、3×3 排滿；原本 4 種的 key 不改（舊紀錄照讀）。
# ⚠️ 一句都不准評判或催促（不准 Go to bed!、You were late）——同「不按也沒關係」。
# ⚠️ 泡泡那句自己寫，不照抄 Finch 的原文。
KINDS = {
    "pet": ("Pet 🐾", "{name} pet your {pet} 🐾", "Let's go give {friend}'s buddy a pat!"),
    "good_night": ("Good night 🌙", "{name}: Good night 🌙", "Let's wish {friend} a good night!"),
    "sleep_well": ("Sleep well 💤", "{name}: Sleep well 💤", "Let's send {friend} sweet dreams!"),
    "proud": ("Proud of you ⭐", "{name}: Proud of you ⭐", "Let's tell {friend} we're proud of them!"),
    "good_morning": ("Good morning ☀️", "{name}: Good morning ☀️", "Let's say good morning to {friend}!"),
    "hugs": ("Hugs 🤗", "{name} sent you a hug 🤗", "Let's send {friend} a big hug!"),
    "you_got_this": ("You got this 💪", "{name}: You got this 💪", "Let's cheer {friend} on!"),
    "thanks": ("Thanks 💛", "{name}: Thank you 💛", "Let's say thanks to {friend}!"),
    "outfit": ("Nice outfit 👕", "{name} loves your {pet}'s outfit 👕", "Let's tell {friend} their buddy looks great!"),
}
# 格子的順序（3×3，跟圖示表的順序一樣）
KIND_ORDER = ("pet", "good_night", "sleep_well",
              "proud", "good_morning", "hugs",
              "you_got_this", "thanks", "outfit")


def visit_day(now):
    """這個時刻算哪一個起床日（同 behavior.adherence.night_date 的約定：加 6 小時）。
    晚上 22:00 送的 Good night，對方隔天早上的「今天」看得到。"""
    return (now + timedelta(hours=NIGHT_ROLLOVER_HOURS)).date().isoformat()


def glows(behavior_rows, night, shares_on_time):
    """那一晚（起床日）準時放下手機、而且有分享 On time → True；其他一律 False（不分原因）。"""
    if not shares_on_time:
        return False
    row = next((r for r in behavior_rows if r.get("date") == night), None)
    return bool(row) and night_achieved(row) is True


def button_label(kind):
    return KINDS[kind][0]


def invite(kind):
    """送禮頁上你的寵物說的那句（{friend} 留給 App 換成朋友的名字）。"""
    return KINDS[kind][2]


def message(kind, sender_name, receiver_species):
    pet = "cat" if receiver_species == "cat" else "dog"
    return KINDS[kind][1].format(name=sender_name, pet=pet)


def display_name(name):
    """示範帳號的暱稱帶「 (demo)」，句子裡不重複寫（App 另外標 Demo）。"""
    return (name or "").removesuffix(" (demo)")
