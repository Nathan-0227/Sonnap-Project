// 睡眠小知識（Insights 頁最下面那張卡）。
//
// ═══════════════════════════════════════════════════════════════════
// ⚠️ 每一條都只引用 repo 裡**已經核對過第一作者**的文獻
// ═══════════════════════════════════════════════════════════════════
//
// 來源一律取自 `Research-Background/Garmin手錶分數.md` 的書目，或 `db.py`
// 挑戰定義裡的 literature_ref——那些都已經照方法論第 6 點核對過第一作者
// （這個專案誤植過兩次：Troxel/Iskander、Mason/Czeisler）。
// `sleep_basics_test.dart` 會把每一條的「第一作者＋年份」拿去那兩個檔案裡
// 找，**同一行找不到就紅**。要新增一條，得先把文獻寫進那份書目。
//
// ⚠️ 摘要只寫原文講得出來的話，不外推成建議。「規律作息預測死亡風險」
//    是那篇研究的結論；「所以你要每天 23:00 睡」不是。
// ⚠️ 不做影片：沒有素材、也沒辦法驗證影片內容。
// ⚠️ 文案英文（全系統輸出語言的既定決策）。

class SleepBasic {
  final String id;
  final String title;
  final String summary;

  /// 第一作者的姓。測試拿它去已驗證的書目裡對。
  final String firstAuthor;
  final int year;

  /// 顯示在卡片上的出處（簡短版）。
  final String source;

  const SleepBasic({
    required this.id,
    required this.title,
    required this.summary,
    required this.firstAuthor,
    required this.year,
    required this.source,
  });
}

const List<SleepBasic> kSleepBasics = [
  SleepBasic(
    id: 'how_much',
    title: 'How much sleep is enough?',
    summary: 'For young adults and adults, the National Sleep Foundation recommends '
        '7 to 9 hours of sleep a night.',
    firstAuthor: 'Hirshkowitz',
    year: 2015,
    source: 'Hirshkowitz M, et al. Sleep Health. 2015;1(1):40-43.',
  ),
  SleepBasic(
    id: 'regularity',
    title: 'A steady bedtime matters, not just the hours',
    summary: 'In a UK Biobank cohort of about 61,000 adults, how regular people\'s '
        'sleep was predicted mortality risk better than how long they slept.',
    firstAuthor: 'Windred',
    year: 2024,
    source: 'Windred DP, et al. Sleep. 2024;47(1):zsad253.',
  ),
  SleepBasic(
    id: 'students',
    title: 'Irregular sleep and grades',
    summary: 'Among university students, more irregular sleep/wake patterns went '
        'together with poorer academic performance and later sleep timing.',
    firstAuthor: 'Phillips',
    year: 2017,
    source: 'Phillips AJK, et al. Sci Rep. 2017;7:3216.',
  ),
  SleepBasic(
    id: 'procrastination',
    title: 'Why "five more minutes" happens',
    summary: 'Bedtime procrastination is going to bed later than you intended when '
        'nothing is stopping you. Sonnap looks at it as the gap between your target '
        'bedtime and when you put the phone down.',
    firstAuthor: 'Kroese',
    year: 2014,
    source: 'Kroese FM, et al. Front Psychol. 2014;5:611.',
  ),
];
