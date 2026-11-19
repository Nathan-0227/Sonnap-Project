import 'key_value_store.dart';

/// 寵物 notes（2026-11-17 使用者 grill 後定，取代夢境日記與報告上的「From your buddy」）。
///
/// 來自後端 `GET /night-summary`，**全部照抄**：
/// - [summary]：AI 寫的總結。手錶資料還沒到（waiting）或 AI 寫不出來（fallback）時是 null——
///   不拿別的句子補上去冒充 AI 寫的。
/// - [tips]：0–3 條建議。AI 寫得出來時是寵物口吻（`text`），原句在 `original`；
///   其他時候兩個一樣。**行動只能來自後端那份有出處的清單**，Dart 一個字都不產生。
/// - [version]：內容一變就換。首頁與報告用它決定紅點要不要再亮——
///   早上讀過「手錶還沒到」的版本，下午多了總結與生理建議，紅點要再亮一次（grill 定）。
///
/// 沒有任何內容（沒總結、沒建議）→ [PetNotes.fromJson] 回 null，日記本不出現。

/// 日記本點開的標題。寵物沒有名字，App 一律叫「your buddy」（小狗、貓都適用）。
const String kNotesTitle = "Your buddy's notes";

class PetNote {
  /// T1–T12、P1–P8（後端 behavior/morning_tips.TIPS 的 id）。
  final String id;

  /// tip（下次可以怎麼做）或 note（只解釋這一晚）。
  final String kind;

  /// 畫面上顯示的那一句（寵物口吻或原句）。
  final String text;

  /// 清單裡的原句。
  final String original;

  const PetNote({
    required this.id,
    required this.kind,
    required this.text,
    required this.original,
  });

  bool get isNote => kind == 'note';
}

class PetNotes {
  final String date;

  /// ok 或 waiting（手錶資料還沒到，只有行為那幾條原句）。
  final String status;

  /// llm、fallback，或 null（waiting）。
  final String? source;
  final String? summary;
  final List<PetNote> tips;
  final String version;

  const PetNotes({
    required this.date,
    required this.status,
    required this.source,
    required this.summary,
    required this.tips,
    required this.version,
  });

  bool get waiting => status == 'waiting';

  /// 解析 `/night-summary`。日期對不上、格式不對、沒有任何內容都回 null。
  ///
  /// ⚠️ 舊版後端（PR #129 之前）沒有 `tips`／`version`：回 null（日記本不出現），
  ///    不拿舊的 `text` 冒充——那時的 text 退回時是 `/home` 的句子，不是寫給 notes 的。
  static PetNotes? fromJson(Map<String, dynamic>? json, {required String date}) {
    if (json == null || json['date'] != date) return null;
    final status = json['status'];
    if (status != 'ok' && status != 'waiting') return null;
    final version = json['version'];
    final rawTips = json['tips'];
    if (version is! String || version.isEmpty || rawTips is! List) return null;
    final tips = <PetNote>[];
    for (final t in rawTips) {
      if (t is! Map) continue;
      final id = t['id'], text = t['text'];
      if (id is! String || text is! String || text.trim().isEmpty) continue;
      final original = t['original'];
      tips.add(
        PetNote(
          id: id,
          kind: t['kind'] == 'note' ? 'note' : 'tip',
          text: text.trim(),
          original: original is String && original.isNotEmpty ? original : text,
        ),
      );
    }
    final raw = json['summary'];
    final summary = raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    if (summary == null && tips.isEmpty) return null;
    return PetNotes(
      date: date,
      status: status as String,
      source: json['source'] as String?,
      summary: summary,
      tips: tips,
      version: version,
    );
  }
}

/// 記住每一晚**看過的是哪個 version**（只存在手機上）。
/// 內容換了（version 不同）就當作沒看過，紅點再亮。首頁與報告共用同一份。
class NotesReadStore {
  final KeyValueStore store;
  const NotesReadStore(this.store);

  static String _key(String date) => 'notes_read_$date';

  Future<bool> isRead(String date, String version) async {
    try {
      return await store.getString(_key(date)) == version;
    } catch (_) {
      return false;
    }
  }

  Future<void> markRead(String date, String version) async {
    try {
      await store.setString(_key(date), version);
    } catch (_) {
      // 記不住就下次再提醒一次，不影響看內容
    }
  }
}
