import cv2
import json
import time
import numpy as np
from datetime import datetime
import os

# ==================== 🛠️ 設定區 ====================
tapo_url = "rtsp://imqs113:Monica113@192.168.137.59:554/stream1"

START_TIME = "22:40:00"  # 自動啟動時間
END_TIME   = "22:41:00"  # 自動關閉與存檔時間

# 🏃 動作靈敏度設定 (數值越小越靈敏)
MOTION_LARGE =  100000    # 超過此數值判定為「大翻身 (large_turn)」
MOTION_MICRO = 10000      # 超過此數值判定為「微動 (micro_motion)」
# ==================================================

os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp"

print("============ 🌙 睡眠 Live 監測 + 自動錄影系統 ============")
print(f"系統設定：每日 {START_TIME} 開啟 Live，{END_TIME} 關閉。")
print(f"目前判定閾值 -> 大翻身: {MOTION_LARGE} | 微動: {MOTION_MICRO}\n")

is_monitoring = False
sleep_timeline = []
video_writer = None
recording_timer = 0
report_generated_today = False

current_dir = os.path.dirname(os.path.abspath(__file__))

try:
    while True:
        now_str = datetime.now().strftime("%H:%M:%S")
        
        if now_str == "00:00:00":
            report_generated_today = False

        if now_str >= START_TIME and now_str < END_TIME and not is_monitoring and not report_generated_today:
            print(f"⏰ [{now_str}] 到達設定時間！啟動監測與 Live 視窗...")
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

        if is_monitoring:
            ret, frame = cap.read()
            if not ret:
                continue

            current_time = datetime.now().strftime("%H:%M:%S")
            file_date = datetime.now().strftime("%Y%m%d_%H%M%S")

            # 1. 動作檢測
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            blurred = cv2.GaussianBlur(gray, (21, 21), 0)
            fgmask = fgbg.apply(blurred)
            _, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
            motion_area = cv2.countNonZero(thresh)
            
            # 使用頂部設定的參數做動態分級
            motion_type = "none"
            if motion_area > MOTION_LARGE: 
                motion_type = "large_turn"
            elif motion_area > MOTION_MICRO: 
                motion_type = "micro_motion"

            # 2. 聲音模擬
            base_noise = 35
            if motion_type == "large_turn": sound_db = int(base_noise + np.random.randint(25, 35))
            elif motion_type == "micro_motion": sound_db = int(base_noise + np.random.randint(10, 18))
            else: sound_db = int(base_noise + np.random.choice([0, 5, 12], p=[0.8, 0.15, 0.05]))

            sound_type = "quiet"
            if sound_db > 60: sound_type = "snoring_or_noise"
            elif sound_db > 45: sound_type = "breathing_heavy"

            # 3. 觸發自動錄影
            video_filename = "none"
            if motion_type == "large_turn" and video_writer is None:
                video_filename = f"turn_{file_date}.mp4"
                video_output_path = os.path.join(current_dir, video_filename)
                print(f"🎬 偵測到大翻身 ({motion_area})！啟動自動錄影: {video_filename}")
                video_writer = cv2.VideoWriter(video_output_path, fourcc, fps, (width, height))
                recording_timer = fps * 5

            if video_writer is not None:
                video_writer.write(frame)
                recording_timer -= 1
                if recording_timer <= 0:
                    video_writer.release()
                    video_writer = None
                    print("💾 翻身短影片剪輯結束。")

            # 4. 記錄數據
            if motion_type != "none" or sound_type != "quiet":
                sleep_timeline.append({
                    "time": current_time,
                    "motion_level": motion_type,
                    "motion_intensity": motion_area,
                    "sound_level": sound_type,
                    "decibel": sound_db,
                    "video_clip": video_filename if motion_type == "large_turn" else "none"
                })

            # 📺 5. 專業級 UI 文字排版 (解決重疊問題)
            # 畫出一個黑色的半透明背景遮罩，讓文字更好讀
            cv2.rectangle(frame, (10, 10), (420, 140), (0, 0, 0), -1)
            cv2.addWeighted(frame, 0.6, frame, 0.4, 0, frame) # 讓方框變半透明
            
            # 設定不同狀態的文字顏色
            if motion_type == "large_turn":
                status_color = (0, 0, 255) # 紅色 (大動作)
            elif motion_type == "micro_motion":
                status_color = (0, 255, 255) # 黃色 (微動)
            else:
                status_color = (0, 255, 0) # 綠色 (安靜)

            # 分層次繪製文字，微調字體大小(0.7)與粗細(2)避免黏在一起
            cv2.putText(frame, f"SYS TIME: {current_time}", (25, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(frame, f"MOTION  : {motion_type.upper()} ({motion_area})", (25, 75), cv2.FONT_HERSHEY_SIMPLEX, 0.7, status_color, 2)
            cv2.putText(frame, f"AUDIO   : {sound_db} dB ({sound_type})", (25, 110), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (254, 186, 91), 2)
            
            cv2.imshow("Tapo C200 Live Feed", frame)

            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("👋 使用者手動提前關閉...")
                now_str = END_TIME

            if now_str >= END_TIME:
                print(f"🌅 [{now_str}] 到達結束時間！正在導出整晚報告...")
                if video_writer is not None:
                    video_writer.release()
                    video_writer = None
                cap.release()
                cv2.destroyAllWindows()
                is_monitoring = False
                report_generated_today = True
                
                large_turns = sum(1 for x in sleep_timeline if x["motion_level"] == "large_turn")
                snore_events = sum(1 for x in sleep_timeline if x["sound_level"] == "snoring_or_noise")
                final_report = {
                    "report_date": datetime.now().strftime("%Y-%m-%d"),
                    "summary": {
                        "total_events": len(sleep_timeline),
                        "large_turn_count": large_turns,
                        "snore_count": snore_events,
                        "sleep_quality_score": max(50, 100 - (large_turns * 5) - (snore_events * 2))
                    },
                    "timeline": sleep_timeline
                }
                
                json_output_path = os.path.join(current_dir, "sleep_report.json")
                with open(json_output_path, "w", encoding="utf-8") as f:
                    json.dump(final_report, f, ensure_ascii=False, indent=4)
                
                print(f"💾 [成功] 報告已安全存入路徑: {json_output_path}\n")

        time.sleep(0.01)

except KeyboardInterrupt:
    if video_writer is not None: video_writer.release()
    cv2.destroyAllWindows()
    print("\n👋 系統關閉。")
