import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/night_curve.dart';
import '../models/yesterday_activity.dart';
import '../models/sleep_session.dart';
import '../models/sleep_stages.dart';
import '../models/wall_clock.dart';
import 'bed_marks.dart';
import 'camera_insights.dart';
import 'game_service.dart';
import 'morning_rating.dart';
import 'pet_notes.dart';
import 'user_identity.dart';

/// 早晨報告（2026-11-12 定案，版面 11-13 依示意圖重做）：滑完 Slide to get up
/// 並填完（或跳過）起床自評之後出現，或從首頁一週心情列點某一天打開。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 報告上每個「好不好」的東西都照抄後端
/// ═══════════════════════════════════════════════════════════════════
///
/// 分數、等級、心情、那句話（`display.mood_description`）一律來自 `/home?date=`；
/// 連不到後端時退回打包檔裡那一晚的 history。**Dart 一個都不推**——
/// 心情要是從 [finalQuality] 推，Good 但 anxious 的夜晚就會畫錯寵物。
///
/// ⚠️ **沒有分數時不顯示睡眠長度也不顯示分數**，只寫
/// [kWaitingForWatch]。剛起床時手錶資料幾乎一定還沒到，
/// 那時畫 0 或畫上一晚的數字都是編造。
///
/// ⚠️ 心情只在有分數時才用（使用者定：還在等資料時畫睡姿小狗）。
///
/// ⚠️ 寵物 notes（AI 總結＋建議，2026-11-17 起取代夢境日記與「From your buddy」）
///    來自 `/night-summary`，**照抄**（見 services/pet_notes.dart）。Dart 不挑也不改字。
const String kWaitingForWatch = 'Waiting for your watch data';

/// 不是剛結束的那一晚、又沒有分數時的說法。
const String kNoWatchData = 'No watch data for this night yet';

/// 資料從哪來。畫面上會照實標出來。
enum ReportSource {
  /// 後端 `/home?date=`
  backend,

  /// 連不到後端，用的是打包在 App 裡的那一晚
  bundled,

  /// 只有手機上的上床／下床時間
  phoneOnly,
}

/// 跟上一晚比的方向。**只代表方向**：上升紅、下降綠（台灣股市慣例，使用者定），
/// 不代表好壞——睡得多不一定好。
enum ChangeDirection { up, down, same }

/// [now] 與 [before] 都有才比；差不到 1 分鐘算 same。
ChangeDirection? changeOf(double? now, double? before) {
  if (now == null || before == null) return null;
  final d = (now - before).round();
  if (d == 0) return ChangeDirection.same;
  return d > 0 ? ChangeDirection.up : ChangeDirection.down;
}

@immutable
class MorningReport {
  /// 那一晚的日期（起床日，與後端 night_date 同一個約定），YYYY-MM-DD。
  final String date;

  /// 上床／下床（按鈕）。沒按就是 null。
  final DateTime? bedStart;
  final DateTime? bedEnd;

  /// 臥床時間。後端給的優先（behavior.time_in_bed_minutes），
  /// 沒有後端時用兩個按鈕相減——那只是兩個時刻的差，不是判斷。
  final double? timeInBedMinutes;

  /// 手錶認定的入睡／起床。
  final DateTime? asleepAt;
  final DateTime? wokeAt;

  final double? score;
  final String? quality;

  /// 後端給的等級顏色（#RRGGBB）。打包檔的舊夜晚沒有，畫面用預設色。
  final String? qualityColor;

  /// 後端的那句話（`display.score_message`，例：Great job!）。
  final String? scoreMessage;

  /// 後端的心情與那句心情說明（`display.mood_description`）。
  final String? mood;
  final String? moodDescription;

  /// 手錶量到的睡眠（分鐘）與三個階段。淺睡只有量到 REM 時才有（後端定）。
  final double? sleepMinutes;
  final double? lightMinutes;
  final double? deepMinutes;
  final double? remMinutes;
  final bool remMeasured;

  /// Sleep phases 圖。後端每一晚都給（只有 Garmin 來源才有）；
  /// 沒有後端時只有打包檔最新那一晚有。
  final SleepStages? stages;


  /// 前一個日曆日的 Garmin 白天資料（`/home` 的 `yesterday`，2026-11-13）。只呈現、不計分；
  /// 沒有後端或那天沒資料是 null，報告整塊不畫。
  final YesterdayActivity? yesterday;

  /// 睡著期間的心率與手錶動作曲線（`metrics.heart_rate_curve`／`movement_curve`，2026-11-13）。
  /// Sleep Stages 卡點 Heart rate／Movement 疊上去。只有 Garmin 來源、有分數時才有。
  final NightCurve? heartRate;
  final NightCurve? movement;

  /// 攝影機看到的動作（`metrics.camera_curve`）。有錄影、有床鋪範圍的晚上才有。
  final NightCurve? cameraMotion;

  final ReportSource source;

  // ── 跟上一晚比：後端給上一個有資料的晚上的原始數字 ──
  final double? previousTimeInBed;
  final double? previousSleepMinutes;

  // ── 放下手機 vs 目標（照抄後端） ──
  final DateTime? lightsOutAt;

  /// 「HH:MM」。
  final String? targetBedtime;

  /// 後端算的「比目標晚幾分鐘」。⚠️ 只照抄，不在 Dart 重算（跨午夜那條紀律）。
  final double? adherenceMinutes;

  /// 按 Start Sleep 之後到放下手機隔了多久（後端 `phone_in_bed_minutes`＝lights_out − bed_start，下界）。
  /// ⚠️ 只照抄；沒按 Start Sleep 是 null（不是 0）。滑到睡著的晚上會偏大（螢幕自動鎖才算放下）。
  final double? phoneAfterStartMinutes;

  /// 起床自評。後端的優先；沒有後端時用手機上存的。
  final MorningRating? rating;

  /// 自評那一行的字。後端給的 label 優先（照抄），否則用 [kRestedLabels]。
  final String? ratingLabel;

  // ── More details（照抄後端） ──
  final double? wasoMinutes;

  /// 半夜醒了幾段（手錶，照抄後端；只有 Garmin 來源有，0 是真的值）。
  final int? awakeCount;
  final double? avgHeartRate;
  final double? restingHeartRate;

  /// **進分數的那一個**效率（三段式，依 composition.efficiency_basis 挑）。
  final double? efficiency;
  final String? efficiencyBasis;

  /// 那一種給人看的名字（後端 composition.efficiency_label，字只在 score_claim.py）。
  final String? efficiencyLabel;

  /// 三種裡的哪一種（決定分母畫哪兩個時刻、長條實心或空心）。
  final EfficiencyKind? efficiencyKind;

  /// 效率那條警語（composition.caveats），照抄。
  final String? efficiencyCaveat;

  /// 攝影機那一晚。只顯示後端寫好的「跟你平常比」那句（不計分）。
  final CameraNight? camera;

  /// 寵物 notes（/night-summary）。null＝沒有內容或還沒拿到，日記本不出現。
  final PetNotes? notes;

  // ── 等級與這一晚的 XP：全部照抄後端 /game ──
  /// null = 沒有後端或讀不到 /game，整塊不畫。
  final int? level;
  final int? xpIntoLevel;

  /// 這一級總共要幾 XP（= 已走的 + 還差的）。最高級時是 null。
  final int? xpLevelSize;
  final double? xpProgress;

  /// 這一晚拿到幾 XP。null = 後端還沒有這一晚（例如還沒上傳），不畫 +N。
  final int? nightXp;

  /// 真時：手錶那部分還沒算進來，畫成「+N XP so far」。
  final bool nightXpSoFar;

  /// 最近幾晚各拿幾 XP（照抄 /game 的 recent_nights，由舊到新），經驗條上一晚畫一格。
  final List<NightXp> recentNightXp;

  /// 睡眠目標（分鐘）＝轉盤上「就寢→起床」的長度。只拿來寫事實，不判斷達標。
  final int? goalMinutes;

  const MorningReport({
    required this.date,
    this.bedStart,
    this.bedEnd,
    this.timeInBedMinutes,
    this.asleepAt,
    this.wokeAt,
    this.score,
    this.quality,
    this.qualityColor,
    this.scoreMessage,
    this.mood,
    this.moodDescription,
    this.sleepMinutes,
    this.lightMinutes,
    this.deepMinutes,
    this.remMinutes,
    this.remMeasured = false,
    this.stages,
    this.yesterday,
    this.heartRate,
    this.movement,
    this.cameraMotion,
    this.source = ReportSource.phoneOnly,
    this.previousTimeInBed,
    this.previousSleepMinutes,
    this.lightsOutAt,
    this.targetBedtime,
    this.adherenceMinutes,
    this.phoneAfterStartMinutes,
    this.rating,
    this.ratingLabel,
    this.wasoMinutes,
    this.awakeCount,
    this.avgHeartRate,
    this.restingHeartRate,
    this.efficiency,
    this.efficiencyBasis,
    this.efficiencyLabel,
    this.efficiencyKind,
    this.efficiencyCaveat,
    this.camera,
    this.notes,
    this.level,
    this.xpIntoLevel,
    this.xpLevelSize,
    this.xpProgress,
    this.nightXp,
    this.nightXpSoFar = false,
    this.recentNightXp = const [],
    this.goalMinutes,
  });

  /// 起床時間：有按 Out of bed 用按鈕，沒按用手錶的。都沒有就是 null。
  DateTime? get wakeAt => bedEnd ?? (hasScore ? wokeAt : null);

  /// 有分數才算「手錶資料到了」。
  bool get hasScore => score != null;

  /// 比例條要三個都有（淺睡由後端決定給不給）。
  bool get hasStageSplit =>
      lightMinutes != null && deepMinutes != null && remMinutes != null;

  /// More details 裡有沒有任何一項。
  bool get hasDetails =>
      (hasScore &&
          (wasoMinutes != null ||
              (heartRate == null &&
                  (avgHeartRate != null || restingHeartRate != null)) ||
              efficiency != null)) ||
      camera?.usualLabel != null;

  /// 所有「之後才接上來的」東西都走這一支，免得新欄位在某一條路徑上被漏掉。
  MorningReport _copy({
    MorningRating? rating,
    String? ratingLabel,
    CameraNight? camera,
    PetNotes? notes,
    int? level,
    int? xpIntoLevel,
    int? xpLevelSize,
    double? xpProgress,
    int? nightXp,
    bool? nightXpSoFar,
    List<NightXp>? recentNightXp,
    int? goalMinutes,
    bool replaceGame = false,
  }) {
    return MorningReport(
      date: date,
      bedStart: bedStart,
      bedEnd: bedEnd,
      timeInBedMinutes: timeInBedMinutes,
      asleepAt: asleepAt,
      wokeAt: wokeAt,
      score: score,
      quality: quality,
      qualityColor: qualityColor,
      scoreMessage: scoreMessage,
      mood: mood,
      moodDescription: moodDescription,
      sleepMinutes: sleepMinutes,
      lightMinutes: lightMinutes,
      deepMinutes: deepMinutes,
      remMinutes: remMinutes,
      remMeasured: remMeasured,
      stages: stages,
      yesterday: yesterday,
      heartRate: heartRate,
      movement: movement,
      cameraMotion: cameraMotion,
      source: source,
      previousTimeInBed: previousTimeInBed,
      previousSleepMinutes: previousSleepMinutes,
      lightsOutAt: lightsOutAt,
      targetBedtime: targetBedtime,
      adherenceMinutes: adherenceMinutes,
      phoneAfterStartMinutes: phoneAfterStartMinutes,
      rating: rating ?? this.rating,
      ratingLabel: ratingLabel ?? this.ratingLabel,
      wasoMinutes: wasoMinutes,
      awakeCount: awakeCount,
      avgHeartRate: avgHeartRate,
      restingHeartRate: restingHeartRate,
      efficiency: efficiency,
      efficiencyBasis: efficiencyBasis,
      efficiencyLabel: efficiencyLabel,
      efficiencyKind: efficiencyKind,
      efficiencyCaveat: efficiencyCaveat,
      camera: camera ?? this.camera,
      notes: notes ?? this.notes,
      level: replaceGame ? level : this.level,
      xpIntoLevel: replaceGame ? xpIntoLevel : this.xpIntoLevel,
      xpLevelSize: replaceGame ? xpLevelSize : this.xpLevelSize,
      xpProgress: replaceGame ? xpProgress : this.xpProgress,
      nightXp: replaceGame ? nightXp : this.nightXp,
      nightXpSoFar: replaceGame ? (nightXpSoFar ?? false) : this.nightXpSoFar,
      recentNightXp: replaceGame
          ? (recentNightXp ?? const [])
          : this.recentNightXp,
      goalMinutes: goalMinutes ?? this.goalMinutes,
    );
  }

  /// 接上等級、這一晚的 XP、睡眠目標、攝影機那一晚、手機上存的自評。其餘欄位原樣保留。
  ///
  /// ⚠️ +N XP 照抄後端那一晚的數字，**差的晚上就是 +0，不藏**（紅線 5）。
  ///    手錶資料還沒到時，後端那一晚只有行為那部分 → 標成 so far。
  /// ⚠️ 自評：後端已經有那一晚的就用後端的，手機上的只在後端沒有時補上。
  ///    例外 [ratingIsFresh]：起床流程裡剛填的那一份——後端那份是動畫一開始就抓的，
  ///    比它舊（同一晚填第二次時，會把剛填的蓋回上一次的答案；2026-11-13 實機抓到）。
  MorningReport withExtras({
    GameState? game,
    int? goalMinutes,
    CameraNight? camera,
    MorningRating? localRating,
    bool ratingIsFresh = false,
  }) {
    NightXp? night;
    for (final n in game?.recentNights ?? const <NightXp>[]) {
      if (n.date == date) night = n;
    }
    final forNext = game?.xpForNext;
    final useLocal =
        (rating == null || ratingIsFresh) && localRating?.date == date;
    return _copy(
      replaceGame: true,
      level: game?.level,
      xpIntoLevel: game?.xpIntoLevel,
      xpLevelSize: game == null || forNext == null
          ? null
          : game.xpIntoLevel + forNext,
      xpProgress: game?.progress,
      nightXp: night?.total,
      nightXpSoFar: night != null && night.finalQuality == null,
      recentNightXp: game?.recentNights,
      goalMinutes: goalMinutes != null && goalMinutes > 0 ? goalMinutes : null,
      camera: camera?.date == date ? camera : null,
      rating: useLocal ? localRating : null,
      ratingLabel: useLocal ? localRating!.label : null,
    );
  }

  /// 接上 `/night-summary` 的回應（寵物 notes）。日期對不上、沒有內容就維持原樣。
  /// waiting（手錶還沒到）也收：那時只有行為那幾條原句，日記本照樣出現。
  MorningReport withNotes(Map<String, dynamic>? json) {
    final parsed = PetNotes.fromJson(json, date: date);
    return parsed == null ? this : _copy(notes: parsed);
  }
}

/// 日期 → YYYY-MM-DD。
String reportDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

double? _minutesBetween(DateTime? a, DateTime? b) {
  if (a == null || b == null || !b.isAfter(a)) return null;
  return b.difference(a).inSeconds / 60.0;
}

/// 進分數的那個效率：依 basis 去 behavior 找同一個 basis 的那一個；
/// 都對不上就是手錶自己的（三段式的 ③）。**basis 字串不寫死在 Dart**。
/// 進分數的效率是三種裡的哪一種。**不寫死 basis 字串**：拿那一晚 behavior 自己帶的
/// `measured_efficiency_basis`／`watch_wake_efficiency_basis` 去對（同 [scoredEfficiency]）。
enum EfficiencyKind {
  /// ① 兩個按鈕都按：手錶睡眠 ÷（Start sleep → Out of bed）
  buttons,

  /// ② 只按 Start sleep：手錶睡眠 ÷（Start sleep → 手錶醒來）
  startToWatchWake,

  /// ③ 沒按：手錶自己的效率（入睡 → 醒來）
  watchOnly,
}

/// [basis] 是哪一種；效率沒算（basis 是 null）→ null。純函式。
EfficiencyKind? efficiencyKindOf(
  String? basis,
  Map<String, dynamic>? behavior,
) {
  if (basis == null) return null;
  if (behavior?['measured_efficiency_basis'] == basis) {
    return EfficiencyKind.buttons;
  }
  if (behavior?['watch_wake_efficiency_basis'] == basis) {
    return EfficiencyKind.startToWatchWake;
  }
  return EfficiencyKind.watchOnly;
}

/// 一晚**進分數的效率**：依 basis 去 behavior 找同一個 basis 的那個數字，都對不上才用手錶的。
/// 早晨報告的 Efficiency 格子與點開後的一週長條**共用這一支**（這一晚的長條一定等於格子上的數字）。
double? scoredEfficiency(
  String? basis,
  Map<String, dynamic>? behavior,
  Map<String, dynamic>? metrics,
) {
  if (basis == null) return null;
  for (final key in const ['measured_efficiency', 'watch_wake_efficiency']) {
    if (behavior?['${key}_basis'] == basis) {
      return (behavior?[key] as num?)?.toDouble();
    }
  }
  return (metrics?['sleep_efficiency'] as num?)?.toDouble();
}

/// 把三個來源併成一份報告。**純函式**，測試直接打這支。
///
/// - [marks]：手機上的上床／下床。只在它屬於 [date] 那一晚時採用。
/// - [home]：`GET /home?date=` 的整份回應；null 代表沒有後端或連不到。
/// - [session]：打包檔。[home] 是 null 時用它那一晚的 history；
///   Sleep Stages 與夢境只在它最新那一晚就是 [date] 時才用。
MorningReport buildMorningReport({
  required String date,
  BedMarks? marks,
  Map<String, dynamic>? home,
  SleepSession? session,
}) {
  DateTime? bedStart;
  DateTime? bedEnd;
  final start = marks?.startAt;
  if (start != null && reportDateKey(nightDateOf(start)) == date) {
    bedStart = start;
    bedEnd = marks?.endAt;
  }

  // 打包檔最新那一晚就是這一晚 → 才拿它的 Sleep Stages
  final latest = session != null && session.history.isNotEmpty
      ? session.history.last
      : null;
  final sameNightAsBundle = latest != null && latest.date == date;
  final bundleStages = sameNightAsBundle ? session!.metrics.sleepStages : null;

  if (home != null && home['date'] == date) {
    final behavior = (home['behavior'] as Map?)?.cast<String, dynamic>();
    final metrics = (home['metrics'] as Map?)?.cast<String, dynamic>();
    final scoring = (home['scoring'] as Map?)?.cast<String, dynamic>();
    final status = (home['status'] as Map?)?.cast<String, dynamic>();
    final display = (home['display'] as Map?)?.cast<String, dynamic>();
    final previous = (home['previous_night'] as Map?)?.cast<String, dynamic>();
    final ratingJson = (home['morning_rating'] as Map?)
        ?.cast<String, dynamic>();
    final composition = (scoring?['composition'] as Map?)
        ?.cast<String, dynamic>();
    final score = (scoring?['final_score'] as num?)?.toDouble();
    final has = score != null;
    double? n(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toDouble();

    final start = bedStart ?? parseWallClock(behavior?['bed_start_at']);
    final end = bedStart != null
        ? bedEnd
        : parseWallClock(behavior?['bed_end_at']);
    final basis = composition?['efficiency_basis'] as String?;
    String? caveat;
    for (final c in (composition?['caveats'] as List?) ?? const []) {
      if (c is Map && c['component'] == 'efficiency') {
        caveat = c['caveat'] as String?;
      }
    }

    MorningRating? rating;
    if (ratingJson != null) {
      rating = MorningRating.fromJsonOrNull({...ratingJson, 'date': date});
    }

    return MorningReport(
      date: date,
      bedStart: start,
      bedEnd: end,
      timeInBedMinutes:
          n(behavior, 'time_in_bed_minutes') ?? _minutesBetween(start, end),
      asleepAt: parseWallClock(metrics?['sleep_start_time']),
      wokeAt: parseWallClock(metrics?['wake_time']),
      score: score,
      quality: has ? (scoring?['final_quality'] as String?) : null,
      qualityColor: has ? (display?['score_color'] as String?) : null,
      scoreMessage: has ? (display?['score_message'] as String?) : null,
      // ⚠️ 心情與那句話只在有分數時用：沒分數時後端的心情是行為驅動的，
      //    而使用者定的是「還在等資料就畫睡姿小狗」。
      mood: has ? (status?['pet_mood'] as String?) : null,
      moodDescription: has ? (display?['mood_description'] as String?) : null,
      sleepMinutes: has ? n(metrics, 'sleep_duration_minutes') : null,
      lightMinutes: has ? n(metrics, 'light_minutes') : null,
      deepMinutes: has ? n(metrics, 'deep_minutes') : null,
      remMinutes: has ? n(metrics, 'rem_minutes') : null,
      remMeasured: scoring?['rem_measured'] == true,
      stages: has
          ? (SleepStages.fromJsonOrNull(metrics?['sleep_stages']) ??
                bundleStages)
          : null,
      // 白天資料跟睡眠分數無關：那一天有就畫（手錶睡眠還沒到也一樣）
      yesterday: YesterdayActivity.fromJsonOrNull(home['yesterday']),
      heartRate: has
          ? NightCurve.fromJsonOrNull(metrics?['heart_rate_curve'])
          : null,
      movement: has
          ? NightCurve.fromJsonOrNull(metrics?['movement_curve'])
          : null,
      cameraMotion: has
          ? NightCurve.fromJsonOrNull(metrics?['camera_curve'])
          : null,
      source: ReportSource.backend,
      previousTimeInBed: n(previous, 'time_in_bed_minutes'),
      previousSleepMinutes: n(previous, 'sleep_duration_minutes'),
      lightsOutAt: parseWallClock(behavior?['lights_out_at']),
      targetBedtime: behavior?['target_bedtime'] as String?,
      adherenceMinutes: n(behavior, 'adherence_minutes'),
      phoneAfterStartMinutes: n(behavior, 'phone_in_bed_minutes'),
      rating: rating,
      ratingLabel: ratingJson?['label'] as String? ?? rating?.label,
      wasoMinutes: has ? n(metrics, 'waso_minutes') : null,
      awakeCount: has ? n(metrics, 'awake_count')?.round() : null,
      avgHeartRate: has ? n(metrics, 'avg_heart_rate') : null,
      restingHeartRate: has ? n(metrics, 'resting_heart_rate') : null,
      efficiency: has ? scoredEfficiency(basis, behavior, metrics) : null,
      efficiencyBasis: has ? basis : null,
      efficiencyLabel: has
          ? (composition?['efficiency_label'] as String?)
          : null,
      efficiencyKind: has ? efficiencyKindOf(basis, behavior) : null,
      efficiencyCaveat: has ? caveat : null,
    );
  }

  // 沒有後端 → 打包檔裡那一晚
  HistoryEntry? entry;
  for (final e in session?.history ?? const <HistoryEntry>[]) {
    if (e.date == date) entry = e;
  }
  if (entry != null && entry.finalScore != null) {
    final hours = entry.sleepDurationHours;
    return MorningReport(
      date: date,
      bedStart: bedStart,
      bedEnd: bedEnd,
      timeInBedMinutes: _minutesBetween(bedStart, bedEnd),
      asleepAt: parseWallClock(entry.bedtime),
      wokeAt: parseWallClock(entry.wakeTime),
      score: entry.finalScore,
      quality: entry.finalQuality,
      // 打包檔只有最新那一晚有 display；舊夜晚就不放那兩句話
      qualityColor: sameNightAsBundle ? session!.display.scoreColor : null,
      scoreMessage: sameNightAsBundle ? session!.display.scoreMessage : null,
      mood: entry.petMood,
      moodDescription: sameNightAsBundle
          ? session!.display.moodDescription
          : null,
      sleepMinutes: hours == null ? null : hours * 60,
      deepMinutes: entry.deepMinutes?.toDouble(),
      // 效率（2026-11-21，首頁點效率格沒有後端時也要開得了）：打包檔只有最新那一晚有進分數的那一個。
      // ⚠️ 種類留 null：判種類要後端的 behavior（basis 字串不寫死在 Dart），效率頁種類未知時不寫分母那一行
      efficiency: sameNightAsBundle
          ? (session!.metrics.scoredEfficiency ?? session.metrics.sleepEfficiency)
          : null,
      efficiencyLabel:
          sameNightAsBundle ? session!.metrics.scoredEfficiencyLabel : null,
      remMeasured: bundleStages?.remMeasured ?? false,
      stages: bundleStages,
      source: ReportSource.bundled,
    );
  }

  return MorningReport(
    date: date,
    bedStart: bedStart,
    bedEnd: bedEnd,
    timeInBedMinutes: _minutesBetween(bedStart, bedEnd),
    source: ReportSource.phoneOnly,
  );
}

/// 拿某一晚的寵物 notes（`/night-summary`）。[generate] = false 時後端絕不呼叫 AI。
/// ⚠️ 沒有分數時一律帶 false：手錶還沒到，後端本來就不會生成，App 也不要求。
typedef NotesLoader = Future<Map<String, dynamic>?> Function({bool generate});

/// 讀 `/home?date=` 與 `/night-summary`。可以換成假的來測。
abstract class MorningReportSource {
  /// 成功回整份 JSON；沒有後端、沒有帳號、連不到都回 null。
  Future<Map<String, dynamic>?> fetchNight(String date);

  /// `/night-summary`（寵物 notes）。同上，失敗回 null（日記本不出現）。
  ///
  /// [generate] = false：後端**絕不呼叫 AI**，只回已經存好的那一份（沒有就回原句）。
  /// 🔴 首頁一律用 false——AI 那段一定要在起床自評送出之後才生成（它會讀自評的標籤）。
  Future<Map<String, dynamic>?> fetchSummary(String date, {bool generate = true});
}

class MorningReportService implements MorningReportSource {
  final String baseUrl;
  final UserIdentity identity;
  final Duration timeout;

  /// AI 那段第一次生成要等模型，給長一點（後端那邊最多試兩次）。
  final Duration summaryTimeout;

  const MorningReportService({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 4),
    this.summaryTimeout = const Duration(seconds: 45),
  });

  @override
  Future<Map<String, dynamic>?> fetchNight(String date) =>
      _get('/home', date, timeout);

  @override
  Future<Map<String, dynamic>?> fetchSummary(String date, {bool generate = true}) =>
      _get('/night-summary', date, generate ? summaryTimeout : timeout,
          extra: generate ? const {} : const {'generate': 'false'});

  Future<Map<String, dynamic>?> _get(
    String path,
    String date,
    Duration wait, {
    Map<String, String> extra = const {},
  }) async {
    if (baseUrl.trim().isEmpty) return null;
    final userId = await identity.currentUserId();
    if (userId == null) return null;
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: {'user_id': userId, 'date': date, ...extra});
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(wait);
      final body = await response.transform(utf8.decoder).join().timeout(wait);
      if (response.statusCode != 200) {
        // ⚠️ 不印 uri：query 帶著 user_id（憑證）。
        debugPrint('MorningReport: GET $path returned ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (error) {
      debugPrint('MorningReport: $path failed - $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// 經驗條上的一格。`date == null` 是「更早累積的」那一段（含挑戰獎勵）。
@immutable
class XpSegment {
  final String? date;
  final int start;
  final int end;
  const XpSegment({required this.date, required this.start, required this.end});

  int get xp => end - start;

  @override
  String toString() => 'XpSegment($date, $start-$end)';
}

/// 經驗條一晚一格：從目前的進度（`into`）往回，依序排最近幾晚（`nights` 由舊到新）。
/// 跨進這一級之前的那一晚只畫在這一級裡的部分；排完剩下的是「更早累積的」一段。
///
/// ⚠️ 只排版、不算 XP：每格的寬度就是後端那一晚的 `total`。+0 的晚上沒有格子（照實）。
/// ⚠️ 挑戰獎勵沒有日期，一律算在「更早累積的」那段——剛領獎勵時，
///    最近幾晚的格子會整體往後挪一點，但每格的大小仍是對的。
List<XpSegment> xpBarSegments({
  required int into,
  required List<NightXp> nights,
}) {
  final out = <XpSegment>[];
  var cursor = into;
  for (final n in nights.reversed) {
    if (cursor <= 0) break;
    if (n.total <= 0) continue;
    final start = cursor - n.total < 0 ? 0 : cursor - n.total;
    out.add(XpSegment(date: n.date, start: start, end: cursor));
    cursor = start;
  }
  if (cursor > 0) out.add(XpSegment(date: null, start: 0, end: cursor));
  return out.reversed.toList();
}
