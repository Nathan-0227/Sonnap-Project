import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bed_marks.dart';
import 'lights_out.dart';
import 'sleep_repository.dart';
import 'user_identity.dart';

/// 上傳的結果。**每一種「沒上傳」的原因都要分得開**——它們在畫面上要講
/// 不同的話，解法也完全不同（沒設定身分 vs 後端沒開 vs 那晚偵測不到）。
enum NightlyUploadStatus {
  /// 傳出去了，後端回了那一晚的達成度
  ok,

  /// 這支 build 沒有 `--dart-define=SONNAP_USER_ID`
  noUser,

  /// 這支 build 沒有 `--dart-define=SONNAP_API_BASE`
  noBackend,

  /// 那個視窗裡偵測不到就寢時刻，**沒有東西可傳**
  nothingDetected,

  /// 傳了但失敗（連不上、逾時、後端回錯）
  failed,
}

@immutable
class NightlyUploadResult {
  final NightlyUploadStatus status;

  /// 後端判定這是哪一晚（起床日）。⚠️ 由 `behavior/adherence.py` 的
  /// `night_date()` 決定，不是 Dart 算的。
  final String? date;

  /// 比目標就寢時間晚幾分鐘。正值＝拖延，負值＝提早。
  ///
  /// ⚠️ **這個數字是後端算的，Dart 只負責顯示。** 跨午夜正規化
  /// （目標 23:30、實際 02:15，直覺相減會得到「提早 21 小時」）寫在
  /// `behavior/adherence.py`；在這裡重算就會有第二個定義處，
  /// 兩份漂移時不會有任何錯誤訊息。
  final int? adherenceMinutes;

  /// 後端判定這一晚算不算熬夜。同樣是後端的判斷，門檻在
  /// `adherence.LATE_THRESHOLD_MINUTES`。
  final bool? isLate;

  /// 後端**實際存下來**的上床標記。null = 沒存。
  ///
  /// ═══════════════════════════════════════════════════════════════
  /// ⚠️ 這不是「我們送了什麼」，是「後端收了什麼」。兩者會不一樣。
  /// ═══════════════════════════════════════════════════════════════
  /// `main.py` 有一條 `same_night` 判斷：`bed_start_at` 屬於的夜晚與
  /// `lights_out_at` 判定的夜晚不一致時，**整組標記靜靜丟掉，但仍然回 201**。
  /// 那條判斷本身是對的（2026-09-07 曾把 09-07 03:36 的標記寫進 09-06 那一列，
  /// 算出 −1282 分鐘），但它讓「上傳成功」與「標記存下來了」變成兩件事。
  ///
  /// 2026-09-10 因此掉了一次資料：App 看到 201 就把本機標記清掉，
  /// 而後端一列都沒存。**成功了但什麼都沒做**——這個專案最常見的那類 bug。
  ///
  /// → 呼叫端要清本機標記時，判準是這個欄位不是 [status]。
  final String? storedBedStartAt;
  final String? storedBedEndAt;

  /// 後端有沒有收下這組標記。
  bool get marksStored => storedBedStartAt != null;

  final String? error;

  const NightlyUploadResult(
    this.status, {
    this.date,
    this.adherenceMinutes,
    this.isLate,
    this.storedBedStartAt,
    this.storedBedEndAt,
    this.error,
  });
}

/// 把偵測到的就寢時刻送去後端 `POST /nightly`。
///
/// ═══════════════════════════════════════════════════════════════════
/// 這一步把 Tier A 的迴圈真的接起來了
/// ═══════════════════════════════════════════════════════════════════
///
///     手機事件流 → lights_out_at → POST /nightly
///                                    ↓
///                          nightly_behavior 資料表
///                                    ↓
///                        挑戰進度、熬夜比率、寵物狀態
///
/// 在此之前後端那一整層有資料表、有端點、有測試，但**沒有任何東西會寫進去**。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 不需要在半夜跑
/// ═══════════════════════════════════════════════════════════════════
///
/// `queryEvents()` 讀的是 Android 自己的歷史紀錄，事件不管 App 有沒有執行
/// 都會被記下來（實測保留 **≥5 天**）。而且 [detectLightsOut] 本來就要求
/// 那段安靜**已經結束**——半夜跑的時候人還在睡，那段安靜還沒結束，
/// 結構上就得不到答案。
///
/// 後端也是為事後上傳設計的：日期來自 `night_date(lights_out_at)` 而不是
/// 「現在」，`upsert_nightly_behavior` 是冪等的，重複傳同一晚不會重複。
/// 所以「每次開 App 就算一次、有結果就傳」是安全的做法。
class NightlyUploader {
  final String baseUrl;
  final UserIdentity identity;

  /// 與 `ApiSleepRepository` 一樣短。這是「demo 當場等多久才放棄」，
  /// 上傳失敗不該讓畫面卡住——那一晚的資料還在手機裡，下次開 App 會再試。
  final Duration timeout;

  const NightlyUploader({
    required this.baseUrl,
    required this.identity,
    this.timeout = const Duration(seconds: 3),
  });

  /// [marks] 是使用者自己按的上床／下床時刻（可選）。
  ///
  /// ⚠️ **它是加分項不是取代品。** 沒按的夜晚照樣上傳，只是後端算不出
  /// 臥床時間與行為版效率（那兩個欄位會是 null，不是 0）。
  /// 絕對不要因為「沒有標記」就跳過上傳 —— 那會讓忘記按按鈕變成
  /// 「這一晚沒有資料」。
  Future<NightlyUploadResult> upload(
    LightsOutResult lightsOut, {
    BedMarks marks = BedMarks.none,
  }) async {
    if (baseUrl.trim().isEmpty) {
      return const NightlyUploadResult(NightlyUploadStatus.noBackend);
    }

    final iso = lightsOut.iso8601;
    if (lightsOut.status != LightsOutStatus.ok || iso == null) {
      // ⚠️ 絕對不要在這裡填一個預設時刻。後端對空的 lights_out_at 明確回
      // 400，理由寫在 main.py：「沒量到」與「準時」是兩件事，
      // 不要上傳沒有量到的夜晚。
      return const NightlyUploadResult(NightlyUploadStatus.nothingDetected);
    }

    final userId = await identity.currentUserId();
    if (userId == null) {
      return const NightlyUploadResult(NightlyUploadStatus.noUser);
    }

    // ⚠️ 按「下床」按得太晚時，那個時刻不是下床時刻，是「想起來要按」的
    //    時刻（2026-09-08 實測：08:20 起床、12:11 才按）。照送會算出一個
    //    錯得很合理的臥床時間與效率。判準見 `bedEndIsPlausible`。
    //    ⚠️ 只丟掉 end，**start 照送**——那一半仍然是有效的自述。
    final endIsStale = marks.endAt != null &&
        !bedEndIsPlausible(marks.endAt!, lightsOut.at, lightsOut.quietMinutes);
    final endIso = endIsStale ? null : marks.endIso;

    final uri = Uri.parse('$baseUrl/nightly');
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'user_id': userId,
        'lights_out_at': iso,
        // 兩個都是**自述**的時刻。後端只在兩者都有時才算得出臥床時間，
        // 少一個就整組是 null（見 behavior/sleep_efficiency.py）。
        if (marks.startIso != null) 'bed_start_at': marks.startIso,
        if (endIso case final String v) 'bed_end_at': v,
        // ⚠️ 刻意**不傳** target_bedtime。後端會用使用者當下的設定並存成
        //    當晚的快照——那個欄位是留給「補填歷史夜晚」的，當晚的目標
        //    可能與現在不同。從 App 每天傳等於天天覆寫快照。
        'source': 'phone',
      }));

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 201) {
        return NightlyUploadResult(
          NightlyUploadStatus.failed,
          error: 'POST $uri returned ${response.statusCode}: $body',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return NightlyUploadResult(
          NightlyUploadStatus.failed,
          error: '$uri 回傳的根節點不是物件',
        );
      }

      final result = NightlyUploadResult(
        NightlyUploadStatus.ok,
        date: decoded['date'] as String?,
        adherenceMinutes: (decoded['adherence_minutes'] as num?)?.round(),
        isLate: decoded['is_late'] as bool?,
        // ⚠️ 回應裡的是**後端存下來的**，不是我們送出去的。見欄位說明。
        storedBedStartAt: decoded['bed_start_at'] as String?,
        storedBedEndAt: decoded['bed_end_at'] as String?,
      );
      // ⚠️ 不印 user_id（它是憑證），只印結果。
      // ⚠️ 只印**有沒有**標記，不印時刻本身也不印 user_id。
      //    這一行是實機 debug 用的：先前查不出「按了按鈕卻沒進 DB」
      //    是 App 沒送還是後端沒存，就是因為兩邊都看不到這件事。
      final marksState = endIsStale
          ? 'end-dropped(stale)'
          : marks.isComplete
              ? 'complete'
              : marks.hasStart
                  ? 'start-only'
                  : 'none';
      debugPrint(
        'NightlyUpload: ok date=${result.date} '
        'adherence=${result.adherenceMinutes}m late=${result.isLate} '
        'marks=$marksState',
      );
      return result;
    } catch (error) {
      debugPrint('NightlyUpload: failed - $error');
      return NightlyUploadResult(
        NightlyUploadStatus.failed,
        error: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// 依建置參數決定要不要上傳。
///
/// 沒給 `--dart-define=SONNAP_API_BASE` 就回 null，整條上傳路徑不存在——
/// 行為與加上它之前**完全相同**。與 `buildSleepRepository()`、
/// `buildUserIdentity()` 是同一個原則：「什麼都沒設定」仍然是那條最穩、
/// demo 一定跑得起來的路徑。
///
/// ⚠️ 只看 API base，不看 user id。少了 user id 時仍然建得出 uploader，
/// 讓它回報 [NightlyUploadStatus.noUser]——「後端沒開」與「這支 build
/// 沒設定身分」是兩個不同的問題，畫面上要分得開。
NightlyUploader? buildNightlyUploader({
  String? baseUrlOverride,
  String? userIdOverride,
}) {
  final baseUrl = (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();
  if (baseUrl.isEmpty) return null;
  return NightlyUploader(
    baseUrl: baseUrl,
    identity: buildUserIdentity(userIdOverride: userIdOverride),
  );
}
