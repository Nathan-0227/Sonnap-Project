import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'key_value_store.dart';

/// 助眠聲音（2026-11-12 使用者定案）。
///
/// - 三種聲音都是**原生端即時合成**的（`SleepSoundService.kt`），沒有音檔、沒有版權問題。
///   雨聲和海浪比真的錄音假一點，之後要換錄音只改原生端。
/// - 播多久、淡出多久、選了哪一種都在 Dart 決定，原生端只照做。
/// - 鬧鐘響、按 Out of bed、按 Cancel 都會停（鬧鐘那條在原生端，App 沒開著也要停）。
/// - 音量用手機側邊的音量鍵，App 裡不做滑桿。
enum SleepSound {
  rain('rain', 'Rain'),
  ocean('ocean', 'Ocean'),
  brown('brown', 'Brown noise');

  final String id;
  final String label;
  const SleepSound(this.id, this.label);

  static SleepSound fromId(String? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => rain);
}

/// 可以選播多久（分鐘）。預設 30。
const List<int> kSleepSoundMinutes = [15, 30, 60];
const int kDefaultSleepSoundMinutes = 30;

/// 最後這段時間慢慢變小聲再停——突然沒聲音可能把剛睡著的人吵醒。
const Duration kSleepSoundFade = Duration(minutes: 1);

/// 記住上次選的聲音與時間（下次直接按播放就好）。
class SleepSoundSettings {
  static const _soundKey = 'sleep_sound';
  static const _minutesKey = 'sleep_sound_minutes';

  final KeyValueStore store;
  const SleepSoundSettings(this.store);

  Future<SleepSound> sound() async =>
      SleepSound.fromId(await store.getString(_soundKey));

  Future<int> minutes() async {
    final m = int.tryParse(await store.getString(_minutesKey) ?? '');
    return kSleepSoundMinutes.contains(m) ? m! : kDefaultSleepSoundMinutes;
  }

  Future<void> save(SleepSound sound, int minutes) async {
    await store.setString(_soundKey, sound.id);
    await store.setString(_minutesKey, '$minutes');
  }
}

/// 原生端的播放器。可注入，測試換成假的。
abstract class SleepSoundPlayer {
  Future<void> play(SleepSound sound, Duration length, Duration fade);
  Future<void> stop();

  /// 正在播的話，幾點會停；沒在播回 null。
  Future<DateTime?> endsAt();
}

class PlatformSleepSoundPlayer implements SleepSoundPlayer {
  static const MethodChannel _channel = MethodChannel('sonnap/sounds');
  const PlatformSleepSoundPlayer();

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('SleepSounds: $method failed - $e');
      return null;
    } on MissingPluginException {
      return null; // 非 Android 平台，或測試環境。
    }
  }

  @override
  Future<void> play(SleepSound sound, Duration length, Duration fade) =>
      _call<void>('play', {
        'sound': sound.id,
        'lengthMillis': length.inMilliseconds,
        'fadeMillis': fade.inMilliseconds,
      });

  @override
  Future<void> stop() => _call<void>('stop');

  @override
  Future<DateTime?> endsAt() async {
    final ms = await _call<int>('endsAt');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// 睡覺畫面用的：設定＋播放器。
class SleepSoundsController {
  final SleepSoundSettings settings;
  final SleepSoundPlayer player;
  const SleepSoundsController({required this.settings, required this.player});

  /// 照記住的聲音與時間播。回傳幾點會停。
  Future<DateTime> play(DateTime now) async {
    final sound = await settings.sound();
    final minutes = await settings.minutes();
    final length = Duration(minutes: minutes);
    await player.play(sound, length, kSleepSoundFade);
    return now.add(length);
  }

  Future<void> stop() => player.stop();
}
