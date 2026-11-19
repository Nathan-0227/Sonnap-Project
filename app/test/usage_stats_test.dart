// 手機使用時間：Dart 端與 Insights 卡片。
//
// 這一組守兩件事：
//
//   1. **語意**。原生端給的是「昨天整天的前景總時間」，不是「睡前一小時」。
//      把整天的數字放在「Top Sleep Distractions」的標題底下，就是拿一個量
//      冒充另一個量——而畫面看起來完全正常，沒有任何跡象。
//      這正是本專案在 `movement_sample_minutes`、`sleep_efficiency` 上
//      反覆記取的同一種錯誤。
//
//   2. **沒有權限時要帶路**。PACKAGE_USAGE_STATS 跳不出系統授權對話框，
//      使用者一定要自己走一趟設定頁。只寫「沒有權限」然後把人丟在原地，
//      這個功能對絕大多數人就等於不存在。

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/nightly_sync.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/pending_nightly.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/usage_stats.dart';


/// 固定回一個結果的 uploader。真的 HTTP 由 nightly_uploader_test.dart 測，
/// 這裡只驗「拿到結果之後畫面怎麼顯示」。
class _StubUploader implements NightlyUploader {
  final NightlyUploadResult result;

  /// 假後端收不收下標記。
  ///
  /// ⚠️ 這個開關存在的理由：真的後端有一條 `same_night` 判斷，夜份不符時
  /// **靜靜丟掉整組標記但仍然回 201**。2026-09-10 因此掉了一次資料——
  /// App 看到 201 就清掉本機標記，而後端一列都沒存。
  /// 所以 stub 必須能重現「上傳成功但沒收下」這個狀態。
  final bool acceptsMarks;

  /// 上傳時實際收到的標記。用來驗「按了按鈕就要送上去」。
  ///
  /// ⚠️ 畫面走的是 [sync] 不是 [upload]，所以兩條都要記——只記 upload
  /// 的話這個欄位永遠是 null，而測試會以為「按了卻沒送上去」。
  BedMarks? received;

  /// 這一晚有沒有被存進離線佇列（上傳失敗但留得住）。
  final bool queued;

  _StubUploader(this.result, {this.acceptsMarks = true, this.queued = false});

  @override
  Future<NightlyUploadResult> upload(
    LightsOutResult lightsOut, {
    BedMarks marks = BedMarks.none,
  }) async {
    received = marks;
    if (!acceptsMarks || !marks.isComplete) return result;
    // 真後端回應裡會帶回**它存下來的**那兩個時刻。
    return NightlyUploadResult(
      result.status,
      date: result.date,
      adherenceMinutes: result.adherenceMinutes,
      isLate: result.isLate,
      storedBedStartAt: marks.startIso,
      storedBedEndAt: marks.endIso,
    );
  }

  /// 畫面走的是這一條（[NightlyUploader.sync]）。補送的舊夜晚固定為空——
  /// 佇列本身由 nightly_uploader_test.dart 測，這裡只驗顯示。
  @override
  Future<NightlyUploadBatch> sync(
    LightsOutResult lightsOut, {
    BedMarks marks = BedMarks.none,
  }) async {
    // ⚠️ 走 upload() 那一段，不要直接回 result。畫面走的是 sync()，
    //    直接回 result 的話 acceptsMarks 就沒有作用——「回 201 但後端沒收下」
    //    與「收下了」會長得一模一樣，守那件事的測試就守不住任何東西。
    final current = await upload(lightsOut, marks: marks);
    return NightlyUploadBatch(current: current, currentQueued: queued);
  }

  @override
  PendingNightlyStore? get pending => null;

  @override
  String get baseUrl => 'stub';

  @override
  UserIdentity get identity => const BuildTimeUserIdentity(overrideId: 'stub');

  @override
  Duration get timeout => const Duration(seconds: 1);
}

class _FakeUsageStats extends UsageStatsService {
  UsageStatsResult result;

  /// ⚠️ 這個一定要一起攔。少了它，widget test 會打到真的 MethodChannel，
  /// 整個 `_loadUsage()` 卡在那個 await 上——畫面停在「Reading phone
  /// usage...」，而失敗訊息看起來像是「找不到 App 名稱」，指向錯的地方。
  LightsOutResult lightsOutResult;

  /// ⚠️ 這個也要一起攔，理由同上 —— 少了它，`_loadUsage()` 會多一次
  /// 真的 MethodChannel 往返，而症狀是**整張卡片不顯示**
  /// （測試訊息會說「找不到 Phone down at 23:12」，指向錯的地方）。
  PreBedResult preBedResult;

  int openSettingsCalls = 0;
  int queryCalls = 0;

  _FakeUsageStats(
    this.result, {
    this.lightsOutResult = const LightsOutResult(LightsOutStatus.noEvents),
    this.preBedResult = const PreBedResult(),
  });

  @override
  bool get isSupported => true;

  @override
  Future<UsageStatsResult> queryYesterday({int limit = 5}) async {
    queryCalls++;
    return result;
  }

  @override
  Future<LightsOutResult> lightsOut({
    Duration window = kLightsOutWindow,
    int minQuietMinutes = kMinQuietMinutes,
    DateTime? now,
  }) async =>
      lightsOutResult;

  @override
  Future<PreBedResult> preBed({
    required LightsOutResult lightsOut,
    Map<String, String> labels = const {},
    Duration window = kPreBedWindow,
  }) async =>
      preBedResult;

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}

void main() {
  /// 跑一次上傳流程（2026-11-19 起在 App 層的 NightlySync，舊 Insights 頁拆掉了）。
  /// 名字留著 pumpReport，下面那幾條的意思沒變：同一份事件、同一個上傳器、同一組按鈕。
  Future<NightlySync> pumpReport(
    WidgetTester tester,
    _FakeUsageStats usage, {
    NightlyUploader? uploader,
    BedMarkStore? bedMarks,
  }) async {
    final sync = NightlySync(
      usageStats: usage,
      bedMarks: bedMarks ?? BedMarkStore(InMemoryKeyValueStore()),
    );
    await sync.run(uploader: uploader);
    return sync;
  }


  group('語意：標題不能把整天的數字說成睡前', () {
    test('服務層的文件與方法名都指向「昨天一整天」', () {
      // queryYesterday 是刻意的命名。改成 queryBeforeBed 之類的名字
      // 而沒有先換掉原生端的 queryUsageStats，就是在說謊。
      const service = UsageStatsService();
      expect(service.queryYesterday, isA<Function>());
    });


    // 反向對照：**有**睡前資料時，標題與說明都要跟著換。
    // 沒有這一條，把標題寫死成 'Phone Use Yesterday' 也會通過上面那條，
    // 而睡前歸因就永遠顯示不出來。
  });

  group('四種狀態各講不同的話', () {





  });

  group('AppUsage 解析原生端傳來的 Map', () {
    test('欄位名與 Kotlin 端一致', () {
      // Kotlin 那邊回的是 package_name / app_name / usage_minutes。
      // 這三個字串是跨語言的契約，改一邊而不改另一邊不會有編譯錯誤，
      // 只會安靜地變成空字串與 0。
      final app = AppUsage.fromMap(const <Object?, Object?>{
        'package_name': 'com.instagram.android',
        'app_name': 'Instagram',
        'usage_minutes': 73,
      });

      expect(app.packageName, 'com.instagram.android');
      expect(app.appName, 'Instagram');
      expect(app.minutes, 73);
    });

    test('欄位缺失時給安全的預設值，不要拋例外', () {
      final app = AppUsage.fromMap(const <Object?, Object?>{});
      expect(app.packageName, '');
      expect(app.appName, '');
      expect(app.minutes, 0);
      expect(app.isLauncher, isFalse);
    });
  });

  group('同名的項目要合併', () {
    // 實機上真的會發生：Samsung 桌面有兩個 package 都叫「One UI Home」，
    // Google 搜尋與 Play 服務都叫「Google」。不合併的話畫面上會出現
    // 「One UI Home 24m」「One UI Home 12m」兩列，看起來像程式壞了。
    test('顯示名稱相同的加總，並重新排序', () {
      final merged = mergeByLabel(const [
        AppUsage(packageName: 'com.sec.launcher', appName: 'One UI Home', minutes: 24),
        AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 30),
        AppUsage(packageName: 'com.sec.launcher2', appName: 'One UI Home', minutes: 12),
      ]);

      expect(merged.length, 2);
      expect(merged.first.appName, 'One UI Home');
      expect(merged.first.minutes, 36, reason: '24 + 12 要加起來');
      expect(merged.last.appName, 'Threads');
      expect(
        merged.map((a) => a.minutes).toList(),
        [36, 30],
        reason: '合併之後名次會變，要重新排序',
      );
    });

    test('合併時只要有一個是啟動器，整組就是啟動器', () {
      final merged = mergeByLabel(const [
        AppUsage(packageName: 'com.a', appName: 'Home', minutes: 5),
        AppUsage(
            packageName: 'com.b', appName: 'Home', minutes: 5, isLauncher: true),
      ]);

      expect(
        merged.single.isLauncher,
        isTrue,
        reason: '合併後漏掉 isLauncher，啟動器就會漏網跑到第一名',
      );
    });
  });

  group('桌面啟動器不算睡眠干擾源', () {
  });

  group('就寢時刻（lights_out_at）在畫面上', () {



  });

  group('上床／下床標記會影響上傳（按鈕本身在 home_screen_test）', () {
    _FakeUsageStats detected() => _FakeUsageStats(
          const UsageStatsResult(UsageStatsStatus.ok, apps: [
            AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 95),
          ]),
          lightsOutResult: LightsOutResult(
            LightsOutStatus.ok,
            at: DateTime(2026, 9, 6, 23, 30),
            quietMinutes: 400,
          ),
        );

    testWidgets('按過的標記要送給後端', (tester) async {
      final kv = InMemoryKeyValueStore();
      final store = BedMarkStore(kv);
      await store.markStart(DateTime.now().subtract(const Duration(hours: 8)));
      await store.markEnd(DateTime.now());

      final stub = _StubUploader(const NightlyUploadResult(
        NightlyUploadStatus.ok,
        date: '2026-09-07',
        adherenceMinutes: 0,
        isLate: false,
      ));
      await pumpReport(tester, detected(), uploader: stub, bedMarks: store);

      expect(stub.received?.isComplete, isTrue,
          reason: '按了卻沒送上去，後端就算不出臥床時間');
      // 上傳成功之後要清掉，否則同一對會被算進第二晚
      expect(await kv.getString(kBedStartKey), isNull);
    });

    testWidgets('⚠️ 反向對照：沒按按鈕**不得**擋住上傳', (tester) async {
      // 這一條擋的是「不按就沒有資料」那種實作。忘記按按鈕只該少掉
      // 臥床時間，不該讓整晚的 lights_out_at 也上傳不了。
      final stub = _StubUploader(const NightlyUploadResult(
        NightlyUploadStatus.ok,
        date: '2026-09-07',
        adherenceMinutes: 12,
        isLate: false,
      ));
      final sync = await pumpReport(tester, detected(), uploader: stub);

      expect(stub.received, isNotNull, reason: '照樣要上傳');
      expect(stub.received!.hasStart, isFalse, reason: '只是沒有標記而已');
      expect(sync.batch?.current.adherenceMinutes, 12,
          reason: '達成度照樣算得出來（照抄後端）');
    });

    testWidgets('上傳失敗、又沒進佇列 → **不要**清掉標記', (tester) async {
      // 後端沒開是 demo 的常態。清掉等於把使用者早上按的那一下弄丟。
      // ⚠️ 判準是「後端真的收下了」。下面兩條測的是另外兩種
      //    「看起來成功、其實還沒落地」的情況。
      final kv = InMemoryKeyValueStore();
      final store = BedMarkStore(kv);
      await store.markStart(DateTime.now().subtract(const Duration(hours: 8)));
      await store.markEnd(DateTime.now());

      final stub = _StubUploader(
          const NightlyUploadResult(NightlyUploadStatus.failed, error: 'boom'));
      await pumpReport(tester, detected(), uploader: stub, bedMarks: store);

      expect(await kv.getString(kBedStartKey), isNotNull);
      expect(await kv.getString(kBedEndKey), isNotNull);
    });

    testWidgets('⚠️ 上傳成功但後端沒收下標記時，也不准清掉', (tester) async {
      // ═══════════════════════════════════════════════════════════════
      // 這是 2026-09-10 真的掉了一次資料的那個情境。
      // ═══════════════════════════════════════════════════════════════
      // `main.py` 的 `same_night` 在 bed_start 屬於的夜晚與 lights_out
      // 判定的夜晚不一致時，**靜靜丟掉整組標記，但仍然回 201**。
      // 那條判斷本身是對的（曾把 09-07 03:36 的標記寫進 09-06 那一列，
      // 算出 −1282 分鐘），但它讓「上傳成功」與「標記存下來了」變成兩件事。
      //
      // → 判準必須是 `marksStored`（後端回應有沒有帶回那兩個時刻）。
      final kv = InMemoryKeyValueStore();
      final store = BedMarkStore(kv);
      await store.markStart(DateTime.now().subtract(const Duration(hours: 8)));
      await store.markEnd(DateTime.now());

      final stub = _StubUploader(
        const NightlyUploadResult(
          NightlyUploadStatus.ok,
          date: '2026-09-01',
          adherenceMinutes: 12,
          isLate: true,
        ),
        acceptsMarks: false, // ← 後端丟掉了，但照樣回 201
      );
      await pumpReport(tester, detected(), uploader: stub, bedMarks: store);

      expect(stub.received?.isComplete, isTrue, reason: '有送出去');
      expect(await kv.getString(kBedStartKey), isNotNull,
          reason: '後端沒收下就清掉，那一晚就永遠回不來了');
      expect(await kv.getString(kBedEndKey), isNotNull);
    });

    testWidgets('⚠️ 送出去的是上一晚的待送那一對 → 只清待送格，今晚剛按的開始要留著', (tester) async {
      // 情境（2026-09-09 真的發生過）：早上沒開 App、晚上又按了下一晚的
      // 「開始」。上一晚那一對被搬進待送格，這一次上傳送的是它。
      // 上傳成功之後**只能清待送格**——用 clear() 的話會把使用者
      // 今晚剛按的「開始」一起刪掉，而畫面上不會有任何跡象。
      //
      // ⚠️ 這一條是變異測試補出來的：主線只在儲存層（bed_marks_test）
      //    測了 clearPending 本身，畫面層「送哪一格就清哪一格」沒有人守。
      final kv = InMemoryKeyValueStore();
      final store = BedMarkStore(kv);
      final now = DateTime.now();
      await store.markStart(now.subtract(const Duration(hours: 20)));
      await store.markEnd(now.subtract(const Duration(hours: 12)));
      await store.markStart(now.subtract(const Duration(minutes: 5))); // 今晚

      final stub = _StubUploader(const NightlyUploadResult(
        NightlyUploadStatus.ok,
        date: '2026-09-01',
        adherenceMinutes: 12,
        isLate: true,
      ));
      await pumpReport(tester, detected(), uploader: stub, bedMarks: store);

      expect(stub.received?.isComplete, isTrue, reason: '送的是待送格那一對');
      expect(await kv.getString(kBedPendingStartKey), isNull,
          reason: '後端收下了，待送格要清');
      expect(await kv.getString(kBedStartKey), isNotNull,
          reason: '今晚剛按的開始不能被一起刪掉');
    });

    testWidgets('上傳失敗、這一晚進了離線佇列 → 本機標記也要**保留**', (tester) async {
      // ⚠️ 上一版的判準是「進佇列就算安全落地、可以清」。主線補上
      //    same_night 之後那個理由不成立了，而且會在補送被後端退回時
      //    把那一對弄丟（佇列裡的被退回、本機的已經清掉）。
      //    只有後端真的收下才清——這一條把它釘住。
      final kv = InMemoryKeyValueStore();
      final store = BedMarkStore(kv);
      await store.markStart(DateTime.now().subtract(const Duration(hours: 8)));
      await store.markEnd(DateTime.now());

      final stub = _StubUploader(
        const NightlyUploadResult(NightlyUploadStatus.failed, error: 'boom'),
        queued: true,
      );
      await pumpReport(tester, detected(), uploader: stub, bedMarks: store);

      expect(stub.received?.isComplete, isTrue, reason: '標記要跟著進佇列');
      expect(await kv.getString(kBedStartKey), isNotNull,
          reason: '還沒有任何一邊確認收下，不能清');
      expect(await kv.getString(kBedEndKey), isNotNull);
    });

    testWidgets('睡前 App 照存（Phone down 詳細頁的 Before bed 讀這一份）', (tester) async {
      final pre = PreBedResult(
        lightsOutAt: DateTime(2026, 9, 6, 23, 30),
        apps: const [AppUsage(packageName: 'com.a', appName: 'Threads', minutes: 20)],
      );
      final usage = _FakeUsageStats(
        const UsageStatsResult(UsageStatsStatus.ok),
        lightsOutResult: LightsOutResult(LightsOutStatus.ok,
            at: DateTime(2026, 9, 6, 23, 30), quietMinutes: 400),
        preBedResult: pre,
      );
      final sync = await pumpReport(tester, usage);
      expect(sync.preBed, same(pre));
    });
  });
}
