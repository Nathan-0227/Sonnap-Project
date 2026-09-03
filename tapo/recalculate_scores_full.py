"""
重新計算所有睡眠品質分數（完整版 + 自動備份）
執行方式: python recalculate_scores_full.py
"""
import mysql.connector
import json
from datetime import datetime, timedelta
import sys
import os

# ==================== 設定 ====================
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "sonnap"
}

# ========== 分數計算參數 ==========
# 翻身總數基礎分數
TURN_BASE_SCORE = {
    "excellent": (0, 5, 95),     # (最小值, 最大值, 基礎分數)
    "good": (6, 10, 85),
    "normal": (11, 20, 70),
    "poor": (21, 30, 50),
    "very_poor": (31, 999, 30)
}

# 間隔懲罰
INTERVAL_PENALTY = {
    "severe": (0, 5, 3),     # < 5 分鐘 → 扣 3 分
    "mild": (5, 15, 1),      # 5-15 分鐘 → 扣 1 分
    "none": (15, 999, 0)     # >= 15 分鐘 → 不扣分
}

SNORE_MAX_PENALTY = 15      # 打呼最多扣 15 分
SNORE_PENALTY_PER_EVENT = 0.2

MICRO_MAX_PENALTY = 5       # 微動最多扣 5 分
MICRO_PENALTY_PER_EVENT = 0.05

SKIP_SLEEP_ONSET = 30       # 跳過前 30 分鐘（入睡期）
# ==================================================

def get_base_score(total_turns):
    """根據翻身總數獲取基礎分數"""
    for key, (min_val, max_val, score) in TURN_BASE_SCORE.items():
        if min_val <= total_turns <= max_val:
            return score
    return 50  # 預設值

def calculate_interval_penalty(large_turns, verbose=False):
    """計算翻身間隔懲罰"""
    penalty = 0
    severe_count = 0
    mild_count = 0
    details = []
    
    if len(large_turns) < 2:
        return 0, 0, 0, []
    
    large_turns.sort()
    
    for i in range(1, len(large_turns)):
        interval = (large_turns[i] - large_turns[i-1]).total_seconds() / 60
        
        if interval < 5:
            penalty += INTERVAL_PENALTY["severe"][2]
            severe_count += 1
            details.append(f"  🔴 {interval:.1f} 分鐘 → 扣 {INTERVAL_PENALTY['severe'][2]} 分")
        elif interval < 15:
            penalty += INTERVAL_PENALTY["mild"][2]
            mild_count += 1
            details.append(f"  🟡 {interval:.1f} 分鐘 → 扣 {INTERVAL_PENALTY['mild'][2]} 分")
        else:
            details.append(f"  ✅ {interval:.1f} 分鐘 → 不扣分")
    
    return penalty, severe_count, mild_count, details

def filter_sleep_data(timeline_data, skip_minutes=30):
    """過濾掉入睡期的數據"""
    if not timeline_data or len(timeline_data) < 5:
        return timeline_data
    
    try:
        first_time_str = timeline_data[0].get("time", "00:00:00")
        first_time = datetime.strptime(first_time_str, "%H:%M:%S")
        cutoff_time = first_time + timedelta(minutes=skip_minutes)
        cutoff_str = cutoff_time.strftime("%H:%M:%S")
    except:
        return timeline_data
    
    filtered = []
    for event in timeline_data:
        try:
            event_time_str = event.get("time", "00:00:00")
            event_time = datetime.strptime(event_time_str, "%H:%M:%S")
            
            if event_time < first_time:
                event_time += timedelta(days=1)
            
            if event_time >= cutoff_time:
                filtered.append(event)
        except:
            continue
    
    if len(filtered) < len(timeline_data) * 0.3:
        skip_count = int(len(timeline_data) * 0.2)
        return timeline_data[skip_count:]
    
    return filtered

def calculate_sleep_quality_score(timeline_data, verbose=False):
    """
    完整版睡眠品質分數計算
    
    分數 = 基礎分數（翻身總數）+ 間隔調整 - 打呼懲罰 - 微動懲罰
    
    翻評級：
    ≤5次   → 95分 (優秀)
    6-10次  → 85分 (良好)
    11-20次 → 70分 (普通)
    21-30次 → 50分 (稍差)
    >30次   → 30分 (差)
    
    間隔懲罰：
    < 5 分鐘   → 扣 3 分/次 (嚴重片段化)
    5-15 分鐘  → 扣 1 分/次 (輕微片段化)
    ≥ 15 分鐘  → 不扣分
    
    打呼懲罰：每次扣 0.2 分，最多扣 15 分
    微動懲罰：每次扣 0.05 分，最多扣 5 分
    """
    if not timeline_data:
        return 0
    
    # 1. 過濾入睡期
    filtered_data = filter_sleep_data(timeline_data, SKIP_SLEEP_ONSET)
    
    if not filtered_data:
        return 0
    
    # 2. 找出所有大翻身事件
    large_turns = []
    for event in filtered_data:
        if event.get("motion_level") == "large_turn":
            time_str = event.get("time", "00:00:00")
            try:
                dt = datetime.strptime(time_str, "%H:%M:%S")
                large_turns.append(dt)
            except:
                pass
    
    total_turns = len(large_turns)
    
    # 3. 基礎分數
    base_score = get_base_score(total_turns)
    
    # 4. 間隔懲罰
    interval_penalty, severe_count, mild_count, interval_details = calculate_interval_penalty(large_turns, verbose)
    
    # 5. 計算其他事件扣分
    snore_events = sum(1 for x in filtered_data if x.get("sound_level") == "snoring_or_noise")
    micro_motions = sum(1 for x in filtered_data if x.get("motion_level") == "micro_motion")
    
    snore_penalty = min(snore_events * SNORE_PENALTY_PER_EVENT, SNORE_MAX_PENALTY)
    micro_penalty = min(micro_motions * MICRO_PENALTY_PER_EVENT, MICRO_MAX_PENALTY)
    
    # 6. 計算最終分數
    total_penalty = interval_penalty + snore_penalty + micro_penalty
    quality_score = int(max(0, min(100, base_score - total_penalty)))
    
    if verbose:
        print(f"\n  📊 分數計算:")
        print(f"     翻身總數: {total_turns} 次")
        print(f"     基礎分數: {base_score}")
        print(f"     間隔懲罰: {interval_penalty} (嚴重: {severe_count} 次, 輕微: {mild_count} 次)")
        for detail in interval_details[:5]:
            print(f"     {detail}")
        if len(interval_details) > 5:
            print(f"     ... 還有 {len(interval_details)-5} 個間隔")
        print(f"     打呼懲罰: {snore_penalty:.1f} ({snore_events} 次 × 0.2, 上限 {SNORE_MAX_PENALTY})")
        print(f"     微動懲罰: {micro_penalty:.1f} ({micro_motions} 次 × 0.05, 上限 {MICRO_MAX_PENALTY})")
        print(f"     總懲罰: {total_penalty:.1f}")
        print(f"     最終分數: {quality_score}")
    
    return quality_score

# ==================== 備份功能 ====================
def create_backup():
    """建立資料備份表"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_table = f"sleep_records_backup_{timestamp}"
        
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS {backup_table} AS 
            SELECT * FROM sleep_records
        """)
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"✅ 備份已建立: {backup_table}")
        return backup_table
    except Exception as e:
        print(f"❌ 備份失敗: {e}")
        return None

def restore_from_backup(backup_table):
    """從備份表恢復"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        # 確認備份表存在
        cursor.execute(f"SHOW TABLES LIKE '{backup_table}'")
        if not cursor.fetchone():
            print(f"❌ 備份表 {backup_table} 不存在")
            return False
        
        # 刪除原表並從備份恢復
        cursor.execute("DROP TABLE IF EXISTS sleep_records_restore")
        cursor.execute(f"CREATE TABLE sleep_records_restore AS SELECT * FROM {backup_table}")
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"✅ 已從 {backup_table} 恢復數據到 sleep_records_restore")
        return True
    except Exception as e:
        print(f"❌ 恢復失敗: {e}")
        return False

# ==================== 資料庫操作 ====================
def get_all_records():
    """從資料庫讀取所有記錄"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("""
            SELECT id, report_date, total_events, large_turn_count, 
                   snore_count, sleep_quality_score, timeline, created_at
            FROM sleep_records
            ORDER BY report_date, id
        """)
        
        records = cursor.fetchall()
        cursor.close()
        conn.close()
        return records
    except Exception as e:
        print(f"❌ 讀取資料失敗: {e}")
        return []

def update_record_score(record_id, new_score):
    """更新資料庫中的分數"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE sleep_records 
            SET sleep_quality_score = %s, updated_at = NOW()
            WHERE id = %s
        """, (new_score, record_id))
        
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"  ❌ 更新失敗: {e}")
        return False

# ==================== 顯示功能 ====================
def show_summary(records):
    """顯示資料摘要"""
    print("\n" + "="*100)
    print("📊 重新計算後的資料摘要")
    print("="*100)
    print(f"{'ID':<6} {'日期':<14} {'事件':<8} {'翻身':<8} {'打呼':<8} {'舊分數':<8} {'新分數':<8} {'差異':<8} {'評級':<10}")
    print("-"*100)
    
    for r in records:
        old_score = r.get('sleep_quality_score', 0)
        new_score = r.get('new_score', old_score)
        diff = new_score - old_score
        diff_str = f"+{diff}" if diff > 0 else str(diff)
        
        # 評級
        turns = r.get('large_turn_count', 0)
        if turns <= 5:
            grade = "優秀"
        elif turns <= 10:
            grade = "良好"
        elif turns <= 20:
            grade = "普通"
        elif turns <= 30:
            grade = "稍差"
        else:
            grade = "待加強"
        
        print(f"{r['id']:<6} {r['report_date']:<14} "
              f"{r['total_events']:<8} {r['large_turn_count']:<8} "
              f"{r['snore_count']:<8} {old_score:<8} {new_score:<8} {diff_str:<8} {grade:<10}")
    
    print("="*100)

def show_recalculation_result(record, new_score):
    """顯示單筆記錄的計算結果"""
    print(f"\n📅 {record['report_date']} (ID: {record['id']})")
    print(f"   翻身次數: {record['large_turn_count']}")
    print(f"   舊分數: {record['sleep_quality_score']}")
    print(f"   新分數: {new_score}")
    print(f"   變化: {'+' if new_score > record['sleep_quality_score'] else ''}{new_score - record['sleep_quality_score']}")

# ==================== 主程式 ====================
def main():
    print("="*100)
    print("🔄 完整版睡眠品質分數重新計算 + 自動備份")
    print("="*100)
    
    print("\n📌 分數計算規則:")
    print("   📊 翻身總數評級:")
    print("      ≤5次  → 95分 (優秀)")
    print("      6-10次 → 85分 (良好)")
    print("      11-20次 → 70分 (普通)")
    print("      21-30次 → 50分 (稍差)")
    print("      >30次  → 30分 (待加強)")
    print("   ⏱️ 間隔懲罰:")
    print("      < 5 分鐘   → 扣 3 分/次")
    print("      5-15 分鐘  → 扣 1 分/次")
    print("      ≥ 15 分鐘  → 不扣分")
    print("   😴 打呼懲罰: 每次扣 0.2 分 (最多扣 15 分)")
    print("   🔄 微動懲罰: 每次扣 0.05 分 (最多扣 5 分)")
    print(f"   🛌 跳過入睡期: 前 {SKIP_SLEEP_ONSET} 分鐘\n")
    
    # 1. 檢查資料庫連線
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        conn.close()
        print("✅ 資料庫連線成功\n")
    except Exception as e:
        print(f"❌ 資料庫連線失敗: {e}")
        return
    
    # 2. 建立備份
    print("📦 建立資料備份...")
    backup_table = create_backup()
    if not backup_table:
        response = input("⚠️ 備份失敗，是否繼續？(y/n): ")
        if response.lower() != 'y':
            print("❌ 已取消")
            return
    
    # 3. 讀取所有記錄
    print("\n📂 讀取資料庫記錄...")
    records = get_all_records()
    
    if not records:
        print("❌ 沒有找到任何記錄")
        return
    
    print(f"✅ 找到 {len(records)} 筆記錄\n")
    
    # 4. 計算分數（預覽）
    print("📊 計算新分數...")
    print("-"*100)
    
    preview_records = []
    for i, record in enumerate(records):
        # 跳過沒有 timeline 的記錄
        if not record['timeline']:
            continue
        
        # 解析 timeline
        try:
            if isinstance(record['timeline'], str):
                timeline_data = json.loads(record['timeline'])
            else:
                timeline_data = record['timeline']
        except:
            print(f"  ⚠️ 無法解析 timeline (ID: {record['id']})")
            continue
        
        if not timeline_data:
            continue
        
        # 計算新分數
        new_score = calculate_sleep_quality_score(timeline_data, verbose=True)
        
        if new_score is not None:
            record['new_score'] = new_score
            preview_records.append(record)
            show_recalculation_result(record, new_score)
    
    # 5. 顯示摘要
    show_summary(preview_records)
    
    # 6. 詢問是否更新
    print("\n" + "="*100)
    print(f"📌 將更新 {len(preview_records)} 筆記錄")
    print(f"💾 備份表: {backup_table}")
    print("📌 如需還原，請執行:")
    print(f"   DROP TABLE sleep_records;")
    print(f"   RENAME TABLE {backup_table} TO sleep_records;")
    
    response = input("\n⚠️ 是否將新分數更新到資料庫？(y/n): ")
    
    if response.lower() != 'y':
        print("❌ 已取消")
        return
    
    # 7. 更新資料庫
    print("\n💾 更新資料庫...")
    
    updated_count = 0
    for record in preview_records:
        if record.get('new_score') is not None:
            if update_record_score(record['id'], record['new_score']):
                updated_count += 1
                print(f"  ✅ ID {record['id']}: {record['sleep_quality_score']} → {record['new_score']}")
    
    print(f"\n✅ 更新完成！共更新 {updated_count} 筆記錄")
    
    # 8. 顯示最終結果
    final_records = get_all_records()
    show_summary(final_records)
    
    print(f"\n💾 備份表: {backup_table}")
    print("📌 如需還原，請執行:")
    print(f"   DROP TABLE sleep_records;")
    print(f"   RENAME TABLE {backup_table} TO sleep_records;")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n👋 已取消")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ 錯誤: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)