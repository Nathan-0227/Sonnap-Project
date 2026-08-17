"""
完整的 Garmin + 攝影機數據整合分析系統
"""
import json
import pandas as pd
import numpy as np
import mysql.connector
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import seaborn as sns
import os
import warnings
warnings.filterwarnings('ignore')

# ==================== 設定 ====================
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "sonnap"
}

GARMIN_DATA_DIR = "garmin/data"

# 睡眠品質評級標準
SCORE_GRADES = {
    "優秀": (85, 100),
    "良好": (70, 84),
    "普通": (55, 69),
    "需改善": (40, 54),
    "待加強": (0, 39)
}

class GarminDataLoader:
    """Garmin 數據載入器"""
    
    def __init__(self, data_dir=GARMIN_DATA_DIR):
        self.data_dir = data_dir
        self.raw_data = {}
        self.merged_data = None
        
    def load_all_data(self):
        """載入所有 Garmin 數據"""
        files = {
            'quality_final': 'garmin_sleep_quality_final.json',
            'quality': 'garmin_sleep_quality.json',
            'summary': 'garmin_sleep_summary.json'
        }
        
        for key, filename in files.items():
            filepath = os.path.join(self.data_dir, filename)
            if os.path.exists(filepath):
                with open(filepath, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        self.raw_data[key] = pd.DataFrame(data)
                        print(f"✅ 載入 {key}: {len(self.raw_data[key])} 筆")
                    else:
                        print(f"⚠️ {key} 格式不是列表")
        
        return self.raw_data
    
    def merge_garmin_data(self):
        """合併所有 Garmin 數據"""
        if not self.raw_data:
            print("❌ 沒有數據可合併")
            return None
        
        # 從 quality_final 開始
        if 'quality_final' in self.raw_data:
            merged = self.raw_data['quality_final'].copy()
        elif 'quality' in self.raw_data:
            merged = self.raw_data['quality'].copy()
        else:
            merged = self.raw_data['summary'].copy()
        
        # 確保日期欄位存在
        if 'date' not in merged.columns:
            if 'sleep_date' in merged.columns:
                merged.rename(columns={'sleep_date': 'date'}, inplace=True)
            elif 'report_date' in merged.columns:
                merged.rename(columns={'report_date': 'date'}, inplace=True)
        
        merged['date'] = pd.to_datetime(merged['date']).dt.date
        
        # 合併其他數據
        for key in ['quality', 'summary']:
            if key in self.raw_data and key != 'quality_final':
                df = self.raw_data[key].copy()
                if 'date' in df.columns:
                    df['date'] = pd.to_datetime(df['date']).dt.date
                    # 找出共同的欄位進行合併
                    common_cols = ['date'] + [col for col in df.columns if col in merged.columns and col != 'date']
                    if len(common_cols) > 1:
                        merged = pd.merge(merged, df[common_cols], on='date', how='left', suffixes=('', '_dup'))
        
        self.merged_data = merged
        print(f"✅ 合併完成: {len(merged)} 筆")
        return self.merged_data

class CameraDataLoader:
    """攝影機數據載入器"""
    
    def __init__(self):
        self.conn = None
        self.data = None
        
    def connect_db(self):
        """連線資料庫"""
        try:
            self.conn = mysql.connector.connect(**DB_CONFIG)
            print("✅ 資料庫連線成功")
            return True
        except Exception as e:
            print(f"❌ 資料庫連線失敗: {e}")
            return False
    
    def load_data(self):
        """載入攝影機數據"""
        if not self.conn:
            if not self.connect_db():
                return None
        
        query = """
            SELECT 
                report_date as date,
                total_events,
                large_turn_count,
                snore_count,
                sleep_quality_score as camera_score,
                timeline,
                created_at
            FROM sleep_records
            ORDER BY report_date
        """
        
        try:
            self.data = pd.read_sql(query, self.conn)
            self.data['date'] = pd.to_datetime(self.data['date']).dt.date
            print(f"✅ 載入攝影機數據: {len(self.data)} 筆")
            return self.data
        except Exception as e:
            print(f"❌ 載入失敗: {e}")
            return None

class SleepDataIntegrator:
    """睡眠數據整合器"""
    
    def __init__(self):
        self.garmin_loader = GarminDataLoader()
        self.camera_loader = CameraDataLoader()
        self.integrated_data = None
        
    def load_all_data(self):
        """載入所有數據"""
        print("📂 載入 Garmin 數據...")
        self.garmin_loader.load_all_data()
        self.garmin_loader.merge_garmin_data()
        
        print("\n📂 載入攝影機數據...")
        self.camera_loader.load_data()
        
        return True
    
    def integrate_data(self):
        """整合數據"""
        garmin_df = self.garmin_loader.merged_data
        camera_df = self.camera_loader.data
        
        if garmin_df is None or camera_df is None:
            print("❌ 缺少數據")
            return None
        
        print(f"\n🔄 整合數據...")
        print(f"  Garmin: {len(garmin_df)} 筆")
        print(f"  攝影機: {len(camera_df)} 筆")
        
        # 合併數據
        self.integrated_data = pd.merge(
            camera_df,
            garmin_df,
            on='date',
            how='inner',
            suffixes=('_camera', '_garmin')
        )
        
        print(f"✅ 整合完成: {len(self.integrated_data)} 筆")
        return self.integrated_data
    
    def calculate_sleep_scores(self):
        """計算睡眠分數"""
        if self.integrated_data is None or self.integrated_data.empty:
            print("❌ 沒有數據")
            return None
        
        df = self.integrated_data.copy()
        
        # 1. Garmin 基礎分數
        if 'final_score' in df.columns:
            df['garmin_score'] = df['final_score']
        elif 'sleep_quality_score' in df.columns:
            df['garmin_score'] = df['sleep_quality_score']
        else:
            # 如果沒有 Garmin 分數，從睡眠數據計算
            df['garmin_score'] = self.calculate_garmin_score_from_features(df)
        
        # 2. 攝影機分數
        if 'camera_score' in df.columns:
            df['camera_score'] = df['camera_score']
        else:
            df['camera_score'] = self.calculate_camera_score(df)
        
        # 3. 整合分數 (Garmin 60% + 攝影機 40%)
        df['integrated_score'] = (
            df['garmin_score'] * 0.6 + 
            df['camera_score'] * 0.4
        ).round().astype(int)
        
        # 4. 分數一致性
        df['score_difference'] = abs(df['garmin_score'] - df['camera_score'])
        
        self.integrated_data = df
        return df
    
    def calculate_garmin_score_from_features(self, df):
        """從 Garmin 特徵計算分數"""
        score = 100
        
        # 睡眠效率
        if 'sleep_efficiency' in df.columns:
            eff = df['sleep_efficiency']
            if eff < 85:
                score -= (85 - eff) * 0.5
        
        # 睡眠時間
        if 'sleep_duration_hours' in df.columns:
            hours = df['sleep_duration_hours']
            if hours < 6:
                score -= (6 - hours) * 5
            elif hours > 11:
                score -= (hours - 11) * 3
        
        # 深層睡眠
        if 'deep_ratio' in df.columns:
            deep = df['deep_ratio']
            if deep < 0.1:
                score -= (0.1 - deep) * 50
        
        # 壓力
        if 'avg_stress_score' in df.columns:
            stress = df['avg_stress_score']
            if stress > 20:
                score -= min(20, (stress - 20) * 0.8)
        
        return np.clip(score, 0, 100).round().astype(int)
    
    def calculate_camera_score(self, df):
        """計算攝影機分數"""
        score = 100
        
        # 翻身懲罰
        if 'large_turn_count' in df.columns:
            turns = df['large_turn_count']
            if turns > 20:
                score -= (turns - 20) * 0.5
        
        # 總事件懲罰
        if 'total_events' in df.columns:
            events = df['total_events']
            if events > 50:
                score -= min(20, (events - 50) * 0.2)
        
        # 打呼懲罰
        if 'snore_count' in df.columns:
            snore = df['snore_count']
            if snore > 10:
                score -= min(15, (snore - 10) * 0.5)
        
        return np.clip(score, 0, 100).round().astype(int)
    
    def get_correlation_analysis(self):
        """獲取相關性分析"""
        if self.integrated_data is None:
            return None
        
        # 選擇數值欄位進行相關性分析
        numeric_cols = ['garmin_score', 'camera_score', 'integrated_score',
                       'total_events', 'large_turn_count', 'snore_count',
                       'sleep_duration_hours', 'sleep_efficiency', 
                       'deep_ratio', 'avg_heart_rate', 'avg_stress_score']
        
        existing_cols = [col for col in numeric_cols if col in self.integrated_data.columns]
        
        if existing_cols:
            correlation = self.integrated_data[existing_cols].corr()
            return correlation
        return None

class ReportGenerator:
    """報告生成器"""
    
    def __init__(self, integrated_data):
        self.data = integrated_data
        
    def generate_summary_report(self):
        """生成摘要報告"""
        if self.data is None or self.data.empty:
            return None
        
        df = self.data
        report = {
            "生成時間": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "資料筆數": len(df),
            "日期範圍": f"{df['date'].min()} ~ {df['date'].max()}",
            "平均 Garmin 分數": df['garmin_score'].mean(),
            "平均攝影機分數": df['camera_score'].mean(),
            "平均整合分數": df['integrated_score'].mean(),
            "最高整合分數": df['integrated_score'].max(),
            "最低整合分數": df['integrated_score'].min(),
            "平均翻身次數": df['large_turn_count'].mean() if 'large_turn_count' in df else None,
            "平均睡眠時間": df['sleep_duration_hours'].mean() if 'sleep_duration_hours' in df else None,
            "平均睡眠效率": df['sleep_efficiency'].mean() if 'sleep_efficiency' in df else None,
        }
        return report
    
    def print_report(self):
        """列印報告"""
        report = self.generate_summary_report()
        if not report:
            return
        
        print("\n" + "="*70)
        print("📊 整合式睡眠分析報告 (Garmin + 攝影機)")
        print("="*70)
        print(f"📅 報告生成: {report['生成時間']}")
        print(f"📈 資料筆數: {report['資料筆數']}")
        print(f"📆 日期範圍: {report['日期範圍']}")
        print("-"*70)
        print("📊 分數統計:")
        print(f"  Garmin 平均分數: {report['平均 Garmin 分數']:.1f}")
        print(f"  攝影機平均分數: {report['平均攝影機分數']:.1f}")
        print(f"  整合平均分數: {report['平均整合分數']:.1f}")
        print(f"  最高分數: {report['最高整合分數']}")
        print(f"  最低分數: {report['最低整合分數']}")
        
        if report['平均翻身次數'] is not None:
            print(f"\n🔄 平均翻身次數: {report['平均翻身次數']:.1f}")
        if report['平均睡眠時間'] is not None:
            print(f"⏰ 平均睡眠時間: {report['平均睡眠時間']:.1f} 小時")
        if report['平均睡眠效率'] is not None:
            print(f"💤 平均睡眠效率: {report['平均睡眠效率']:.1f}%")
        
        # 顯示最近 5 筆
        print("\n📋 最近 5 筆記錄:")
        print("-"*70)
        cols = ['date', 'garmin_score', 'camera_score', 'integrated_score', 'large_turn_count']
        available_cols = [col for col in cols if col in self.data.columns]
        if available_cols:
            print(self.data[available_cols].tail(5).to_string(index=False))
    
    def generate_charts(self, output_dir=None):
        """生成圖表"""
        if self.data is None or self.data.empty:
            return
        
        if output_dir is None:
            output_dir = "garmin_camera_analysis"
        
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        # 設定中文字體
        plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'DejaVu Sans']
        plt.rcParams['axes.unicode_minus'] = False
        
        df = self.data.sort_values('date')
        dates = df['date'].astype(str)
        
        fig, axes = plt.subplots(2, 3, figsize=(16, 10))
        fig.suptitle('📊 Garmin + 攝影機 整合睡眠分析', fontsize=16, fontweight='bold')
        
        # 1. 分數趨勢
        ax1 = axes[0, 0]
        ax1.plot(dates, df['garmin_score'], 'g-o', label='Garmin', linewidth=2)
        ax1.plot(dates, df['camera_score'], 'b-s', label='攝影機', linewidth=2)
        ax1.plot(dates, df['integrated_score'], 'r-^', label='整合', linewidth=2)
        ax1.set_xlabel('日期')
        ax1.set_ylabel('分數')
        ax1.set_title('📈 睡眠分數趨勢')
        ax1.legend()
        ax1.tick_params(axis='x', rotation=45)
        ax1.set_ylim(0, 105)
        
        # 2. 分數差異
        ax2 = axes[0, 1]
        ax2.bar(dates, df['score_difference'], color='orange', alpha=0.7)
        ax2.axhline(y=df['score_difference'].mean(), color='r', linestyle='--',
                   label=f'平均: {df["score_difference"].mean():.1f}')
        ax2.set_xlabel('日期')
        ax2.set_ylabel('分數差異')
        ax2.set_title('🔍 Garmin vs 攝影機 分數差異')
        ax2.legend()
        ax2.tick_params(axis='x', rotation=45)
        
        # 3. 翻身 vs 分數
        ax3 = axes[0, 2]
        if 'large_turn_count' in df.columns:
            ax3.scatter(df['large_turn_count'], df['integrated_score'], 
                       s=100, alpha=0.6, c='green')
            ax3.set_xlabel('翻身次數')
            ax3.set_ylabel('整合分數')
            ax3.set_title('🔄 翻身次數 vs 睡眠品質')
        
        # 4. 分數分布
        ax4 = axes[1, 0]
        ax4.hist([df['garmin_score'], df['camera_score'], df['integrated_score']],
                bins=10, alpha=0.5, label=['Garmin', '攝影機', '整合'])
        ax4.set_xlabel('分數')
        ax4.set_ylabel('天數')
        ax4.set_title('📊 分數分布')
        ax4.legend()
        
        # 5. 睡眠時間 vs 分數
        ax5 = axes[1, 1]
        if 'sleep_duration_hours' in df.columns:
            ax5.scatter(df['sleep_duration_hours'], df['integrated_score'],
                       s=100, alpha=0.6, c='purple')
            ax5.set_xlabel('睡眠時間 (小時)')
            ax5.set_ylabel('整合分數')
            ax5.set_title('⏰ 睡眠時間 vs 睡眠品質')
            ax5.axvline(x=7, color='g', linestyle='--', label='建議下限 7h')
            ax5.axvline(x=9, color='g', linestyle='--', label='建議上限 9h')
            ax5.legend()
        
        # 6. 睡眠效率 vs 分數
        ax6 = axes[1, 2]
        if 'sleep_efficiency' in df.columns:
            ax6.scatter(df['sleep_efficiency'], df['integrated_score'],
                       s=100, alpha=0.6, c='teal')
            ax6.set_xlabel('睡眠效率 (%)')
            ax6.set_ylabel('整合分數')
            ax6.set_title('💤 睡眠效率 vs 睡眠品質')
            ax6.axvline(x=85, color='r', linestyle='--', label='良好門檻 85%')
            ax6.legend()
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, 'garmin_camera_integrated_analysis.png'), dpi=150)
        plt.close()
        print(f"✅ 圖表已儲存: {output_dir}/garmin_camera_integrated_analysis.png")
    
    def export_excel(self, filename=None):
        """匯出 Excel"""
        if self.data is None or self.data.empty:
            return
        
        if filename is None:
            filename = f"garmin_camera_integrated_{datetime.now().strftime('%Y%m%d')}.xlsx"
        
        with pd.ExcelWriter(filename, engine='openpyxl') as writer:
            self.data.to_excel(writer, sheet_name='整合數據', index=False)
            
            # 統計摘要
            report = self.generate_summary_report()
            if report:
                pd.DataFrame([report]).to_excel(writer, sheet_name='統計摘要', index=False)
            
            # 相關性分析
            numeric_cols = self.data.select_dtypes(include=[np.number]).columns
            if len(numeric_cols) > 1:
                self.data[numeric_cols].corr().to_excel(writer, sheet_name='相關性')
        
        print(f"✅ Excel 已匯出: {filename}")

def main():
    """主程式"""
    print("="*70)
    print("🌙 Garmin + 攝影機 整合睡眠分析系統")
    print("="*70)
    
    # 1. 載入數據
    integrator = SleepDataIntegrator()
    integrator.load_all_data()
    
    # 2. 整合數據
    integrated_data = integrator.integrate_data()
    
    if integrated_data is None or integrated_data.empty:
        print("❌ 沒有數據可分析")
        return
    
    # 3. 計算分數
    integrator.calculate_sleep_scores()
    
    # 4. 顯示整合數據
    print(f"\n📊 整合數據 ({len(integrator.integrated_data)} 筆):")
    print(integrator.integrated_data.head().to_string())
    
    # 5. 相關性分析
    correlation = integrator.get_correlation_analysis()
    if correlation is not None:
        print("\n📊 相關性分析:")
        print(correlation)
    
    # 6. 生成報告
    report_gen = ReportGenerator(integrator.integrated_data)
    report_gen.print_report()
    
    # 7. 生成圖表
    report_gen.generate_charts()
    
    # 8. 匯出 Excel
    report_gen.export_excel()
    
    print("\n" + "="*70)
    print("✅ 分析完成！")
    print("="*70)

if __name__ == "__main__":
    main()