import mysql.connector
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib
from datetime import datetime, timedelta
import json
import os
from collections import Counter

# 設定中文字體
matplotlib.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'DejaVu Sans']
matplotlib.rcParams['axes.unicode_minus'] = False

# ==================== 設定 ====================
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "sonnap"
}

# 分數評級標準
SCORE_GRADES = {
    "優秀": (90, 100),
    "良好": (75, 89),
    "普通": (60, 74),
    "需改善": (40, 59),
    "待加強": (0, 39)
}

class SleepAnalyzer:
    def __init__(self):
        self.conn = None
        self.data = None
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
    
    def fetch_all_data(self):
        """讀取所有睡眠記錄"""
        if not self.conn:
            if not self.connect_db():
                return False
        
        try:
            cursor = self.conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT id, report_date, total_events, large_turn_count, 
                       snore_count, sleep_quality_score, timeline, created_at
                FROM sleep_records
                ORDER BY report_date DESC, created_at DESC
            """)
            self.data = cursor.fetchall()
            cursor.close()
            
            print(f"✅ 讀取到 {len(self.data)} 筆記錄")
            return True
            
        except Exception as e:
            print(f"❌ 讀取資料失敗: {e}")
            return False
    
    def load_data_to_dataframe(self):
        """將資料轉換為 DataFrame"""
        if not self.data:
            print("❌ 沒有資料可載入")
            return False
        
        # 轉換為 DataFrame
        self.df = pd.DataFrame(self.data)
        
        # 轉換日期格式
        self.df['report_date'] = pd.to_datetime(self.df['report_date'])
        self.df['created_at'] = pd.to_datetime(self.df['created_at'])
        
        # 按日期排序
        self.df = self.df.sort_values('report_date')
        
        # 計算平均翻身次數
        self.df['avg_turn_per_hour'] = self.df['large_turn_count'] / 8  # 假設8小時睡眠
        
        # 計算睡眠效率 (翻身越少越好)
        max_turns = self.df['large_turn_count'].max() + 1
        self.df['sleep_efficiency'] = (1 - self.df['large_turn_count'] / max_turns) * 100
        
        print(f"✅ 載入 {len(self.df)} 筆資料到 DataFrame")
        return True
    
    def get_basic_stats(self):
        """獲取基本統計"""
        if self.df is None or self.df.empty:
            print("❌ 沒有資料")
            return None
        
        stats = {
            "總記錄數": len(self.df),
            "開始日期": self.df['report_date'].min().strftime("%Y-%m-%d"),
            "結束日期": self.df['report_date'].max().strftime("%Y-%m-%d"),
            "平均睡眠品質分數": round(self.df['sleep_quality_score'].mean(), 1),
            "最高分數": self.df['sleep_quality_score'].max(),
            "最低分數": self.df['sleep_quality_score'].min(),
            "平均翻身次數": round(self.df['large_turn_count'].mean(), 1),
            "最多翻身": self.df['large_turn_count'].max(),
            "最少翻身": self.df['large_turn_count'].min(),
            "平均打呼次數": round(self.df['snore_count'].mean(), 1),
            "平均事件數": round(self.df['total_events'].mean(), 1),
            "總事件數": self.df['total_events'].sum(),
        }
        
        return stats
    
    def get_grade_distribution(self):
        """獲取分數評級分布"""
        if self.df is None or self.df.empty:
            return None
        
        grades = {}
        for grade, (min_score, max_score) in SCORE_GRADES.items():
            count = len(self.df[(self.df['sleep_quality_score'] >= min_score) & 
                               (self.df['sleep_quality_score'] <= max_score)])
            grades[grade] = count
        
        return grades
    
    def get_trend_data(self):
        """獲取趨勢數據"""
        if self.df is None or self.df.empty:
            return None
        
        # 按日期排序
        df_sorted = self.df.sort_values('report_date')
        
        trend = {
            "dates": df_sorted['report_date'].dt.strftime('%m/%d').tolist(),
            "scores": df_sorted['sleep_quality_score'].tolist(),
            "turns": df_sorted['large_turn_count'].tolist(),
            "events": df_sorted['total_events'].tolist(),
            "snore": df_sorted['snore_count'].tolist(),
        }
        
        return trend
    
    def get_best_worst_days(self, n=3):
        """獲取最佳和最差的日子"""
        if self.df is None or self.df.empty:
            return None
        
        best_days = self.df.nlargest(n, 'sleep_quality_score')
        worst_days = self.df.nsmallest(n, 'sleep_quality_score')
        
        return {
            "best": best_days[['report_date', 'sleep_quality_score', 'large_turn_count', 'total_events']].to_dict('records'),
            "worst": worst_days[['report_date', 'sleep_quality_score', 'large_turn_count', 'total_events']].to_dict('records')
        }
    
    def get_weekly_summary(self):
        """獲取週摘要"""
        if self.df is None or self.df.empty:
            return None
        
        # 按週分組
        df_copy = self.df.copy()
        df_copy['week'] = df_copy['report_date'].dt.isocalendar().week
        df_copy['year'] = df_copy['report_date'].dt.year
        df_copy['week_start'] = df_copy['report_date'] - pd.to_timedelta(df_copy['report_date'].dt.weekday, unit='D')
        
        weekly = df_copy.groupby(['year', 'week']).agg({
            'sleep_quality_score': 'mean',
            'large_turn_count': 'mean',
            'total_events': 'mean',
            'report_date': 'count'
        }).round(1)
        
        weekly.columns = ['平均分數', '平均翻身', '平均事件', '天數']
        weekly['週標示'] = weekly.index.map(lambda x: f"{x[0]}-W{x[1]:02d}")
        
        return weekly.reset_index(drop=True)
    
    def analyze_timeline_patterns(self):
        """分析時間軸模式（翻身和打呼的時間分布）"""
        if not self.data:
            return None
        
        all_timelines = []
        for record in self.data:
            if record['timeline']:
                try:
                    timeline = json.loads(record['timeline'])
                    for event in timeline:
                        event['report_date'] = record['report_date']
                        all_timelines.append(event)
                except:
                    continue
        
        if not all_timelines:
            return None
        
        df_timeline = pd.DataFrame(all_timelines)
        
        # 提取小時
        df_timeline['hour'] = df_timeline['time'].str.split(':').str[0].astype(int)
        df_timeline['minute'] = df_timeline['time'].str.split(':').str[1].astype(int)
        
        # 按小時統計
        hourly_motion = df_timeline[df_timeline['motion_level'] != 'none'].groupby('hour').size()
        hourly_snore = df_timeline[df_timeline['sound_level'] == 'snoring_or_noise'].groupby('hour').size()
        
        return {
            "hourly_motion": hourly_motion.to_dict(),
            "hourly_snore": hourly_snore.to_dict(),
            "total_events": len(df_timeline)
        }
    
    def generate_report(self):
        """生成完整分析報告"""
        print("\n" + "="*60)
        print("📊 睡眠記錄分析報告")
        print("="*60)
        print(f"📅 報告生成時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        # 1. 基本統計
        stats = self.get_basic_stats()
        if stats:
            print("\n📈 基本統計:")
            print("-"*40)
            for key, value in stats.items():
                print(f"  {key}: {value}")
        
        # 2. 評級分布
        grades = self.get_grade_distribution()
        if grades:
            print("\n📊 睡眠品質評級分布:")
            print("-"*40)
            for grade, count in grades.items():
                percentage = (count / len(self.df) * 100) if len(self.df) > 0 else 0
                print(f"  {grade}: {count} 天 ({percentage:.1f}%)")
        
        # 3. 最佳/最差
        best_worst = self.get_best_worst_days()
        if best_worst:
            print("\n🌟 最佳睡眠日:")
            print("-"*40)
            for day in best_worst['best']:
                date_str = day['report_date'].strftime('%Y-%m-%d')
                print(f"  {date_str}: 分數 {day['sleep_quality_score']}, 翻身 {day['large_turn_count']} 次")
            
            print("\n💤 最差睡眠日:")
            print("-"*40)
            for day in best_worst['worst']:
                date_str = day['report_date'].strftime('%Y-%m-%d')
                print(f"  {date_str}: 分數 {day['sleep_quality_score']}, 翻身 {day['large_turn_count']} 次")
        
        # 4. 週摘要
        weekly = self.get_weekly_summary()
        if weekly is not None and not weekly.empty:
            print("\n📅 週摘要:")
            print("-"*40)
            print(weekly.to_string(index=False))
        
        # 5. 時間軸分析
        timeline_patterns = self.analyze_timeline_patterns()
        if timeline_patterns:
            print("\n⏰ 事件時間分布:")
            print("-"*40)
            print(f"  總事件數: {timeline_patterns['total_events']}")
            print("  每小時運動分布:")
            for hour, count in sorted(timeline_patterns['hourly_motion'].items()):
                bar = "█" * min(count // 5, 20)
                print(f"    {hour:02d}:00  {bar} ({count})")
    
    def generate_charts(self, output_dir=None):
        """生成圖表"""
        if self.df is None or self.df.empty:
            print("❌ 沒有資料可生成圖表")
            return
        
        if output_dir is None:
            output_dir = os.path.join(os.path.dirname(__file__), "sleep_analysis_charts")
        
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            print(f"📁 建立圖表資料夾: {output_dir}")
        
        plt.style.use('seaborn-v0_8-darkgrid')
        
        # 圖表1: 睡眠品質趨勢
        trend = self.get_trend_data()
        if trend:
            fig, axes = plt.subplots(2, 2, figsize=(14, 10))
            fig.suptitle('📊 睡眠品質分析圖表', fontsize=16, fontweight='bold')
            
            # 1.1 分數趨勢
            ax1 = axes[0, 0]
            ax1.plot(trend['dates'], trend['scores'], 'b-o', linewidth=2, markersize=8)
            ax1.axhline(y=80, color='g', linestyle='--', alpha=0.7, label='良好 (80分)')
            ax1.axhline(y=60, color='y', linestyle='--', alpha=0.7, label='普通 (60分)')
            ax1.axhline(y=40, color='r', linestyle='--', alpha=0.7, label='需改善 (40分)')
            ax1.set_xlabel('日期', fontsize=10)
            ax1.set_ylabel('睡眠品質分數', fontsize=10)
            ax1.set_title('📈 睡眠品質趨勢', fontsize=12)
            ax1.legend(loc='best')
            ax1.tick_params(axis='x', rotation=45)
            
            # 1.2 翻身次數趨勢
            ax2 = axes[0, 1]
            ax2.bar(trend['dates'], trend['turns'], color='orange', alpha=0.7)
            ax2.set_xlabel('日期', fontsize=10)
            ax2.set_ylabel('翻身次數', fontsize=10)
            ax2.set_title('🔄 翻身次數趨勢', fontsize=12)
            ax2.tick_params(axis='x', rotation=45)
            
            # 1.3 分數分布直方圖
            ax3 = axes[1, 0]
            ax3.hist(trend['scores'], bins=10, color='skyblue', edgecolor='black', alpha=0.7)
            ax3.axvline(x=np.mean(trend['scores']), color='r', linestyle='--', 
                       label=f'平均: {np.mean(trend["scores"]):.1f}')
            ax3.set_xlabel('睡眠品質分數', fontsize=10)
            ax3.set_ylabel('天數', fontsize=10)
            ax3.set_title('📊 分數分布', fontsize=12)
            ax3.legend()
            
            # 1.4 分數 vs 翻身次數散佈圖
            ax4 = axes[1, 1]
            ax4.scatter(trend['turns'], trend['scores'], s=100, alpha=0.6, c='green')
            ax4.set_xlabel('翻身次數', fontsize=10)
            ax4.set_ylabel('睡眠品質分數', fontsize=10)
            ax4.set_title('🔄 翻身次數 vs 睡眠品質', fontsize=12)
            
            # 添加趨勢線
            if len(trend['turns']) > 1:
                z = np.polyfit(trend['turns'], trend['scores'], 1)
                p = np.poly1d(z)
                x_line = np.linspace(min(trend['turns']), max(trend['turns']), 100)
                ax4.plot(x_line, p(x_line), 'r--', alpha=0.8, label='趨勢線')
                ax4.legend()
            
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, 'sleep_quality_analysis.png'), dpi=150, bbox_inches='tight')
            plt.close()
            print(f"✅ 圖表已儲存: {os.path.join(output_dir, 'sleep_quality_analysis.png')}")
        
        # 圖表2: 評級分布餅圖
        grades = self.get_grade_distribution()
        if grades:
            fig, ax = plt.subplots(figsize=(8, 6))
            colors = ['#2ecc71', '#f1c40f', '#e67e22', '#e74c3c', '#95a5a6']
            labels = [f"{grade}\n({count}天)" for grade, count in grades.items() if count > 0]
            values = [count for grade, count in grades.items() if count > 0]
            colors = colors[:len(values)]
            
            ax.pie(values, labels=labels, colors=colors, autopct='%1.1f%%', startangle=90)
            ax.set_title('🎯 睡眠品質評級分布', fontsize=14, fontweight='bold')
            
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, 'grade_distribution.png'), dpi=150, bbox_inches='tight')
            plt.close()
            print(f"✅ 評級圖表已儲存: {os.path.join(output_dir, 'grade_distribution.png')}")
        
        # 圖表3: 時間軸分析（如果有的話）
        timeline_patterns = self.analyze_timeline_patterns()
        if timeline_patterns and timeline_patterns['hourly_motion']:
            fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
            fig.suptitle('⏰ 事件時間分布', fontsize=14, fontweight='bold')
            
            # 運動分布
            hours = list(range(24))
            motion_counts = [timeline_patterns['hourly_motion'].get(h, 0) for h in hours]
            snore_counts = [timeline_patterns['hourly_snore'].get(h, 0) for h in hours]
            
            ax1.bar(hours, motion_counts, color='blue', alpha=0.6, label='運動事件')
            ax1.set_xlabel('小時', fontsize=10)
            ax1.set_ylabel('事件數', fontsize=10)
            ax1.set_title('🏃 每小時運動事件', fontsize=12)
            ax1.legend()
            
            ax2.bar(hours, snore_counts, color='red', alpha=0.6, label='打呼事件')
            ax2.set_xlabel('小時', fontsize=10)
            ax2.set_ylabel('事件數', fontsize=10)
            ax2.set_title('😴 每小時打呼事件', fontsize=12)
            ax2.legend()
            
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, 'hourly_events.png'), dpi=150, bbox_inches='tight')
            plt.close()
            print(f"✅ 時間分布圖表已儲存: {os.path.join(output_dir, 'hourly_events.png')}")
    
    def export_to_excel(self, filename=None):
        """匯出到 Excel"""
        if self.df is None or self.df.empty:
            print("❌ 沒有資料可匯出")
            return
        
        if filename is None:
            filename = f"sleep_analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
        
        with pd.ExcelWriter(filename, engine='openpyxl') as writer:
            # 主要資料
            self.df.to_excel(writer, sheet_name='所有記錄', index=False)
            
            # 統計摘要
            stats = self.get_basic_stats()
            if stats:
                pd.DataFrame([stats]).to_excel(writer, sheet_name='統計摘要', index=False)
            
            # 評級分布
            grades = self.get_grade_distribution()
            if grades:
                pd.DataFrame([grades]).to_excel(writer, sheet_name='評級分布', index=False)
            
            # 週摘要
            weekly = self.get_weekly_summary()
            if weekly is not None and not weekly.empty:
                weekly.to_excel(writer, sheet_name='週摘要', index=False)
            
        print(f"✅ 資料已匯出到: {filename}")

def main():
    """主程式"""
    print("="*60)
    print("🌙 睡眠記錄分析系統")
    print("="*60)
    
    analyzer = SleepAnalyzer()
    
    if not analyzer.connect_db():
        return
    
    if not analyzer.fetch_all_data():
        return
    
    if not analyzer.load_data_to_dataframe():
        return
    
    # 生成報告
    analyzer.generate_report()
    
    # 生成圖表
    analyzer.generate_charts()
    
    # 匯出 Excel
    analyzer.export_to_excel()
    
    print("\n" + "="*60)
    print("✅ 分析完成！")
    print("="*60)

if __name__ == "__main__":
    main()