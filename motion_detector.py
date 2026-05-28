import cv2
import json
import time
from datetime import datetime

# 格式為：rtsp://帳號:密碼@攝影機的IP地址:554/stream1
# 舉例（假設你在 App 設定的帳號是 admin，密碼是 password123，攝影機 IP 是 192.168.1.100）：
tapo_url = "rtsp://admin:password123@192.168.1.100:554/stream1"
cap = cv2.VideoCapture(tapo_url)

if not cap.isOpened():
    print("Error: 無法開啟攝影機。")
    exit()

# 初始化背景分離器 (這裡使用 MOG2 演算法，對環境光線變化較具魯棒性)
fgbg = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=16, detectShadows=True)

# 用於儲存偵測數據的列表
motion_data_list = []

print("開始偵測... 按下 'q' 鍵可停止並儲存數據。")

try:
    while True:
        ret, frame = cap.read()
        if not ret:
            print("無法接收畫面。")
            break

        # 1. 影像預處理：轉灰階並模糊化，減少雜訊干擾
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (21, 21), 0)

        # 2. 應用背景相減法得到前景面罩 (Foreground Mask)
        fgmask = fgbg.apply(blurred)

        # 3. 進行二值化與膨脹處理，讓動作區域更明顯
        _, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
        thresh = cv2.dilate(thresh, None, iterations=2)

        # 4. 計算變動區域的面積
        # countNonZero 可以計算白色像素（即移動物體）的數量
        motion_area = cv2.countNonZero(thresh)

        # 設定觸發門檻（根據實際鏡頭距離與解析度調整，例如 5000 像素）
        MOTION_THRESHOLD = 5000 

        if motion_area > MOTION_THRESHOLD:
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"[{current_time}] 偵測到動作！強度 (面積): {motion_area}")
            
            # 紀錄數據
            motion_data_list.append({
                "timestamp": current_time,
                "event": "motion_detected",
                "intensity": motion_area
            })
            
            # 在畫面上標示文字
            cv2.putText(frame, "MOTION DETECTED", (10, 30), 
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)

        # 顯示即時畫面
        cv2.imshow('Camera Feed', frame)
        cv2.imshow('Motion Mask', thresh) # 觀察雜訊用

        # 按 'q' 鍵退出迴圈
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

finally:
    # 釋放資源
    cap.release()
    cv2.destroyAllWindows()

    # ---- 步驟三：輸出為 JSON 格式 ----
    # ⚠️ 請根據你的專案規範 /data/standard_format.json 修改下方的 Dict 欄位名稱
    output_data = {
        "device_id": "camera_01",
        "description": "翻身與動作偵測數據",
        "total_events": len(motion_data_list),
        "records": motion_data_list
    }

    output_path = "motion_data.json" # 可以改成專案要求的絕對或相對路徑
    
    try:
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, ensure_ascii=False, indent=4)
        print(f"\n數據已成功輸出至：{output_path}")
    except Exception as e:
        print(f"寫入 JSON 失敗: {e}")
