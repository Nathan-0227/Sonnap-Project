import 'package:flutter/material.dart';

import 'screens/assistant_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const SonnapApp());
}

class SonnapApp extends StatelessWidget {
  const SonnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int currentIndex = 0;

  late final List<Widget> pages = [
    const HomeScreen(),
    const FriendsScreen(),
    const ReportScreen(),
    const AssistantScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081326),

      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B2548),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFFFD96A),
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() {
              currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_rounded),
              label: "Friends",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: "Insights",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_toy_rounded),
              label: "Assistants",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: "Settings",
            ),
          ],
        ),
      ),
    );
  }
}