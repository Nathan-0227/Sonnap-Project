// ═══════════════════════════════════════════════════════════════════
// Dart 語法導覽（給第一次讀 Dart 的人）
// ═══════════════════════════════════════════════════════════════════
//
// 這個檔案做的事，用 Python 講就是「把 dict 轉成 dataclass」。
// Dart 寫起來比 Python 囉唆，但換到編譯期的型別檢查。
//
// 五個會一直遇到的語法，先一次講完：
//
//  1. `int?` 的問號 —— **可為 null 的型別**
//     Dart 有 null safety：`int` 保證不是 null，`int?` 才可以是 null。
//     這是編譯器強制的，忘了處理 null 會直接編譯失敗。
//     （Python 沒有這層保護，None 要到執行時才爆。）
//
//  2. `final` —— 建立後不能再改，等於 Python 的唯讀屬性。
//     資料類別全部用 final，兩個理由：
//       (a) payload 讀進來就不該被改——否則會出現「A 頁面改了資料，
//           B 頁面顯示跟著變」這種極難查的 bug
//       (b) `const` 建構子要求所有欄位都是 final（見 5.）
//
//  3. `{...}` 包住的建構子參數 —— **具名參數**
//     呼叫時要寫 `Metrics(motionCount: 5)`，不能寫 `Metrics(5)`。
//     欄位一多，這樣才不會弄錯順序。
//     參數列裡直接寫 `this.motionCount`，Dart 會自動幫你賦值，
//     省掉 `: this.motionCount = motionCount` 那一長串。
//
//  4. `?.` —— **null 安全存取**，編譯器展開成 if：
//         a?.b()  ⇔  (a == null) ? null : a.b()
//     ⚠️ 注意兩個問號是不同的東西：
//        型別上的 `num?` 在**編譯期**作用（宣告「允許 null」）；
//        運算子 `?.` 在**執行期**真的去檢查。
//
//  5. `const` 建構子 —— 參數在編譯期就已知時，物件會在編譯期建好，
//     而且**內容相同的 const 物件共用同一份實體**：
//         identical(const GarminMovement(), const GarminMovement())  // true
//         identical(GarminMovement(), GarminMovement())              // false
//     沒有 const 程式一樣正確，只是每次都重新配置記憶體。
//     在 Flutter 裡它特別值錢：重繪時 Flutter 比對 widget 是否為同一實體，
//     是的話**整個子樹跳過不重建**。
//
// ═══════════════════════════════════════════════════════════════════

import 'wall_clock.dart';

/// Garmin 手錶的動作資料。
///
/// ⚠️ 這**不是** [Metrics.motionCount]（翻身次數）的替代品，兩者測的東西不同。
///    刻意包成獨立類別而不是攤平成四個 `garminMovementXxx` 欄位，
///    是為了讓「這是獨立的一組資料」在型別上就講清楚，
///    而不是讓它們跟 motionCount 並排、看起來可以互相比較。
///
/// 資料來源是 Garmin 的 `sleepMovement.activityLevel`，每分鐘一筆的連續值
/// （實測範圍 0.00–7.64）。
///
/// ⚠️ [sampleMinutes] 就是舊的 `movement_count`。它**不是動作量**——
///    46 晚實測與睡眠時長相關 r = +0.929、與夜間清醒 r = −0.138，
///    且 43/48 天正好等於錄製跨距分鐘數。它測的是時鐘，不是身體。
///    真正的動作訊號是 [levelMean] 與 [activeMinutes]。
class GarminMovement {
  /// 手錶取樣了幾分鐘（≈ 戴了多久）。判斷資料完整性用，不是動作量。
  final int? sampleMinutes;

  /// 整夜 activityLevel 的平均。
  final double? levelMean;

  /// 整夜 activityLevel 的峰值。
  final double? levelMax;

  /// 超過門檻（後端常數 MOVEMENT_ACTIVE_THRESHOLD = 1.0）的分鐘數。
  ///
  /// ⚠️ 那個門檻**不是文獻推導的**，是看資料分布訂的，所以這個數字
  ///    只供呈現，後端也刻意不拿它計分。
  final int? activeMinutes;

  const GarminMovement({
    this.sampleMinutes,
    this.levelMean,
    this.levelMax,
    this.activeMinutes,
  });

  /// 從 JSON 建立物件。
  ///
  /// 參數型別是 `Map<String, dynamic>?`，結尾的 `?` 代表整個 map 可能是 null——
  /// 因為舊版 payload 根本沒有 `garmin_movement` 這個 key。
  ///
  /// 用 `factory` 而不是一般建構子，是因為下面那行**提早回傳現成物件**——
  /// 一般建構子做不到，它一定要產生新實體、也不能中途 return。
  factory GarminMovement.fromJson(Map<String, dynamic>? json) {
    // 整包不存在時回傳「四個欄位都是 null」的物件，而不是回 null。
    // 這樣 UI 寫 `metrics.garminMovement.levelMean` 永遠不會炸，
    // 拿到的就是 null——正好是「這個值我們沒有」的正確語意。
    if (json == null) return const GarminMovement();

    return GarminMovement(
      // 拆解 `(json['x'] as num?)?.toInt()` 這一串：
      //   json['x']   → Map 找不到 key 時回 null（Dart 的 Map 不會丟 KeyError）
      //   as num?     → 執行期轉型。null 過、數字過、字串會💥丟例外。
      //                 只擋 null 不擋型別錯誤——敢這樣寫是因為這份 JSON
      //                 由自家 Python 產生，型別可控。
      //                 先轉 num 是因為 int 與 double 都是 num 的子型別。
      //   ?.toInt()   → null 就整串 null，否則呼叫 toInt()
      sampleMinutes: (json['sample_minutes'] as num?)?.toInt(),
      levelMean: (json['level_mean'] as num?)?.toDouble(),
      levelMax: (json['level_max'] as num?)?.toDouble(),
      activeMinutes: (json['active_minutes'] as num?)?.toInt(),
    );
  }
}

/// 睡眠量測數值 — 對應 data contract 的 `metrics` 區塊。
///
/// ⚠️ 有兩個欄位**故意是 null**，不是 bug：
///
/// - [motionCount]：README 定義它是「翻身次數，由影像組提供」。Garmin 給不出
///   這個東西，不能拿它的動作資料默默對映（那是不同的構念）。
///   TAPO 的 `large_turn_count` 才是語意相符的來源，但目前只有 5 晚且尚未接入。
///   Garmin 自己的動作資料另外放在 [garminMovement]。
///
/// - [ambientNoiseDb]：Garmin 沒有這個感測器。產生現有 TAPO 資料的那版程式
///   分貝是 `np.random` 模擬的。新版雖然真的用 ffmpeg 收音了，但它算的是
///   `20*log10(RMS)`，測的是**數位訊號振幅**而不是空氣中的聲壓：
///   麥克風靈敏度、前級增益、攝影機的自動增益控制（AGC）、擺放距離
///   都會改變這個數字，而房間並沒有變吵。
///   真正的分貝（SPL）以 20 μPa 為參考基準，必須拿分貝計校準才算得出來。
///   → 未校準的值不能跨使用者比較，也不能寫成「環境音 35 分貝」；
///     它只在「同一次錄影、設定不變」時能反映相對變化。
///
/// UI 遇到 null 應顯示「—」或隱藏該欄，**不要顯示 0**——
/// 「沒量到」和「量到是 0」是兩件事。
class Metrics {
  final int? motionCount;

  // 注意這個欄位**沒有問號**：型別是 `GarminMovement` 不是 `GarminMovement?`。
  // 因為 fromJson 保證一定會給一個物件（頂多裡面四個值都是 null），
  // 這樣 UI 就不用每次先檢查外層是不是 null，少一層判斷。
  final GarminMovement garminMovement;

  final int? sleepDurationMinutes;
  final double? ambientNoiseDb;
  final DateTime? sleepStartTime;
  final DateTime? wakeTime;
  final int? deepMinutes;
  final int? remMinutes;
  final int? wasoMinutes;
  final double? sleepEfficiency;
  final double? avgHeartRate;
  final int? restingHeartRate;

  const Metrics({
    this.motionCount,
    // 沒有問號的欄位必須給預設值，否則編譯器會抱怨「這個欄位可能沒被初始化」。
    // 這就是 null safety 在保護你——它不讓你留下未定義的狀態。
    this.garminMovement = const GarminMovement(),
    this.sleepDurationMinutes,
    this.ambientNoiseDb,
    this.sleepStartTime,
    this.wakeTime,
    this.deepMinutes,
    this.remMinutes,
    this.wasoMinutes,
    this.sleepEfficiency,
    this.avgHeartRate,
    this.restingHeartRate,
  });

  /// REM 未測得 — 舊錶（Vivoactive 3）的偵測限制，不代表當晚沒有 REM 睡眠。
  /// 46 晚裡有 11 晚是這種情況，UI 不該顯示成「REM 0 分鐘」。
  ///
  /// `bool get xxx => ...` 是 Dart 的**計算屬性**：外面用起來像欄位
  /// （寫 `metrics.remUnmeasured`，不用加括號），但實際上每次都重算。
  /// 等於 Python 的 @property。
  bool get remUnmeasured => remMinutes == null || remMinutes == 0;

  factory Metrics.fromJson(Map<String, dynamic> json) {
    return Metrics(
      motionCount: (json['motion_count'] as num?)?.toInt(),
      // `as Map<String, dynamic>?` 跟上面的 `as num?` 是同一回事：
      // JSON 解出來是 dynamic，要先宣告「我預期它是這個型別（或 null）」。
      garminMovement: GarminMovement.fromJson(
        json['garmin_movement'] as Map<String, dynamic>?,
      ),
      sleepDurationMinutes: (json['sleep_duration_minutes'] as num?)?.toInt(),
      ambientNoiseDb: (json['ambient_noise_db'] as num?)?.toDouble(),
      sleepStartTime: _parseTime(json['sleep_start_time']),
      wakeTime: _parseTime(json['wake_time']),
      deepMinutes: (json['deep_minutes'] as num?)?.toInt(),
      remMinutes: (json['rem_minutes'] as num?)?.toInt(),
      wasoMinutes: (json['waso_minutes'] as num?)?.toInt(),
      sleepEfficiency: (json['sleep_efficiency'] as num?)?.toDouble(),
      avgHeartRate: (json['avg_heart_rate'] as num?)?.toDouble(),
      restingHeartRate: (json['resting_heart_rate'] as num?)?.toInt(),
    );
  }

  /// 把 ISO8601 字串轉成 DateTime，轉不動就回 null。
  ///
  /// `static` 代表這個方法屬於類別本身、不屬於某個物件，所以它不能存取 this。
  /// 等於 Python 的 @staticmethod。
  ///
  /// 開頭底線 `_parseTime` 是 Dart 的**私有標記**：底線開頭的名稱只有
  /// 同一個檔案看得到，外部 import 不到。Dart 沒有 private 關鍵字，
  /// 就是用底線這個命名慣例——但它是編譯器強制的，不像 Python 的底線只是君子協定。
  static DateTime? _parseTime(dynamic value) {
    // ⚠️ 這裡刻意**不用** DateTime.tryParse。
    //    payload 的時間長這樣：2026-08-22T22:32:00+08:00
    //    tryParse 會把它轉成 UTC，`.hour` 讀出來是 14 不是 22——
    //    畫面上每一個就寢時間都會早 8 小時。理由與作法見 wall_clock.dart。
    //
    // 轉不動回 null；一筆壞資料不該讓整個 App 崩掉。
    return parseWallClock(value);
  }
}
