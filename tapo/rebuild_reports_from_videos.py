import cv2
import json
import numpy as np
from datetime import datetime
import os
import mysql.connector
import glob

# ==================== 設定 ====================
MOTION_LARGE = 150000
MOTION_MICRO = 30000

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",          
    "database": "sonnap"      
}

video_folder = r"C:\Users\USER\Documents\3-1\BD4\sleep_videos"

# 要處理的日期列表
TARGET_DATES = [
    {"date_str": "20260806", "report_date": "2026-08-06"},
    {"date_str": "20260807", "report_date": "2026-08-07"},
]

def analyze_videos_for_date(video_folder, date_str, report_date_str):
    """
    分析指定日期的所有影片，生成報告
    """
    
    if not os.path.exists(video_folder):
        print(f"❌ 影片資料夾不存在: {video_folder}")
        return None
    
    # 找出該日期的所有影片
    all_videos = glob.glob(os.path.join(video_folder, "*.mp4"))
    target_videos = [v for v in all_videos if date_str in os.path.basename(v)]
    
    if not target_videos:
        print(f"⚠️ 沒有找到 {date_str} 的影片")
        return None
    
    print(f"📹 找到 {len(target_videos)} 個 {date_str} 的影片\n")
    
    all_timeline = []
    
    for video_path in target_videos:
        print(f"  📹 分析: {os.path.basename(video_path)}")
        
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            print(f"    ❌ 無法開啟影片")
            continue
        
        # 獲取影片資訊
        fps = int(cap.get(cv2.CAP_PROP_FPS))
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = total_frames / fps
        
        # 初始化背景減除
        fgbg = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=16, detectShadows=False)
        
        frame_count = 0
        process_every_n = 5
        events_in_video = 0
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            frame_count += 1
            
            if frame_count % process_every_n != 0:
                continue
            
            # 動作檢測
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            blurred = cv2.GaussianBlur(gray, (21, 21), 0)
            fgmask = fgbg.apply(blurred)
            _, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
            motion_area = cv2.countNonZero(thresh)
            
            # 判斷動作類型
            motion_type = "none"
            if motion_area > MOTION_LARGE:
                motion_type = "large_turn"
            elif motion_area > MOTION_MICRO:
                motion_type = "micro_motion"
            
            # 如果有動作，記錄時間
            if motion_type != "none":
                seconds = frame_count / fps
                time_str = f"{int(seconds // 3600):02d}:{int((seconds % 3600) // 60):02d}:{int(seconds % 60):02d}"
                
                all_timeline.append({
                    "time": time_str,
                    "motion_level": motion_type,
                    "motion_intensity": motion_area,
                    "sound_level": "unknown",
                    "decibel": 0,
                    "video_clip": os.path.basename(video_path)
                })
                
                events_in_video += 1
        
        cap.release()
        print(f"    ✅ 偵測到 {events_in_video} 個事件")
    
    if not all_timeline:
        print(f"⚠️ {date_str} 沒有偵測到任何事件")
        return None
    
    # 生成報告
    print(f"\n  📊 總共偵測到 {len(all_timeline)} 個事件")
    
    # 計算統計
    large_turns = sum(1 for x in all_timeline if x["motion_level"] == "large_turn")
    micro_motions = sum(1 for x in all_timeline if x["motion_level"] == "micro_motion")
    total_events = len(all_timeline)
    
    deduction = (large_turns * 2.0) + (micro_motions * 0.1)
    quality_score = int(max(0, 100 - deduction))
    
    if total_events < 20 and quality_score < 100:
        quality_score = int(max(0, 100 - (large_turns * 3)))
    
    # 生成報告
    final_report = {
        "report_date": report_date_str,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "source": f"{len(target_videos)} videos from {date_str}",
        "summary": {
            "total_events": total_events,
            "large_turn_count": large_turns,
            "micro_motion_count": micro_motions,
            "snore_count": 0,
            "sleep_quality_score": quality_score
        },
        "timeline": all_timeline
    }
    
    return final_report

def save_report_to_database(report):
    """儲存報告到資料庫"""
    if not report:
        return False
    
    try:
        timeline = report['timeline']
        report_date = report['report_date']
        summary = report['summary']
        
        print(f"\n  💾 儲存到資料庫...")
        print(f"    日期: {report_date}")
        print(f"    事件數: {summary['total_events']}")
        print(f"    翻身次數: {summary['large_turn_count']}")
        print(f"    品質分數: {summary['sleep_quality_score']}")
        
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        # 先檢查是否已有同一天的資料（避免重複）
        cursor.execute("SELECT COUNT(*) FROM sleep_records WHERE report_date = %s", (report_date,))
        existing_count = cursor.fetchone()[0]
        
        if existing_count > 0:
            print(f"    ⚠️ 已有 {existing_count} 筆 {report_date} 的資料")
            response = input("    是否要新增？(y/n): ")
            if response.lower() != 'y':
                print("    ⏭️ 跳過")
                return False
        
        timeline_json_str = json.dumps(timeline, ensure_ascii=False)
        
        sql_query = """
        INSERT INTO sleep_records 
        (report_date, total_events, large_turn_count, snore_count, sleep_quality_score, timeline) 
        VALUES (%s, %s, %s, %s, %s, %s)
        """
        sql_values = (
            report_date,
            summary['total_events'],
            summary['large_turn_count'],
            0,
            summary['sleep_quality_score'],
            timeline_json_str
        )
        
        cursor.execute(sql_query, sql_values)
        conn.commit()
        
        print(f"    ✅ 成功儲存到資料庫！")
        return True
        
    except Exception as e:
        print(f"    ❌ 儲存失敗: {e}")
        return False
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()

def save_report_to_json(report):
    """儲存報告到 JSON 檔案"""
    if not report:
        return
    
    # 建立日期資料夾
    report_dir = os.path.join(os.path.dirname(video_folder), "sleep_reports", report['report_date'])
    if not os.path.exists(report_dir):
        os.makedirs(report_dir)
        print(f"  📁 建立資料夾: {report_dir}")
    
    # 儲存 JSON
    timestamp = datetime.now().strftime("%H%M%S")
    json_path = os.path.join(report_dir, f"sleep_report_{timestamp}_recovered.json")
    
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=4)
    
    print(f"  💾 JSON 已儲存: {json_path}")

def check_database_for_date(report_date):
    """檢查資料庫中是否有特定日期的資料"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT COUNT(*), SUM(total_events), AVG(sleep_quality_score)
            FROM sleep_records 
            WHERE report_date = %s
        """, (report_date,))
        
        count, total_events, avg_score = cursor.fetchone()
        
        if count > 0:
            print(f"  ✅ 已有 {count} 筆 {report_date} 的記錄")
            print(f"     總事件: {total_events if total_events else 0}")
            print(f"     平均分數: {avg_score:.1f}" if avg_score else "     平均分數: N/A")
            return True
        else:
            print(f"  📭 沒有 {report_date} 的記錄")
            return False
            
    except Exception as e:
        print(f"  ❌ 查詢失敗: {e}")
        return False
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()

def show_all_videos():
    """顯示所有影片檔案"""
    if not os.path.exists(video_folder):
        print(f"❌ 影片資料夾不存在: {video_folder}")
        return
    
    all_videos = glob.glob(os.path.join(video_folder, "*.mp4"))
    
    if not all_videos:
        print("📭 沒有找到任何影片")
        return
    
    print(f"\n📹 所有影片檔案 ({len(all_videos)} 個):")
    for video in sorted(all_videos):
        filename = os.path.basename(video)
        # 嘗試從檔名判斷日期
        date_part = filename.split('_')[1] if '_' in filename else 'unknown'
        size = os.path.getsize(video) / (1024 * 1024)  # MB
        print(f"  - {filename} ({size:.1f} MB)")

# ==================== 主程式 ====================

print("=" * 60)
print("🔄 從影片重建報告 (8/6 和 8/7)")
print("=" * 60)

# 先顯示所有影片
show_all_videos()

print("\n" + "=" * 60)
print("開始處理...")
print("=" * 60)

success_count = 0
failed_count = 0

for target in TARGET_DATES:
    date_str = target["date_str"]
    report_date = target["report_date"]
    
    print(f"\n{'='*60}")
    print(f"📅 處理日期: {report_date}")
    print(f"{'='*60}")
    
    # 檢查資料庫是否已有資料
    has_data = check_database_for_date(report_date)
    
    if has_data:
        print(f"⏭️ 跳過 {report_date}（已有資料）")
        continue
    
    # 分析影片
    report = analyze_videos_for_date(video_folder, date_str, report_date)
    
    if report:
        print(f"\n✅ {report_date} 報告已生成:")
        print(f"   📊 總事件: {report['summary']['total_events']}")
        print(f"   📊 翻身次數: {report['summary']['large_turn_count']}")
        print(f"   📊 品質分數: {report['summary']['sleep_quality_score']}")
        
        # 儲存到 JSON
        save_report_to_json(report)
        
        # 儲存到資料庫
        if save_report_to_database(report):
            success_count += 1
        else:
            failed_count += 1
    else:
        print(f"❌ {report_date} 無法生成報告（沒有影片或沒有事件）")
        failed_count += 1

# 總結
print("\n" + "=" * 60)
print("📊 處理完成!")
print(f"✅ 成功: {success_count} 天")
print(f"❌ 失敗: {failed_count} 天")
print("=" * 60)

# 檢查最終結果
print("\n📋 最終資料庫狀態:")
for target in TARGET_DATES:
    check_database_for_date(target["report_date"])
    