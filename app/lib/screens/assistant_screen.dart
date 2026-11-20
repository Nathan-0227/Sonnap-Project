import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/chat_service.dart';
import '../services/chat_thread.dart';
import '../services/key_value_store.dart';
import '../widgets/home_pet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/sleep_basics_card.dart';

/// 睡眠助理（2026-11-19 第二版：對話介面）。答案來自後端的 Claude（`POST /chat`），
/// 只根據這個人自己的資料。
///
/// 版面（使用者定）：上半是使用者生成的寵物房間（`assets/backgrounds/assistant_room.jpg`，
/// 下半自己淡成 [_bg]），寵物站在房間地板上；回答的角色是**寵物**（標題 Your buddy，
/// 跟寵物 notes 同一個角色）。訊息從底部往上長；輸入框固定在最下面；建議問題是固定清單
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
class AssistantScreen extends StatefulWidget {
  final String username;

  /// null = 這支 build 沒有後端。
  final ChatService? chat;

  /// 對話存在哪（null＝手機的 `sonnap/store`）。
  final KeyValueStore? store;

  /// 房間裡那隻寵物的心情（同首頁那一份）；拿不到就是 bored（`HomePet` 的退路）。
  final Future<String?> Function()? petMood;

  const AssistantScreen({
    super.key,
    this.username = kFallbackDisplayName,
    this.chat,
    this.store,
    this.petMood,
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

/// 固定的建議問題。
const List<String> kAssistantSuggestions = [
  "Why am I tired today?",
  "How much deep sleep did I get?",
  "How is my pet's mood related to my sleep?",
  "Give me some tips for tonight.",
  "How can I improve my sleep score?",
];

const _bg = Color(0xFF0D164D); // 房間圖最底下的顏色
const _room = 'assets/backgrounds/assistant_room.jpg';
const _roomAspect = 1672 / 941;
const _floorY = 0.50; // 地板（床與地毯之間）在圖高的哪裡
const _purple = Color(0xFF7B61FF);
const _bubble = Color(0xF21B2A66);

class _AssistantScreenState extends State<AssistantScreen> {
  final List<ChatTurn> _turns = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final ChatThreadStore _thread =
      ChatThreadStore(widget.store ?? const PlatformKeyValueStore());
  bool _loading = false;
  String? _mood;

  @override
  void initState() {
    super.initState();
    _thread.load().then((saved) {
      if (!mounted || saved.isEmpty || _turns.isNotEmpty) return;
      setState(() => _turns.addAll(saved));
    });
    widget.petMood?.call().then((m) {
      if (mounted) setState(() => _mood = m);
    }, onError: (_) {});
  }

  @override
  void dispose() {
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
          ? ChatTurn.buddy(result.answer!)
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
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SingleChildScrollView(child: SleepBasicsCard(initiallyExpanded: true)),
      ),
    );
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
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final imgH = w * _roomAspect;
      const petSize = 120.0;
      return Container(
        color: _bg,
        child: Stack(children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: imgH,
            child: Image.asset(_room,
                fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
          Positioned(
            left: w / 2 - petSize / 2,
            top: imgH * _floorY - petSize * 0.86,
            child: IgnorePointer(
              child: HomePet(mood: _mood, size: petSize, animate: false),
            ),
          ),
          SafeArea(
            child: Center(
              child: SizedBox(
                width: w > 560 ? 560 : w,
                child: Column(children: [
                  _header(),
                  Expanded(child: _messages()),
                  _suggestions(),
                  _inputBar(),
                ]),
              ),
            ),
          ),
        ]),
      );
    });
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(children: [
        const _Avatar(size: 40),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your buddy',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Answers from your own sleep data',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
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
        color: const Color(0x66101A4A),
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
    final items = <Widget>[
      _BuddyBubble(
        text: "Hi ${widget.username}! Ask me anything about your sleep. "
            "I only use your own data.",
      ),
      for (var i = 0; i < _turns.length; i++)
        _turns[i].fromUser
            ? _UserBubble(text: _turns[i].text)
            : _BuddyBubble(
                text: _turns[i].text,
                failed: _turns[i].failed,
                onRetry: _turns[i].failed && widget.chat != null ? () => _retry(i) : null,
              ),
      if (_loading) const _BuddyBubble(typing: true),
    ];
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: items.reversed.toList(),
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
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final q in kAssistantSuggestions)
            Padding(padding: const EdgeInsets.only(right: 8, bottom: 6), child: _chip(q)),
        ],
      ),
    );
  }

  Widget _chip(String q, {bool big = false}) {
    return Material(
      color: const Color(0xCC24346F),
      shape: StadiumBorder(side: BorderSide(color: _purple.withValues(alpha: 0.55))),
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
              cursorColor: _purple,
              decoration: const InputDecoration(
                hintText: 'Ask your buddy…',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: _purple,
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

/// 寵物頭像：圓框裡的 [HomePet]（跟著設定頁選的小狗／貓）。
class _Avatar extends StatelessWidget {
  final double size;
  const _Avatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2B3C82),
        border: Border.all(color: _purple.withValues(alpha: 0.7), width: 1.5),
      ),
      child: ClipOval(
        child: OverflowBox(
          maxWidth: size * 1.7,
          maxHeight: size * 1.7,
          alignment: const Alignment(0.15, 0.55),
          child: HomePet(size: size * 1.7, animate: false, mood: 'happy'),
        ),
      ),
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
      child: Container(
        margin: const EdgeInsets.only(left: 56, top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: _purple,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
      ),
    );
  }
}

class _BuddyBubble extends StatelessWidget {
  final String? text;
  final bool failed;
  final bool typing;
  final VoidCallback? onRetry;
  const _BuddyBubble({this.text, this.failed = false, this.typing = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const _Avatar(size: 30),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            margin: const EdgeInsets.only(right: 40),
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
                      Text(text ?? '',
                          style: TextStyle(
                              color: failed ? const Color(0xFFFFD9D2) : Colors.white,
                              fontSize: 15,
                              height: 1.35)),
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
