import os
import json
import glob

def check_backup_files():
    """檢查所有可能的備份檔案"""
    
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 檢查 sleep_reports 資料夾
    reports_dir = os.path.join(current_dir, "sleep_reports")
    if os.path.exists(reports_dir):
        print(f"\n📂 找到 sleep_reports 資料夾:")
        json_files = glob.glob(os.path.join(reports_dir, "**/*.json"), recursive=True)
        for f in json_files:
            if not f.endswith('daily_summary.json') and not f.endswith('all_history.json'):
                print(f"  ✅ {os.path.basename(f)}")
    
    # 檢查 backup_reports 資料夾
    backup_dir = os.path.join(current_dir, "backup_reports")
    if os.path.exists(backup_dir):
        print(f"\n📂 找到 backup_reports 資料夾:")
        json_files = glob.glob(os.path.join(backup_dir, "*.json"))
        for f in json_files:
            print(f"  ✅ {os.path.basename(f)}")
    
    # 檢查根目錄的 JSON 檔案
    print(f"\n📂 根目錄的 JSON 檔案:")
    json_files = glob.glob(os.path.join(current_dir, "*.json"))
    for f in json_files:
        print(f"  ✅ {os.path.basename(f)}")

if __name__ == "__main__":
    check_backup_files()
    