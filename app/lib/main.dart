import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/assistant_screen.dart';
import 'theme/app_accent.dart';
import 'screens/rewards_screen.dart';
import 'screens/bedtime_guard_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/friend_sharing_screen.dart';
import 'screens/health_connect_screen.dart';
import 'screens/home_screen.dart';
import 'services/pet_choice.dart';
import 'services/start_sleep_requests.dart';
import 'widgets/entry_intro.dart';
import 'widgets/moon_nav_bar.dart';
import 'widgets/tab_switcher.dart';
import 'screens/welcome_flow.dart';
import 'screens/log_in_screen.dart';
import 'services/login_service.dart';
import 'services/plan_goals.dart';
import 'widgets/plan_goal_picker.dart' show addGoalHabits;
import 'services/usage_stats.dart';
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
import 'services/morning_rating.dart';
import 'services/morning_report.dart';
import 'services/key_value_store.dart';
import 'services/bed_marks.dart';
import 'models/sleep_session.dart';
import 'widgets/data_status_section.dart';
import 'services/nightly_sync.dart';
import 'widgets/sleep_dial.dart';
import 'services/alarm.dart';
import 'screens/insights_screen.dart';
import 'services/nightly_uploader.dart';
import 'services/notification_service.dart';
import 'services/pending_nightly.dart';
import 'services/phone_model.dart';
import 'services/plan_reminders.dart';
import 'services/sleep_plan.dart';
import 'services/journey_service.dart';
import 'services/latest_night.dart';
import 'services/sleep_repository.dart';
import 'screens/plan_screen.dart';
import 'widgets/today_plan_card.dart';
import 'services/user_settings.dart';

void main() {
  runApp(const SonnapApp(entryAnimation: true));
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

  /// 測試用注入點。null = 自己建一個。
  /// ⚠️ 存在的理由是「打開 App、回到前景都要跑一次上傳」只在 [MainPage] 裡接得起來，
  /// 漏接了不會報錯——只是昨晚沒上傳（`nightly_trigger_test.dart` 守著）。
  final NightlySync? nightly;

  /// 測試用注入點。null = 真的手機使用權限與通知權限。
  final WelcomePermissions? welcomePermissions;

  /// 進場動畫（2026-11-22，`widgets/entry_intro.dart`）。只有 `main()` 打開；
  /// 測試預設關，不然每一條都要多等兩秒、而且播的時候點不到東西。
  final bool entryAnimation;

  /// email＋密碼登入（2026-11-22）。測試注入假的；null＝照建置參數（有後端就打真的）。
  final LoginApi? loginApi;

  const SonnapApp({
    super.key,
    this.loginApi,
    this.store,
    this.accounts,
    this.reminders,
    this.guard,
    this.health,
    this.nightly,
    this.welcomePermissions,
    this.entryAnimation = false,
  });

  @override
  Widget build(BuildContext context) {
    // 主題色換了整個 App 重畫；App 內的減少動態效果疊在系統設定上（2026-11-22 Q5）
    return ValueListenableBuilder<AccentTheme>(
      valueListenable: AppLook.accent,
      builder: (context, accent, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: sonnapTheme(accent),
      builder: applyReduceMotion,
      home: MainPage(
        store: store,
        accounts: accounts,
        reminders: reminders,
        guard: guard,
        health: health,
        nightly: nightly,
        welcomePermissions: welcomePermissions,
        entryAnimation: entryAnimation,
        loginApi: loginApi,
      ),
    ),
    );
  }
}

class MainPage extends StatefulWidget {
  final KeyValueStore? store;
  final AccountService? accounts;
  final ReminderScheduler? reminders;
  final GuardPlatform? guard;
  final HealthPlatform? health;
  final NightlySync? nightly;

  /// 第一次登入流程的權限那一頁（測試注入假的）。
  final WelcomePermissions? welcomePermissions;

  /// 進場動畫（見 [SonnapApp.entryAnimation]）。
  final bool entryAnimation;

  /// 見 [SonnapApp.loginApi]。
  final LoginApi? loginApi;

  const MainPage({
    super.key,
    this.loginApi,
    this.store,
    this.accounts,
    this.reminders,
    this.guard,
    this.health,
    this.nightly,
    this.welcomePermissions,
    this.entryAnimation = false,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  /// 偵測昨晚幾點放下手機 → 上傳 → 問挑戰（2026-11-19 從舊 Insights 頁搬到 App 層）。
  /// ⚠️ 一打開、每次回到前景都跑，**跟停在哪一頁無關**——漏跑不會報錯，只是昨晚沒上傳。
  late final NightlySync _nightly = widget.nightly ??
      NightlySync(
        bedMarks: BedMarkStore(widget.store ?? const PlatformKeyValueStore()),
      );

  /// 上傳完再同步一次 Journey：這一晚可能是第 3 天準時，後端剛把目標換成下一站。
  void _runNightly() => unawaited(() async {
        await _nightly.run(
          uploader: _uploader,
          challengesService: _challenges,
          homeService: _home,
        );
        await _syncJourney();
      }());

  /// 設定頁「Data」那一段的來源清單（打包檔或後端那一份的 data_sources）。
  late final Future<SleepSession> _sessionForData = _repository.load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 從系統設定開完使用權限回來、或隔天早上打開，都要重跑一次
    // 起床目標先送：POST /nightly 存的是當晚的目標快照，後端要先知道新的目標。
    if (state == AppLifecycleState.resumed && _account != null) {
      _latest.refresh();
      unawaited(() async {
        await _syncJourney();
        await _syncWake();
        _runNightly();
      }());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intro.dispose();
    _latest.dispose();
    // 注入的那一份由測試自己管
    if (widget.nightly == null) _nightly.dispose();
    super.dispose();
  }

  int currentIndex = 0;

  /// 下一次換分頁要不要滑（Replay welcome 降落時要立刻停在首頁，不滑）。
  bool _tabAnimate = true;

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
  /// 睡眠計畫（2026-11-19）：自己勾的習慣，只存在手機上。
  late final PlanStore _plan = PlanStore.shared =
      PlanStore(widget.store ?? const PlatformKeyValueStore())
        // Habits 徽章：那一天勾了幾條／總共幾條送後端（只有數字）。沒有後端就不送。
        ..onDaySummary = (day, checked, total) {
          _game?.postHabitDay(day, checked, total);
        };
  final PlanReminderScheduler _planReminders = const PlatformPlanReminderScheduler();

  Future<TimeOfDay> _wakeNow() =>
      AlarmSettingsStore(widget.store ?? const PlatformKeyValueStore()).wakeTime(targetBedtime);

  /// 有任何一條開了提醒才重排（開 App 時；就寢或起床改了也要，提醒跟著作息走）。
  Future<void> _syncPlanReminders() async {
    if (!_plan.loaded) await _plan.load();
    if (!_plan.items.any((i) => i.notify)) return;
    await syncPlanReminders(_planReminders, _plan.items,
        now: DateTime.now(), bedtime: targetBedtime, wake: await _wakeNow());
  }

  void _openPlan() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanScreen(
          plan: _plan,
          nightly: _nightly,
          bedtime: targetBedtime,
          alarmSettings: AlarmSettingsStore(widget.store ?? const PlatformKeyValueStore()),
          alarmScheduler: const PlatformAlarmScheduler(),
          reminders: _planReminders,
          onBedtimeChanged: _setBedtime,
          onWakeChanged: () => unawaited(_syncWake()),
          game: _game,
          petMood: () async => (await _latest.load()).status.petMood,
          loadChallenges: _challenges?.fetch,
          journey: _journey,
        ),
      ),
    );
  }

  late final UserSettingsStore _settings = UserSettingsStore(
    widget.store ?? const PlatformKeyValueStore(),
  );

  /// 三個畫面**共用同一個** repository 實例。
  ///
  /// 各自 `const AssetSleepRepository()` 也能跑，但那樣「這份資料是從哪來的」
  /// 會有三個答案，Insights 頁就沒辦法誠實地顯示來源。共用一個實例之後，
  /// [FallbackSleepRepository.lastSource] 才代表整個 App 的實際狀態。
  ///
  /// 沒給 `--dart-define=SONNAP_API_BASE` 時這裡回的就是 AssetSleepRepository，
  /// 行為與加這一層之前完全相同。
  final SleepRepository _repository = buildSleepRepository();

  /// 首頁、助理頁、計畫頁的「最近一晚」：打包檔＋`/home` 最新那一晚（2026-11-22，latest_night.dart）。
  /// 三頁共用這一個；回到前景、關掉早晨報告之後重讀。設定頁「Data」照舊看 [_repository]。
  late final LatestNightRepository _latest = LatestNightRepository(
    base: _repository,
    fetchNight: (date) async => await _morningReport?.fetchNight(date),
  );

  /// 這台裝置代表誰。App 啟動時解析一次。
  ///
  /// ⚠️ **null 不等於「沒身分」**——它代表「還在解析」。兩者混在一起的話，
  /// 第一幀就會閃過一次問暱稱的畫面，然後在解析完成後又消失。
  AccountStatus? _account;

  late final AccountService _accounts =
      widget.accounts ??
      AccountService(
        baseUrl: ApiSleepRepository.configuredBaseUrl,
        store: widget.store ?? const PlatformKeyValueStore(),
      );

  /// email＋密碼登入（2026-11-22）。null＝這支 build 沒有後端。
  /// ⚠️ API 照舊用 user_id 認人：登入只是用 email＋密碼換回原本的 id。
  late final LoginApi? _loginApi = widget.loginApi ??
      (ApiSleepRepository.configuredBaseUrl.trim().isEmpty
          ? null
          : HttpLoginApi(baseUrl: ApiSleepRepository.configuredBaseUrl));

  AccountStorage get _accountStorage => AccountStorage(widget.store ?? const PlatformKeyValueStore());

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
      phoneModel: readPhoneModel,
      // ⚠️ 有了這個，連不到後端的那一晚才不會永久消失（偵測視窗是往回
      //    24 小時的滑動視窗，隔天就算不出來了）。理由見 PendingNightlyStore。
      pending: PendingNightlyStore(
        widget.store ?? const PlatformKeyValueStore(),
      ),
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

  /// Insights 的 Week／Month／Year 要一整年（2026-11-19）：同一支 `/insights`，多要幾天、多等一點。
  /// Day 分頁點開的一週詳細頁也讀這一份。
  CameraInsightsService? get _insightsYear {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return CameraInsightsService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
      days: 365,
      timeout: const Duration(seconds: 8),
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
  /// 早晨報告讀 `/home?date=`。與 [_home] 同一個理由依 [_account] 重建。
  MorningReportService? get _morningReport {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return MorningReportService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  /// 起床自評送後端。與 [_morningReport] 同一個理由依 [_account] 重建。
  RestedService? get _rested {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return RestedService(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

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
          : WearableUploader(
              baseUrl: baseUrl,
              identity: ResolvedUserIdentity(_account?.userId),
            ),
    );
  }

  void _openHealth() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HealthConnectScreen(controller: _healthSync),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 計畫頁開始／停止 Journey、或同步拿到新的一站 → 目標、鬧鐘、提醒跟著換
    _journey.addListener(() => unawaited(_applyJourney()));
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
    // Journey 先：這一站就是目標，後端可能已經換站了，要先換好再送起床目標
    await _syncJourney();
    // 排在 _runNightly 前面：POST /nightly 存的是當晚的起床目標快照。
    await _syncWake();
    unawaited(_syncPlanReminders());
    // ⚠️ 排在帳號之後（要 user_id 才送得出去），而且不 await、不問授權：
    //    沒授權就什麼都不做，授權只在設定頁使用者按了按鈕才問。
    unawaited(_healthSync.sync());
    // 要 user_id 才傳得出去，所以排在帳號之後
    _runNightly();
  }

  Future<void> _restoreSettings() async {
    // 選的寵物（小狗／貓，只存在手機上）：讀回來，首頁寵物插槽跟著換
    await PetChoice.load(widget.store ?? const PlatformKeyValueStore());
    await AppLook.load(widget.store ?? const PlatformKeyValueStore());
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BedtimeGuardScreen(controller: _guard, bedtime: targetBedtime),
      ),
    );
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
      final canPost = await _reminder.sync(
        on: reminderOn,
        bedtime: targetBedtime,
      );
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

  /// Journey（睡眠計畫，2026-11-19）。整個 App 一份，計畫頁與首頁小卡都聽它。
  late final JourneyController _journey =
      JourneyController(store: widget.store ?? const PlatformKeyValueStore());

  /// 問後端現在第幾站（後端順便重算、需要就換站）。連不到就留著上一份。
  Future<void> _syncJourney() async {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    final userId = _account?.userId;
    if (baseUrl.isEmpty || userId == null || userId.isEmpty) return;
    _journey.api = HttpJourneyApi(baseUrl: baseUrl, identity: ResolvedUserIdentity(userId));
    await _journey.refresh();
  }

  /// **這一站就是目標**（使用者定 Q2）：就寢、鬧鐘的起床、提醒、守門都換成這一站。
  /// 後端那邊已經換好了，這裡只是讓手機跟上。停掉的 Journey 不碰（目標留在停下的那一站）。
  Future<void> _applyJourney() async {
    final j = _journey.journey;
    final cur = j?.current;
    if (j == null || cur == null || j.status == JourneyStatus.stopped) return;
    final alarm = AlarmSettingsStore(widget.store ?? const PlatformKeyValueStore());
    final wake = await alarm.wakeTime(targetBedtime);
    if (wake != cur.wake) {
      await alarm.save(wake: cur.wake, enabled: await alarm.enabled());
    }
    if (cur.bedtime != targetBedtime) {
      await _setBedtime(cur.bedtime); // 裡面會送起床目標、重排提醒
    } else if (wake != cur.wake) {
      await _syncWake();
      unawaited(_syncPlanReminders());
    }
  }

  /// 補送目標起床時間（睡眠計畫的「準時起床」要在後端判）。
  ///
  /// 送的是**畫面上看到的那一個**：轉盤沒設過時是就寢 + 8 小時
  /// （`defaultWakeTime`），那也是使用者在 Plan 頁看到的起床時間。
  /// 只在跟上次成功送出去的不同時才發請求（同 [_syncBedtime]）。
  Future<void> _syncWake() async {
    final userId = _account?.userId;
    if (userId == null || userId.isEmpty) return;
    final wake = await AlarmSettingsStore(widget.store ?? const PlatformKeyValueStore())
        .wakeTime(targetBedtime);
    final hhmm = formatBedtime(wake.hour, wake.minute);
    if (await _settings.syncedWake() == hhmm) return;
    final ok = await _accounts.updateTargetWake(userId: userId, targetWake: hhmm);
    if (ok) await _settings.markWakeSynced(hhmm);
  }

  Future<void> _resolveAccount() async {
    final status = await _accounts.resolve();
    if (!mounted) return;
    setState(() => _account = status);
    // 冷啟動的短版進場動畫（第一次登入的人改走長版，在按 Let's go 的時候）。只播一次。
    if (widget.entryAnimation && !_introPlayed && status.state != AccountState.needsOnboarding) {
      _introPlayed = true;
      _intro.play();
    }
    // 建置參數只帶 id，暱稱要另外向後端拿（不擋啟動）
    if (status.state == AccountState.buildTime) {
      final named = await _accounts.refreshBuildTimeName(status);
      if (!mounted || named.displayName == _account?.displayName) return;
      setState(() => _account = named);
    }
  }

  /// 建帳號（帶目前的目標就寢時間）。成功回新的狀態，**不切畫面**：第一次登入流程要先停在完成頁，
  /// 按了 Let's go 才換成這個帳號（[_enterApp]）。
  Future<AccountStatus?> _createAccount(String displayName) async {
    final hh = targetBedtime.hour.toString().padLeft(2, '0');
    final mm = targetBedtime.minute.toString().padLeft(2, '0');
    final status = await _accounts.createAccount(
      displayName: displayName,
      targetBedtime: '$hh:$mm',
    );
    if (status == null) return null;
    // ⚠️ POST /users 已經把這個目標帶過去了，所以直接記成「已同步」。
    //    少了這一行，下次開 App 會白白再 PATCH 一次同樣的值。
    await _settings.markSynced('$hh:$mm');
    return status;
  }

  /// 第一次登入流程走完時建好的帳號；null＝沒建（跳過暱稱或連不到後端）。
  AccountStatus? _pendingAccount;

  late final WelcomePermissions _welcomePermissions =
      widget.welcomePermissions ?? _AppWelcomePermissions(const UsageStatsService(), _reminder.scheduler);

  /// 存作息（就寢走 [_setBedtime]：存手機、送後端、重排提醒；起床存手機，有帳號就 PATCH）。
  Future<void> _saveSchedule(TimeOfDay bed, TimeOfDay wake) async {
    await _setBedtime(bed);
    final alarm = AlarmSettingsStore(widget.store ?? const PlatformKeyValueStore());
    await alarm.save(wake: wake, enabled: await alarm.enabled());
  }

  /// 想改善什麼：記下選了什麼（跳過也算問過了，計畫頁就不會再自己跳出來），勾著的加進計畫。只存在手機上。
  Future<void> _saveGoals(WelcomeResult r) async {
    await PlanGoalsStore(widget.store ?? const PlatformKeyValueStore()).save(r.goals);
    if (!_plan.loaded) await _plan.load();
    await addGoalHabits(_plan, r.habits);
  }

  /// 第一次登入流程（Q12）：作息先存，最後才一次建帳號。送不出去時回那句話給完成頁照實說。
  Future<String?> _finishWelcome(WelcomeResult r) async {
    await _saveSchedule(r.bedtime, r.wake);
    await _saveGoals(r);
    final name = r.name;
    if (name == null) return null;
    _pendingAccount = await _createAccount(name);
    final pending = _pendingAccount;
    if (pending == null) {
      return "We couldn't reach Sonnap's server, so your nickname wasn't saved. "
          "You can still use Sonnap, and we'll ask again next time.";
    }
    // 設登入那一步填了：帳號建好才送（同暱稱，Q12）。送不出去不影響帳號，設定頁還能再設。
    final email = r.email, password = r.password, api = _loginApi;
    if (email != null && password != null && api != null && pending.userId != null) {
      final out = await api.setUp(pending.userId!, email, password);
      if (!out.isOk) {
        return "Your account is ready, but your login wasn't saved: ${out.problem} "
            'You can set it up later in Settings.';
      }
    }
    return null;
  }

  /// 歡迎頁的 I already have an account：email＋密碼 → 原本的帳號，直接進 App（不走後面幾頁）。
  Future<void> _openLogIn() async {
    final api = _loginApi;
    if (api == null) return;
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => LogInScreen(onLogIn: (email, password) async {
        final out = await api.logIn(email, password);
        if (!out.isOk) return out.problem;
        await _adoptLogin(out.value!);
        return null;
      }),
    ));
  }

  /// 登入成功：存成這台手機的帳號，**採用後端存的目標就寢／起床**並記成已同步——
  /// 新手機上的是預設值，不採用的話 [_syncBedtime]／[_syncWake] 會把預設值 PATCH 回去蓋掉。
  Future<void> _adoptLogin(LoggedIn r) async {
    final status = await _accountStorage.adopt(r);
    final store = widget.store ?? const PlatformKeyValueStore();
    final bed = parseBedtime(r.targetBedtime);
    if (bed != null) {
      final hhmm = formatBedtime(bed.hour, bed.minute);
      await _settings.saveBedtime(hhmm);
      await _settings.markSynced(hhmm);
    }
    final wake = parseBedtime(r.targetWake);
    if (wake != null) {
      final alarm = AlarmSettingsStore(store);
      await alarm.save(wake: TimeOfDay(hour: wake.hour, minute: wake.minute), enabled: await alarm.enabled());
      await _settings.markWakeSynced(formatBedtime(wake.hour, wake.minute));
    }
    if (!mounted) return;
    setState(() {
      if (bed != null) targetBedtime = TimeOfDay(hour: bed.hour, minute: bed.minute);
      _account = status;
      currentIndex = 0;
    });
    _syncReminder();
    _syncGuard();
    if (widget.entryAnimation && !_introPlayed) {
      _introPlayed = true;
      _intro.play();
    }
  }

  /// 設定頁的 Log out：清掉手機上的帳號 → 回歡迎頁。睡眠資料在後端，再登入就回來。
  Future<void> _logOut() async {
    await _accountStorage.forget();
    if (!mounted) return;
    setState(() {
      _pendingAccount = null;
      _account = const AccountStatus(AccountState.needsOnboarding);
      currentIndex = 0;
    });
  }

  /// 完成頁的 Let's go。沒有帳號＝跟原本的「跳過」一樣（不寫進儲存，下次再問）。
  void _enterApp() {
    if (widget.entryAnimation) _beginDescent();
    final pending = _pendingAccount;
    if (pending == null) {
      _skipOnboarding();
      return;
    }
    setState(() => _account = pending);
    unawaited(_syncWake());
  }

  /// 設定頁名片的 Lv：開獎勵頁，房間裡的寵物用首頁同一份心情。
  Future<void> _openRewardsFromSettings() async {
    final game = _game;
    if (game == null) return;
    String? mood;
    try {
      mood = (await _latest.load()).status.petMood;
    } catch (_) {
      mood = null;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RewardsScreen(service: game, mood: mood)));
  }

  /// 設定頁名片的 Edit name：同 Replay welcome 的改暱稱（PATCH display_name）。回 null＝成功。
  Future<String?> _renameFromSettings(String name) async {
    final account = _account;
    if (account == null) return "We couldn't reach Sonnap's server, so your name didn't change.";
    final renamed = await _accounts.rename(account, name);
    if (renamed == null) return "We couldn't reach Sonnap's server, so your name didn't change.";
    if (mounted) setState(() => _account = renamed);
    return null;
  }

  /// 設定頁的 Replay welcome（Q11）：從頭走一次，不建帳號、不覆蓋資料；暱稱改了走 PATCH。
  Future<void> _replayWelcome() async {
    final store = widget.store ?? const PlatformKeyValueStore();
    final wake = await AlarmSettingsStore(store).wakeTime(targetBedtime);
    final locked = await journeyLocksSchedule(store);
    if (!mounted) return;
    final account = _account;
    final petKey = GlobalKey();
    Widget builder(BuildContext context) => WelcomeFlow(
        replay: true,
        donePetKey: petKey,
        animateOpening: widget.entryAnimation,
        initialName: account?.displayName,
        initialBedtime: targetBedtime,
        initialWake: wake,
        scheduleLocked: locked,
        store: store,
        permissions: _welcomePermissions,
        alreadyInPlan: {for (final i in _plan.items) i.id},
        onFinish: (r) async {
          if (!locked) {
            await _saveSchedule(r.bedtime, r.wake);
            unawaited(_syncWake());
          }
          await _saveGoals(r);
          final name = r.name;
          if (name == null || account == null || name == account.displayName) return null;
          final renamed = await _accounts.rename(account, name);
          if (renamed == null) return "We couldn't reach Sonnap's server, so your nickname didn't change.";
          if (mounted) setState(() => _account = renamed);
          return null;
        },
        onDone: () {
          // 長版：跟第一次登入一樣降落到首頁（流程頁淡出、寵物從完成頁的位置飄下來）
          if (widget.entryAnimation) {
            final from = _rectOf(petKey);
            // 直接停在首頁不滑：降落要量寵物在首頁的位置，滑到一半量到的是錯的
            setState(() {
              currentIndex = 0;
              _tabAnimate = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _tabAnimate = true);
            _intro.play(long: true, petFrom: from);
          }
          Navigator.of(context).pop();
        },
      );
    await Navigator.of(context).push(widget.entryAnimation
        ? PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (context, _, _) => builder(context),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          )
        : MaterialPageRoute<void>(builder: builder));
  }

  /// 跳過註冊。**不寫進儲存**——下次開 App 會再問一次。
  ///
  /// 刻意這樣：跳過的最常見原因是「現在連不到後端」，那是暫時的。
  /// 記成永久決定的話，使用者之後在 WiFi 底下也永遠不會被問第二次，
  /// 而且畫面上沒有任何地方看得出來他錯過了什麼。
  // ── 進場動畫（2026-11-22）──────────────────────────────────────────

  late final EntryIntro _intro = EntryIntro()..ui.addListener(_onIntroUi);
  bool _introPlayed = false;

  /// 導覽列那一組到位了沒（還沒的時候頁面延伸到導覽列後面）。
  bool _introUiDone = true;

  void _onIntroUi() {
    final done = _intro.ui.value >= 1;
    if (done != _introUiDone && mounted) setState(() => _introUiDone = done);
  }

  /// 第一次登入流程：完成頁那隻寵物（降落時從這裡飄下來）、流程本身（淡出時要留著同一份）。
  final GlobalKey _welcomePetKey = GlobalKey();
  final GlobalKey _welcomeFlowKey = GlobalKey();

  /// 按了 Let's go：流程還蓋在首頁上、正在淡出。
  bool _welcomeLeaving = false;
  bool _welcomeFading = false;

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 長版：首頁從天空降下來，第一次登入流程在上面淡出。
  void _beginDescent() {
    _introPlayed = true;
    _intro.play(long: true, petFrom: _rectOf(_welcomePetKey));
    setState(() {
      _welcomeLeaving = true;
      _welcomeFading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _welcomeFading = true);
    });
  }

  Widget _buildWelcome() => WelcomeFlow(
        key: _welcomeFlowKey,
        initialBedtime: targetBedtime,
        initialWake: defaultWakeTime(targetBedtime),
        store: widget.store ?? const PlatformKeyValueStore(),
        permissions: _welcomePermissions,
        donePetKey: _welcomePetKey,
        animateOpening: widget.entryAnimation,
        offerLogin: _loginApi != null,
        onHaveAccount: _loginApi == null ? null : _openLogIn,
        onFinish: _finishWelcome,
        onDone: _enterApp,
      );

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
    // 起床沒設過時是「就寢 + 8 小時」，就寢一改它也跟著變
    await _syncWake();
    unawaited(_syncPlanReminders());
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

  final _startSleepRequests = StartSleepRequests();

  /// 設定頁的分頁位置（2026-11-13 起不在導覽列，從首頁右上角的人像切過來）。
  /// ⚠️ 刻意留在 TabSwitcher 裡、不另開一頁：首頁與設定頁共用同一個就寢時間，
  ///    在一頁改了另一頁要立刻跟著變（bedtime_sync_test 守著）。
  static const _settingsIndex = 4;

  /// 在 `build()` 裡組而不是 `late final`——就寢時間改變時整個清單要重建，
  /// 新的值才傳得下去。TabSwitcher 每一頁有固定的 key、保留 State，
  /// 所以重建 widget 不會讓首頁重新讀一次 payload。
  /// 助理頁在第幾個分頁（Home · Friends · Insights · Assistant · Settings）。
  static const int _assistantIndex = 3;

  List<Widget> _buildPages(AccountStatus account) {
    return <Widget>[
      HomeScreen(
        displayName: account.displayName ?? kFallbackDisplayName,
        repository: _latest,
        game: _game,
        cameraInsights: _cameraInsights,
        morningReport: _morningReport,
        rested: _rested,
        // 早晨報告的 View sleep insights → Insights 分頁（第 3 個）
        onOpenInsights: () => setState(() => currentIndex = 2),
        // 導覽列中間的月亮 → 首頁照原本的流程開始睡覺；首頁右上角的人像 → 設定
        startSleepRequests: _startSleepRequests,
        intro: widget.entryAnimation ? _intro : null,
        onOpenSettings: () => setState(() => currentIndex = _settingsIndex),
        sleepStatus: _friends?.sendSleepStatus,
        planCard: TodayPlanCard(plan: _plan, wake: _wakeNow, onOpen: _openPlan, journey: _journey),
        targetBedtime: targetBedtime,
        reminderOn: reminderOn,
        onBedtimeChanged: _setBedtime,
        onReminderChanged: _setReminder,
      ),
      FriendsScreen(service: _friends, animateScenes: widget.entryAnimation),
      // Insights（2026-11-19 改版：頂端 Day／Week／Month／Year）。
      InsightsScreen(
        nightly: _nightly,
        repository: _repository,
        cameraInsights: _insightsYear,
        morningReport: _morningReport,
        game: _game,
        goalMinutes: () async {
          final wake = await const AlarmSettingsStore(PlatformKeyValueStore())
              .wakeTime(targetBedtime);
          return sleepSpan(targetBedtime, wake).inMinutes;
        },
      ),
      AssistantScreen(
        chat: _chat,
        username: account.displayName ?? kFallbackDisplayName,
        store: widget.store,
        petMood: () async => (await _latest.load()).status.petMood,
        moodChanges: _latest,
        // 打招呼那一則：今天起床的那一晚（照抄 /home 的數字，App 不呼叫 AI）
        greetingNight: _morningReport == null ? null : (date) => _morningReport!.fetchNight(date),
        // 分頁疊在 TabSwitcher 裡：不在畫面上時背景動畫要停，不然在背後一直跑
        visible: currentIndex == _assistantIndex,
      ),
      SettingsScreen(
        username: account.displayName ?? kFallbackDisplayName,
        visible: currentIndex == _settingsIndex,
        onBack: () => setState(() => currentIndex = 0),
        // 名片：寵物頭用首頁那一份心情、等級與邀請碼照抄後端（2026-11-22 設定頁改版）
        petMood: () async => (await _latest.load()).status.petMood,
        moodChanges: _latest,
        loadGame: _game == null ? null : () async => (await _game!.fetchGame()).value,
        loadInviteCode: _friends == null
            ? null
            : () async {
                final r = await _friends!.fetch();
                return r.isOk ? r.value!.myInviteCode : null;
              },
        onOpenRewards: _game == null ? null : _openRewardsFromSettings,
        onRename: ApiSleepRepository.configuredBaseUrl.trim().isEmpty ? null : _renameFromSettings,
        dataLive: () {
          final r = _repository;
          return r is FallbackSleepRepository ? r.lastSource == SleepDataSource.api : null;
        },
        initialTargetBedtime: targetBedtime,
        initialReminderOn: reminderOn,
        onBedtimeChanged: _setBedtime,
        onReminderChanged: _setReminder,
        onBedtimeGuardTap: _openGuard,
        onHealthConnectTap: _openHealth,
        onReplayWelcome: _replayWelcome,
        dataSection: FutureBuilder<SleepSession>(
          future: _sessionForData,
          builder: (context, snap) => ListenableBuilder(
            listenable: _nightly,
            builder: (context, _) => DataStatusSection(
              repository: _repository,
              nightly: _nightly,
              sources: snap.data?.dataSources ?? const [],
            ),
          ),
        ),
        // 登入（2026-11-22）：建置參數那支 APK 認的是寫死的 id，登出了下次打開還是它 → 不給登出、照實說
        loadLogin: (_loginApi == null || account.userId == null) ? null : () => _loginApi.fetch(account.userId!),
        onSetUpLogin: (_loginApi == null || account.userId == null)
            ? null
            : (email, password) async => (await _loginApi.setUp(account.userId!, email, password)).problem,
        onChangePassword: (_loginApi == null || account.userId == null)
            ? null
            : (old, password) async =>
                (await _loginApi.changePassword(account.userId!, old, password)).problem,
        onLogOut: account.state == AccountState.stored ? _logOut : null,
        logOutBlockedReason: "This test build is tied to one account, so it can't log out.",
        onFriendSharingTap: _friends == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => FriendSharingScreen(service: _friends!))),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;

    // 還在解析。⚠️ 這一格不能省——少了它，第一幀會閃過一次問暱稱的畫面
    // 然後又消失，看起來像 App 在抽搐。
    if (account == null) {
      // 進場動畫：系統啟動畫面之後直接是那片天空（不轉圈），接著降落到首頁
      if (widget.entryAnimation) {
        // 星星先不畫：接下來不管是首頁降落還是歡迎頁開場，星星都要從暗一顆顆亮起來
        return const Scaffold(backgroundColor: kEntrySkyTop, body: EntrySky(starOpacity: 0));
      }
      return const Scaffold(
        backgroundColor: Color(0xFF081326),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (account.state == AccountState.needsOnboarding) return _buildWelcome();

    final app = PopScope(
      // 在設定頁按返回 → 回首頁（設定頁不在導覽列上，沒有別的路回去）
      canPop: currentIndex != _settingsIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => currentIndex = 0);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF081326),

        // 頁面延伸到月亮凸出的那一塊後面（不然那一塊是一條底色），
        // 但內容只排到導覽列上緣為止——最底下的東西才不會被導覽列蓋住。
        body: Builder(
          builder: (context) {
            // extendBody 底下，padding.bottom＝整個導覽列的高度（含月亮凸出那塊與系統手勢列）。
            // ⚠️ 不能用 viewPadding：Scaffold 給 body 的那一份已經把系統那段拿掉了（實機量過）。
            final navHeight = MediaQuery.of(context).padding.bottom;
            return MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Padding(
                // 進場時頁面延伸到導覽列後面（導覽列還沒出來，不然底下會露一條底色）
                padding: EdgeInsets.only(
                  bottom: !_introUiDone
                      ? 0
                      : (navHeight - MoonNavBar.moonRise).clamp(0.0, double.infinity),
                ),
                // 換分頁左右滑＋視差（2026-11-22，tab_switcher.dart）；跟 TabSwitcher 一樣所有分頁一直留著
                child: TabSwitcher(
                  index: currentIndex,
                  animate: widget.entryAnimation && _tabAnimate,
                  children: _buildPages(account),
                ),
              ),
            );
          },
        ),

        // 月亮凸出導覽列上緣，頁面要延伸到導覽列後面，凸出那一塊才不會是一條底色
        extendBody: true,
        // 進場時導覽列最後從下面滑上來（沒在播時 ui＝1，原樣）
        bottomNavigationBar: ValueListenableBuilder<double>(
          valueListenable: _intro.ui,
          builder: (context, p, child) => IgnorePointer(
            ignoring: p < 1,
            child: Opacity(
              opacity: p,
              child: Transform.translate(offset: Offset(0, (1 - p) * 40), child: child),
            ),
          ),
          child: MoonNavBar(
            currentIndex: currentIndex,
            bedtime: targetBedtime, // 快到就寢時中間那顆發亮（同守門那一窗）
            onTab: (index) => setState(() => currentIndex = index),
            onMoon: () {
              // 在別的分頁按也一樣：先回首頁，起床後的報告流程從首頁接下去
              setState(() => currentIndex = 0);
              _startSleepRequests.request();
            },
          ),
        ),
      ),
    );

    if (!_welcomeLeaving) return app;
    // 第一次登入流程按了 Let's go：流程留在上面淡出（同一份，靠 GlobalKey 保住狀態）
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        app,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _welcomeFading ? 0 : 1,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 350),
            onEnd: () {
              if (mounted) setState(() => _welcomeLeaving = false);
            },
            child: _buildWelcome(),
          ),
        ),
      ],
    );
  }
}

/// 權限那一頁接到真的平台（手機使用權限＋通知）。
class _AppWelcomePermissions implements WelcomePermissions {
  final UsageStatsService usage;
  final ReminderScheduler reminders;
  const _AppWelcomePermissions(this.usage, this.reminders);

  @override
  Future<bool> hasUsageAccess() => usage.hasAccess();

  @override
  Future<void> openUsageSettings() => usage.openSettings();

  @override
  Future<void> requestNotifications() => reminders.requestPermission();
}
