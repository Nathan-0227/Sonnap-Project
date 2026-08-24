"""
behavior/ — Tier A：行為介入層

⚠️ **這個套件絕不 import 評分層**（garmin/evaluate_sleep_quality.py、
   garmin/apply_recovery_modifier.py）。

理由是 PROJECT_STATUS.md 8.7 定的架構紅線：「遊戲化層只讀，不得回寫評分層」。
本專案最難複製的資產是「每一項計分都有文獻引文」，而加遊戲化功能時最容易
在這裡破功——最典型的說法是「為了讓挑戰有感，完成挑戰的夜晚加 5 分」，
那一步就會讓分數不再只由文獻決定。

在目前的架構下這條紅線是**結構上成立**的，不必靠紀律：
遊戲化完全建立在 Tier A（行為）上，而 Tier A 的資料來源是手機，
跟評分器根本不在同一條路徑上。

機械化驗收（**只比對 import 行**）：

    grep -rnE "^[[:space:]]*(import|from)[[:space:]]+.*(evaluate_sleep_quality|apply_recovery_modifier|garmin)" behavior/
    # 必須零結果

⚠️ 不要寫成單純搜關鍵字。那樣會抓到這段說明本身——一個永遠「失敗」的檢查
   比沒有檢查更糟，因為大家很快就會學會忽略它。（這個坑是實際踩過才發現的。）
"""
