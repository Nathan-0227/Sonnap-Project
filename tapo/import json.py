import json
import mysql.connector
import os
import glob
from datetime import datetime

# 資料庫設定
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "sonnap"
}

def import_from_sleep_reports():
    """從 sleep_reports 資料夾匯入所有資料"""
    
    current_dir = os.path.dirname(os.path.abspath(__file__))
    reports_dir = os.path.join(current_dir, "sleep_reports")
    
    if not os.path.exists(reports_dir):
        print(f"❌ 找不到 sleep_reports 資料夾")
        return
    
    print(f"📂 從 {reports_dir} 匯入資料...")
    
    # 找到所有 JSON 檔案（排除 daily_summary.json）
    json_files = []
    for root, dirs, files in os.walk(reports_dir):
        for file in files:
            if file.endswith('.json') and file != 'daily_summary.json' and file != 'all_history.json':
                json_files.append(os.path.join(root, file))
    
    if not json_files:
        print("❌ 沒有找到任何 JSON 檔案")
        return
    
    print(f"✅ 找到 {len(json_files)} 個 JSON 檔案\n")
    
    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()
    
    imported = 0
    
    for json_file in json_files:
        try:
            print(f"📄 處理: {os.path.basename(json_file)}")
            
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            # 提取資料
            if 'timeline' in data:
                timeline = data['timeline']
                report_date = data.get('report_date', os.path.basename(os.path.dirname(json_file)))
                summary = data.get('summary', {})
                
                total_events = summary.get('total_events', len(timeline))
                large_turns = summary.get('large_turn_count', 0)
                snore_events = summary.get('snore_count', 0)
                quality_score = summary.get('sleep_quality_score', 0)
            else:
                timeline = data
                report_date = os.path.basename(os.path.dirname(json_file))
                total_events = len(timeline)
                large_turns = sum(1 for x in timeline if x.get('motion_level') == 'large_turn')
                snore_events = sum(1 for x in timeline if x.get('sound_level') == 'snoring_or_noise')
                
                # 計算分數
                micro_motions = sum(1 for x in timeline if x.get('motion_level') == 'micro_motion')
                deduction = (large_turns * 2.0) + (micro_motions * 0.1) + (snore_events * 0.4)
                quality_score = int(max(0, 100 - deduction))
            
            if not timeline:
                print(f"  ⚠️ 沒有資料，跳過")
                continue
            
            # 檢查是否已存在
            cursor.execute("SELECT COUNT(*) FROM sleep_records WHERE report_date = %s", (report_date,))
            existing = cursor.fetchone()[0]
            
            if existing > 0:
                print(f"  ⚠️ {report_date} 已有 {existing} 筆資料，跳過")
                continue
            
            # 插入資料
            timeline_json = json.dumps(timeline, ensure_ascii=False)
            
            sql = """
            INSERT INTO sleep_records 
            (report_date, total_events, large_turn_count, snore_count, sleep_quality_score, timeline) 
            VALUES (%s, %s, %s, %s, %s, %s)
            """
            values = (report_date, total_events, large_turns, snore_events, quality_score, timeline_json)
            
            cursor.execute(sql, values)
            conn.commit()
            
            print(f"  ✅ 匯入成功! {total_events} 筆事件, 分數: {quality_score}")
            imported += 1
            
        except Exception as e:
            print(f"  ❌ 匯入失敗: {e}")
    
    cursor.close()
    conn.close()
    
    print(f"\n🎉 匯入完成！共匯入 {imported} 筆記錄")

if __name__ == "__main__":
    import_from_sleep_reports()