"""攝影機動作曲線的**純函式**部分（2026-11-13）：只用標準庫，後端與打包檔都可以放心 import。

曲線本身在 tapo_sleep_onset.motion_curve() 算（那支會連帶載入 OpenCV——錄影器的相依），
存進 camera_nightly.motion_curve；這裡只負責「只留手錶入睡 → 起床那段」。
"""
from datetime import datetime


def clip_curve(curve, sleep_start, wake_time, min_points=6):
    """整晚的攝影機曲線 → 只留手錶入睡 → 起床那段（Sleep Stages 卡的 Camera 線）。

    /home（main.py）與首頁的打包檔（build_app_payload.py）**共用這一份**，兩邊才不會漂移。
    ⚠️ 攝影機的時間沒有時區標記、手錶的有：比的時候都當**牆鐘**；輸出時把手錶的時區標記
       貼上去——不貼的話 App 會把兩種當成不同時區、差 8 小時，整條被濾光（2026-11-13 實機）。
    資料不夠、時刻壞掉 → None。
    """
    if not curve or not sleep_start or not wake_time:
        return None
    try:
        start_dt = datetime.fromisoformat(sleep_start)
        lo = start_dt.replace(tzinfo=None)
        hi = datetime.fromisoformat(wake_time).replace(tzinfo=None)
        pts = []
        for p in curve.get("points", []):
            t = datetime.fromisoformat(p["t"]).replace(tzinfo=None)
            if lo <= t <= hi:
                pts.append({"t": t.replace(tzinfo=start_dt.tzinfo).isoformat(),
                            "value": p["value"]})
    except (TypeError, ValueError, KeyError, AttributeError):
        return None
    if len(pts) < min_points:
        return None
    values = [p["value"] for p in pts]
    return {
        "points": pts,
        "avg": round(sum(values) / len(values), 3),
        "min": min(values),
        "max": max(values),
        "bucket_minutes": curve.get("bucket_minutes", 5),
    }
