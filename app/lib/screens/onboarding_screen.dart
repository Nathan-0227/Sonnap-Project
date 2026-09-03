import 'package:flutter/material.dart';

/// 首次開啟時取一個暱稱。
///
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ 這個畫面一定要能被跳過
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端沒開是 demo 的常態（`FallbackSleepRepository` 整個就是為此存在的）。
/// 建不了帳號時使用者仍然要看得到睡眠報告、夢境日記、寵物——只是那一晚的
/// 行為資料上傳不了。把人卡在一個「連不上伺服器」的畫面前面，
/// 是這個 App 最不該發生的事。
///
/// ═══════════════════════════════════════════════════════════════════
/// 為什麼沒有密碼
/// ═══════════════════════════════════════════════════════════════════
///
/// 後端是暱稱制免註冊，`user_id` 本身就是憑證。這在 D2「側載 APK、區網、
/// 十來個同學」的情境下是刻意的取捨（`main.py` 的 `create_user` docstring
/// 寫得很清楚），但**同意書要寫明，上架前必須先補認證**。
///
/// 所以這個畫面不要出現任何「安全」「隱私保護」之類的字眼——那會是謊。
class OnboardingScreen extends StatefulWidget {
  /// 回傳 true = 建立成功。
  final Future<bool> Function(String displayName) onCreate;

  /// 跳過，直接進 App（不上傳行為資料）。
  final VoidCallback onSkip;

  const OnboardingScreen({
    super.key,
    required this.onCreate,
    required this.onSkip,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color backgroundColor = Color(0xFF06142D);
  static const Color cardColor = Color(0xFF0A2142);
  static const Color purpleColor = Color(0xFF7657FF);

  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pick any name you like.');
      return;
    }
    // 後端的上限是 40（main.py 的 CreateUserRequest）。在這裡先擋掉，
    // 不要讓使用者打完一長串才被一個 422 退回來。
    if (name.length > 40) {
      setState(() => _error = 'Keep it under 40 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await widget.onCreate(name);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. You can still use Sonnap - '
            'your sleep reports work offline.';
      });
    }
    // 成功的話上層會換掉整個畫面，這裡不用做事。
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.nightlight_round,
                    color: purpleColor, size: 44),
                const SizedBox(height: 18),
                const Text(
                  'What should we call you?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A nickname is enough. No email, no password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8498B7), fontSize: 12),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  enabled: !_busy,
                  autofocus: true,
                  maxLength: 40,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nickname',
                    hintStyle: const TextStyle(color: Color(0xFF5B6E8C)),
                    counterStyle: const TextStyle(color: Color(0xFF5B6E8C)),
                    filled: true,
                    fillColor: cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: const TextStyle(
                        color: Color(0xFFFFC83D), fontSize: 11, height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: purpleColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Start'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : widget.onSkip,
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(color: Color(0xFF8498B7), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Skipping keeps every sleep report and dream entry. '
                  'Only the bedtime tracking needs an account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF5B6E8C), fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
