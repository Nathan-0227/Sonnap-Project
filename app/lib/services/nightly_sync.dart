import 'package:flutter/foundation.dart';

import 'backfill.dart' as backfill;
import 'bed_marks.dart';
import 'challenges_service.dart';
import 'home_service.dart';
import 'lights_out.dart';
import 'nightly_uploader.dart';
import 'pre_bed_apps.dart';
import 'usage_stats.dart';

/// 偵測昨晚幾點放下手機 → 上傳 `POST /nightly` → 問挑戰進度（2026-11-19 從舊 Insights 頁搬出來）。
///
/// ⚠️ **這段原本藏在 Insights 頁的 initState 裡**：Insights 改版之後那一頁拆掉了，
/// 所以搬到 App 層，**一打開、每次回到前景都跑一次，跟停在哪一頁無關**。
/// 漏跑的後果不會報錯：只是昨晚沒上傳、熬夜與挑戰少一晚。
///
/// 規則全部照舊（搬家不改行為）：
///   - 上傳之前先看「已經按完、還沒上傳」的那一對（pending），那屬於上一晚
///   - 只有**後端真的收下按鈕**才清本機的標記，而且只清送出去的那一個槽
///   - 挑戰一定要在上傳**之後**問（後端即時重算，順序反了會少算今晚）
///   - 沒有上傳器（沒有後端的 build）照樣問挑戰
class NightlySync extends ChangeNotifier {
  final UsageStatsService usageStats;
  final BedMarkStore bedMarks;

  NightlySync({
    this.usageStats = const UsageStatsService(),
    required this.bedMarks,
  });

  /// 昨天一整天的 App 使用時間。
  UsageStatsResult? usage;

  /// 上一次放下手機的時刻。
  LightsOutResult? lightsOut;

  /// 放下手機前那一小時，每個 App 各用了多久（Phone down 詳細頁的 Before bed）。
  PreBedResult? preBed;

  /// 上傳的結果（含補送的舊夜晚）。設定頁的「資料送到了沒」。
  NightlyUploadBatch? batch;

  /// `GET /challenges`。每一格數字都是後端算的。
  ChallengesResult? challenges;

  /// `GET /home` 的 behavior 區塊。
  HomeResult? home;

  bool _running = false;

  /// 跑一次。同時只跑一個（回到前景很快連按兩次時不要上傳兩次）。
  Future<void> run({
    NightlyUploader? uploader,
    ChallengesService? challengesService,
    HomeService? homeService,
  }) async {
    if (_running) return;
    _running = true;
    try {
      final result = await usageStats.queryYesterday();
      // ⚠️ 補填模式只換 `now`，其餘完全走同一條路（見 services/backfill.dart）。
      final lo = await usageStats.lightsOut(now: backfill.backfillNow);
      // 事件流只有 package name，顯示名稱要跟日彙總借。
      final labels = {for (final a in result.apps) a.packageName: a.appName};
      final pb = await usageStats.preBed(lightsOut: lo, labels: labels);
      // ⚠️ 先看 pending：那是「已經按完、但還沒上傳」的一對，屬於上一晚。
      //    2026-09-09 真的掉過一晚（見 bed_marks.dart 的 markStart）。
      final pending = await bedMarks.readPending();
      final marks = pending.isComplete ? pending : await bedMarks.read();
      usage = result;
      lightsOut = lo;
      preBed = pb;
      notifyListeners();

      // ⚠️ 上傳失敗不影響上面任何一格（後端沒開是 demo 的常態）。
      if (uploader != null) {
        // sync() 而不是 upload()：先把之前連不到後端那幾晚補送掉。
        final b = await uploader.sync(lo, marks: marks);
        batch = b;
        notifyListeners();
        // ⚠️ 判準是「後端收下了」不是「上傳成功」（same_night 夜份不符時照樣回 201、
        //    但一列都沒存——2026-09-10 掉過一次）。進了離線佇列也不清。
        //    清的必須是送出去的那一個槽，不然會把今晚剛按的「開始」一起刪掉。
        final current = b.current;
        if (current.status == NightlyUploadStatus.ok && current.marksStored) {
          if (pending.isComplete) {
            await bedMarks.clearPending();
          } else {
            await bedMarks.clear();
          }
        }
      }

      // ⚠️ 一定在上傳之後，而且沒有 uploader 的 build 照樣要問。
      if (challengesService != null) {
        challenges = await challengesService.fetch();
        notifyListeners();
      }
      if (homeService != null) {
        home = await homeService.fetch();
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }
}
