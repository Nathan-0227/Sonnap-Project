import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../services/account_service.dart';
import '../services/chat_service.dart';
import '../services/chat_thread.dart';
import '../services/key_value_store.dart';
import '../services/night_sheet_link.dart';
import '../services/sleep_plan.dart';
import 'morning_report_screen.dart' show reportDateTitle;
import '../widgets/assistant_chrome.dart';
import '../widgets/report_sheet.dart';
import '../content/sleep_basics.dart';
import '../widgets/sleep_basics_card.dart';

/// 睡眠助理（2026-11-19 第二版：對話介面）。答案來自後端的 Claude（`POST /chat`），
/// 只根據這個人自己的資料。
///
/// 回答的角色是**寵物**（標題 Your buddy，跟寵物 notes 同一個角色；外觀見下面「聊天室外觀」）。訊息從底部往上長；輸入框固定在最下面；建議問題是固定清單
/// （不讓 AI 生，免得多花額度）；右上 📖 睡眠小知識、✎ 開新對話。對話存在手機上，
/// 只留一段。舊版寫死的「What affected your sleep」三條拿掉了（每個人每天都一樣，
/// 是在 Dart 自己下判斷）。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ LLM 是唯一的答案來源（計畫檔 B6，使用者的決定）
/// ═══════════════════════════════════════════════════════════════════
///
/// 查表路由器（`services/assistant_answers.dart`）已退場，**預設不接**。
/// ⚠️ 連不到後端、伺服器沒設定金鑰、或回答沒過驗證時，**老實講答不出來**，
///    不在 Dart 編一段看起來像答案的通用句子。
/// ⚠️ 失敗的原因照抄後端的 detail（沒設定／連不上／沒過驗證），不自己改寫。
/// ⚠️ 每問一次都會花 API 額度；追問時一起送最近 [kChatContextRounds] 輪。
///
/// ═══════════════════════════════════════════════════════════════════
/// 分段回答（2026-11-22，參考 Oura／WHOOP，使用者 grill 定）
/// ═══════════════════════════════════════════════════════════════════
///
/// 泡泡裡：粗體一句直接回答＋小一號的為什麼。泡泡底下：對得上睡眠計畫的建議各一行
/// 「+ Add "caffeine earlier" to my plan」＋後端那句 Why（設計稿 A）→ 詳細頁連結 → 兩顆追問
/// （[kAssistantSuggestions] 裡這段對話還沒問過的，不經過 AI）。輸入框上方固定 [kAssistantDisclaimer]。
/// ⚠️ 加進計畫的是清單原句（`kPlanSuggestions`），不是 AI 寫的字；Why 也是後端固定表的字。
///
/// ═══════════════════════════════════════════════════════════════════
/// 聊天室外觀（2026-11-22 使用者 grill 定，設計稿 D；元件在 widgets/assistant_chrome.dart）
/// ═══════════════════════════════════════════════════════════════════
///
/// 房間圖與站在房間裡的大寵物拿掉了（泡泡一捲就蓋住牠、頭像又漫出圓框）。現在：
/// 會動的背景（深藍＋往上飄的塗鴉＋星星與流星）、實心標題列（頭像＋Your buddy＋照後端心情的狀態）、
/// 第一則是 App 用固定句型組的打招呼（照抄 `/home` 那一晚的數字，不呼叫 AI、不當前文送出）、
/// 日期改成置中膠囊（換晚上或換一段時才出現）、泡泡有小尾巴、每則旁邊不再放小頭像。
/// 想答案時：狀態 thinking…、頭像歪頭、星星閃快。⚠️ [visible] 為 false（切到別的分頁）
/// 或系統開「減少動態效果」時動畫全停。
class AssistantScreen extends StatefulWidget {
  final String username;

  /// null = 這支 build 沒有後端。
  final ChatService? chat;

  /// 對話存在哪（null＝手機的 `sonnap/store`）。
  final KeyValueStore? store;

  /// 頭像與狀態列的心情（同首頁那一份）；拿不到就是 bored。
  final Future<String?> Function()? petMood;

  /// 最近一晚換了就重讀 [petMood]（main.dart 的 LatestNightRepository；分頁疊在 TabSwitcher 裡，
  /// 不重讀的話標題列會一直停在打開 App 那時的心情）。
  final Listenable? moodChanges;

  /// 打招呼那一則要的那一晚：`/home?date=<今天>` 的回應（null＝沒有後端或拿不到 → 只打招呼）。
  final Future<Map<String, dynamic>?> Function(String date)? greetingNight;

  /// 這一頁現在在不在畫面上（App 的分頁疊在 TabSwitcher 裡）。false 時動畫全停。
  final bool visible;

  /// 測試換時鐘用。
  final DateTime Function() clock;

  const AssistantScreen({
    super.key,
    this.username = kFallbackDisplayName,
    this.chat,
    this.store,
    this.petMood,
    this.moodChanges,
    this.greetingNight,
    this.visible = true,
    this.clock = DateTime.now,
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

/// 固定的建議問題。
const List<String> kAssistantSuggestions = [
  "Why am I tired today?",
  "Did I put my phone down on time last night?",
  "How is my pet's mood related to my sleep?",
  "Give me some tips for tonight.",
  "How can I improve my sleep score?",
];

/// 輸入框上方那一行（2026-11-22 使用者定）。
const String kAssistantDisclaimer = 'Your buddy only knows your Sonnap data · not medical advice';

/// 泡泡上方那行小字（2026-11-22）：一晚寫「Wednesday, Nov 19」（同早晨報告的標題），
/// 一段寫「Nov 17 – Nov 23」。日期照抄後端（起床日）。
String chatPeriodLabel(ChatPeriod p) {
  String short(String iso) => reportDateTitle(DateTime.parse(iso)).split(', ').last;
  return p.kind == 'night'
      ? reportDateTitle(DateTime.parse(p.date!))
      : '${short(p.start!)} – ${short(p.end!)}';
}

/// 回答底下最多幾顆追問。
const int kFollowUpCount = 2;

/// 追問：建議問題裡這段對話還沒問過的前 [kFollowUpCount] 題。
List<String> followUpQuestions(List<ChatTurn> turns) {
  final asked = askedQuestions(turns);
  return [for (final q in kAssistantSuggestions) if (!asked.contains(q)) q].take(kFollowUpCount).toList();
}

/// 日期膠囊的鍵：同一晚、同一段只出一次。
String chatPeriodKey(ChatPeriod p) => p.kind == 'night' ? 'n:${p.date}' : 'r:${p.start}:${p.end}';

/// 哪幾則回答上面要放日期膠囊（2026-11-22 使用者定）：最上面已經有「Today」，
/// 之後只在講的晚上或那一段**跟上一個膠囊不同**時才再放一個。
Set<int> periodChipsAt(List<ChatTurn> turns) {
  final out = <int>{};
  String? last;
  for (var i = 0; i < turns.length; i++) {
    final p = turns[i].period;
    if (turns[i].fromUser || p == null) continue;
    final key = chatPeriodKey(p);
    if (key != last) out.add(i);
    last = key;
  }
  return out;
}

const _bubble = Color(0xFF1E2C6B);
const _bar = Color(0xFF121A47);

class _AssistantScreenState extends State<AssistantScreen> {
  final List<ChatTurn> _turns = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final ChatThreadStore _thread =
      ChatThreadStore(widget.store ?? const PlatformKeyValueStore());
  bool _loading = false;
  String? _mood;
  Map<String, dynamic>? _greetingNight;

  @override
  void initState() {
    super.initState();
    final now = widget.clock();
    final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
    widget.greetingNight?.call(today).then((n) {
      if (mounted && n != null) setState(() => _greetingNight = n);
    }, onError: (_) {});
    _thread.load().then((saved) {
      if (!mounted || saved.isEmpty || _turns.isNotEmpty) return;
      setState(() => _turns.addAll(saved));
    });
    _loadMood();
    widget.moodChanges?.addListener(_loadMood);
  }

  void _loadMood() {
    widget.petMood?.call().then((m) {
      if (mounted) setState(() => _mood = m);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    widget.moodChanges?.removeListener(_loadMood);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String question, {bool retry = false}) async {
    final q = question.trim();
    if (q.isEmpty || _loading) return;
    if (!retry) _input.clear();

    final context = chatContext(_turns);
    setState(() {
      if (!retry) _turns.add(ChatTurn.user(q));
      _loading = widget.chat != null;
    });
    _toBottom();

    final chat = widget.chat;
    if (chat == null) {
      setState(() => _turns.add(const ChatTurn.buddy(
          "The sleep assistant needs the Sonnap backend. "
          "Connect to the server to ask questions about your sleep.",
          failed: true)));
      return;
    }

    final result = await chat.ask(q, history: context);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _turns.add(result.isOk
          ? (result.reply ?? ChatTurn.buddy(result.answer!))
          : ChatTurn.buddy(
              result.message ?? "The sleep assistant cannot be reached right now.",
              failed: true));
    });
    _toBottom();
    await _thread.save(_turns);
  }

  /// 答不出來那則的「Try again」：拿掉那則，用同一題再問一次（不重複加問題）。
  void _retry(int failedIndex) {
    if (_loading || failedIndex < 1) return;
    final q = _turns[failedIndex - 1];
    if (!q.fromUser) return;
    setState(() => _turns.removeAt(failedIndex));
    _send(q.text, retry: true);
  }

  Future<void> _newChat() async {
    if (_loading) return;
    setState(_turns.clear);
    await _thread.clear();
  }

  void _openBasics() {
    showReportSheet<void>(
      context: context,
      // 底部留系統導覽列的高度：三顆按鈕的導覽原本蓋住最後一條的出處（2026-11-22 實機）
      builder: (context) => Padding(
        key: const Key('assistant-basics-sheet'),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        child: const SingleChildScrollView(child: SleepBasicsCard(initiallyExpanded: true)),
      ),
    );
  }

  /// 點 Sleep basics 的膠囊：問題＝那一條的標題，寵物回的是**原文＋出處**（不經過 AI、不花額度）。
  Future<void> _showBasic(SleepBasic b) async {
    if (_loading) return;
    setState(() {
      _turns
        ..add(ChatTurn.user(b.title))
        ..add(ChatTurn.buddy(b.summary, basic: b.id));
    });
    _toBottom();
    await _thread.save(_turns);
  }

  /// 這段對話還沒看過的 Sleep basics（看過的那顆就不再出現；開新對話又全部回來）。
  List<SleepBasic> _unseenBasics() {
    final seen = {for (final t in _turns) if (t.basic != null) t.basic};
    return [for (final b in kSleepBasics) if (!seen.contains(b.id)) b];
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: widget.visible,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(children: [
          Positioned.fill(child: ChatBackdrop(thinking: _loading)),
          SafeArea(
            child: Center(
              child: SizedBox(
                width: w > 560 ? 560 : w,
                child: Column(children: [
                  _header(),
                  Expanded(child: _messages()),
                  _suggestions(),
                  _basicsRow(),
                  const Padding(
                    key: Key('assistant-disclaimer'),
                    padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
                    child: Text(kAssistantDisclaimer,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 11.5)),
                  ),
                  _inputBar(),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  /// 實心標題列：訊息只在它底下捲，不會再被切一半疊在標題後面。
  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        color: _bar.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(children: [
        BuddyAvatar(mood: _mood, size: 44, tilt: _loading),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your buddy',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(buddyStatus(_mood, thinking: _loading),
                key: const Key('assistant-status'),
                style: TextStyle(
                    color: _loading ? const Color(0xFFC8BCFF) : const Color(0xFF9FE6C4), fontSize: 12)),
          ]),
        ),
        _roundIcon(Icons.menu_book_rounded, 'Sleep basics', _openBasics,
            const Key('assistant-basics')),
        _roundIcon(Icons.edit_square, 'New chat', _turns.isEmpty ? null : _newChat,
            const Key('assistant-new-chat')),
      ]),
    );
  }

  Widget _roundIcon(IconData icon, String label, VoidCallback? onTap, Key key) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: IconButton(
          key: key,
          tooltip: label,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          color: Colors.white,
          disabledColor: Colors.white30,
        ),
      ),
    );
  }

  Widget _messages() {
    // 從底部往上長：最新的在最下面、靠近輸入框。
    final chips = periodChipsAt(_turns);
    final items = <Widget>[
      const ChatDateChip('Today', key: Key('assistant-chip-today')),
      _BuddyBubble(
        key: const Key('assistant-greeting'),
        text: buildGreeting(name: widget.username, now: widget.clock(), night: _greetingNight),
      ),
      for (var i = 0; i < _turns.length; i++) ...[
        if (chips.contains(i))
          // key 一定要每顆不同（同一晚可能問好幾次，所以用第幾則）：列表重建時用 key 找新位置，
          // 重複的話兩顆被對到同一格，整片對話變紅畫面（11-22 實機）。
          ChatDateChip(chatPeriodLabel(_turns[i].period!), key: Key('assistant-period-$i')),
        _turns[i].fromUser
            ? _UserBubble(text: _turns[i].text)
            : _BuddyBubble(
                text: _turns[i].text,
                source: _basicSource(_turns[i].basic),
                headline: _turns[i].headline,
                why: _turns[i].why,
                failed: _turns[i].failed,
                onRetry: _turns[i].failed && widget.chat != null ? () => _retry(i) : null,
              ),
        if (!_turns[i].fromUser && !_turns[i].failed) ..._extras(_turns[i]),
      ],
      if (_loading) const _BuddyBubble(typing: true),
      if (!_loading && _turns.isNotEmpty && !_turns.last.fromUser && !_turns.last.failed)
        _followUps(),
    ];
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: items.reversed.toList(),
    );
  }

  /// 泡泡底下：建議那幾行、詳細頁連結（都靠左、對齊泡泡）。
  List<Widget> _extras(ChatTurn t) {
    final plan = PlanStore.shared;
    final open = NightSheetLinks.shared;
    final label = t.link == null ? null : kNightSheetLinkLabels[t.link!.key];
    return [
      if (plan != null)
        for (final tip in t.tips)
          if (kTipToPlan[tip.id] != null) _TipLine(tip: tip, planId: kTipToPlan[tip.id]!, plan: plan),
      if (open != null && label != null)
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key('assistant-link-${t.link!.key}'),
              onPressed: () => open(context, t.link!.date, t.link!.key),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB9A9FF)),
              child: Text('$label ›', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
    ];
  }

  /// Sleep basics 那則底下的出處（照 `kSleepBasics` 原文；不認得的 id 不寫）。
  String? _basicSource(String? id) {
    if (id == null) return null;
    for (final b in kSleepBasics) {
      if (b.id == id) return b.source;
    }
    return null;
  }

  /// 輸入框上方一排可以左右滑的 Sleep basics 膠囊（2026-11-22 使用者定：A＋B，📖 面板也留著）。
  Widget _basicsRow() {
    final items = _unseenBasics();
    if (items.isEmpty) return const SizedBox.shrink();
    final accent = accentOf(context);
    return SizedBox(
      key: const Key('assistant-basics-row'),
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final b = items[i];
          return Center(
            child: Material(
              color: const Color(0xCC17305A),
              shape: StadiumBorder(side: BorderSide(color: accent.withValues(alpha: 0.7))),
              child: InkWell(
                key: Key('assistant-basic-${b.id}'),
                customBorder: const StadiumBorder(),
                onTap: _loading ? null : () => _showBasic(b),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.menu_book_rounded, size: 15, color: accent),
                    const SizedBox(width: 6),
                    Text(b.title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _followUps() {
    final qs = followUpQuestions(_turns);
    if (qs.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('assistant-follow-ups'),
      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: [for (final q in qs) _chip(q)]),
    );
  }

  Widget _suggestions() {
    if (_turns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in kAssistantSuggestions.take(4)) _chip(q, big: true),
          ],
        ),
      );
    }
    // 有對話之後，建議問題換成回答底下那兩顆追問（[_followUps]）。
    return const SizedBox.shrink();
  }

  Widget _chip(String q, {bool big = false}) {
    return Material(
      color: const Color(0xCC24346F),
      shape: StadiumBorder(side: BorderSide(color: accentOf(context).withValues(alpha: 0.55))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _loading ? null : () => _send(q),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: big ? 14 : 12, vertical: big ? 10 : 7),
          child: Text(q,
              style: TextStyle(
                  color: Colors.white, fontSize: big ? 13.5 : 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1B2A66),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('assistant-input'),
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: accentOf(context),
              decoration: const InputDecoration(
                hintText: 'Message your buddy…',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: accentOf(context),
          shape: const CircleBorder(),
          child: IconButton(
            key: const Key('assistant-send'),
            tooltip: 'Send',
            onPressed: _loading ? null : () => _send(_input.text),
            icon: const Icon(Icons.send_rounded),
            color: Colors.white,
            disabledColor: Colors.white54,
          ),
        ),
      ]),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(left: 56, top: 6, bottom: 6),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: accentOf(context),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35)),
            ),
          ),
          BubbleTail(color: accentOf(context), left: false),
        ]),
      ),
    );
  }
}

class _BuddyBubble extends StatelessWidget {
  final String? text;

  /// 分段的回答：粗體那一句＋小一號的為什麼。沒有（舊訊息、打招呼、答不出來）就照 [text] 一段。
  final String? headline;
  final String? why;

  /// Sleep basics 那則的出處（第一作者＋期刊），小字放在泡泡最底下。
  final String? source;

  final bool failed;
  final bool typing;
  final VoidCallback? onRetry;
  const _BuddyBubble(
      {super.key,
      this.text,
      this.source,
      this.headline,
      this.why,
      this.failed = false,
      this.typing = false,
      this.onRetry});

  @override
  Widget build(BuildContext context) {
    // 每則旁邊不再放小頭像（標題列已經有牠）；靠左、深藍、左下一個小尾巴
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const BubbleTail(color: _bubble, left: true),
        Flexible(
          child: Container(
            margin: const EdgeInsets.only(right: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _bubble,
              border: Border.all(
                  color: failed ? const Color(0x66FFB4A8) : Colors.white.withValues(alpha: 0.08)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: typing
                ? const _TypingDots()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (headline != null) ...[
                        Text(headline!,
                            key: const Key('assistant-headline'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.38)),
                        if (why != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(why!,
                                key: const Key('assistant-why'),
                                style: const TextStyle(
                                    color: Color(0xFFC9CFEE), fontSize: 13.5, height: 1.38)),
                          ),
                      ] else
                        Text(text ?? '',
                            style: TextStyle(
                                color: failed ? const Color(0xFFFFD9D2) : Colors.white,
                                fontSize: 15,
                                height: 1.35)),
                      if (source != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(source!,
                              key: const Key('assistant-basic-source'),
                              style: const TextStyle(color: Color(0xFF9FB3D1), fontSize: 11.5)),
                        ),
                      if (onRetry != null)
                        TextButton.icon(
                          key: const Key('assistant-retry'),
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try again'),
                        ),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}

/// 一條建議（設計稿 A）：「+ Add "caffeine earlier" to my plan」＋後端那句 Why；
/// 已經在計畫裡就寫「✓ "caffeine earlier" is in your plan」。加進去的是清單那一整句。
class _TipLine extends StatefulWidget {
  final ChatTip tip;
  final String planId;
  final PlanStore plan;
  const _TipLine({required this.tip, required this.planId, required this.plan});

  @override
  State<_TipLine> createState() => _TipLineState();
}

class _TipLineState extends State<_TipLine> {
  @override
  void initState() {
    super.initState();
    widget.plan.addListener(_changed);
    if (!widget.plan.loaded) widget.plan.load();
  }

  @override
  void dispose() {
    widget.plan.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = suggestionById(widget.planId);
    final name = kPlanShortNames[widget.planId];
    if (s == null || name == null || !widget.plan.loaded) return const SizedBox.shrink();
    final inPlan = widget.plan.contains(s.id);
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
      child: inPlan
          ? Row(key: Key('assistant-in-plan-${widget.planId}'), children: [
              const Icon(Icons.check_rounded, size: 16, color: Color(0xFF7FE0B0)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('"$name" is in your plan',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton.icon(
                key: Key('assistant-add-${widget.planId}'),
                onPressed: () => widget.plan.add(PlanItem.fromSuggestion(s)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB9A9FF),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Add "$name" to my plan',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              if (widget.tip.why != null)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(widget.tip.why!,
                      key: Key('assistant-tip-why-${widget.tip.id}'),
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ),
            ]),
    );
  }
}

/// 「想答案中」的三個點；減少動態效果時靜止。
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('assistant-typing'),
      height: 20,
      width: 42,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset(0, -3 * _bounce((_c.value - i * 0.18) % 1.0)),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double _bounce(double t) => t < 0.4 ? (t < 0.2 ? t / 0.2 : (0.4 - t) / 0.2) : 0;
}
