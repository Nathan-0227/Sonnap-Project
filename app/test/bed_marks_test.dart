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

  group('⚠️ 完整的一對不可以被下一晚銷毀', () {
    // 2026-09-09 真的掉了一晚的資料：
    //   09-08 01:53 按開始 / 12:11 按下床（完整的一對）
    //   整天沒開 Insights → 沒上傳
    //   09-09 00:49 按下一晚的開始 → 舊版在這裡把 end 刪掉
    //   上傳時只剩 start=09-09，後端 same_night 判定不同夜，整組丟掉
    //
    // 兩個守門都正常運作，資料是在更早一步掉的。

    final n1s = DateTime(2026, 9, 8, 1, 53);
    final n1e = DateTime(2026, 9, 8, 12, 11);
    final n2s = DateTime(2026, 9, 9, 0, 49);

    test('按下一晚的開始時，上一晚完整的一對移到 pending', () async {
      await marks.markStart(n1s);
      await marks.markEnd(n1e);
      await marks.markStart(n2s);

      final pending = await marks.readPending(now: n2s);
      expect(pending.isComplete, isTrue, reason: '這一對還沒上傳，不能銷毀');
      expect(pending.startAt, n1s);
      expect(pending.endAt, n1e);
    });

    test('而且當前那一槽是新的一晚，沒有殘留的 end', () async {
      await marks.markStart(n1s);
      await marks.markEnd(n1e);
      await marks.markStart(n2s);

      final current = await marks.read(now: n2s);
      expect(current.startAt, n2s);
      expect(current.endAt, isNull,
          reason: '留著昨天的 end 會配成錯的一對——那是本來就對的顧慮');
    });

    test('⚠️ 反向對照：只按了開始（沒按下床）就不該進 pending', () async {
      // 沒有這一條，把「無條件搬進 pending」也會讓上面兩條通過，
      // 而那會讓一個沒有結束的殘骸永遠卡在 pending 槽裡。
      await marks.markStart(n1s);
      await marks.markStart(n2s);
      expect((await marks.readPending(now: n2s)).isComplete, isFalse);
    });

    test('clearPending() 不可以動到當前那一槽', () async {
      await marks.markStart(n1s);
      await marks.markEnd(n1e);
      await marks.markStart(n2s);
      await marks.clearPending();

      expect((await marks.readPending(now: n2s)).isComplete, isFalse);
      expect((await marks.read(now: n2s)).startAt, n2s,
          reason: '清錯槽會把使用者今晚剛按的開始刪掉');
    });

    test('過期的 pending 一樣當作沒有', () async {
      await marks.markStart(n1s);
      await marks.markEnd(n1e);
      await marks.markStart(n2s);
      final late = n1s.add(kBedMarkMaxAge + const Duration(minutes: 1));
      expect((await marks.readPending(now: late)).isComplete, isFalse);
    });

    test('沒有 pending 時回 none，不是丟例外', () async {
      expect((await marks.readPending(now: n2s)).isComplete, isFalse);
    });
  });
}

