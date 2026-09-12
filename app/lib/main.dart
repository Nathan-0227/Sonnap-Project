import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/assistant_screen.dart';
import 'screens/bedtime_guard_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/health_connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';
import 'services/account_service.dart';
import 'services/bedtime_guard.dart';
import 'services/bedtime_reminder.dart';
import 'services/camera_insights.dart';
import 'services/challenges_service.dart';
import 'services/chat_service.dart';
import 'services/friends_service.dart';
import 'services/game_service.dart';
import 'services/health_connect.dart';
import 'services/home_service.dart';
import 'services/key_value_store.dart';
import 'services/nightly_uploader.dart';
import 'services/notification_service.dart';
import 'services/pending_nightly.dart';
import 'services/sleep_repository.dart';
import 'services/user_settings.dart';

void main() {
  runApp(const SonnapApp());
}

class SonnapApp extends StatelessWidget {
  /// 測試用注入點。null = 用真的 `sonnap/store`。
  ///
  /// ⚠️ 這兩個參數存在的理由是**設定的持久化與後端同步只在
  /// [MainPage] 裡接得起來**（那是 targetBedtime 的唯一擁有者）。
  /// 沒有注入點的話，「改了目標有沒有真的告訴後端」這條就測不到，
  /// 而它壞掉時完全沒有錯誤訊息——只是達成度拿舊目標在算。
  final KeyValueStore? store;

  /// 測試用注入點。null = 依 `SONNAP_API_BASE` 建一個真的。
  final AccountService? accounts;

  /// 測試用注入點。null = 走真的 `sonnap/notify`（AlarmManager）。
  final ReminderScheduler? reminders;

  /// 測試用注入點。null = 走真的 `sonnap/guard`（無障礙服務）。
  final GuardPlatform? guard;

  /// 測試用注入點。null = 走真的 `sonnap/health`（Health Connect）。
  final HealthPlatform? health;

  const SonnapApp({super.key, this.store, this.accounts, this.reminders, this.guard, this.health});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainPage(store: store, accounts: accounts, reminders: reminders, guard: guard, health: health),
    );
  }
}

class MainPage extends StatefulWidget {
  final KeyValueStore? store;
  final AccountService? accounts;
  final ReminderScheduler? reminders;
  final GuardPlatform? guard;
  final HealthPlatform? health;

  const MainPage({super.key, this.store, this.accounts, this.reminders, this.guard, this.health});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int currentIndex = 0;

  /// 目標就寢時間與提醒開關的**唯一擁有者**。
  ///
  /// ⚠️ **不要讓 HomeScreen 或 SettingsScreen 各自持有這兩個值。**
  /// 在此之前正是那樣：`header_card.dart` 與 `settings_screen.dart` 各存一份
  /// state、各自寫死 23:30，所以在 Settings 改完切回首頁，倒數完全沒變——
  /// 同一個設定在兩個畫面顯示互相矛盾的值，而且不會有任何錯誤訊息。
  ///
  /// 那兩個 widget 本身早就寫成受控元件了（`initial*` 參數 ＋ `onChanged`
  /// callback ＋ `didUpdateWidget`），缺的只是一個共用的擁有者，就是這裡。
  /// 所以這次修正**沒有動那兩個 widget 的內部一行**。
  ///
  /// ⚠️ **這個設定有兩份，而且會安靜地漂移。** 畫面上的倒數用這一份，
  /// 但**達成度是後端拿 `users.target_bedtime` 算的**。改完不通知後端的話，
  /// 首頁倒數到 01:00、後端還在用註冊當天填的 23:30，隔天早上使用者會收到
  /// 「比目標晚了 90 分鐘」而完全不知道那個「目標」是什麼。
  /// 所以 [_setBedtime] 一定要同時做三件事：改畫面、存本機、PATCH 後端。
  /// 完整說明見 [UserSettingsStore]。
  ///
  /// 預設值只在「使用者從來沒動過」時才用得到——存過的話 [_restoreSettings]
  /// 會蓋掉它。
  TimeOfDay targetBedtime = const TimeOfDay(hour: 23, minute: 30);
  bool reminderOn = true;

  /// 設定存在哪。⚠️ 與 [AccountService] 用同一個 `sonnap/store`
  /// （Android SharedPreferences），**不裝 shared_preferences**。
  late final UserSettingsStore _settings =
      UserSettingsStore(widget.store ?? const PlatformKeyValueStore());

  /// 三個畫面**共用同一個** repository 實例。
  ///
  /// 各自 `const AssetSleepRepository()` 也能跑，但那樣「這份資料是從哪來的」
  /// 會有三個答案，Insights 頁就沒辦法誠實地顯示來源。共用一個實例之後，
  /// [FallbackSleepRepository.lastSource] 才代表整個 App 的實際狀態。
  ///
  /// 沒給 `--dart-define=SONNAP_API_BASE` 時這裡回的就是 AssetSleepRepository，
  /// 行為與加這一層之前完全相同。
  final SleepRepository _repository = buildSleepRepository();

  /// 這台裝置代表誰。App 啟動時解析一次。
  ///
  /// ⚠️ **null 不等於「沒身分」**——它代表「還在解析」。兩者混在一起的話，
  /// 第一幀就會閃過一次問暱稱的畫面，然後在解析完成後又消失。
  AccountStatus? _account;

  late final AccountService _accounts = widget.accounts ??
      AccountService(
        baseUrl: ApiSleepRepository.configuredBaseUrl,
        store: widget.store ?? const PlatformKeyValueStore(),
      );

  /// 把偵測到的就寢時刻送去後端。
  ///
  /// ⚠️ 依 [_account] 重建：帳號是在 App 開起來之後才建立的，
  /// uploader 若在啟動時就固定住，剛註冊完的那一次上傳會用到空的身分。
  NightlyUploader? get _uploader {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return NightlyUploader(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
      // ⚠️ 有了這個，連不到後端的那一晚才不會永久消失（偵測視窗是往回
      //    24 小時的滑動視窗，隔天就算不出來了）。理由見 PendingNightlyStore。
      pending: PendingNightlyStore(widget.store ?? const PlatformKeyValueStore()),
    );
  }

  /// 攝影機的臥床時間／入睡潛伏期。與 [_uploader] 同一個理由依 [_account]
  /// 重建：帳號是在 App 開起來之後才建立的，啟動時固定住會用到空的身分。
  CameraInsightsService? get _cameraInsights {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return CameraInsightsService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// 挑戰進度的來源。與 [_uploader] 一樣依 [_account] 重建——
  /// 帳號是 App 開起來之後才建立的，固定住的話剛註冊完那一次會用到空身分。
  ChallengesService? get _challenges {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return ChallengesService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// 熬夜比率的來源。與 [_challenges] 一樣依 [_account] 重建。
  HomeService? get _home {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return HomeService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// 睡眠助理。與 [_challenges] 一樣依 [_account] 重建。
  /// ⚠️ 每問一次都會花 API 額度（後端呼叫 Claude）。
  ChatService? get _chat {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return ChatService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// 好友。與 [_challenges] 一樣依 [_account] 重建。
  FriendsService? get _friends {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return FriendsService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// 遊戲化層。與 [_challenges] 一樣依 [_account] 重建——帳號是 App
  /// 開起來之後才建立的，固定住的話剛註冊完那一次會用到空身分。
  GameService? get _game {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return GameService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// Health Connect 同步。與 [_challenges] 一樣依 [_account] 重建。
  /// 沒有後端時 uploader 是 null，同步什麼都不碰（見 [HealthSyncController.uploader]）。
  HealthSyncController get _healthSync {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    return HealthSyncController(
      platform: widget.health ?? const PlatformHealth(),
      store: widget.store ?? const PlatformKeyValueStore(),
      uploader: baseUrl.isEmpty
          ? null
          : WearableUploader(baseUrl: baseUrl, identity: ResolvedUserIdentity(_account?.userId)),
    );
  }

  void _openHealth() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HealthConnectScreen(controller: _healthSync),
    ));
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// ⚠️ **[_syncBedtime] 一定要排在 [_resolveAccount] 後面。**
  ///
  /// 它需要 `_account.userId` 才發得出 PATCH；排在前面的話 userId 還是
  /// null，補送直接 return——結果是**上次沒同步成功的目標永遠補不回來**，
  /// 而畫面上一切正常（本機那份是對的，錯的是後端在拿舊目標算達成度）。
  ///
  /// [_restoreSettings] 的位置則不影響正確性：[_syncBedtime] 讀的是
  /// **儲存**而不是記憶體裡的 [targetBedtime]，所以它拿到的一定是使用者
  /// 存下來的值。放在最前面只是為了讓畫面早一幀顯示正確的倒數。
  /// （這一段原本寫成「順序反了會拿預設值去蓋掉使用者的設定」，
  /// 是錯的——變異測試把它抓出來了：那個變異不會讓任何測試變紅，
  /// 因為那條路徑根本不存在。）
  Future<void> _start() async {
    // ⚠️ **讀本機設定不能擋住 App 啟動。** 畫面在 `_account == null`
    //    時只有一個轉圈圈，而 `_account` 是 [_resolveAccount] 設的。
    //    把 [_restoreSettings] 寫成 `await` 排在它前面的話，`sonnap/store`
    //    一旦沒有回應（原生端沒註冊、非 Android 平台、widget test），
    //    整個 App 就永遠停在轉圈圈上——實測 widget test 裡那個
    //    MethodChannel **從來不會完成**，症狀就是 HomeScreen 根本不存在。
    //    這與 [PlatformKeyValueStore] 自己寫的紀律是同一條：讀不到最壞
    //    的後果是退回預設值，不該讓整個 App 開不起來。
    final restore = _restoreSettings();
    await _resolveAccount();
    await restore;
    await _syncBedtime();
    // ⚠️ 排在帳號之後（要 user_id 才送得出去），而且不 await、不問授權：
    //    沒授權就什麼都不做，授權只在設定頁使用者按了按鈕才問。
    unawaited(_healthSync.sync());
  }

  Future<void> _restoreSettings() async {
    final stored = await _settings.load();
    if (!mounted) return;
    final parsed = parseBedtime(stored.targetBedtime);
    setState(() {
      if (parsed != null) {
        targetBedtime = TimeOfDay(hour: parsed.hour, minute: parsed.minute);
      }
      reminderOn = stored.reminderOn ?? reminderOn;
    });
    // 讀回設定之後才排提醒——排在前面的話會用預設的 23:30 排一次。
    _syncReminder(askIfMissing: true);
    _syncGuard();
  }

  /// 就寢守門。時間窗、名單、模式都在 bedtime_guard.dart（Dart 端）。
  late final BedtimeGuardController _guard = BedtimeGuardController(
    platform: widget.guard ?? const PlatformGuard(),
    store: widget.store ?? const PlatformKeyValueStore(),
  );

  /// 把守門的時間窗推給原生端。⚠️ 不 await，理由同 [_syncReminder]。
  void _syncGuard() => unawaited(_guard.push(targetBedtime));

  void _openGuard() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BedtimeGuardScreen(controller: _guard, bedtime: targetBedtime),
    ));
  }

  /// 就寢提醒。提前幾分鐘、通知寫什麼都在 bedtime_reminder.dart（Dart 端）。
  late final BedtimeReminderController _reminder = BedtimeReminderController(
    scheduler: widget.reminders ?? const PlatformReminderScheduler(),
  );

  /// 依目前的開關與目標時間重排提醒。
  ///
  /// ⚠️ **不 await。** 通知是加分項：`sonnap/notify` 沒有回應時
  ///    （非 Android、widget test）不能擋住任何東西——與讀本機設定
  ///    不能擋住 App 啟動是同一條紀律。
  /// ⚠️ askIfMissing：開 App 時如果手機沒有通知權限（Android 13+ 的預設），
  ///    要一次。提醒開關預設是開的，不問的話大部分受測者的提醒永遠不會出現，
  ///    而開關看起來是開著的。
  void _syncReminder({bool askIfMissing = false}) {
    unawaited(() async {
      final canPost = await _reminder.sync(on: reminderOn, bedtime: targetBedtime);
      if (askIfMissing && reminderOn && !canPost) {
        await _reminder.scheduler.requestPermission();
      }
    }());
  }

  /// 補送上次沒同步成功的目標就寢時間。
  ///
  /// ⚠️ 只在「本機存的」與「上次同步成功的」不同時才發請求——否則每次
  /// 開 App 都會 PATCH 一次，而後端的 `update_user` 沒有任何節流。
  Future<void> _syncBedtime() async {
    final userId = _account?.userId;
    if (userId == null || userId.isEmpty) return;

    final stored = await _settings.load();
    if (!stored.needsSync) return;

    final ok = await _accounts.updateTargetBedtime(
      userId: userId,
      targetBedtime: stored.targetBedtime!,
    );
    if (ok) await _settings.markSynced(stored.targetBedtime!);
  }

  Future<void> _resolveAccount() async {
    final status = await _accounts.resolve();
    if (!mounted) return;
    setState(() => _account = status);
  }

  Future<bool> _createAccount(String displayName) async {
    final hh = targetBedtime.hour.toString().padLeft(2, '0');
    final mm = targetBedtime.minute.toString().padLeft(2, '0');
    final status = await _accounts.createAccount(
      displayName: displayName,
      targetBedtime: '$hh:$mm',
    );
    if (status == null) return false;
    // ⚠️ POST /users 已經把這個目標帶過去了，所以直接記成「已同步」。
    //    少了這一行，下次開 App 會白白再 PATCH 一次同樣的值。
    await _settings.markSynced('$hh:$mm');
    if (!mounted) return true;
    setState(() => _account = status);
    return true;
  }

  /// 跳過註冊。**不寫進儲存**——下次開 App 會再問一次。
  ///
  /// 刻意這樣：跳過的最常見原因是「現在連不到後端」，那是暫時的。
  /// 記成永久決定的話，使用者之後在 WiFi 底下也永遠不會被問第二次，
  /// 而且畫面上沒有任何地方看得出來他錯過了什麼。
  void _skipOnboarding() {
    setState(() => _account = const AccountStatus(AccountState.noBackend));
  }

  /// ⚠️ 三件事一起做：改畫面、存本機、告訴後端。
  ///
  /// 少掉第三件，達成度就會拿舊目標去算，而畫面上看不出來（見
  /// [targetBedtime] 的說明）。PATCH 失敗**不擋使用者**——本機已經存下來，
  /// [_syncBedtime] 下次開 App 會補送。
  Future<void> _setBedtime(TimeOfDay value) async {
    if (value == targetBedtime) return;
    setState(() => targetBedtime = value);
    // ⚠️ 改了目標就要重排，否則提醒還停在舊的時間；守門也一樣，
    //    否則原生端還在守舊的時間窗（23:00 起擋，但目標已經改到 01:00）。
    _syncReminder();
    _syncGuard();

    final hhmm = formatBedtime(value.hour, value.minute);
    await _settings.saveBedtime(hhmm);
    await _syncBedtime();
  }

  Future<void> _setReminder(bool value) async {
    if (value == reminderOn) return;
    setState(() => reminderOn = value);
    // 使用者親手打開提醒 → 這是要權限的正確時機。
    if (value) unawaited(_reminder.scheduler.requestPermission());
    // ⚠️ 關掉時 sync 會 cancel——已經排好的那一則不取消的話照樣會響。
    _syncReminder();
    // 提醒開關只有本機意義，後端沒有這個欄位。
    await _settings.saveReminder(value);
  }

  /// 在 `build()` 裡組而不是 `late final`——就寢時間改變時整個清單要重建，
  /// 新的值才傳得下去。IndexedStack 依「型別 ＋ 位置」保留 State，
  /// 所以重建 widget 不會讓首頁重新讀一次 payload。
  List<Widget> _buildPages(AccountStatus account) {
    return <Widget>[
      HomeScreen(
        displayName: account.displayName ?? kFallbackDisplayName,
        repository: _repository,
        game: _game,
        targetBedtime: targetBedtime,
        reminderOn: reminderOn,
        onBedtimeChanged: _setBedtime,
        onReminderChanged: _setReminder,
      ),
      FriendsScreen(service: _friends),
      ReportScreen(
        repository: _repository,
        uploader: _uploader,
        cameraInsights: _cameraInsights,
        challenges: _challenges,
        home: _home,
      ),
      AssistantScreen(
        chat: _chat,
        username: account.displayName ?? kFallbackDisplayName,
      ),
      SettingsScreen(
        username: account.displayName ?? kFallbackDisplayName,
        initialTargetBedtime: targetBedtime,
        initialReminderOn: reminderOn,
        onBedtimeChanged: _setBedtime,
        onReminderChanged: _setReminder,
        onBedtimeGuardTap: _openGuard,
        onHealthConnectTap: _openHealth,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;

    // 還在解析。⚠️ 這一格不能省——少了它，第一幀會閃過一次問暱稱的畫面
    // 然後又消失，看起來像 App 在抽搐。
    if (account == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF081326),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7657FF)),
        ),
      );
    }

    if (account.state == AccountState.needsOnboarding) {
      return OnboardingScreen(
        onCreate: _createAccount,
        onSkip: _skipOnboarding,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF081326),

      body: IndexedStack(
        index: currentIndex,
        children: _buildPages(account),
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B2548),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFFFD96A),
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,

          onTap: (index) {
            setState(() {
              currentIndex = index;
            });
          },

          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_rounded),
              label: "Friends",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: "Insights",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_toy_rounded),
              label: "Assistants",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: "Settings",
            ),
          ],
        ),
      ),
    );
  }
}