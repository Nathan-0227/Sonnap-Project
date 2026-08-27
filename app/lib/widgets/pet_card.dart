import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class PetCard extends StatelessWidget {
  final String message;
  final String animationPath;
  final VoidCallback? onDiaryTap;
  final VoidCallback? onFlowerTap;

  /// [animationPath] 讀不到時改播的資產。給 null 就直接退到靜態 icon。
  final String? fallbackAnimationPath;

  /// 套在 [fallbackAnimationPath] 上的濾鏡。用途見 pet_mood_animation.dart：
  /// 心情專屬的動畫檔還沒到位時，靠它讓 tired／anxious 不要看起來跟 happy 一樣。
  /// ⚠️ 只套在退路上，不套在 [animationPath]——美術給的檔要照原樣播。
  final ColorFilter? fallbackFilter;

  const PetCard({
    super.key,
    required this.message,
    required this.animationPath,
    this.fallbackAnimationPath,
    this.fallbackFilter,
    this.onDiaryTap,
    this.onFlowerTap,
  });

  /// 第二、三層退路。抽成方法是因為 errorBuilder 裡塞三層巢狀很難讀。
  Widget _buildFallback() {
    const double size = 190;

    if (fallbackAnimationPath != null) {
      final Widget animation = Lottie.asset(
        fallbackAnimationPath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // 第三層：連退路資產都讀不到才走這裡
        errorBuilder: (context, error, stackTrace) => _buildIcon(),
      );
      return fallbackFilter == null
          ? animation
          : ColorFiltered(colorFilter: fallbackFilter!, child: animation);
    }

    return _buildIcon();
  }

  Widget _buildIcon() {
    return const SizedBox(
      width: 190,
      height: 190,
      child: Center(
        child: Icon(Icons.pets_rounded, color: Colors.white54, size: 80),
      ),
    );
  }

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
              // 三層退路，由好到壞：
              //   ① 該心情專屬的 Lottie 檔
              //   ② 檔案不存在 → happy_dog.json + 該心情的濾鏡
              //   ③ 連 happy_dog.json 都讀不到 → 靜態的爪印 icon
              // ② 是目前的實際情況（美術只給了 happy_dog.json），
              // 用意是不要出現「文字寫 Anxious、圖在搖尾巴」的矛盾畫面。
              child: Lottie.asset(
                animationPath,
                width: 190,
                height: 190,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallback();
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