import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守的是 `pre_bed_apps.dart` 那幾個**壞掉時不會報錯**的地方。
///
/// 這支永遠算得出「幾分鐘」，算錯不會拋例外、也不會有空值，
/// 只會讓睡前那張卡顯示錯的 App 或錯的時間。

InteractionEvent ev(String type, DateTime t, [String pkg = '']) =>
    InteractionEvent(timestamp: t, type: type, packageName: pkg);

void main() {
  // 上床時刻固定在 23:30，視窗預設 60 分鐘 → 22:30–23:30
  final bed = DateTime(2026, 9, 6, 23, 30);
  DateTime at(int h, int m) => DateTime(2026, 9, 6, h, m);

  group('preBedApps', () {
    test('基本切段：兩個 App 各算各的', () {
      final apps = preBedApps(
        [
          ev('resumed', at(22, 40), 'com.ig'),
          ev('paused', at(23, 0), 'com.ig'),
          ev('resumed', at(23, 0), 'com.yt'),
          ev('paused', at(23, 20), 'com.yt'),
        ],
        lightsOutAt: bed,
      );
      expect(apps.map((a) => a.packageName), ['com.ig', 'com.yt']);
      expect(apps.map((a) => a.minutes), [20, 20]);
    });

    test('沒有配對結束事件的區段要延續到上床時刻 —— 那是常態不是壞資料', () {
      // 使用者拿著手機睡著了，最後那個 App 沒有 paused。
      final apps = preBedApps(
        [ev('resumed', at(23, 0), 'com.ig')],
        lightsOutAt: bed,
      );
      expect(apps.single.packageName, 'com.ig');
      expect(apps.single.minutes, 30, reason: '23:00 → 23:30');
    });

    test('丟掉未配對的區段會少算 —— 反向對照', () {
      // 這一條是上一條的反面：如果實作只認「有 paused 的區段」，
      // 上面那個案例會回空陣列。明寫出來，免得有人「修」成那樣。
      final apps = preBedApps(
        [
          ev('resumed', at(22, 35), 'com.a'),
          ev('paused', at(22, 40), 'com.a'),
          ev('resumed', at(23, 0), 'com.ig'), // 沒有 paused
        ],
        lightsOutAt: bed,
      );
      expect(apps.length, 2, reason: '兩個都要在，不能只留有配對的那個');
      expect(apps.first.packageName, 'com.ig', reason: '30 分鐘 > 5 分鐘，排前面');
    });

    test('螢幕關閉要關掉開著的區段', () {
      // 沒有這一條，關螢幕之後到上床時刻都會被算成那個 App 在前景。
      final apps = preBedApps(
        [
          ev('resumed', at(22, 40), 'com.ig'),
          ev('screen_off', at(22, 50)),
        ],
        lightsOutAt: bed,
      );
      expect(apps.single.minutes, 10, reason: '22:40 → 22:50，不是 → 23:30');
    });

    test('區段要與視窗取交集，不是整段算', () {
      // 21:00 就開始滑，視窗從 22:30 起算 → 只有 60 分鐘落在視窗內。
      final apps = preBedApps(
        [
          ev('resumed', at(21, 0), 'com.ig'),
          ev('paused', at(23, 30), 'com.ig'),
        ],
        lightsOutAt: bed,
      );
      expect(apps.single.minutes, 60, reason: '不是 150 分鐘');
    });

    test('上床之後的事件不算', () {
      final apps = preBedApps(
        [
          ev('resumed', at(23, 40), 'com.ig'),
          ev('paused', at(23, 55), 'com.ig'),
        ],
        lightsOutAt: bed,
      );
      expect(apps, isEmpty);
    });

    test('別的 App 的 paused 不得關掉現在開著的那個', () {
      // 實機上系統事件不保證嚴格交錯：A 的 paused 可能晚於 B 的 resumed。
      final apps = preBedApps(
        [
          ev('resumed', at(22, 40), 'com.a'),
          ev('resumed', at(22, 50), 'com.b'),
          ev('paused', at(22, 51), 'com.a'), // 遲到的 A
          ev('paused', at(23, 10), 'com.b'),
        ],
        lightsOutAt: bed,
      );
      final b = apps.firstWhere((a) => a.packageName == 'com.b');
      expect(b.minutes, 20, reason: '22:50 → 23:10，不能被 A 的 paused 砍成 1 分鐘');
    });

    test('顯示名稱查得到就用，查不到用 package 名', () {
      final apps = preBedApps(
        [
          ev('resumed', at(23, 0), 'com.ig'),
          ev('paused', at(23, 20), 'com.ig'),
        ],
        lightsOutAt: bed,
        labels: {'com.ig': 'Instagram'},
      );
      expect(apps.single.appName, 'Instagram');

      final unnamed = preBedApps(
        [
          ev('resumed', at(23, 0), 'com.unknown'),
          ev('paused', at(23, 20), 'com.unknown'),
        ],
        lightsOutAt: bed,
      );
      expect(unnamed.single.appName, 'com.unknown');
    });

    test('不到一分鐘的切換不顯示', () {
      final apps = preBedApps(
        [
          ev('resumed', at(23, 0), 'com.launcher'),
          ev('paused', at(23, 0, ), 'com.launcher'),
        ],
        lightsOutAt: bed,
      );
      expect(apps, isEmpty);
    });

    test('沒有事件 → 空陣列，不是丟例外', () {
      expect(preBedApps(const [], lightsOutAt: bed), isEmpty);
    });
  });

  group('PreBedResult', () {
    test('偵測不到上床時刻時 hasData 是 false', () {
      const r = PreBedResult();
      expect(r.hasData, isFalse);
      expect(r.totalMinutes, 0);
    });

    test('totalMinutes 是各 App 相加', () {
      final r = PreBedResult(
        lightsOutAt: bed,
        apps: preBedApps(
          [
            ev('resumed', at(22, 40), 'com.a'),
            ev('paused', at(23, 0), 'com.a'),
            ev('resumed', at(23, 10), 'com.b'),
            ev('paused', at(23, 25), 'com.b'),
          ],
          lightsOutAt: bed,
        ),
      );
      expect(r.hasData, isTrue);
      expect(r.totalMinutes, 35);
    });
  });
}
