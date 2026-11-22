# 助理頁的寵物頭像（使用者生成）

檔名：`<寵物>_<心情>.png`，寵物 = dog / cat，心情 = happy / bored / tired / anxious（共 8 張）。
規格：正方形 512×512、透明背景、只有頭、置中，頭約佔畫面 80%。

缺某一張時：先退回同一隻寵物的 bored，再退回程式裁切的寵物（`widgets/buddy_avatar.dart`）。
⚠️ 絕不退回 happy（焦慮的夜晚畫成開心的寵物＝紅線 5）。
