plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ⚠️ 至少 26（Android 8.0）：Health Connect 的函式庫要求的最低版本。
        //    Flutter 預設是 24，不拉高的話 manifest 合併直接失敗。
        //    Health Connect 本身要 Android 9 以上，更舊的手機 App 照樣能用，
        //    只是設定頁顯示「這支手機沒有 Health Connect」。
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Health Connect（B8）。⚠️ 走 Gradle 而不是 Flutter 套件：pub 上的 health
    // 套件會連帶動到 iOS／其他平台的設定，這個專案只出 Android。
    implementation("androidx.health.connect:connect-client:1.1.0")
    // HealthConnectClient 的 API 都是 suspend，要在主執行緒回 MethodChannel。
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
