import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.chithram.chithram"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.chithram.chithram"
        // Android 5.0+: covers older Android TV boxes (armeabi-v7a).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: android/key.properties (storeFile, storePassword,
    // keyAlias, keyPassword) or the CHITHRAM_KEYSTORE* environment variables
    // (CI). Without either, release builds use the debug key.
    val keyProps = Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    fun signing(prop: String, env: String): String? = keyProps.getProperty(prop) ?: System.getenv(env)
    val storePath = signing("storeFile", "CHITHRAM_KEYSTORE")

    signingConfigs {
        if (storePath != null) {
            create("release") {
                storeFile = file(storePath)
                storePassword = signing("storePassword", "CHITHRAM_KEYSTORE_PASSWORD")
                keyAlias = signing("keyAlias", "CHITHRAM_KEY_ALIAS")
                keyPassword = signing("keyPassword", "CHITHRAM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
