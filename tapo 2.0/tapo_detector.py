import cv2
import json
import time
import numpy as np
from datetime import datetime, timedelta
import os
import mysql.connector
import atexit
import signal
import sys
import subprocess
import threading
import queue
import argparse

# ==================== 🛠️ 設定區 ====================
def load_config():
    """載入設定（優先順序：命令列 > 設定檔 > 預設值）"""
    
    # 1. 預設值
    default_config = {
        "start_time": "01:00:00",
        "end_time": "08:00:00",
        "motion_large": 350000,
        "motion_micro": 250000,
        "min_motion_area": 50000,
        "audio_silence_threshold": 30,
        "audio_snooze_threshold": 40,
        "tapo_url": "rtsp://imqs113:Monica113@10.22.221.253:554/stream1",
        "video_min_duration": 5,
        "video_extend_duration": 5,
        "video_max_duration": 30,
        "video_extend_cooldown": 10,
        "max_timeline_events": 500,
        "enable_auto_cleanup": False,
        "min_valid_events": 5          # 最少 5 筆事件才算有效睡眠
    }
    
    # 2. 從設定檔載入
    config_path = "config.json"
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                file_config = json.load(f)
                default_config.update(file_config)
                print(f"✅ 從設定檔載入: {config_path}")
        except Exception as e:
            print(f"⚠️ 讀取設定檔失敗: {e}")
    
    # 3. 解析命令列參數
    parser = argparse.ArgumentParser(description='🌙 睡眠監測系統')
    parser.add_argument('--start', '-s', help='開始時間 (HH:MM:SS)')
    parser.add_argument('--end', '-e', help='結束時間 (HH:MM:SS)')
    parser.add_argument('--config', '-c', help='設定檔路徑')
    parser.add_argument('--interactive', '-i', action='store_true', help='互動模式')
    args = parser.parse_args()
    
    # 命令列參數覆蓋設定檔
    if args.start:
        default_config['start_time'] = args.start
    if args.end:
        default_config['end_time'] = args.end
    if args.config:
        try:
            with open(args.config, 'r', encoding='utf-8') as f:
                custom_config = json.load(f)
                default_config.update(custom_config)
                print(f"✅ 從指定設定檔載入: {args.config}")
        except Exception as e:
            print(f"⚠️ 讀取指定設定檔失敗: {e}")
    
    # 4. 互動模式
    if args.interactive or (not args.start and not args.end and not os.path.exists(config_path)):
        print("\n" + "="*60)
        print("🕐 互動式設定")
        print("="*60)
        print("(直接按 Enter 使用預設值)")
        
        user_input = input(f"開始時間 (預設 {default_config['start_time']}): ").strip()
        if user_input:
            try:
                datetime.strptime(user_input, "%H:%M:%S")
                default_config['start_time'] = user_input
            except ValueError:
                print(f"❌ 格式錯誤，使用預設值")
        
        user_input = input(f"結束時間 (預設 {default_config['end_time']}): ").strip()
        if user_input:
            try:
                datetime.strptime(user_input, "%H:%M:%S")
                default_config['end_time'] = user_input
            except ValueError:
                print(f"❌ 格式錯誤，使用預設值")
        
        print(f"\n✅ 設定完成: {default_config['start_time']} ~ {default_config['end_time']}")
        print("="*60 + "\n")
    
    return default_config

# 載入設定
config = load_config()

# 套用到全域變數
START_TIME = config['start_time']
END_TIME = config['end_time']
MOTION_LARGE = config['motion_large']
MOTION_MICRO = config['motion_micro']
MIN_MOTION_AREA = config.get('min_motion_area', 50000)
AUDIO_SILENCE_THRESHOLD = config['audio_silence_threshold']
AUDIO_SNOOZE_THRESHOLD = config['audio_snooze_threshold']
tapo_url = config['tapo_url']
MIN_VALID_EVENTS = config.get('min_valid_events', 5)

# ✅ 錄影設定（從設定檔載入）
VIDEO_MIN_DURATION = config.get('video_min_duration', 5)
VIDEO_EXTEND_DURATION = config.get('video_extend_duration', 5)
VIDEO_MAX_DURATION = config.get('video_max_duration', 30)
VIDEO_EXTEND_COOLDOWN = config.get('video_extend_cooldown', 10)

# ✅ 數據品質設定
MAX_TIMELINE_EVENTS = config.get('max_timeline_events', 500)
ENABLE_AUTO_CLEANUP = config.get('enable_auto_cleanup', True)

print(f"\n🌙 睡眠監測系統")
print(f"⏰ 監測時間: {START_TIME} ~ {END_TIME}")
print(f"🎯 動作閾值: 大翻身={MOTION_LARGE}, 微動={MOTION_MICRO}")
print(f"🎤 音頻閾值: 靜音={AUDIO_SILENCE_THRESHOLD}, 打呼={AUDIO_SNOOZE_THRESHOLD}")
print(f"🎬 錄影設定: 最小{VIDEO_MIN_DURATION}s, 延長{VIDEO_EXTEND_DURATION}s, 最長{VIDEO_MAX_DURATION}s\n")

# FFmpeg paths
FFMPEG_PATH = r"C:\Users\USER\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
FFPROBE_PATH = r"C:\Users\USER\AppData\Local\Microsoft\WinGet\Links\ffprobe.exe"

# 動作過濾
MOTION_MIN_DURATION = 3
MOTION_COOLDOWN = 30

# 顯示設定
DISPLAY_WIDTH = 640
DISPLAY_HEIGHT = 480     
KEEP_ASPECT_RATIO = True
PROCESS_EVERY_N_FRAMES = 2
DISPLAY_FPS = 20

# 音頻設定
AUDIO_SAMPLE_RATE = 16000
AUDIO_CHUNK_SIZE = 4096
AUDIO_BUFFER_SIZE = 5

# 自動儲存間隔 (秒)
AUTO_SAVE_INTERVAL = 300

# ✅ 保留的動作和聲音類型
KEEP_EVENT_TYPES = ['large_turn', 'micro_motion']
KEEP_SOUND_TYPES = ['snoring_or_noise', 'breathing_heavy']

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

# 音頻相關全域變數
audio_queue = queue.Queue()
current_audio_db = 30
current_sound_type = "quiet"
audio_buffer = []
audio_lock = threading.Lock()
audio_initialized = False
audio_stats = {
    "peak_db": 0,
    "avg_db": 0,
    "sample_count": 0
}

# 動作過濾變數
motion_frame_counter = 0
last_motion_time = 0
motion_cooldown_counter = 0

# ✅ 錄影相關變數
recording_timer = 0
video_extension_timer = 0
video_start_time = None
video_events = []

# ========== ✅ 日期判斷函數 ==========


# 設定區加入
CUTOFF_HOUR = 15 # 幾點算隔天 (預設 14:00)
CUTOFF_MINUTE = 0

def get_sleep_date():
    """記錄日期 = 起床當天的日期"""
    return datetime.now().strftime("%Y-%m-%d")

# ========== ✅ 防止重複記錄函數 ==========
def is_event_duplicate(timeline, time_str, motion_type, threshold_seconds=3):
    """
    檢查事件是否在短時間內重複
    """
    if not timeline:
        return False
    
    recent_events = timeline[-10:]
    
    try:
        t2 = datetime.strptime(time_str, "%H:%M:%S")
    except:
        return False
    
    for event in recent_events:
        event_time = event.get('time', '')
        if event_time == time_str:
            return True
        
        event_motion = event.get('motion_level', '')
        if event_motion == motion_type:
            try:
                t1 = datetime.strptime(event_time, "%H:%M:%S")
                diff = abs((t2 - t1).total_seconds())
                if diff < threshold_seconds:
                    return True
            except:
                pass
    
    return False

def add_event_to_timeline(timeline, event_data, threshold_seconds=3):
    """安全地添加事件到 timeline（防止重複）"""
    time_str = event_data.get('time', '')
    motion_type = event_data.get('motion_level', '')
    
    if is_event_duplicate(timeline, time_str, motion_type, threshold_seconds):
        return False, f"⏭️ 跳過重複事件: {time_str} ({motion_type})"
    
    timeline.append(event_data)
    return True, f"✅ 記錄事件: {time_str} ({motion_type})"
# ==================================================

# ==================== 🔍 FFmpeg 檢查 ====================
def check_ffmpeg():
    try:
        result = subprocess.run([FFMPEG_PATH, '-version'], 
                              capture_output=True, 
                              check=True,
                              timeout=5)
        print(f"✅ FFmpeg 已安裝: {FFMPEG_PATH}")
        return True
    except:
        try:
            result = subprocess.run(['ffmpeg', '-version'], 
                                  capture_output=True, 
                                  check=True,
                                  timeout=5)
            print("✅ FFmpeg 已安裝 (系統 PATH)")
            return True
        except:
            print("❌ FFmpeg 未安裝！")
            return False

# ==================== 💾 資料庫操作 ====================
def test_database_connection():
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        conn.close()
        print("✅ 資料庫連線成功")
        return True
    except:
        print("❌ 資料庫連線失敗")
        return False

def get_daily_record_count(report_date):
    """取得當天的記錄數量"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT COUNT(*) FROM sleep_records WHERE report_date = %s",
            (report_date,)
        )
        count = cursor.fetchone()[0]
        cursor.close()
        conn.close()
        return count
    except:
        return 0

def get_existing_timeline(report_date):
    """取得現有的 timeline"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT timeline FROM sleep_records WHERE report_date = %s",
            (report_date,)
        )
        record = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if record and record['timeline']:
            return json.loads(record['timeline'])
        return []
    except:
        return []

def calculate_completeness_score(timeline):
    """完整度分數 - 時長權重提高"""
    if not timeline:
        return 0
    
    total_events = len(timeline)
    large_turns = sum(1 for x in timeline if x.get("motion_level") == "large_turn")
    
    # 計算時間跨度
    try:
        first_time = datetime.strptime(timeline[0].get('time', '00:00:00'), "%H:%M:%S")
        last_time = datetime.strptime(timeline[-1].get('time', '00:00:00'), "%H:%M:%S")
        if last_time < first_time:
            duration_hours = (last_time - first_time).total_seconds() / 3600 + 24
        else:
            duration_hours = (last_time - first_time).total_seconds() / 3600
    except:
        duration_hours = 0
    
    # ✅ 時長權重 5 → 15，確保長時間數據不會被短時間數據覆蓋
    score = total_events + (large_turns * 2) + (duration_hours * 15)
    return score

def calculate_duration_hours(timeline):
    """計算睡眠時長（小時）"""
    if not timeline or len(timeline) < 2:
        return 0
    
    try:
        first_time = datetime.strptime(timeline[0].get('time', '00:00:00'), "%H:%M:%S")
        last_time = datetime.strptime(timeline[-1].get('time', '00:00:00'), "%H:%M:%S")
        if last_time < first_time:
            return (last_time - first_time).total_seconds() / 3600 + 24
        else:
            return (last_time - first_time).total_seconds() / 3600
    except:
        return 0

# ========== ✅ 數據清理函數 ==========
def clean_timeline_data(timeline):
    """清理 timeline 數據"""
    if not timeline or not isinstance(timeline, list):
        return []
    
    cleaned = []
    
    for event in timeline:
        motion_level = event.get('motion_level', 'none')
        sound_level = event.get('sound_level', 'quiet')
        motion_intensity = event.get('motion_intensity', 0)
        
        if motion_intensity > MOTION_LARGE:
            motion_level = "large_turn"
        elif motion_intensity > MOTION_MICRO:
            motion_level = "micro_motion"
        else:
            motion_level = "none"
        
        event['motion_level'] = motion_level
        
        keep = False
        if motion_level in KEEP_EVENT_TYPES:
            keep = True
        if sound_level in KEEP_SOUND_TYPES:
            keep = True
        
        if keep:
            cleaned.append(event)
    
    if len(cleaned) > MAX_TIMELINE_EVENTS:
        priority_events = [e for e in cleaned 
                          if e.get('motion_level') == 'large_turn' 
                          or e.get('sound_level') == 'snoring_or_noise']
        other_events = [e for e in cleaned if e not in priority_events]
        cleaned = priority_events + other_events[:MAX_TIMELINE_EVENTS - len(priority_events)]
        cleaned = cleaned[:MAX_TIMELINE_EVENTS]
    
    return cleaned

def calculate_sleep_quality_score(timeline_data):
    """
    根據翻身間隔計算睡眠品質分數
    
    分數計算邏輯：
    - 翻身間隔 < 5 分鐘：扣 10 分/次（嚴重片段化）
    - 翻身間隔 5-15 分鐘：扣 5 分/次（輕微片段化）
    - 翻身間隔 15-30 分鐘：扣 2 分/次（尚可）
    - 翻身間隔 ≥ 30 分鐘：扣 0 分/次（連續深層睡眠）
    
    另外：
    - 打呼事件：扣 0.4 分/次
    - 微動事件：扣 0.1 分/次（但微動不影響間隔計算）
    """
    if not timeline_data:
        return 0
    
    # 1. 找出所有大翻身事件（按時間排序）
    large_turns = []
    for event in timeline_data:
        if event.get("motion_level") == "large_turn":
            time_str = event.get("time", "00:00:00")
            try:
                dt = datetime.strptime(time_str, "%H:%M:%S")
                large_turns.append(dt)
            except:
                pass
    
    # 2. 計算翻身間隔分數
    turn_penalty = 0
    if len(large_turns) >= 2:
        for i in range(1, len(large_turns)):
            interval = (large_turns[i] - large_turns[i-1]).total_seconds() / 60  # 分鐘
            
            if interval < 5:
                turn_penalty += 10  # 嚴重片段化
                print(f"   🔴 翻身間隔 {interval:.1f} 分鐘 (<5) → 扣 10 分")
            elif interval < 15:
                turn_penalty += 5   # 輕微片段化
                print(f"   🟡 翻身間隔 {interval:.1f} 分鐘 (5-15) → 扣 5 分")
            elif interval < 30:
                turn_penalty += 2   # 尚可
                print(f"   🟢 翻身間隔 {interval:.1f} 分鐘 (15-30) → 扣 2 分")
            else:
                print(f"   ✅ 翻身間隔 {interval:.1f} 分鐘 (≥30) → 不扣分")
    
    # 3. 計算其他事件扣分
    snore_events = sum(1 for x in timeline_data if x.get("sound_level") == "snoring_or_noise")
    micro_motions = sum(1 for x in timeline_data if x.get("motion_level") == "micro_motion")
    
    snore_penalty = snore_events * 0.4
    micro_penalty = micro_motions * 0.1
    
    # 4. 計算最終分數
    total_penalty = turn_penalty + snore_penalty + micro_penalty
    quality_score = int(max(0, 100 - total_penalty))
    
    print(f"\n📊 分數計算:")
    print(f"   翻身間隔懲罰: {turn_penalty}")
    print(f"   打呼懲罰: {snore_penalty:.1f} ({snore_events} 次 × 0.4)")
    print(f"   微動懲罰: {micro_penalty:.1f} ({micro_motions} 次 × 0.1)")
    print(f"   總懲罰: {total_penalty:.1f}")
    print(f"   最終分數: {quality_score}")
    
    return quality_score

# ========== ✅ 主要儲存函數（新邏輯） ==========
def save_current_data_to_database(timeline_data, report_date=None):
    """
    儲存資料到資料庫
    
    規則：
    1. 如果沒有指定 report_date，自動以起床日期判斷
    2. 如果舊數據時長 < 1 小時 → 視為測試數據，直接覆蓋
    3. 如果新數據時長 >= 3 小時，且舊數據 < 3 小時 → 強制覆蓋
    4. 否則比較完整度，只有新數據更完整時才覆蓋
    """
    if not timeline_data:
        print("📭 沒有資料需要儲存")
        return False
    
    try:
        # ✅ 自動判斷日期
        if report_date is None:
            report_date = get_sleep_date()
            print(f"📅 自動判斷為 {report_date} 的睡眠記錄")
        
        # ✅ 計算新數據的完整度和時長
        new_score = calculate_completeness_score(timeline_data)
        new_duration = calculate_duration_hours(timeline_data)
        total_events = len(timeline_data)
        
        print(f"📊 新數據: {total_events} 筆事件, 時長: {new_duration:.1f}h, 完整度: {new_score:.1f}")
        
        # ✅ 檢查是否已有記錄
        existing_count = get_daily_record_count(report_date)
        
        if existing_count > 0:
            # 讀取舊數據
            old_timeline = get_existing_timeline(report_date)
            old_score = calculate_completeness_score(old_timeline)
            old_duration = calculate_duration_hours(old_timeline)
            old_events = len(old_timeline)
            
            print(f"📊 舊數據: {old_events} 筆事件, 時長: {old_duration:.1f}h, 完整度: {old_score:.1f}")
            
            # ✅ 規則 1: 舊數據時長 < 1 小時 → 視為測試數據，強制覆蓋
            if old_duration < 1:
                print(f"🔄 舊數據時長 {old_duration:.1f}h < 1h (測試數據)，強制覆蓋")
            
            # ✅ 規則 2: 新數據時長 >= 3 小時，且舊數據 < 3 小時 → 強制覆蓋
            elif new_duration >= 3 and old_duration < 3:
                print(f"🔄 新數據 {new_duration:.1f}h >= 3h，且舊數據僅 {old_duration:.1f}h，強制覆蓋")
            
            # ✅ 規則 3: 正常比較完整度
            elif new_score <= old_score:
                print(f"⏭️ 新數據完整度較低 ({new_score:.1f} <= {old_score:.1f})，保留舊數據")
                return False
            
            else:
                print(f"🔄 新數據更完整 ({new_score:.1f} > {old_score:.1f})，覆蓋中...")
            
            # 刪除舊記錄
            conn = mysql.connector.connect(**DB_CONFIG)
            cursor = conn.cursor()
            cursor.execute(
                "DELETE FROM sleep_records WHERE report_date = %s",
                (report_date,)
            )
            conn.commit()
            cursor.close()
            conn.close()
            print(f"🗑️ 已刪除舊記錄")
        
        # ✅ 檢查是否有效數據（至少有 MIN_VALID_EVENTS 筆事件）
        if total_events < MIN_VALID_EVENTS:
            print(f"⚠️ 數據量過少 ({total_events} < {MIN_VALID_EVENTS})，可能是雜訊，不儲存")
            return False
        
        # ✅ 清理數據
        if ENABLE_AUTO_CLEANUP:
            print(f"🧹 清理數據中... (原始: {len(timeline_data)} 筆)")
            cleaned_timeline = clean_timeline_data(timeline_data)
            print(f"   清理後: {len(cleaned_timeline)} 筆")
        else:
            cleaned_timeline = timeline_data
        
        # 計算統計
        total_events = len(cleaned_timeline)

        # 使用新的分數計算方式
        quality_score = calculate_sleep_quality_score(cleaned_timeline)

        # 保留其他統計（但不影響分數）
        large_turns = sum(1 for x in cleaned_timeline if x.get("motion_level") == "large_turn")
        micro_motions = sum(1 for x in cleaned_timeline if x.get("motion_level") == "micro_motion")
        snore_events = sum(1 for x in cleaned_timeline if x.get("sound_level") == "snoring_or_noise")

        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        timeline_json_str = json.dumps(cleaned_timeline, ensure_ascii=False)
        
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
        print(f"📅 記錄日期: {report_date}")
        return True
        
    except Exception as err:
        print(f"❌ 儲存資料失敗: {err}")
        return False
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()


def emergency_save():
    global current_sleep_timeline, current_report_date
    if current_sleep_timeline:
        print(f"\n⚠️ 緊急儲存 {len(current_sleep_timeline)} 筆資料...")
        # 緊急儲存使用自動日期判斷
        save_current_data_to_database(current_sleep_timeline)
        print("✅ 緊急儲存完成")
    else:
        print("📭 沒有資料需要儲存")

atexit.register(emergency_save)

def signal_handler(sig, frame):
    print("\n\n🛑 偵測到中斷訊號 (Ctrl+C)")
    
    # ✅ Force save even if timeline is empty (save audio buffer)
    global current_sleep_timeline, current_report_date
    
    # Try to create events from recent audio
    if audio_initialized and current_audio_db > AUDIO_SILENCE_THRESHOLD:
        current_time = datetime.now().strftime("%H:%M:%S")
        event_data = {
            "time": current_time,
            "motion_level": "none",
            "motion_intensity": 0,
            "sound_level": current_sound_type,
            "decibel": current_audio_db,
            "video_clip": "none"
        }
        if current_sound_type != "quiet":
            add_event_to_timeline(current_sleep_timeline, event_data)
    
    if 'audio_thread' in globals() and audio_thread:
        audio_thread.stop()
        audio_thread.join(timeout=2)
    
    emergency_save()
    
    global cap, video_writer
    if video_writer is not None:
        video_writer.release()
    if cap is not None:
        cap.release()
    cv2.destroyAllWindows()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

def cleanup_existing_records():
    if not ENABLE_AUTO_CLEANUP:
        return
    
    print("\n🧹 檢查並清理現有數據...")
    
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("SELECT id, report_date, timeline FROM sleep_records WHERE timeline IS NOT NULL")
        records = cursor.fetchall()
        
        if not records:
            print("   📭 沒有需要清理的記錄")
            cursor.close()
            conn.close()
            return
        
        cleaned_count = 0
        for record in records:
            try:
                timeline = json.loads(record['timeline'])
                if not isinstance(timeline, list):
                    continue
                
                original_count = len(timeline)
                cleaned = clean_timeline_data(timeline)
                new_count = len(cleaned)
                
                if new_count < original_count:
                    large_turns = sum(1 for x in cleaned if x.get("motion_level") == "large_turn")
                    micro_motions = sum(1 for x in cleaned if x.get("motion_level") == "micro_motion")
                    snore_events = sum(1 for x in cleaned if x.get("sound_level") == "snoring_or_noise")
                    total_events = len(cleaned)
                    
                    deduction = (large_turns * 2.0) + (micro_motions * 0.1) + (snore_events * 0.4)
                    quality_score = int(max(0, 100 - deduction))
                    
                    if total_events < 20 and quality_score < 100:
                        quality_score = int(max(0, 100 - (large_turns * 3)))
                    
                    cursor.execute("""
                        UPDATE sleep_records 
                        SET 
                            total_events = %s,
                            large_turn_count = %s,
                            snore_count = %s,
                            sleep_quality_score = %s,
                            timeline = %s,
                            updated_at = %s
                        WHERE id = %s
                    """, (
                        total_events,
                        large_turns,
                        snore_events,
                        quality_score,
                        json.dumps(cleaned, ensure_ascii=False),
                        datetime.now(),
                        record['id']
                    ))
                    
                    cleaned_count += 1
                    print(f"   ✅ {record['report_date']}: {original_count} → {new_count} 筆")
                    
            except Exception as e:
                print(f"   ⚠️ ID {record['id']} 清理失敗: {e}")
        
        conn.commit()
        cursor.close()
        conn.close()
        
        if cleaned_count > 0:
            print(f"✅ 共清理 {cleaned_count} 筆記錄")
        else:
            print("   ✅ 所有記錄都是乾淨的")
            
    except Exception as e:
        print(f"⚠️ 清理失敗: {e}")

# ==================== 🎤 音頻捕獲 ====================
class AudioCaptureFFmpeg(threading.Thread):
    def __init__(self, rtsp_url):
        super().__init__()
        self.rtsp_url = rtsp_url
        self.running = False
        self.daemon = True
        self.process = None
        self.audio_received = False
        self.error_message = None
        self.frame_count = 0
        self.last_status_time = time.time()
        
    def run(self):
        self.running = True
        
        cmd = [
            FFMPEG_PATH,
            '-rtsp_transport', 'tcp',
            '-i', self.rtsp_url,
            '-vn',
            '-acodec', 'pcm_s16le',
            '-ar', str(AUDIO_SAMPLE_RATE),
            '-ac', '1',
            '-f', 's16le',
            '-'
        ]
        
        try:
            startupinfo = None
            if sys.platform == "win32":
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startupinfo.wShowWindow = subprocess.SW_HIDE
            
            self.process = subprocess.Popen(
                cmd, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.DEVNULL,
                bufsize=0,
                startupinfo=startupinfo
            )
            
            print("🎤 音頻捕獲已啟動...")
            
            startup_timeout = 10
            start_wait = time.time()
            
            while self.running:
                raw_data = self.process.stdout.read(AUDIO_CHUNK_SIZE * 2)
                if not raw_data:
                    if time.time() - start_wait > startup_timeout:
                        print("⚠️ 音頻流無數據")
                        self.error_message = "無音頻數據"
                        break
                    time.sleep(0.01)
                    continue
                
                self.audio_received = True
                self.frame_count += 1
                
                audio_data = np.frombuffer(raw_data, dtype=np.int16)
                if len(audio_data) > 0:
                    rms = np.sqrt(np.mean(audio_data**2))
                    if rms > 0:
                        db = 20 * np.log10(rms)
                    else:
                        db = 0
                    
                    audio_queue.put({
                        'data': audio_data,
                        'rms': rms,
                        'db': db
                    })
                    
                    current_time = time.time()
                    if current_time - self.last_status_time >= 5:
                        sound_level = "quiet"
                        if db > AUDIO_SNOOZE_THRESHOLD:
                            sound_level = "LOUD"
                        elif db > AUDIO_SILENCE_THRESHOLD:
                            sound_level = "medium"
                        print(f"🎤 音頻: {db:.1f} dB ({sound_level}) - 幀: {self.frame_count}")
                        self.last_status_time = current_time
            
        except Exception as e:
            self.error_message = str(e)
            if self.running:
                print(f"⚠️ 音頻線程錯誤: {e}")
        finally:
            if self.process:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            print("\n🎤 音頻捕獲已停止")
    
    def stop(self):
        self.running = False
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()

def process_audio(audio_info):
    global current_audio_db, current_sound_type, audio_buffer, audio_initialized, audio_stats
    
    db_value = audio_info['db']
    
    with audio_lock:
        audio_stats["sample_count"] += 1
        audio_stats["peak_db"] = max(audio_stats["peak_db"], db_value)
        audio_stats["avg_db"] = (audio_stats["avg_db"] * (audio_stats["sample_count"] - 1) + db_value) / audio_stats["sample_count"]
        
        audio_buffer.append(db_value)
        if len(audio_buffer) > AUDIO_BUFFER_SIZE:
            audio_buffer.pop(0)
        
        if audio_buffer:
            smooth_db = np.median(audio_buffer)
            current_audio_db = int(smooth_db)
            audio_initialized = True
        
        if current_audio_db > AUDIO_SNOOZE_THRESHOLD:
            current_sound_type = "snoring_or_noise"
        elif current_audio_db > AUDIO_SILENCE_THRESHOLD:
            current_sound_type = "breathing_heavy"
        else:
            current_sound_type = "quiet"

def get_audio_stats():
    global audio_stats
    return {
        "current_db": current_audio_db,
        "sound_type": current_sound_type,
        "peak_db": audio_stats["peak_db"],
        "avg_db": int(audio_stats["avg_db"]),
        "samples": audio_stats["sample_count"]
    }

def resize_with_aspect_ratio(frame, target_width=640, target_height=480):
    h, w = frame.shape[:2]
    aspect = w / h
    scale_w = target_width / w
    scale_h = target_height / h
    scale = min(scale_w, scale_h, 1.0)
    new_w = int(w * scale)
    new_h = int(h * scale)
    return cv2.resize(frame, (new_w, new_h))

# ==================== 🚀 主程式 ====================
print("============ 🌙 睡眠定時監測 (起床日期版 + 完整度比較) ============")
print(f"系統設定：每日 {START_TIME} 自動開啟監測，{END_TIME} 自動關閉\n")
print(f"🎯 動作閾值: 大翻身={MOTION_LARGE}, 微動={MOTION_MICRO}")
print(f"⏱️ 動作持續時間要求: {MOTION_MIN_DURATION} 幀")
print(f"🎬 錄影: 最小{VIDEO_MIN_DURATION}s, 延長{VIDEO_EXTEND_DURATION}s, 最長{VIDEO_MAX_DURATION}s")
print(f"🧹 自動清理: {'啟用' if ENABLE_AUTO_CLEANUP else '停用'}")
print(f"📅 記錄日期: 以起床日期為準 (凌晨 0-12 點 → 前一天)")
print(f"📊 完整度比較: 新數據更完整時才會覆蓋\n")

if not check_ffmpeg():
    print("\n⚠️ 將使用僅視頻模式")
    audio_available = False
else:
    audio_available = True

db_available = test_database_connection()
if not db_available:
    print("⚠️ 資料庫不可用")

if db_available and ENABLE_AUTO_CLEANUP:
    cleanup_existing_records()

print("\n💡 按 's' 鍵手動儲存 | 按 'q' 鍵關閉\n")

is_monitoring = False
sleep_timeline = []
recording_timer = 0
report_generated_today = False
frame_counter = 0
last_display_time = 0
last_auto_save_time = time.time()

last_motion_type = "none"
last_motion_area = 0
current_dir = os.path.dirname(os.path.abspath(__file__))
audio_thread = None

try:
    while True:
        now_str = datetime.now().strftime("%H:%M:%S")
        
        if now_str == "00:00:00":
            report_generated_today = False

        if START_TIME < END_TIME:
            in_monitoring_time = START_TIME <= now_str < END_TIME
        else:
            in_monitoring_time = now_str >= START_TIME or now_str < END_TIME
        
        # ✅ 檢查今天是否已有完整數據
        today = datetime.now().strftime("%Y-%m-%d")
        has_today_data = get_daily_record_count(today) > 0
        
        if in_monitoring_time and not is_monitoring and not has_today_data:
            print(f"⏰ [{now_str}] 到達設定時間！正在連線 Tapo 攝影機...")
            
            if audio_available:
                print("🎤 啟動音頻捕獲...")
                audio_thread = AudioCaptureFFmpeg(tapo_url)
                audio_thread.start()
                time.sleep(5)
                
                if audio_thread.error_message:
                    print(f"⚠️ 音頻啟動失敗: {audio_thread.error_message}")
                    audio_available = False
            else:
                print("🎤 音頻功能已停用")
            
            cap = cv2.VideoCapture(tapo_url, cv2.CAP_FFMPEG)
            if cap.isOpened():
                fgbg = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=16, detectShadows=False)
                sleep_timeline = []  
                is_monitoring = True
                frame_counter = 0
                last_auto_save_time = time.time()
                audio_buffer = []
                
                motion_frame_counter = 0
                last_motion_time = 0
                motion_cooldown_counter = 0
                
                # ✅ 重置錄影變數
                video_writer = None
                recording_timer = 0
                video_extension_timer = 0
                video_start_time = None
                video_events = []
                
                current_sleep_timeline = sleep_timeline
                current_is_monitoring = is_monitoring
                
                width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                fps = int(cap.get(cv2.CAP_PROP_FPS)) if cap.get(cv2.CAP_PROP_FPS) > 0 else 20
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                print(f"✅ 連線成功！解析度: {width}x{height}, FPS: {fps}")
                print("✅ 開始監測睡眠...\n")
                
                cv2.namedWindow("Tapo C200 Sleep Monitor", cv2.WINDOW_NORMAL)
                cv2.resizeWindow("Tapo C200 Sleep Monitor", DISPLAY_WIDTH, DISPLAY_HEIGHT)
            else:
                print("❌ 連線失敗，10 秒後重新嘗試...")
                if audio_thread:
                    audio_thread.stop()
                time.sleep(10)
                continue

        if is_monitoring and cap is not None:
            ret, frame = cap.read()
            if not ret:
                print("⚠️ 無法讀取畫面，重新連線...")
                cap.release()
                cap = cv2.VideoCapture(tapo_url, cv2.CAP_FFMPEG)
                time.sleep(1)
                continue

            if audio_available and audio_thread and audio_thread.running:
                try:
                    while not audio_queue.empty():
                        audio_info = audio_queue.get_nowait()
                        process_audio(audio_info)
                except queue.Empty:
                    pass

            current_time = datetime.now().strftime("%H:%M:%S")
            report_date = datetime.now().strftime("%Y-%m-%d")
            current_report_date = report_date
            
            frame_counter += 1
            should_process = (frame_counter % PROCESS_EVERY_N_FRAMES == 0)
            
            if should_process:
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                blurred = cv2.GaussianBlur(gray, (21, 21), 0)
                fgmask = fgbg.apply(blurred)
                _, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
                motion_area = cv2.countNonZero(thresh)

                    # ✅ Get audio values FIRST (always available)
                if audio_available and audio_initialized:
                    real_audio_db = current_audio_db
                    real_sound_type = current_sound_type
                else:
                    real_audio_db = 0
                    real_sound_type = "quiet"

                if audio_available and audio_initialized:
                    if real_sound_type != "quiet":
                        event_data = {
                            "time": current_time,
                            "motion_level": "none",
                            "motion_intensity": 0,
                            "sound_level": real_sound_type,
                            "decibel": real_audio_db,
                            "video_clip": "none"
                        }
                        added, msg = add_event_to_timeline(sleep_timeline, event_data, threshold_seconds=10)
                        if added:
                            print(f"🔊 {msg}")
                
                if motion_area < MIN_MOTION_AREA:
                    current_motion_type = "none"
                    is_motion = False
                    motion_frame_counter = 0
                else:
                    is_motion = False
                    current_motion_type = "none"

                    if motion_area > MOTION_LARGE:
                        current_motion_type = "large_turn"
                        is_motion = True
                    elif motion_area > MOTION_MICRO:
                        current_motion_type = "micro_motion"
                        is_motion = True
                
                if motion_cooldown_counter > 0:
                    motion_cooldown_counter -= 1
                
                if is_motion:
                    motion_frame_counter += 1
                else:
                    motion_frame_counter = 0
                
                # ========== ✅ 只有大翻身才觸發錄影 ==========
                if is_motion and motion_frame_counter >= MOTION_MIN_DURATION and motion_cooldown_counter == 0:
                    last_motion_time = frame_counter
                    motion_cooldown_counter = MOTION_COOLDOWN
                    
                    if audio_available and audio_initialized:
                        real_audio_db = current_audio_db
                        real_sound_type = current_sound_type
                    else:
                        real_audio_db = 0
                        real_sound_type = "quiet"
                    
                    # ✅ 只有大翻身才錄影
                    if current_motion_type == "large_turn":
                        video_filename = "none"
                        
                        if video_writer is not None:
                            extension_time = VIDEO_EXTEND_DURATION * fps
                            if recording_timer + extension_time <= VIDEO_MAX_DURATION * fps:
                                recording_timer += extension_time
                                video_extension_timer = VIDEO_EXTEND_COOLDOWN * fps
                                print(f"⏱️ 連續大翻身！延長錄影 +{VIDEO_EXTEND_DURATION}s (剩餘 {recording_timer/fps:.1f}s)")
                                
                                video_events.append({
                                    "time": current_time,
                                    "motion_level": "large_turn",
                                    "motion_intensity": motion_area,
                                    "sound_level": real_sound_type,
                                    "decibel": real_audio_db
                                })
                            else:
                                print(f"⚠️ 已達最大錄影時間 {VIDEO_MAX_DURATION}s")
                        else:
                            video_dir = os.path.join(current_dir, "sleep_videos")
                            if not os.path.exists(video_dir): 
                                os.makedirs(video_dir)
                            
                            unique_suffix = f"{datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]}_{np.random.randint(100, 999)}"
                            video_filename = f"turn_{unique_suffix}.mp4"
                            video_output_path = os.path.join(video_dir, video_filename)
                            
                            print(f"🎬 大翻身！開始錄影: {video_filename}")
                            video_writer = cv2.VideoWriter(video_output_path, fourcc, fps, (width, height))
                            recording_timer = VIDEO_MIN_DURATION * fps
                            video_extension_timer = 0
                            video_start_time = current_time
                            video_events = [{
                                "time": current_time,
                                "motion_level": "large_turn",
                                "motion_intensity": motion_area,
                                "sound_level": real_sound_type,
                                "decibel": real_audio_db
                            }]
                            
                            event_data = {
                                "time": current_time,
                                "motion_level": "large_turn",
                                "motion_intensity": motion_area,
                                "sound_level": real_sound_type,
                                "decibel": real_audio_db,
                                "video_clip": video_filename
                            }
                            added, msg = add_event_to_timeline(sleep_timeline, event_data, threshold_seconds=3)
                            if added:
                                print(f"📝 {msg}")
                            else:
                                print(f"⚠️ {msg}")
                    
                    # ========== ✅ 微動和打呼：只記錄，不錄影 ==========
                    else:
                        if current_motion_type == "micro_motion" or real_sound_type != "quiet":
                            if video_writer is not None:
                                video_events.append({
                                    "time": current_time,
                                    "motion_level": current_motion_type,
                                    "motion_intensity": motion_area,
                                    "sound_level": real_sound_type,
                                    "decibel": real_audio_db
                                })
                                if real_sound_type == "snoring_or_noise":
                                    print(f"🔊 [{current_time}] 錄影中打呼 ({real_audio_db} dB)")
                                elif current_motion_type == "micro_motion":
                                    print(f"🔄 [{current_time}] 錄影中微動 ({motion_area})")
                            else:
                                event_data = {
                                    "time": current_time,
                                    "motion_level": current_motion_type,
                                    "motion_intensity": motion_area,
                                    "sound_level": real_sound_type,
                                    "decibel": real_audio_db,
                                    "video_clip": "none"
                                }
                                added, msg = add_event_to_timeline(sleep_timeline, event_data, threshold_seconds=5)
                                if added:
                                    if real_sound_type == "snoring_or_noise":
                                        print(f"🔊 [{current_time}] 打呼/噪音 ({real_audio_db} dB) → 只記錄")
                                    elif current_motion_type == "micro_motion":
                                        print(f"🔄 [{current_time}] 微動 ({motion_area}) → 只記錄")
                                else:
                                    print(f"⏭️ {msg}")
                            
                
                # ========== ✅ 錄影計時器處理 ==========
                if video_writer is not None:
                    video_writer.write(frame)
                    recording_timer -= 1
                    
                    if video_extension_timer > 0:
                        video_extension_timer -= 1
                    
                    if recording_timer <= 0:
                        if video_extension_timer > 0:
                            recording_timer = fps
                        else:
                            video_writer.release()
                            video_writer = None
                            print(f"💾 影片已儲存 (共 {len(video_events)} 個事件)")
                
                last_motion_type = current_motion_type
                last_motion_area = motion_area

            # ========== 📺 顯示畫面 ==========
            if KEEP_ASPECT_RATIO:
                display_frame = resize_with_aspect_ratio(frame, DISPLAY_WIDTH, DISPLAY_HEIGHT)
            else:
                display_frame = cv2.resize(frame, (DISPLAY_WIDTH, DISPLAY_HEIGHT))
            
            cv2.rectangle(display_frame, (10, 10), (550, 280), (0, 0, 0), -1)
            cv2.addWeighted(display_frame, 0.6, display_frame, 0.4, 0, display_frame)
            
            if video_writer is not None:
                status_text = f"🔴 RECORDING ({recording_timer/fps:.0f}s)"
                status_color = (0, 0, 255)
            elif last_motion_type == "micro_motion":
                status_text = "🟡 MICRO_MOTION"
                status_color = (0, 255, 255)
            else:
                status_text = "🟢 NONE"
                status_color = (0, 255, 0)

            cv2.putText(display_frame, f"SYS TIME: {current_time}", (25, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(display_frame, f"MOTION  : {status_text} ({last_motion_area})", (25, 75), cv2.FONT_HERSHEY_SIMPLEX, 0.7, status_color, 2)
            cv2.putText(display_frame, f"FRAME  : {motion_frame_counter}/{MOTION_MIN_DURATION}", (25, 110), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            
            if audio_available:
                if audio_initialized:
                    audio_color = (0, 255, 0) if current_sound_type == "quiet" else (0, 255, 255) if current_sound_type == "breathing_heavy" else (0, 0, 255)
                    audio_status = f"AUDIO   : {current_audio_db} dB ({current_sound_type})"
                else:
                    audio_color = (255, 255, 0)
                    audio_status = "AUDIO   : 等待中..."
                
                cv2.putText(display_frame, audio_status, (25, 145), cv2.FONT_HERSHEY_SIMPLEX, 0.7, audio_color, 2)
            else:
                cv2.putText(display_frame, "AUDIO   : 已停用", (25, 145), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (128, 128, 128), 2)
            
            cv2.putText(display_frame, f"📊 EVENTS: {len(sleep_timeline)}", (25, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (100, 255, 100), 2)
            
            if video_writer is not None:
                cv2.putText(display_frame, f"🎬 REC: {recording_timer/fps:.0f}s / {VIDEO_MAX_DURATION}s", (25, 210), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 200, 255), 2)
            
            # ✅ 顯示當前儲存日期
            sleep_date = get_sleep_date()
            cv2.putText(display_frame, f"📅 SAVE DATE: {sleep_date}", (25, 245), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
            
            if audio_available and audio_initialized:
                audio_dot_color = (0, 0, 255) if current_sound_type == "snoring_or_noise" else (0, 255, 255) if current_sound_type == "breathing_heavy" else (0, 255, 0)
                cv2.circle(display_frame, (510, 25), 10, audio_dot_color, -1)
                cv2.circle(display_frame, (510, 25), 10, (255, 255, 255), 2)
            
            current_time_ms = time.time()
            if current_time_ms - last_display_time >= (1.0 / DISPLAY_FPS):
                cv2.imshow("Tapo C200 Sleep Monitor", display_frame)
                last_display_time = current_time_ms

            # ========== ⌨️ 按鍵控制 ==========
            key = cv2.waitKey(1) & 0xFF
            
            if key == ord('s'):
                if sleep_timeline:
                    print(f"\n💾 手動儲存 ({len(sleep_timeline)} 筆資料)...")
                    save_current_data_to_database(sleep_timeline)
                else:
                    print("📭 沒有資料需要儲存")
                continue
            
            if key == ord('q'):
                print("\n👋 使用者手動關閉，儲存資料...")
                if sleep_timeline:
                    save_current_data_to_database(sleep_timeline)
                is_monitoring = False
                break

            # ========== 💾 自動儲存 ==========
            current_time_sec = time.time()
            if current_time_sec - last_auto_save_time >= AUTO_SAVE_INTERVAL:
                if sleep_timeline:
                    print(f"\n🔄 自動儲存 ({len(sleep_timeline)} 筆資料)...")
                    save_current_data_to_database(sleep_timeline)
                last_auto_save_time = current_time_sec

            # ========== 🌅 結束時間檢查 ==========
            if START_TIME < END_TIME:
                monitoring_should_continue = START_TIME <= now_str < END_TIME
            else:
                monitoring_should_continue = now_str >= START_TIME or now_str < END_TIME

            if is_monitoring and not monitoring_should_continue:
                print(f"🌅 [{now_str}] 到達結束時間！正在關閉監測...")
                if video_writer is not None:
                    video_writer.release()
                    video_writer = None
                
                if audio_thread:
                    audio_thread.stop()
                    audio_thread.join(timeout=2)
                
                if sleep_timeline:
                    save_current_data_to_database(sleep_timeline)
                
                if cap is not None:
                    cap.release()
                cv2.destroyAllWindows()
                is_monitoring = False
                report_generated_today = True
                current_is_monitoring = False

        if not is_monitoring:
            time.sleep(1)
        else:
            time.sleep(0.001)

except KeyboardInterrupt:
    pass
finally:
    if video_writer is not None:
        video_writer.release()
    if cap is not None:
        cap.release()
    if audio_thread:
        audio_thread.stop()
        audio_thread.join(timeout=2)
    cv2.destroyAllWindows()
    print("\n👋 程式已安全關閉")