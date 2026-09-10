import 'package:app/services/backfill.dart' as backfill;
import 'package:flutter_test/flutter_test.dart';

/// 守補填模式那兩個**壞掉時不會報錯**的地方。
///
/// ⚠️ 最危險的情況不是補填失敗，是**有人拿補填版的 APK 當日常版在用**——
///    那樣每天上傳的都是同一個過去的夜晚，而畫面看起來完全正常，
///    後端也會照收（同一晚一直被 upsert 覆蓋）。
///
/// ⚠️ 這個檔案在**沒有** --dart-define 的情況下跑，所以測得到的是
///    「沒開補填時一切照舊」那一半。開啟時的行為由
///    `report_screen_test.dart` 用注入的方式測（那裡才有 widget）。

void main() {
  group('沒給 SONNAP_BACKFILL_NOW 時', () {
    test('backfillNow 是 null —— 也就是 lightsOut() 收到 null、行為與先前逐字相同', () {
      expect(backfill.kBackfillNowRaw, '',
          reason: '測試環境不該帶著 --dart-define 跑');
      expect(backfill.backfillNow, isNull);
    });

    test('isActive 是 false', () {
      expect(backfill.isActive, isFalse);
    });

    test('⚠️ isMisconfigured 也要是 false —— 沒給不等於給錯', () {
      // 少了這個區分，正常的 build 會一直掛著紅色的「格式錯誤」橫幅，
      // 幾天之後就沒有人會再看橫幅了——那等於把警示機制關掉。
      expect(backfill.isMisconfigured, isFalse);
    });
  });

  group('解析規則（不依賴 --dart-define）', () {
    // ⚠️ 這幾條驗的是 DateTime.tryParse 的行為本身。補填時刻打錯字
    //    **不可以**讓 App 開不起來（受測者手上那支就再也打不開了），
    //    但也不可以安靜地退回正常模式——所以是 tryParse + 一個旗標，
    //    不是 parse。

    test('正常的 ISO8601 解析得出來', () {
      expect(DateTime.tryParse('2026-09-09T12:00:00'),
          DateTime(2026, 9, 9, 12));
    });

    test('打錯字回 null 而不是丟例外', () {
      expect(DateTime.tryParse('2026-09-09 12:00 pm'), isNull);
      expect(DateTime.tryParse('yesterday'), isNull);
      expect(DateTime.tryParse(''), isNull);
    });

    test('⚠️ 只給日期也算合法 —— 但那會變成當天 00:00', () {
      // 要補「09-09 凌晨上床、早上起床」那一夜，給 2026-09-09 會讓視窗
      // 變成 09-08 00:00 ~ 09-09 00:00，**整段安靜期都在視窗外**。
      // 這不是 bug，是使用者要知道的事——所以檔頭寫明要給「中午」。
      expect(DateTime.tryParse('2026-09-09'), DateTime(2026, 9, 9));
    });
  });
}
