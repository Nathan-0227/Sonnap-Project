"""
完整的 Garmin + 攝影機數據整合分析系統
"""
import json
import sys
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import seaborn as sns
import os
import warnings
warnings.filterwarnings('ignore')

# 攝影機資料改由 tapo_index 提供（見下方 CameraDataLoader 的說明）。
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import tapo_index

# ==================== 設定 ====================
GARMIN_DATA_DIR = "garmin/data"

# 睡眠品質評級標準。
#
# ⚠️ 2026-08-30 從五級（優秀/良好/普通/需改善/待加強，切點 85/70/55/40）改成
#    四級，與正式評分器對齊（garmin/evaluate_sleep_quality.py 的
#    Good/Normal/Poor/Bad，切點 80/65/50）。
#    改之前同一個 0–100 的數字會被兩套標準講成不同的等級——例如 82 分在
#    正式評分器是 Good、在這裡是「良好」而不是「優秀」，報告裡並排會自相矛盾。
SCORE_GRADES = {
    "Good": (80, 100),
    "Normal": (65, 79),
    "Poor": (50, 64),
    "Bad": (0, 49),
}

# integrated_score 的權重。
#
# ⚠️ **這兩個數字沒有依據**，本專案 Tier1/2 的每一個權重都有文獻
#    （Garmin手錶分數.md 附錄有對照表），這裡是唯一的例外。
#    而且 camera_score 目前是「timeline 有多長」的函數而不是睡眠品質的量度
#    （同一晚跨來源差 80 分，重跑 python inspect_tapo_score.py 表二），
#    所以這個加權平均在攝影機的偵測器修好之前**沒有解讀價值**。
#
#    保留它是為了讓既有的圖表與報告能跑，輸出一律標成 provisional，
#    並且**同時並列** garmin_score 與 camera_score 讓讀者自己看。
GARMIN_WEIGHT = 0.6
CAMERA_WEIGHT = 0.4
WEIGHTS_ARE_PROVISIONAL = True

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
    """
    攝影機數據載入器。

    ⚠️ 2026-08-30 從 MySQL 改成讀 tapo_index。三個理由，每一個單獨都足以擋掉舊寫法：

      ① **那個資料庫不在這台機器上。** 本機 MySQL 只有系統內建的五個 schema，
         沒有 `sonnap`，17 個 binlog 全是 198–221 bytes（只有啟動/關閉事件）
         → 這個 server 從沒被寫過東西。所以整支程式**從來沒有跑過真實資料**。

      ② **合併鍵 `report_date` 會錯。** 實例：sleep_reports/2026-08-04/
         sleep_report_003653.json 的 report_date 寫 08-04，但裡面 106 個
         video_clip 全是 turn_20260803_*。日期錯了就是把 A 晚的攝影機資料
         配上 B 晚的手錶資料，而 how='inner' 會**安靜地**丟掉配不上的列。
         tapo_index 改用 video_clip 檔名定日期。

      ③ dump 檔案（tapo/sleep_records.sql）本來就在 repo 裡，讀檔比要求
         每個人先架好 MySQL 合理。
    """

    def __init__(self):
        self.data = None

    def load_data(self):
        """從 tapo_index 載入攝影機數據，回傳與舊版相同形狀的 DataFrame。"""
        index = tapo_index.get_index()
        if not index:
            print("❌ 找不到攝影機資料（tapo/sleep_records.sql 與 "
                  "tapo/sleep_reports/ 都是空的）")
            return None

        rows = []
        excluded = []
        for night in sorted(index.values(), key=lambda n: n["date"]):
            # ⚠️ 這個過濾不能省。06-12 那筆是 29 秒的白天測試錄影，
            #    而它是**唯一**讓 TAPO 與 Garmin 的六月資料產生重疊的紀錄——
            #    不濾掉就會憑空多出一個橫跨兩個月的「共同樣本」，
            #    整份相關性分析都會被它拉歪。
            problem = tapo_index.sleep_recording_problem(night)
            if problem:
                excluded.append((night["date"], problem))
                continue
            scores = [s for _, s in night["scores"]]
            rows.append({
                "date": datetime.fromisoformat(night["date"]).date(),
                "total_events": night["total_events"],
                "large_turn_count": night["large_turn_count"],
                "snore_count": night["snore_count"],
                # 同一晚有多個來源時取中位數；落差另外用 score_disagreement 呈現，
                # 不藏起來。**這一欄本身不可信**，見檔頭 SCORE_GRADES 的說明。
                "camera_score": int(np.median(scores)) if scores else np.nan,
                "camera_score_disagreement": night["score_disagreement"],
                "camera_first": night["camera_first"],
                "camera_last": night["camera_last"],
            })

        self.data = pd.DataFrame(rows)
        conflicts = int((self.data["camera_score_disagreement"] > 0).sum())
        print(f"✅ 載入攝影機數據: {len(self.data)} 晚"
              f"（依 video_clip 檔名定日期）")
        for date_str, problem in excluded:
            print(f"   ⏭️  排除 {date_str}：{problem}")
        if conflicts:
            worst = int(self.data["camera_score_disagreement"].max())
            print(f"   ⚠️ 其中 {conflicts} 晚的兩個來源對自己的分數就不一致，"
                  f"最大差 {worst} 分")
        return self.data

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
        """
        算出三個分數並排在一起。

        ⚠️ 這裡**不再**有 fallback 自行計算分數的分支。原本有兩支
           （calculate_garmin_score_from_features / calculate_camera_score），
           2026-08-30 刪掉，理由有二：

           ① 它們是死碼。garmin_score 一定走 final_score 那一支（quality_final
              永遠有這欄），camera_score 也一定已經在 SQL 的 SELECT 裡取好別名。
           ② 就算走到了也會當場炸掉——裡面寫 `if eff < 85:`，而 eff 是
              一個 pandas Series，對 Series 取真值會拋
              ValueError: The truth value of a Series is ambiguous。

           換句話說那兩支既跑不到、跑到也會壞。留著只會讓讀的人以為
           「沒有 Garmin 分數時系統會自己算」——那是假的。
        """
        if self.integrated_data is None or self.integrated_data.empty:
            print("❌ 沒有數據")
            return None

        df = self.integrated_data.copy()

        if 'final_score' not in df.columns:
            print("❌ Garmin 資料缺 final_score 欄位。"
                  "先跑 python garmin/run_pipeline.py")
            return None
        df['garmin_score'] = df['final_score']

        if 'camera_score' not in df.columns:
            print("❌ 攝影機資料缺 camera_score 欄位")
            return None

        # ⚠️ 加權平均只是暫定值，權重沒有依據（見檔頭 GARMIN_WEIGHT 的說明）。
        #    真正該看的是並排的兩欄與它們的差，不是這一個合成數字。
        df['integrated_score'] = (
            df['garmin_score'] * GARMIN_WEIGHT +
            df['camera_score'] * CAMERA_WEIGHT
        ).round().astype(int)

        # 逐晚的絕對差。⚠️ 在 camera_score 幾乎恆為 0 的情況下，
        #    這一欄量到的是**尺度差**而不是共識，沒有解讀價值。
        df['score_difference'] = abs(df['garmin_score'] - df['camera_score'])

        self.integrated_data = df
        return df

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
        print(f"  Garmin 平均分數: {report['平均 Garmin 分數']:.1f}   ← 每項有文獻依據")
        print(f"  攝影機平均分數: {report['平均攝影機分數']:.1f}   ← ⚠️ 零文獻依據，"
              f"且量的是 timeline 長度")
        if WEIGHTS_ARE_PROVISIONAL:
            print(f"  整合平均分數: {report['平均整合分數']:.1f}   "
                  f"⚠️ PROVISIONAL（{GARMIN_WEIGHT:.0%}/{CAMERA_WEIGHT:.0%} "
                  f"權重無依據）")
        else:
            print(f"  整合平均分數: {report['平均整合分數']:.1f}")
        print(f"  最高分數: {report['最高整合分數']}")
        print(f"  最低分數: {report['最低整合分數']}")

        # ⚠️ 一致性指標在這個樣本數下跑不了，講清楚比留白好。
        #    Spearman 至少需 8–10 個點、Bland–Altman 建議 30+。
        n = report['資料筆數']
        print(f"\n🔬 一致性分析: n={n}。", end="")
        if n < 8:
            print("樣本不足（Spearman 至少需 8–10 點），不做等級相關。")
        else:
            print("可做 Spearman 等級相關；但 camera_score 若集中在少數值，"
                  "算出來的是尺度差不是共識。")
        print("   ⚠️ 建議報告採「兩個分數並列 + 一致性指標」，"
              "不要只寫加權平均後的單一數字。")
        
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

        # openpyxl 是選用的。缺了就跳過 Excel，不要讓整支程式在**圖表已經
        # 產生之後**才炸掉——那會讓人以為前面的分析也失敗了。
        try:
            import openpyxl  # noqa: F401
        except ImportError:
            print("⏭️  略過 Excel 匯出：沒有安裝 openpyxl"
                  "（pip install openpyxl）。圖表與報告不受影響。")
            return

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