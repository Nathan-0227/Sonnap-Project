import 'package:flutter/material.dart';

import '../services/login_service.dart';
import '../theme/app_accent.dart';
import 'settings_list.dart';

/// 登入用的三張表單（2026-11-22）：設定登入、改密碼、登入。設定頁面板、第一次登入流程、
/// 歡迎頁的「I already have an account」共用，樣子只在這裡一份。
///
/// 表單只管輸入與送出前的本地檢查（[newPasswordProblem]）；送出交給呼叫端，
/// 呼叫端回 null＝成功、否則是那句要照實寫出來的話（後端的 message 照抄）。
///
/// ⚠️ 不寫 secure／encrypted／safe：API 照舊用 user_id 認人，密碼只是用來拿回 id。

typedef LoginSubmit = Future<String?> Function(String email, String password);

/// 一格輸入框（深色、圓角）。
class LoginField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboard;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final List<String>? autofill;

  const LoginField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboard,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.autofill,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: !obscure,
        keyboardType: keyboard,
        textInputAction: action,
        onSubmitted: onSubmitted,
        autofillHints: autofill,
        style: const TextStyle(color: Colors.white, fontSize: 17),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF5B6E8C)),
          filled: true,
          fillColor: const Color(0x1AFFFFFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      );
}

/// 紅字的那一句（後端或本地檢查的問題）。
class LoginProblem extends StatelessWidget {
  final String text;
  const LoginProblem(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(text,
            key: const Key('login-problem'),
            style: const TextStyle(color: Color(0xFFFF9C9C), fontSize: 14, height: 1.35)),
      );
}

/// 主色的大按鈕；送出中轉圈、不能再按。
class LoginButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const LoginButton({super.key, required this.label, required this.busy, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accentOf(context),
            disabledBackgroundColor: accentOf(context).withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );
}

/// 設定登入：email＋密碼打兩次。
class SetUpLoginForm extends StatefulWidget {
  final LoginSubmit onSubmit;
  final String buttonLabel;
  const SetUpLoginForm({super.key, required this.onSubmit, this.buttonLabel = 'Save login'});

  @override
  State<SetUpLoginForm> createState() => _SetUpLoginFormState();
}

class _SetUpLoginFormState extends State<SetUpLoginForm> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final local = email.isEmpty ? 'Enter your email.' : newPasswordProblem(_pw.text, _pw2.text);
    if (local != null) {
      setState(() => _problem = local);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await widget.onSubmit(email, _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoginField(
            key: const Key('login-email'),
            controller: _email,
            hint: 'Email',
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
          ),
          const SizedBox(height: 10),
          LoginField(
            key: const Key('login-password'),
            controller: _pw,
            hint: 'Password (at least $kMinPasswordLength characters)',
            obscure: true,
            autofill: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 10),
          LoginField(
            key: const Key('login-password-again'),
            controller: _pw2,
            hint: 'Password again',
            obscure: true,
            action: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_problem case final p?) LoginProblem(p),
          const SizedBox(height: 18),
          LoginButton(key: const Key('login-save'), label: widget.buttonLabel, busy: _busy, onPressed: _submit),
        ],
      );
}

/// 改密碼：舊的一次、新的兩次。
class ChangePasswordForm extends StatefulWidget {
  final Future<String?> Function(String oldPassword, String newPassword) onSubmit;
  const ChangePasswordForm({super.key, required this.onSubmit});

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _old = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final local = _old.text.isEmpty ? 'Enter your current password.' : newPasswordProblem(_pw.text, _pw2.text);
    if (local != null) {
      setState(() => _problem = local);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await widget.onSubmit(_old.text, _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoginField(
            key: const Key('password-old'),
            controller: _old,
            hint: 'Current password',
            obscure: true,
            autofill: const [AutofillHints.password],
          ),
          const SizedBox(height: 10),
          LoginField(
            key: const Key('password-new'),
            controller: _pw,
            hint: 'New password (at least $kMinPasswordLength characters)',
            obscure: true,
            autofill: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 10),
          LoginField(
            key: const Key('password-new-again'),
            controller: _pw2,
            hint: 'New password again',
            obscure: true,
            action: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_problem case final p?) LoginProblem(p),
          const SizedBox(height: 18),
          LoginButton(key: const Key('password-save'), label: 'Change password', busy: _busy, onPressed: _submit),
          const SizedBox(height: 12),
          const Text(kForgotPasswordNote, style: TextStyle(color: kSettingsSub, fontSize: 13, height: 1.35)),
        ],
      );
}

/// 登入：email＋密碼一次。
class LogInForm extends StatefulWidget {
  final LoginSubmit onSubmit;
  const LogInForm({super.key, required this.onSubmit});

  @override
  State<LogInForm> createState() => _LogInFormState();
}

class _LogInFormState extends State<LogInForm> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _problem = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await widget.onSubmit(_email.text.trim(), _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoginField(
            key: const Key('login-email'),
            controller: _email,
            hint: 'Email',
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
          ),
          const SizedBox(height: 10),
          LoginField(
            key: const Key('login-password'),
            controller: _pw,
            hint: 'Password',
            obscure: true,
            action: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            autofill: const [AutofillHints.password],
          ),
          if (_problem case final p?) LoginProblem(p),
          const SizedBox(height: 18),
          LoginButton(key: const Key('login-submit'), label: 'Log in', busy: _busy, onPressed: _submit),
          const SizedBox(height: 14),
          const Text(kForgotPasswordNote,
              textAlign: TextAlign.center, style: TextStyle(color: kSettingsSub, fontSize: 13, height: 1.35)),
        ],
      );
}
