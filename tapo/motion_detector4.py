import cv2
import json
import time
import numpy as np
from datetime import datetime
import os
import mysql.connector
import atexit
import signal
import sys

# ==================== 🛠️ 設定區 ====================
tapo_url = "rtsp://imqs113:Monica113@192.168.124.4:554/stream1"

START_TIME = "00:30:00"
END_TIME   = "08:00:00"

MOTION_LARGE = 150000
MOTION_MICRO = 30000

DISPLAY_WIDTH = 640
DISPLAY_HEIGHT = 480     
KEEP_ASPECT_RATIO = True
PROCESS_EVERY_N_FRAMES = 2
DISPLAY_FPS = 20

# 自動儲存間隔 (秒)
AUTO_SAVE_INTERVAL = 300  # 5分鐘

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",          
    "database": "sonnap"      
}
# ==================================================

os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp"

# 全域變數
current_sleep_timeline = []
current_report_date = ""
current_is_monitoring = False
cap = None
video_writer = None

def save_current_data_to_database(timeline_data, report_date):
    """儲存資料到資料庫"""
    if not timeline_data:
        print("📭 沒有資料需要儲存")
        return False
    
    try:
        large_turns = sum(1 for x in timeline_data if x["motion_level"] == "large_turn")
        micro_motions = sum(1 for x in timeline_data if x["motion_level"] == "micro_motion")
        snore_events = sum(1 for x in timeline_data if x["sound_level"] == "snoring_or_noise")
        total_events = len(timeline_data)

        deduction = (large_turns * 2.0) + (micro_motions * 0.1) + (snore_events * 0.4)
        quality_score = int(max(0, 100 - deduction))
        
        if total_events < 20 and quality_score < 100:
            quality_score = int(max(0, 100 - (large_turns * 3)))

        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        timeline_json_str = json.dumps(timeline_data, ensure_ascii=False)
        
        if not report_date:
            report_date = datetime.now().strftime("%Y-%m-%d")
        
        sql_query = """
        INSERT INTO sleep_records 
        (report_date, total_events, large_turn_count, snore_count, sleep_quality_score, timeline) 
        VALUES (%s, %s, %s, %s, %s, %s)
        """
        sql_values = (report_date, total_events, large_turns, snore_events, quality_score, timeline_json_str)
        
        cursor.execute(sql_query, sql_values)
        conn.commit()
        
        print(f"✅ 成功儲存 {total_events} 筆資料到資料庫！")
        print(f"📊 睡眠品質分數: {quality_score}")
        return True
        
    except Exception as err:
        print(f"❌ 儲存資料失敗: {err}")
        return False
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()

def emergency_save():
    """緊急儲存所有資料（程式關閉時呼叫）"""
    global current_sleep_timeline, current_report_date
    
    if current_sleep_timeline:
        print(f"\n⚠️ 緊急儲存 {len(current_sleep_timeline)} 筆資料...")
        save_current_data_to_database(current_sleep_timeline, current_report_date)
        print("✅ 緊急儲存完成")
    else:
        print("📭 沒有資料需要儲存")

# 註冊退出時自動儲存
atexit.register(emergency_save)

def signal_handler(sig, frame):
    """處理 Ctrl+C"""
    print("\n\n🛑 偵測到中斷訊號 (Ctrl+C)")
    emergency_save()
    # 釋放資源
    global cap, video_writer
    if video_writer is not None:
        video_writer.release()
    if cap is not None:
        cap.release()
    cv2.destroyAllWindows()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

def resize_with_aspect_ratio(frame, target_width=640, target_height=480):
    """保持原始比例縮放影像"""
    h, w = frame.shape[:2]
    aspect = w / h
    
    scale_w = target_width / w
    scale_h = target_height / h
    scale = min(scale_w, scale_h, 1.0)
    
    new_w = int(w * scale)
    new_h = int(h * scale)
    
    return cv2.resize(frame, (new_w, new_h))

print("============ 🌙 睡眠定時監測與資料庫系統已在背景待命 ============")
print(f"系統設定：每日 {START_TIME} 自動開啟監測，{END_TIME} 自動關閉並上傳資料庫。\n")
print(f"⚡ 效能優化：每 {PROCESS_EVERY_N_FRAMES} 幀處理一次檢測，顯示幀率限制 {DISPLAY_FPS} FPS\n")
print("💡 按 's' 鍵手動儲存當前資料")
print("💡 按 'q' 鍵關閉程式並自動儲存\n")

is_monitoring = False
sleep_timeline = []
recording_timer = 0
report_generated_today = False
frame_counter = 0
last_display_time = 0
last_auto_save_time = time.time()

# 儲存上一次的檢測結果
last_motion_type = "none"
last_sound_db = 30
last_sound_type = "quiet"
last_motion_area = 0

current_dir = os.path.dirname(os.path.abspath(__file__))

try:
    while True:
        now_str = datetime.now().strftime("%H:%M:%S")
        
        # 每天午夜 12 點重設保險鎖
        if now_str == "00:00:00":
            report_generated_today = False

        # 檢查是否到達啟動時間
        if START_TIME < END_TIME:
            in_monitoring_time = START_TIME <= now_str < END_TIME
        else:
            in_monitoring_time = now_str >= START_TIME or now_str < END_TIME
        
        # 啟動監測
        if in_monitoring_time and not is_monitoring and not report_generated_today:
            print(f"⏰ [{now_str}] 到達設定時間！正在連線 Tapo 攝影機...")
            cap = cv2.VideoCapture(tapo_url, cv2.CAP_FFMPEG)
            if cap.isOpened():
                fgbg = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=16, detectShadows=False)
                sleep_timeline = []  
                is_monitoring = True
                frame_counter = 0
                last_auto_save_time = time.time()
                
                # 更新全域變數
                current_sleep_timeline = sleep_timeline
                current_is_monitoring = is_monitoring
                
                width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                fps = int(cap.get(cv2.CAP_PROP_FPS)) if cap.get(cv2.CAP_PROP_FPS) > 0 else 20
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                print(f"✅ 連線成功！解析度: {width}x{height}, FPS: {fps}")
                
                cv2.namedWindow("Tapo C200 Live Feed", cv2.WINDOW_NORMAL)
                cv2.resizeWindow("Tapo C200 Live Feed", DISPLAY_WIDTH, DISPLAY_HEIGHT)
            else:
                print("❌ 連線失敗，10 秒後重新嘗試...")
                time.sleep(10)
                continue

        # 監測執行中
        if is_monitoring and cap is not None:
            ret, frame = cap.read()
            if not ret:
                print("⚠️ 無法讀取畫面，嘗試重新連線...")
                cap.release()
                cap = cv2.VideoCapture(tapo_url, cv2.CAP_FFMPEG)
                time.sleep(1)
                continue

            current_time = datetime.now().strftime("%H:%M:%S")
            report_date = datetime.now().strftime("%Y-%m-%d")
            current_report_date = report_date  # 更新全域變數
            
            # 幀計數器 - 控制檢測頻率
            frame_counter += 1
            should_process = (frame_counter % PROCESS_EVERY_N_FRAMES == 0)
            
            if should_process:
                # ========== 1. 動作檢測 ==========
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                blurred = cv2.GaussianBlur(gray, (21, 21), 0)
                fgmask = fgbg.apply(blurred)
                _, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
                last_motion_area = cv2.countNonZero(thresh)
                
                last_motion_type = "none"
                if last_motion_area > MOTION_LARGE: 
                    last_motion_type = "large_turn"
                elif last_motion_area > MOTION_MICRO: 
                    last_motion_type = "micro_motion"

                # ========== 2. 聲音模擬 ==========
                base_noise = 30
                if last_motion_type == "large_turn":
                    last_sound_db = int(base_noise + np.random.randint(25, 35))
                elif last_motion_type == "micro_motion":
                    last_sound_db = int(base_noise + np.random.randint(5, 12))
                else:
                    last_sound_db = int(base_noise + np.random.choice([0, 3, 8], p=[0.96, 0.035, 0.005]))

                # 聲音品質類型判定
                last_sound_type = "quiet"
                if last_sound_db > 55:    
                    last_sound_type = "snoring_or_noise"
                elif last_sound_db > 48:  
                    last_sound_type = "breathing_heavy"

                # ========== 3. 觸發自動錄影 ==========
                video_filename = "none"
                if last_motion_type == "large_turn" and video_writer is None:
                    video_dir = os.path.join(current_dir, "sleep_videos")
                    if not os.path.exists(video_dir): 
                        os.makedirs(video_dir)
                    
                    unique_suffix = f"{datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]}_{np.random.randint(100, 999)}"
                    video_filename = f"turn_{unique_suffix}.mp4"
                    video_output_path = os.path.join(video_dir, video_filename)
                    
                    print(f"🎬 [新事件] 偵測到大翻身 ({last_motion_area})！啟動 5 秒冷卻鎖與錄影: {video_filename}")
                    video_writer = cv2.VideoWriter(video_output_path, fourcc, fps, (width, height))
                    recording_timer = fps * 5

                # ========== 4. 正在錄影的處理 ==========
                if video_writer is not None:
                    video_writer.write(frame)
                    recording_timer -= 1
                    
                    if recording_timer == (fps * 5 - 1):
                        sleep_timeline.append({
                            "time": current_time,
                            "motion_level": "large_turn",
                            "motion_intensity": last_motion_area,
                            "sound_level": last_sound_type,
                            "decibel": last_sound_db,
                            "video_clip": video_filename
                        })
                    
                    if recording_timer <= 0:
                        video_writer.release()
                        video_writer = None
                        print("💾 翻身短影片已安全儲存，5秒冷卻鎖解開。\n")

                # ========== 5. 記錄微動或打呼數據 ==========
                else:
                    if last_motion_type == "micro_motion" or last_sound_type != "quiet":
                        sleep_timeline.append({
                            "time": current_time,
                            "motion_level": last_motion_type,
                            "motion_intensity": last_motion_area,
                            "sound_level": last_sound_type,
                            "decibel": last_sound_db,
                            "video_clip": "none"
                        })

            # ========== 6. 顯示畫面 ==========
            if KEEP_ASPECT_RATIO:
                display_frame = resize_with_aspect_ratio(frame, DISPLAY_WIDTH, DISPLAY_HEIGHT)
            else:
                display_frame = cv2.resize(frame, (DISPLAY_WIDTH, DISPLAY_HEIGHT))
            
            # 實時 UI 文字排版
            cv2.rectangle(display_frame, (10, 10), (420, 180), (0, 0, 0), -1)
            cv2.addWeighted(display_frame, 0.6, display_frame, 0.4, 0, display_frame)
            
            if video_writer is not None:
                status_text = "LARGE_TURN (RECORDING)"
                status_color = (0, 0, 255)
            elif last_motion_type == "micro_motion":
                status_text = "MICRO_MOTION"
                status_color = (0, 255, 255)
            else:
                status_text = "NONE"
                status_color = (0, 255, 0)

            cv2.putText(display_frame, f"SYS TIME: {current_time}", (25, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(display_frame, f"MOTION  : {status_text} ({last_motion_area})", (25, 75), cv2.FONT_HERSHEY_SIMPLEX, 0.7, status_color, 2)
            cv2.putText(display_frame, f"AUDIO   : {last_sound_db} dB ({last_sound_type})", (25, 110), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (244, 186, 91), 2)
            
            # 顯示未儲存數量
            cv2.putText(display_frame, f"📊 EVENTS: {len(sleep_timeline)}", (25, 145), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (100, 255, 100), 2)
            
            # 限制顯示幀率
            current_time_ms = time.time()
            if current_time_ms - last_display_time >= (1.0 / DISPLAY_FPS):
                cv2.imshow("Tapo C200 Live Feed", display_frame)
                last_display_time = current_time_ms

            # ========== 按鍵控制 ==========
            key = cv2.waitKey(1) & 0xFF
            
            # 按 's' 鍵手動儲存
            if key == ord('s'):
                if sleep_timeline:
                    print(f"\n💾 手動儲存 ({len(sleep_timeline)} 筆資料)...")
                    save_current_data_to_database(sleep_timeline, report_date)
                else:
                    print("📭 沒有資料需要儲存")
                continue
            
            # 按 'q' 鍵關閉並儲存
            if key == ord('q'):
                print("\n👋 使用者手動關閉，儲存資料...")
                if sleep_timeline:
                    save_current_data_to_database(sleep_timeline, report_date)
                is_monitoring = False
                break

            # ========== 自動定期儲存 ==========
            current_time_sec = time.time()
            if current_time_sec - last_auto_save_time >= AUTO_SAVE_INTERVAL:
                if sleep_timeline:
                    print(f"\n🔄 自動儲存 ({len(sleep_timeline)} 筆資料)...")
                    save_current_data_to_database(sleep_timeline, report_date)
                last_auto_save_time = current_time_sec

            # ========== 結算控制區塊（到達結束時間） ==========
            if START_TIME < END_TIME:
                monitoring_should_continue = START_TIME <= now_str < END_TIME
            else:
                monitoring_should_continue = now_str >= START_TIME or now_str < END_TIME

            if is_monitoring and not monitoring_should_continue:
                print(f"🌅 [{now_str}] 到達結束時間！正在關閉監測並計算整晚報告...")
                if video_writer is not None:
                    video_writer.release()
                    video_writer = None
                
                if sleep_timeline:
                    save_current_data_to_database(sleep_timeline, report_date)
                
                if cap is not None:
                    cap.release()
                cv2.destroyAllWindows()
                is_monitoring = False
                report_generated_today = True
                current_is_monitoring = False

        # 節省 CPU
        if not is_monitoring:
            time.sleep(1)
        else:
            time.sleep(0.001)

except KeyboardInterrupt:
    # 信號處理器會處理這個
    pass
finally:
    # 確保所有資源被釋放
    if video_writer is not None:
        video_writer.release()
    if cap is not None:
        cap.release()
    cv2.destroyAllWindows()
    print("\n👋 程式已安全關閉")