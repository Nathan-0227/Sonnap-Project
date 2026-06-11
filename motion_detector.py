import cv2
import json
import time
import numpy as np
from datetime import datetime
import os
import mysql.connector

# ==================== 🛠️ 設定區 ====================
tapo_url = "rtsp://imqs113:Monica113@192.168.50.204:554/stream1"

START_TIME = "17:26:00"  # 開始睡眠監測時間
END_TIME   = "17:28:00"  # 結束監測並產出報告時間

# 🏃 動作靈敏度設定 (調大數值 = 抗夜視雜訊)
MOTION_LARGE = 150000    # 超過 30 萬像素判定為大翻身
MOTION_MICRO =  30000    # 超過 4 萬像素判定為微動

# 🌐 phpMyAdmin 資料庫設定
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",          
    "database": "sonnap"      
}
# ==================================================

os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp"

print("============ 🌙 睡眠定時監測與資料庫系統已在背景待命 ============")
print(f"系統設定：每日 {START_TIME} 自動開啟監測，{END_TIME} 自動關閉並上傳資料庫。\n")

is_monitoring = False
sleep_timeline = []
video_writer = None
recording_timer = 0
report_generated_today = False  # 🔒 保險鎖

current_dir = os.path.dirname(os.path.abspath(__file__))

try:
    while True:
        now_str = datetime.now().strftime("%H:%M:%S")
        
        # 每天午夜 12 點重設保險鎖
        if now_str == "00:00:00":
            report_generated_today = False

        # 檢查是否到達啟動時間
        if now_str >= START_TIME and now_str < END_TIME and not is_monitoring and not report_generated_today:
            print(f"⏰ [{now_str}] 到達設定時間！正在連線 Tapo 攝影機啟動監測與實時畫面...")
            cap = cv2.VideoCapture(tapo_url, cv2.CAP_FFMPEG)
            if cap.isOpened():
                fgbg = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=16, detectShadows=False)
                sleep_timeline = []  
                is_monitoring = True
                
                width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                fps = int(cap.get(cv2.CAP_PROP_FPS)) if cap.get(cv2.CAP_PROP_FPS) > 0 else 20
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                print(f"✅ 連線成功！解析度: {width}x{height}, FPS: {fps}")
            else:
                print("❌ 連線失敗，10 秒後重新嘗試...")
                time.sleep(10)
                continue

        # 監測執行中
        if is_monitoring:
            ret, frame = cap.read()
            if not ret:
                continue

            current_time = datetime.now().strftime("%H:%M:%S")
            report_date = datetime.now().strftime("%Y-%m-%d")

            # 1. 動作檢測
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            blurred = cv2.GaussianBlur(gray, (21, 21), 0)
            fgmask = fgbg.apply(blurred)
            _, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
            motion_area = cv2.countNonZero(thresh)
            
            motion_type = "none"
            if motion_area > MOTION_LARGE: motion_type = "large_turn"
            elif motion_area > MOTION_MICRO: motion_type = "micro_motion"

            # 2. 聲音模擬 (平滑抗雜訊優化版：讓沒動靜時保持真正的安靜)
            base_noise = 30  # 將基底環境音調低到 30 dB (符合深夜安靜房間)
            
            if motion_type == "large_turn":
                sound_db = int(base_noise + np.random.randint(25, 35))
            elif motion_type == "micro_motion":
                sound_db = int(base_noise + np.random.randint(5, 12))
            else:
                # 🛌 當完全沒有動作時，極高機率保持安靜，徹底修復誤判
                sound_db = int(base_noise + np.random.choice([0, 3, 8], p=[0.96, 0.035, 0.005]))

            # 🔊 聲音品質類型判定
            sound_type = "quiet"
            if sound_db > 55:    
                sound_type = "snoring_or_noise"
            elif sound_db > 48:  
                sound_type = "breathing_heavy"

            # 3. 觸發自動錄影 (5秒防重複計算冷卻鎖)
            video_filename = "none"
            if motion_type == "large_turn" and video_writer is None:
                video_dir = os.path.join(current_dir, "sleep_videos")
                if not os.path.exists(video_dir): 
                    os.makedirs(video_dir)
                
                unique_suffix = f"{datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]}_{np.random.randint(100, 999)}"
                video_filename = f"turn_{unique_suffix}.mp4"
                video_output_path = os.path.join(video_dir, video_filename)
                
                print(f"🎬 [新事件] 偵測到大翻身 ({motion_area})！啟動 5 秒冷卻鎖與錄影: {video_filename}")
                video_writer = cv2.VideoWriter(video_output_path, fourcc, fps, (width, height))
                recording_timer = fps * 5

            # 📹 正在錄影的處理
            if video_writer is not None:
                video_writer.write(frame)
                recording_timer -= 1
                
                # 方案 B 核心：只有在觸發的第一格才寫入紀錄，防止 5 秒內重複計數
                if recording_timer == (fps * 5 - 1):
                    sleep_timeline.append({
                        "time": current_time,
                        "motion_level": "large_turn",
                        "motion_intensity": motion_area,
                        "sound_level": sound_type,
                        "decibel": sound_db,
                        "video_clip": video_filename
                    })
                
                if recording_timer <= 0:
                    video_writer.release()
                    video_writer = None
                    print("💾 翻身短影片已安全儲存，5秒冷卻鎖解開。\n")

            # 4. 記錄微動或打呼數據 (沒有在錄大翻身時才紀錄)
            else:
                if motion_type == "micro_motion" or sound_type != "quiet":
                    sleep_timeline.append({
                        "time": current_time,
                        "motion_level": motion_type,
                        "motion_intensity": motion_area,
                        "sound_level": sound_type,
                        "decibel": sound_db,
                        "video_clip": "none"
                    })

            # 📺 5. 實時 UI 文字排版
            cv2.rectangle(frame, (10, 10), (420, 140), (0, 0, 0), -1)
            cv2.addWeighted(frame, 0.6, frame, 0.4, 0, frame)
            
            if video_writer is not None:
                status_text = "LARGE_TURN (RECORDING)"
                status_color = (0, 0, 255)
            elif motion_type == "micro_motion":
                status_text = "MICRO_MOTION"
                status_color = (0, 255, 255)
            else:
                status_text = "NONE"
                status_color = (0, 255, 0)

            cv2.putText(frame, f"SYS TIME: {current_time}", (25, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(frame, f"MOTION  : {status_text} ({motion_area})", (25, 75), cv2.FONT_HERSHEY_SIMPLEX, 0.7, status_color, 2)
            cv2.putText(frame, f"AUDIO   : {sound_db} dB ({sound_type})", (25, 110), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (244, 186, 91), 2)
            
            cv2.imshow("Tapo C200 Live Feed", frame)

            # 按 'q' 鍵手動提前關閉並結算
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                print("👋 使用者手動提前關閉並結算資料...")
                now_str = END_TIME

            # 🌅 ==================== 正確的結算控制區塊 ====================
            if now_str >= END_TIME:
                print(f"🌅 [{now_str}] 到達結束時間！正在關閉監測並計算整晚報告...")
                if video_writer is not None:
                    video_writer.release()
                    video_writer = None
                
                cap.release()
                cv2.destroyAllWindows()
                is_monitoring = False
                report_generated_today = True  # 上鎖，防止同一分鐘重複執行
                
                # 📊 [無保底分數演算法邏輯]
                large_turns = sum(1 for x in sleep_timeline if x["motion_level"] == "large_turn")
                micro_motions = sum(1 for x in sleep_timeline if x["motion_level"] == "micro_motion")
                snore_events = sum(1 for x in sleep_timeline if x["sound_level"] == "snoring_or_noise")
                total_events = len(sleep_timeline)

                # 扣分權重分配
                deduction = (large_turns * 2.0) + (micro_motions * 0.1) + (snore_events * 0.4)
                
                # 計算最終分數 (無保底，最低可到 0 分，用 max(0,...) 防禦負數)
                quality_score = int(max(0, 100 - deduction))
                
                # 極短時間測試平滑優化
                if total_events < 20 and quality_score < 100:
                    quality_score = int(max(0, 100 - (large_turns * 3)))

                final_report = {
                    "report_date": report_date,
                    "summary": {
                        "total_events": total_events,
                        "large_turn_count": large_turns,
                        "snore_count": snore_events,
                        "sleep_quality_score": quality_score
                    },
                    "timeline": sleep_timeline
                }
                
                # 寫入本地端備份 JSON
                output_path = os.path.join(current_dir, "sleep_report.json")
                with open(output_path, "w", encoding="utf-8") as f:
                    json.dump(final_report, f, ensure_ascii=False, indent=4)
                print(f"💾 [成功] 本地 JSON 報告已寫入：{output_path}")

                # 🌐 ⚡ 直連 phpMyAdmin 連線與資料上傳
                try:
                    print("🌐 正在自動連線至 phpMyAdmin 的 sonnap 資料庫...")
                    conn = mysql.connector.connect(**DB_CONFIG)
                    cursor = conn.cursor()
                    
                    timeline_json_str = json.dumps(sleep_timeline, ensure_ascii=False)
                    
                    sql_query = """
                    INSERT INTO sleep_records 
                    (report_date, total_events, large_turn_count, snore_count, sleep_quality_score, timeline) 
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """
                    sql_values = (report_date, total_events, large_turns, snore_events, quality_score, timeline_json_str)
                    
                    cursor.execute(sql_query, sql_values)
                    conn.commit()
                    print("🚀 [大成功] 數據與 Timeline 紀錄已上傳至 phpMyAdmin！資料表更新完成。\n")
                    
                except Exception as err:
                    print(f"❌ 自動寫入資料庫失敗，錯誤原因: {err}")
                finally:
                    if 'conn' in locals() and conn.is_connected():
                        cursor.close()
                        conn.close()
                        print("🔌 資料庫連線已安全斷開，系統持續背景待命。\n")
            # =============================================================

        # 🎯 節省 CPU 效能控制
        if not is_monitoring:
            time.sleep(1)
        else:
            time.sleep(0.001)

except KeyboardInterrupt:
    if video_writer is not None: video_writer.release()
    cv2.destroyAllWindows()
    print("\n👋 定時監測系統已安全退出。")
