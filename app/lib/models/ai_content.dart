/// AI 生成的內容 — 對應 data contract 的 `ai_content` 區塊。
///
/// ⚠️ **[dreamSummary] 是虛構的，而且虛構的是「寵物的夢」不是使用者的夢。**
///
/// Garmin 完全沒有量測任何夢境內容——REM 分鐘數只說明睡眠階段發生過，
/// 沒說夢到什麼。所以 UI 文案必須寫成「小寵物昨晚的夢境日記」之類，
/// 絕不能寫成「你昨晚的夢」。
///
/// [isAiGenerated] 為 false 時代表 AI 沒跑或降級了，此時 [advice] 會是
/// 規則式評分產生的原文——**使用者一點實質內容都沒少，只少了語氣潤飾**。
class AiContent {
  /// 給使用者的建議。永遠有值（AI 掛掉時是規則式原文）。
  final String? advice;

  /// 寵物的夢境日記。AI 沒跑時為 null。
  final String? dreamSummary;

  /// 跨夜趨勢的一句話觀察。這是 AI 的主要價值——規則式評分一次只看一晚，
  /// 看不到「這週心率比上個月高」這種變化。
  final String? trendNote;

  /// 這段內容是不是 LLM 生成的。UI 應據此顯示標記。
  final bool isAiGenerated;

  /// "fiction+advice"（含虛構夢境）或 "advice"（純規則式）
  final String? contentType;

  /// "llm" 或 "rule_based"
  final String? source;

  final String? model;

  const AiContent({
    this.advice,
    this.dreamSummary,
    this.trendNote,
    this.isAiGenerated = false,
    this.contentType,
    this.source,
    this.model,
  });

  bool get hasDream => dreamSummary != null && dreamSummary!.isNotEmpty;

  factory AiContent.fromJson(Map<String, dynamic> json) {
    return AiContent(
      advice: json['advice'] as String?,
      dreamSummary: json['dream_summary'] as String?,
      trendNote: json['trend_note'] as String?,
      isAiGenerated: json['is_ai_generated'] as bool? ?? false,
      contentType: json['content_type'] as String?,
      source: json['source'] as String?,
      model: json['model'] as String?,
    );
  }
}
