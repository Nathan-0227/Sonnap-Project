import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class PetCard extends StatelessWidget {
  final String message;
  final String animationPath;
  final VoidCallback? onDiaryTap;
  final VoidCallback? onFlowerTap;

  const PetCard({
    super.key,
    required this.message,
    required this.animationPath,
    this.onDiaryTap,
    this.onFlowerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 360,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 0,
            child: Container(
              width: 145,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEEFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF10265A),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
            ),
          ),

          const Positioned(
            left: 120,
            top: 120,
            child: CircleAvatar(
              radius: 8,
              backgroundColor: Color(0xFFEDEEFF),
            ),
          ),

          const Positioned(
            left: 140,
            top: 140,
            child: CircleAvatar(
              radius: 5,
              backgroundColor: Color(0xFFEDEEFF),
            ),
          ),

          const Positioned(
            left: 155,
            top: 155,
            child: CircleAvatar(
              radius: 3,
              backgroundColor: Color(0xFFEDEEFF),
            ),
          ),

          const Positioned(
            top: 22,
            right: 22,
            child: Icon(
              Icons.nightlight_round,
              color: Color(0xFFFFD96A),
              size: 28,
            ),
          ),

          Positioned(
            right: 25,
            bottom: 25,
            child: IconButton(
              onPressed: onFlowerTap,
              tooltip: "Open pet activity",
              icon: const Icon(
                Icons.local_florist,
                color: Color(0xFF9AD36A),
                size: 42,
              ),
            ),
          ),

          Positioned(
            bottom: 25,
            left: 95,
            child: Container(
              width: 190,
              height: 55,
              decoration: BoxDecoration(
                color: const Color(0xFF594EA8),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 65),
              child: Lottie.asset(
                animationPath,
                width: 190,
                height: 190,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox(
                    width: 190,
                    height: 190,
                    child: Center(
                      child: Icon(
                        Icons.pets_rounded,
                        color: Colors.white54,
                        size: 80,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const Positioned(
            bottom: 10,
            left: 20,
            child: Icon(
              Icons.star,
              color: Color(0xFF8B6DFF),
              size: 34,
            ),
          ),

          Positioned(
            bottom: 8,
            right: 5,
            child: IconButton(
              onPressed: onDiaryTap,
              tooltip: "Open dream diary",
              icon: const Icon(
                Icons.menu_book_rounded,
                color: Color(0xFFFFD96A),
                size: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}