"""
game/inventory.py —— 衣櫃：有哪些衣服、幾級解鎖、誰已經擁有。純函式。

⚠️ 「解鎖」有兩個來源，取聯集：
     1. 目前等級解鎖的（依 unlock_level）
     2. 資料庫裡記著「曾經穿過」的（user_inventory）
   第 2 項存在的理由：XP 規則日後可能調整，等級可能因此下降。
   **已經穿過的衣服不能因為改規則而被收回**——那等於懲罰使用者，
   而且他完全不知道自己做錯了什麼。

⚠️ 文案是英文（全系統輸出語言的既定決策）；emoji 讓 App 不必另外準備圖檔。
"""

CATALOG = (
    {"item_id": "scarf",   "name": "Cosy scarf",      "emoji": "🧣", "unlock_level": 2},
    {"item_id": "cap",     "name": "Sleepy cap",      "emoji": "🧢", "unlock_level": 3},
    {"item_id": "bow",     "name": "Ribbon bow",      "emoji": "🎀", "unlock_level": 4},
    {"item_id": "glasses", "name": "Reading glasses", "emoji": "👓", "unlock_level": 5},
    {"item_id": "top_hat", "name": "Top hat",         "emoji": "🎩", "unlock_level": 6},
    {"item_id": "crown",   "name": "Crown",           "emoji": "👑", "unlock_level": 8},
)

ITEMS = {item["item_id"]: item for item in CATALOG}


def level_unlocked(level):
    """這個等級解鎖了哪些衣服（不含曾經穿過的）。"""
    return {i["item_id"] for i in CATALOG if level >= i["unlock_level"]}


def is_unlocked(item_id, level, owned_ids):
    return item_id in level_unlocked(level) or item_id in set(owned_ids or ())


def closet_view(level, owned_ids, equipped_id):
    """App 衣櫃畫面要的清單：每一件都標出解鎖與否、穿著與否、幾級解鎖。"""
    owned = set(owned_ids or ())
    unlocked = level_unlocked(level) | owned
    return [
        {
            **item,
            "unlocked": item["item_id"] in unlocked,
            "equipped": item["item_id"] == equipped_id,
        }
        for item in CATALOG
    ]
