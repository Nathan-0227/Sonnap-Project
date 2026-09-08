import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bed_marks.dart';
import 'key_value_store.dart';
import 'lights_out.dart';
import 'pending_nightly.dart';
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

  final String? error;

  const NightlyUploadResult(
    this.status, {
    this.date,
    this.adherenceMinutes,
    this.isLate,
    this.error,
  });
}

/// 一次同步的結果：這一晚，加上補送掉的舊夜晚。
///
/// ⚠️ **[current] 與 [replayed] 一定要分開。** 畫面上的達成度只能講
/// [current]——把補送的夜晚混進去，使用者早上看到的會是三天前那一晚的
/// 數字，而畫面上完全看不出來講的是哪一天。這就是「補送不得重複計算」
/// 具體長什麼樣子。
@immutable
class NightlyUploadBatch {
  /// 這一次偵測到的那一晚。沒偵測到時 status 是 nothingDetected。
  final NightlyUploadResult current;

  /// 這一次順便補送成功的**舊**夜晚，不含 [current]。
  final List<NightlyUploadResult> replayed;

  /// 補送完之後還留在手機裡沒送出去的夜晚數。
  final int stillPending;

  /// 今晚這一筆**已經安全地存進佇列**了嗎（上傳失敗但留得住）。
  ///
  /// ⚠️ 呼叫端靠這個決定要不要清掉本機的上床標記。
  /// 在有佇列之前，`bed_marks` 只在上傳成功時清——因為失敗時清掉就
  /// 等於把使用者按的那一下弄丟。有了佇列之後那個取捨不存在了：
  /// 標記已經跟著那一晚一起存進佇列，留在 [BedMarkStore] 裡反而會被
  /// **明天那一晚**再讀一次（[kBedMarkMaxAge] 是 36 小時），
  /// 同一對標記因此配到兩個不同的夜晚。
  final bool currentQueued;

  const NightlyUploadBatch({
    required this.current,
    this.replayed = const <NightlyUploadResult>[],
    this.stillPending = 0,
    this.currentQueued = false,
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

  /// 上傳失敗的夜晚存在哪裡。null = 不留存（舊行為）。
  ///
  /// ⚠️ 給了它才有 [sync]，而**只有 [sync] 補得回連不到後端的那一晚**。
  /// 見 [PendingNightlyStore] 的檔頭：偵測視窗是往回 24 小時的滑動視窗，
  /// 隔天再開一次 App 是救不回來的。
  final PendingNightlyStore? pending;

  const NightlyUploader({
    required this.baseUrl,
    required this.identity,
    this.pending,
    this.timeout = const Duration(seconds: 3),
  });

  /// 送這一晚，順便把之前沒送成功的補送掉。
  ///
  /// 順序是**先補舊的、再送今晚**：畫面上顯示的是今晚，所以它要是最後
  /// 拿到的那一份。
  ///
  /// ⚠️ 沒有 [pending] 時退化成單純的 [upload]，行為與加這一層之前
  /// 完全相同——與 `buildSleepRepository()` 的「什麼都沒設定仍然跑得起來」
  /// 是同一個原則。
  Future<NightlyUploadBatch> sync(
    LightsOutResult lightsOut, {
    BedMarks marks = BedMarks.none,
  }) async {
    final queue = pending;
    if (queue == null) {
      return NightlyUploadBatch(current: await upload(lightsOut, marks: marks));
    }

    final todayIso =
        lightsOut.status == LightsOutStatus.ok ? lightsOut.iso8601 : null;

    final stored = await queue.load();
    // ⚠️ 今晚這一筆如果已經在佇列裡就先拿掉。24 小時的視窗會連續兩天算出
    //    **同一個時刻**，不拿掉的話同一晚會被送兩次、畫面上也會算兩次。
    stored.removeWhere((night) => night.lightsOutIso == todayIso);

    final replayed = <NightlyUploadResult>[];
    final remaining = <PendingNight>[];
    for (final night in stored) {
      // ⚠️ 補送要帶著**那一晚自己的**上床標記，不是現在手機裡的那一組。
      //    拿今天的標記去補三天前那一晚，算出來的臥床時間是假的。
      final result = await _post(night.lightsOutIso, night.marks);
      if (result.status == NightlyUploadStatus.ok) {
        replayed.add(result);
      } else if (_worthKeeping(result.status)) {
        remaining.add(night);
      }
      // 其餘狀態代表「這筆補不回來了」（例如後端回 400 說時刻壞掉），
      // 留著只會每天重試一次同一個失敗。
    }

    final current = await upload(lightsOut, marks: marks);
    final queuedToday = todayIso != null && _worthKeeping(current.status);
    if (queuedToday) {
      remaining.add(PendingNight(todayIso, marks: marks));
    }

    await queue.save(remaining);
    return NightlyUploadBatch(
      current: current,
      replayed: replayed,
      stillPending: remaining.length,
      currentQueued: queuedToday,
    );
  }

  /// 這種失敗值不值得留下來下次再試。
  ///
  /// ⚠️ 只有這兩種：
  ///   - [NightlyUploadStatus.failed]：連不上／逾時／後端回錯。**這是
  ///     這整個機制存在的理由**（受測者早上不在同一個 Wi-Fi 底下）。
  ///   - [NightlyUploadStatus.noUser]：還沒建帳號。跳過註冊是刻意不寫進
  ///     儲存的（見 `main.dart` 的 `_skipOnboarding`），所以之後一定還會
  ///     被問一次；那時候這幾晚要補得回來。
  ///
  /// `noBackend` 不留：那支 build 根本沒有 `--dart-define=SONNAP_API_BASE`，
  /// 留著也永遠送不出去。`nothingDetected` 不留：沒有東西可留。
  static bool _worthKeeping(NightlyUploadStatus status) =>
      status == NightlyUploadStatus.failed ||
      status == NightlyUploadStatus.noUser;

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

    return _post(iso, marks);
  }

  /// 真正發出請求的那一段。吃 ISO8601 字串而不是 [LightsOutResult]，
  /// 因為補送時手上只剩存下來的那一筆 [PendingNight]——達成度那三個欄位
  /// 刻意不存（理由見 [PendingNightlyStore]）。
  Future<NightlyUploadResult> _post(String iso, BedMarks marks) async {
    final userId = await identity.currentUserId();
    if (userId == null) {
      return const NightlyUploadResult(NightlyUploadStatus.noUser);
    }

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
        if (marks.endIso != null) 'bed_end_at': marks.endIso,
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
      );
      // ⚠️ 不印 user_id（它是憑證），只印結果。
      // ⚠️ 只印**有沒有**標記，不印時刻本身也不印 user_id。
      //    這一行是實機 debug 用的：先前查不出「按了按鈕卻沒進 DB」
      //    是 App 沒送還是後端沒存，就是因為兩邊都看不到這件事。
      final marksState = marks.isComplete
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
  KeyValueStore? store,
}) {
  final baseUrl = (baseUrlOverride ?? ApiSleepRepository.configuredBaseUrl).trim();
  if (baseUrl.isEmpty) return null;
  return NightlyUploader(
    baseUrl: baseUrl,
    identity: buildUserIdentity(userIdOverride: userIdOverride),
    pending: PendingNightlyStore(store ?? const PlatformKeyValueStore()),
  );
}
