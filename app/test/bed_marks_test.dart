import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守的是 `bed_marks.dart` 那幾個**壞掉時不會報錯**的地方。
///
/// 這一層的失敗都是安靜的：一個過期的標記會被配成一對，算出一個
/// 看起來合理但完全錯的臥床時間，而且不會拋任何例外。

void main() {
  final t0 = DateTime(2026, 9, 6, 23, 0);

  late InMemoryKeyValueStore kv;
  late BedMarkStore marks;

  setUp(() {
    kv = InMemoryKeyValueStore();
    marks = BedMarkStore(kv);
  });

  test('按了開始 → 讀得回來', () async {
    await marks.markStart(t0);
    final m = await marks.read(now: t0.add(const Duration(hours: 1)));
    expect(m.startAt, t0);
    expect(m.endAt, isNull);
    expect(m.hasStart, isTrue);
    expect(m.isComplete, isFalse);
  });

  test('兩端都按了 → isComplete', () async {
    await marks.markStart(t0);
    await marks.markEnd(t0.add(const Duration(hours: 8)));
    final m = await marks.read(now: t0.add(const Duration(hours: 9)));
    expect(m.isComplete, isTrue);
    expect(m.endAt, t0.add(const Duration(hours: 8)));
  });

  test('⚠️ 過期的標記一律當作沒有 —— 不然上禮拜按的會被算進今晚', () async {
    await marks.markStart(t0);
    final m = await marks.read(now: t0.add(kBedMarkMaxAge + const Duration(minutes: 1)));
    expect(m.startAt, isNull, reason: '超過 ${kBedMarkMaxAge.inHours} 小時就丟掉');
    expect(m.isComplete, isFalse);
  });

  test('反向對照：剛好在期限內要留著', () async {
    // 沒有這一條，把期限寫成 0 也會讓上一條通過。
    await marks.markStart(t0);
    final m = await marks.read(now: t0.add(kBedMarkMaxAge - const Duration(minutes: 1)));
    expect(m.startAt, t0);
  });

  test('結束早於開始 = 按錯了 → 丟掉結束、保留開始', () async {
    await marks.markStart(t0);
    await kv.setString(kBedEndKey, t0.subtract(const Duration(hours: 2)).toIso8601String());
    final m = await marks.read(now: t0.add(const Duration(hours: 1)));
    expect(m.startAt, t0, reason: '人可能還在床上');
    expect(m.endAt, isNull);
    expect(m.isComplete, isFalse, reason: '算不出臥床時間，不能假裝算得出來');
  });

  test('沒有開始卻有結束 → 兩個都不算', () async {
    await marks.markEnd(t0);
    final m = await marks.read(now: t0.add(const Duration(hours: 1)));
    expect(m.hasStart, isFalse);
    expect(m.endAt, isNull, reason: '沒有起點的結束算不出任何東西');
  });

  test('重按開始要清掉上一次的結束 —— 否則會配成錯的一對', () async {
    await marks.markStart(t0);
    await marks.markEnd(t0.add(const Duration(hours: 8)));
    // 隔天晚上又按了開始
    final next = t0.add(const Duration(hours: 24));
    await marks.markStart(next);
    final m = await marks.read(now: next.add(const Duration(hours: 1)));
    expect(m.startAt, next);
    expect(m.endAt, isNull,
        reason: '留著昨天的結束會算出一個負的或亂七八糟的臥床時間');
  });

  test('clear() 之後兩個都沒了', () async {
    await marks.markStart(t0);
    await marks.markEnd(t0.add(const Duration(hours: 8)));
    await marks.clear();
    final m = await marks.read(now: t0.add(const Duration(hours: 9)));
    expect(m.hasStart, isFalse);
    expect(m.endAt, isNull);
  });

  test('壞掉的字串不會讓整支炸掉', () async {
    await kv.setString(kBedStartKey, 'not-a-timestamp');
    final m = await marks.read(now: t0);
    expect(m.hasStart, isFalse);
  });

  test('空的儲存 → BedMarks.none', () async {
    final m = await marks.read(now: t0);
    expect(m.startAt, isNull);
    expect(m.endAt, isNull);
  });

  group('⚠️ 按太晚的「下床」', () {
    // 2026-09-08 實測：08:20 起床、12:11 才想起來按。那個 12:11 不是
    // 下床時刻，而中間 3 小時 51 分會被算成躺在床上——臥床時間與
    // 行為版睡眠效率兩個都錯，而且錯得看起來很合理。
    //
    // 參考點是現成的：lightsOut + quietMinutes = 手機第一次被碰。

    final lightsOut = DateTime(2026, 9, 8, 2, 30);
    const quiet = 350; // 安靜到 08:20

    test('按得剛好（起床後 10 分鐘）→ 說得通', () {
      expect(
        bedEndIsPlausible(DateTime(2026, 9, 8, 8, 30), lightsOut, quiet),
        isTrue,
      );
    });

    test('賴床兩小時（10:20）→ 仍然說得通', () {
      // 寬限是 2 小時，邊界內要放行——起床後在床上滑手機是常態。
      expect(
        bedEndIsPlausible(DateTime(2026, 9, 8, 10, 20), lightsOut, quiet),
        isTrue,
      );
    });

    test('⚠️ 中午 12:11 才按 → 不說得通（就是實機那一晚）', () {
      expect(
        bedEndIsPlausible(DateTime(2026, 9, 8, 12, 11), lightsOut, quiet),
        isFalse,
        reason: '這個時刻會讓臥床時間多算 3 小時 51 分',
      );
    });

    test('沒有安靜期資料時一律放行——寧可放行也不要丟掉使用者的輸入', () {
      expect(bedEndIsPlausible(DateTime(2026, 9, 8, 12, 11), null, 0), isTrue);
      expect(
        bedEndIsPlausible(DateTime(2026, 9, 8, 12, 11), lightsOut, 0),
        isTrue,
        reason: 'quietMinutes 是 0 就沒有參考點',
      );
    });

    test('反向對照：參考點真的有被用到', () {
      // 沒有這一條，把函式寫成 `=> true` 也會讓上面全部通過。
      final early = DateTime(2026, 9, 8, 2, 30);
      expect(
        bedEndIsPlausible(DateTime(2026, 9, 8, 12, 11), early, 30),
        isFalse,
        reason: '安靜期只到 03:00，12:11 差了 9 小時',
      );
    });
  });
}

