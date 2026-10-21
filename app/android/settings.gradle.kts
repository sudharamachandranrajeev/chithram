pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// nova_host: the isolated plugin process reads CPython's stdlib zip and extension
// modules from the native library directory, so the app must install its native libs
// extracted (AGP otherwise maps them from the APK). Set while the Android plugin is
// applied, before AGP reads the option (settable only that early; reflection because
// AGP's types are not visible to the settings script).
gradle.lifecycle.beforeProject {
    if (path == ":app") {
        pluginManager.withPlugin("com.android.application") {
            val android = extensions.getByName("android")
            val packaging = android.javaClass.getMethod("getPackaging").invoke(android)
            val jni = packaging.javaClass.getMethod("getJniLibs").invoke(packaging)
            jni.javaClass.getMethod("setUseLegacyPackaging", Boolean::class.javaPrimitiveType).invoke(jni, true)
        }
    }
}
