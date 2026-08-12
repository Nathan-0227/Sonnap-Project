import mysql.connector
import json
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime
import os

# ==================== 設定 ====================
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "sonnap"
}

# 睡眠品質評分標準
SCORE_GRADES = {
    "優秀": (85, 100),
    "良好": (70, 84),
    "普通": (55, 69),
    "需改善": (40, 54),
    "待加強": (0, 39)
}

class SleepAnalyzer:
    def __init__(self):
        self.conn = None
        self.df = None
        
    def connect_db(self):
        """連線資料庫"""
        try:
            self.conn = mysql.connector.connect(**DB_CONFIG)
            print("✅ 資料庫連線成功")
            return True
        except Exception as e:
            print(f"❌ 資料庫連線失敗: {e}")
            return False
    
    def fetch_and_fix_data(self):
        """讀取並修復資料"""
        if not self.conn:
            if not self.connect_db():
                return False
        
        try:
            cursor = self.conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT id, report_date, total_events, large_turn_count, 
                       snore_count, sleep_quality_score, timeline, created_at
                FROM sleep_records
                ORDER BY report_date
            """)
            data = cursor.fetchall()
            cursor.close()
            
            print(f"✅ 讀取到 {len(data)} 筆記錄")
            
            # 修復資料並重新計算分數
            fixed_count = 0
            for record in data:
                score = self.calculate_sleep_score(record)
                if score != record['sleep_quality_score']:
                    # 更新分數
                    update_cursor = self.conn.cursor()
                    update_cursor.execute(
                        "UPDATE sleep_records SET sleep_quality_score = %s WHERE id = %s",
                        (score, record['id'])
                    )
                    self.conn.commit()
                    update_cursor.close()
                    fixed_count += 1
                    print(f"  🔄 更新 ID {record['id']}: {record['sleep_quality_score']} → {score}")
            
            if fixed_count > 0:
                print(f"✅ 已修復 {fixed_count} 筆記錄的分數")
            
            # 重新讀取資料
            cursor = self.conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT id, report_date, total_events, large_turn_count, 
                       snore_count, sleep_quality_score, timeline, created_at
                FROM sleep_records
                ORDER BY report_date
            """)
            self.data = cursor.fetchall()
            cursor.close()
            
            return True
            
        except Exception as e:
            print(f"❌ 讀取資料失敗: {e}")
            return False
    
    def calculate_sleep_score(self, record):
        """計算睡眠品質分數"""
        total_events = record['total_events'] or 0
        large_turns = record['large_turn_count'] or 0
        snore_count = record['snore_count'] or 0
        
        # 計算翻身頻率 (每小時翻身次數)
        # 假設睡眠時間為 8 小時
        sleep_hours = 8
        turns_per_hour = large_turns / sleep_hours if sleep_hours > 0 else 0
        
        # 基礎分數 100 分
        base_score = 100
        
        # 1. 翻身懲罰 (翻身越少越好)
        # 每小時翻身 0-1 次: 不扣分
        # 每小時翻身 1-2 次: 扣 5-10 分
        # 每小時翻身 2-3 次: 扣 10-20 分
        # 每小時翻身 > 3 次: 扣 20-40 分
        if turns_per_hour <= 1:
            turn_penalty = 0
        elif turns_per_hour <= 2:
            turn_penalty = int((turns_per_hour - 1) * 5) + 5
        elif turns_per_hour <= 3:
            turn_penalty = int((turns_per_hour - 2) * 10) + 10
        else:
            turn_penalty = min(40, int((turns_per_hour - 3) * 15) + 20)
        
        # 2. 打呼懲罰 (打呼越少越好)
        # 打呼次數 0-5: 不扣分
        # 打呼次數 5-15: 扣 5-10 分
        # 打呼次數 15-30: 扣 10-20 分
        # 打呼次數 > 30: 扣 20-30 分
        if snore_count <= 5:
            snore_penalty = 0
        elif snore_count <= 15:
            snore_penalty = int((snore_count - 5) * 0.5) + 5
        elif snore_count <= 30:
            snore_penalty = int((snore_count - 15) * 0.8) + 10
        else:
            snore_penalty = min(30, int((snore_count - 30) * 0.5) + 20)
        
        # 3. 總事件數懲罰 (事件越多可能睡眠越不安穩)
        if total_events <= 50:
            event_penalty = 0
        elif total_events <= 100:
            event_penalty = int((total_events - 50) * 0.2) + 5
        elif total_events <= 200:
            event_penalty = int((total_events - 100) * 0.3) + 10
        else:
            event_penalty = min(20, int((total_events - 200) * 0.1) + 20)
        
        # 計算最終分數
        final_score = base_score - turn_penalty - snore_penalty - event_penalty
        
        # 確保分數在 0-100 之間
        final_score = max(0, min(100, final_score))
        
        return int(final_score)
    
    def load_to_dataframe(self):
        """載入資料到 DataFrame"""
        if not hasattr(self, 'data') or not self.data:
            print("❌ 沒有資料")
            return False
        
        self.df = pd.DataFrame(self.data)
        self.df['report_date'] = pd.to_datetime(self.df['report_date'])
        self.df['created_at'] = pd.to_datetime(self.df['created_at'])
        self.df = self.df.sort_values('report_date')
        
        # 計算每小時翻身次數
        self.df['turns_per_hour'] = self.df['large_turn_count'] / 8
        
        print(f"✅ 載入 {len(self.df)} 筆資料")
        return True
    
    def get_statistics(self):
        """獲取統計數據"""
        if self.df is None or self.df.empty:
            return None
        
        stats = {
            "總記錄數": len(self.df),
            "開始日期": self.df['report_date'].min().strftime('%Y-%m-%d'),
            "結束日期": self.df['report_date'].max().strftime('%Y-%m-%d'),
            "平均睡眠品質": round(self.df['sleep_quality_score'].mean(), 1),
            "最高分數": self.df['sleep_quality_score'].max(),
            "最低分數": self.df['sleep_quality_score'].min(),
            "平均翻身次數": round(self.df['large_turn_count'].mean(), 1),
            "平均每小時翻身": round(self.df['turns_per_hour'].mean(), 2),
            "最多翻身": self.df['large_turn_count'].max(),
            "平均打呼次數": round(self.df['snore_count'].mean(), 1),
            "平均總事件": round(self.df['total_events'].mean(), 1),
            "總事件數": self.df['total_events'].sum()
        }
        return stats
    
    def get_grade_distribution(self):
        """獲取評級分布"""
        if self.df is None or self.df.empty:
            return None
        
        grades = {}
        for grade, (min_score, max_score) in SCORE_GRADES.items():
            count = len(self.df[(self.df['sleep_quality_score'] >= min_score) & 
                               (self.df['sleep_quality_score'] <= max_score)])
            grades[grade] = count
        
        return grades
    
    def generate_report(self):
        """生成報告"""
        print("\n" + "="*70)
        print("📊 睡眠品質分析報告")
        print("="*70)
        
        stats = self.get_statistics()
        if stats:
            print("\n📈 基本統計:")
            print("-"*50)
            for key, value in stats.items():
                print(f"  {key}: {value}")
        
        grades = self.get_grade_distribution()
        if grades:
            print("\n📊 睡眠品質評級分布:")
            print("-"*50)
            for grade, count in grades.items():
                percentage = (count / len(self.df) * 100) if len(self.df) > 0 else 0
                bar = "█" * int(percentage / 2)
                print(f"  {grade}: {count} 天 ({percentage:.1f}%) {bar}")
        
        print("\n📋 詳細記錄:")
        print("-"*70)
        display_cols = ['report_date', 'sleep_quality_score', 'large_turn_count', 
                       'turns_per_hour', 'snore_count', 'total_events']
        print(self.df[display_cols].to_string(index=False))
    
    def generate_charts(self, output_dir=None):
        """生成圖表"""
        if self.df is None or self.df.empty:
            print("❌ 沒有資料")
            return
        
        if output_dir is None:
            output_dir = os.path.join(os.path.dirname(__file__), "sleep_analysis_charts")
        
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            print(f"📁 建立圖表資料夾: {output_dir}")
        
        # 設定中文字體
        plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'DejaVu Sans']
        plt.rcParams['axes.unicode_minus'] = False
        
        df_sorted = self.df.sort_values('report_date')
        dates = df_sorted['report_date'].dt.strftime('%m/%d')
        
        # 圖表 1: 睡眠品質趨勢
        fig, axes = plt.subplots(2, 2, figsize=(14, 10))
        fig.suptitle('📊 睡眠品質分析圖表', fontsize=16, fontweight='bold')
        
        # 1.1 分數趨勢
        ax1 = axes[0, 0]
        ax1.plot(dates, df_sorted['sleep_quality_score'], 'b-o', linewidth=2, markersize=8)
        ax1.axhline(y=85, color='g', linestyle='--', alpha=0.7, label='優秀 (85分)')
        ax1.axhline(y=70, color='y', linestyle='--', alpha=0.7, label='良好 (70分)')
        ax1.axhline(y=55, color='orange', linestyle='--', alpha=0.7, label='普通 (55分)')
        ax1.set_xlabel('日期', fontsize=10)
        ax1.set_ylabel('睡眠品質分數', fontsize=10)
        ax1.set_title('📈 睡眠品質趨勢', fontsize=12)
        ax1.legend(loc='best')
        ax1.tick_params(axis='x', rotation=45)
        ax1.set_ylim(0, 105)
        
        # 1.2 翻身次數趨勢
        ax2 = axes[0, 1]
        ax2.bar(dates, df_sorted['large_turn_count'], color='orange', alpha=0.7)
        ax2.set_xlabel('日期', fontsize=10)
        ax2.set_ylabel('翻身次數', fontsize=10)
        ax2.set_title('🔄 翻身次數趨勢', fontsize=12)
        ax2.tick_params(axis='x', rotation=45)
        
        # 1.3 分數分布
        ax3 = axes[1, 0]
        ax3.hist(df_sorted['sleep_quality_score'], bins=10, color='skyblue', edgecolor='black', alpha=0.7)
        ax3.axvline(x=df_sorted['sleep_quality_score'].mean(), color='r', linestyle='--', 
                   label=f'平均: {df_sorted["sleep_quality_score"].mean():.1f}')
        ax3.set_xlabel('睡眠品質分數', fontsize=10)
        ax3.set_ylabel('天數', fontsize=10)
        ax3.set_title('📊 分數分布', fontsize=12)
        ax3.legend()
        
        # 1.4 翻身 vs 分數
        ax4 = axes[1, 1]
        ax4.scatter(df_sorted['large_turn_count'], df_sorted['sleep_quality_score'], 
                   s=100, alpha=0.6, c='green')
        ax4.set_xlabel('翻身次數', fontsize=10)
        ax4.set_ylabel('睡眠品質分數', fontsize=10)
        ax4.set_title('🔄 翻身次數 vs 睡眠品質', fontsize=12)
        
        # 趨勢線
        if len(df_sorted) > 1:
            z = np.polyfit(df_sorted['large_turn_count'], df_sorted['sleep_quality_score'], 1)
            p = np.poly1d(z)
            x_line = np.linspace(df_sorted['large_turn_count'].min(), 
                               df_sorted['large_turn_count'].max(), 100)
            ax4.plot(x_line, p(x_line), 'r--', alpha=0.8, label='趨勢線')
            ax4.legend()
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, 'sleep_quality_analysis.png'), dpi=150, bbox_inches='tight')
        plt.close()
        print(f"✅ 圖表已儲存: {os.path.join(output_dir, 'sleep_quality_analysis.png')}")
        
        # 圖表 2: 評級分布
        grades = self.get_grade_distribution()
        if grades:
            fig, ax = plt.subplots(figsize=(8, 6))
            colors = ['#2ecc71', '#3498db', '#f1c40f', '#e67e22', '#e74c3c']
            labels = [f"{grade}\n({count}天)" for grade, count in grades.items() if count > 0]
            values = [count for grade, count in grades.items() if count > 0]
            
            ax.pie(values, labels=labels, colors=colors[:len(values)], autopct='%1.1f%%', startangle=90)
            ax.set_title('🎯 睡眠品質評級分布', fontsize=14, fontweight='bold')
            
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, 'grade_distribution.png'), dpi=150, bbox_inches='tight')
            plt.close()
            print(f"✅ 評級圖已儲存: {os.path.join(output_dir, 'grade_distribution.png')}")
    
    def export_excel(self, filename=None):
        """匯出 Excel"""
        if self.df is None or self.df.empty:
            print("❌ 沒有資料")
            return
        
        if filename is None:
            filename = f"sleep_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
        
        with pd.ExcelWriter(filename, engine='openpyxl') as writer:
            self.df.to_excel(writer, sheet_name='所有記錄', index=False)
            
            stats = self.get_statistics()
            if stats:
                pd.DataFrame([stats]).to_excel(writer, sheet_name='統計摘要', index=False)
            
            grades = self.get_grade_distribution()
            if grades:
                pd.DataFrame([grades]).to_excel(writer, sheet_name='評級分布', index=False)
        
        print(f"✅ 已匯出: {filename}")

def main():
    print("="*70)
    print("🌙 睡眠記錄分析系統")
    print("="*70)
    
    analyzer = SleepAnalyzer()
    
    if not analyzer.connect_db():
        return
    
    if not analyzer.fetch_and_fix_data():
        return
    
    if not analyzer.load_to_dataframe():
        return
    
    analyzer.generate_report()
    analyzer.generate_charts()
    analyzer.export_excel()
    
    print("\n" + "="*70)
    print("✅ 分析完成！")
    print("="*70)

if __name__ == "__main__":
    main()