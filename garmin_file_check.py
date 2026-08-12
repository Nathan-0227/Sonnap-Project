# 檢查 Garmin 數據的內容
import json
import pandas as pd
import os

def explore_garmin_data():
    """探索 Garmin 數據的結構"""
    
    # 檢查各種 JSON 檔案
    garmin_files = [
        "garmin_sleep_features.json",
        "garmin_sleep_quality.json",
        "garmin_sleep_summary.json",
        "garmin_standard_data.json"
    ]
    
    for filename in garmin_files:
        filepath = os.path.join("garmin", "data", filename)
        if os.path.exists(filepath):
            print(f"\n📄 {filename}:")
            print("-"*40)
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        print(f"  筆數: {len(data)}")
                        if data:
                            print(f"  欄位: {list(data[0].keys())[:10]}...")
                            print(f"  範例: {data[0]}")
                    else:
                        print(f"  內容: {list(data.keys()) if isinstance(data, dict) else '非字典格式'}")
            except Exception as e:
                print(f"  ❌ 讀取失敗: {e}")
        else:
            print(f"❌ 檔案不存在: {filepath}")

# 執行探索
explore_garmin_data()
