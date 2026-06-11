import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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
    const Center(
      child: Text(
        "Dream Diary",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
    const Center(
      child: Text(
        "Insights",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
    const Center(
      child: Text(
        "Settings",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081326),
      body: pages[currentIndex],
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
              icon: Icon(Icons.favorite_rounded),
              label: "Diary",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.nightlight_round),
              label: "Insights",
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget buildCard({required Widget child, double? height}) {
    return Container(
      width: double.infinity,
      height: height,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2548),
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                buildCard(
                  height: 160,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "23:00",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Sleep at 23:30",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 21,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        Icons.nightlight_round,
                        size: 54,
                        color: Color(0xFFFFD96A),
                      ),
                      Icon(
                        Icons.settings_rounded,
                        size: 42,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),

                buildCard(
                  height: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Great job today ! ✨",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Lottie.asset(
                            "assets/animations/happy_dog.json",
                            width: 160,
                            height: 160,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const Center(
                        child: Text(
                          "Your buddy is happy",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                buildCard(
                  height: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Sleep Score",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text(
                            "82",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 58,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                value: 0.82,
                                minHeight: 16,
                                backgroundColor: Colors.white24,
                                color: const Color(0xFFFFD96A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        "Great Sleep! ✨",
                        style: TextStyle(
                          color: Color(0xFFFFD96A),
                          fontSize: 21,
                        ),
                      ),
                    ],
                  ),
                ),

                Row(
                  children: [
                    Expanded(
                      child: buildCard(
                        height: 150,
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.checkroom_rounded,
                              color: Color(0xFFFFD96A),
                              size: 44,
                            ),
                            Spacer(),
                            Text(
                              "Closet",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Dress up your buddy!",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildCard(
                        height: 150,
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.task_alt_rounded,
                              color: Color(0xFFFFD96A),
                              size: 44,
                            ),
                            Spacer(),
                            Text(
                              "Mission",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Complete missions!",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}