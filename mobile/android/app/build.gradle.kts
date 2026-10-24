import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter passes Dart defines as a comma-separated list of base64 values.
// Derive native identity from the same switch as Dart, so the two cannot diverge.
val offlineDemo = providers.gradleProperty("dart-defines").orNull
    ?.split(",")
    ?.any { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() == "DEMO_MODE=true" }
    ?: false
val publicServer = providers.gradleProperty("dart-defines").orNull
    ?.split(",")
    ?.any { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() == "PUBLIC_BUILD=true" }
    ?: false

android {
    namespace = "ru.uunit.pulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (offlineDemo) "ru.uunit.pulse.demo" else "ru.uunit.pulse"
        manifestPlaceholders["appLabel"] = if (offlineDemo) "Пульс Демо" else "Пульс"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode + if (offlineDemo) 1000 else 0
        versionName = flutter.versionName
        versionNameSuffix = if (offlineDemo) "-demo" else ""
        // Native plugins must follow the engine ABI for the compact phone APK.
        if (providers.gradleProperty("target-platform").orNull == "android-arm64" &&
            providers.gradleProperty("split-per-abi").orNull != "true") {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }

    if (offlineDemo) {
        sourceSets.getByName("release").manifest.srcFile("src/offline/AndroidManifest.xml")
    } else if (publicServer) {
        sourceSets.getByName("release").manifest.srcFile("src/public/AndroidManifest.xml")
    }

    buildTypes {
        release {
            // Hackathon APKs share the project-local Android development key.
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
