import 'package:flutter/foundation.dart';

/// 這台裝置上的資料算誰的。
///
/// ═══════════════════════════════════════════════════════════════════
/// 為什麼需要這一層
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端是**多使用者**的：`POST /nightly`、`GET /home`、`GET /challenges`
/// 每一個都要 `user_id`。而 App 在此之前完全沒有「使用者」的概念——
/// 它只讀一份打包好的 JSON，從來不需要知道你是誰。
///
/// 這個介面就是那個缺口，而且刻意做成**一個接縫**：
///
/// | 實作 | 身分從哪來 | 用在哪 |
/// |---|---|---|
/// | [BuildTimeUserIdentity] | 建置參數 `--dart-define` | demo。一支 APK = 一個人 |
/// | （待做）本機帳號 | 首次開啟 `POST /users`，存在手機上 | D2。一支 APK 給所有人 |
///
/// 換實作時**上層一行都不用改**，與 `SleepRepository` 在 asset / API
/// 之間切換是同一個手法。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ user_id 本身就是憑證
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端是暱稱制免註冊，沒有密碼——**誰拿到這個 id 就能讀寫那個人的資料**
/// （`main.py` 的 `create_user` docstring 寫得很清楚）。所以：
///
/// - 不要把它印進 logcat（裝了 adb 就讀得到）
/// - 不要放進任何會外流的檔案
/// - 上架前必須先補認證，這是已知的技術債不是疏漏
abstract class UserIdentity {
  /// 目前的 `user_id`。**null 代表還沒有身分**，這時候不該上傳任何東西。
  ///
  /// ⚠️ 回傳 null 與「上傳失敗」是兩件事。前者是「這支 build 沒設定身分」，
  /// 後者是「有身分但送不出去」——畫面上要講不同的話，解法也不同。
  Future<String?> currentUserId();
}

/// 建置時用 `--dart-define` 帶入固定的 id。
///
/// ```
/// flutter build apk --dart-define=SONNAP_USER_ID=00000000-...-000000000001
/// ```
///
/// 那個測試用的 id 由 `migrate_garmin_to_db.py` 的 `RESEARCHER_USER_ID`
/// 產生，是固定值，跑過 migration 的資料庫裡就有。
///
/// ⚠️ **這支 APK 裝到誰的手機上，資料都算同一個人。** demo 夠用（demo 是
/// 一個人展示），D2 不行（十來個同學要十來份客製 APK）。那時候換成
/// 本機帳號的實作即可。
class BuildTimeUserIdentity implements UserIdentity {
  static const String defineKey = 'SONNAP_USER_ID';
  static const String configured =
      String.fromEnvironment(defineKey, defaultValue: '');

  /// 測試要塞值時用；正式路徑一律走 [configured]。
  final String? overrideId;

  const BuildTimeUserIdentity({this.overrideId});

  @override
  Future<String?> currentUserId() async {
    final value = (overrideId ?? configured).trim();
    return value.isEmpty ? null : value;
  }
}

/// 依建置參數決定身分從哪來。
///
/// 沒給 `--dart-define=SONNAP_USER_ID` 就回傳一個永遠給 null 的身分，
/// 行為與加上這一層之前**完全相同**——「什麼都沒設定」仍然是那條最穩、
/// demo 一定跑得起來的路徑，與 `buildSleepRepository()` 同一個原則。
UserIdentity buildUserIdentity({String? userIdOverride}) {
  final identity = BuildTimeUserIdentity(overrideId: userIdOverride);
  final configured = (userIdOverride ?? BuildTimeUserIdentity.configured).trim();
  // ⚠️ 只印「有沒有」，不印值本身——它是憑證，而 logcat 裝了 adb 就讀得到。
  debugPrint(
    'UserIdentity: ${configured.isEmpty ? "not configured "
        "(pass --dart-define=${BuildTimeUserIdentity.defineKey}=...)" : "configured"}',
  );
  return identity;
}
