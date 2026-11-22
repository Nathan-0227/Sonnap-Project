import 'package:flutter/material.dart';

import '../widgets/entry_intro.dart';
import '../widgets/login_forms.dart';

/// 歡迎頁的「I already have an account」（2026-11-22）：email＋密碼 → 原本的帳號。
///
/// [onLogIn] 回 null＝登入好了（呼叫端已經換成那個帳號），這一頁自己關掉；否則照實寫那句。
/// 背景同歡迎流程那一片天空。
class LogInScreen extends StatelessWidget {
  final LoginSubmit onLogIn;
  const LogInScreen({super.key, required this.onLogIn});

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('log-in-screen'),
        backgroundColor: kEntrySkyTop,
        body: Stack(
          children: [
            const Positioned.fill(child: EntrySky()),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: const Key('log-in-back'),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Welcome back',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Nunito',
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          const Text('Log in with the email and password you set in Sonnap.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Nunito', color: Color(0xFF9AA8C7), fontSize: 15)),
                          const SizedBox(height: 28),
                          LogInForm(onSubmit: (email, pw) async {
                            final problem = await onLogIn(email, pw);
                            if (problem == null && context.mounted) Navigator.of(context).pop(true);
                            return problem;
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
