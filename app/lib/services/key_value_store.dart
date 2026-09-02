import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 存一點點東西在這台裝置上，跨重開機還在。
///
/// 抽成介面是為了讓測試不必碰原生端——widget test 跑在 Dart VM 上，
/// MethodChannel 沒有另一頭。
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// 走 `sonnap/store` channel，另一頭是 Android 的 SharedPreferences。
///
/// ## 為什麼不裝 shared_preferences 套件
///
/// 只需要存一個字串（user_id），而 `pubspec.yaml` 目前只有 lottie 與 intl。
/// 加一個套件會連帶動到 linux / macos / windows 三個平台的
/// generated_plugin_registrant——這個專案不出那三個平台，那些改動全是雜訊。
/// 而 MethodChannel 的基礎建設這個 App 已經有了（`sonnap/usage`）。
///
/// 同一個取捨也出現在 [ApiSleepRepository] 用 `dart:io` 而不裝
/// `package:http`、`ai/llm_client.py` 用 `urllib` 而不裝 SDK。
///
/// ⚠️ **失敗時一律當成「沒有值」而不是拋例外。** 這個儲存放的是
/// user_id，讀不到最壞的後果是「重新建一個帳號」；為了它讓整個 App
/// 開不起來完全不成比例。
class PlatformKeyValueStore implements KeyValueStore {
  static const MethodChannel _channel = MethodChannel('sonnap/store');

  const PlatformKeyValueStore();

  @override
  Future<String?> getString(String key) async {
    try {
      return await _channel.invokeMethod<String>('getString', {'key': key});
    } on PlatformException catch (e) {
      debugPrint('KeyValueStore: getString failed - $e');
      return null;
    } on MissingPluginException {
      // 非 Android 平台，或測試環境。
      return null;
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    try {
      await _channel.invokeMethod<void>(
        'setString',
        {'key': key, 'value': value},
      );
    } on PlatformException catch (e) {
      debugPrint('KeyValueStore: setString failed - $e');
    } on MissingPluginException {
      // 存不進去就是存不進去。呼叫端下次會再問一次，
      // 使用者最多是再取一次暱稱——比整個 App 掛掉好。
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _channel.invokeMethod<void>('remove', {'key': key});
    } on PlatformException catch (e) {
      debugPrint('KeyValueStore: remove failed - $e');
    } on MissingPluginException {
      // 同上
    }
  }
}

/// 測試用。也是非 Android 平台的退路。
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values;

  InMemoryKeyValueStore([Map<String, String>? initial])
      : _values = {...?initial};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
