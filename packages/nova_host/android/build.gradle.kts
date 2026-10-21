group = "dev.chithram.nova_host"
version = "1.0"

// CPython's official Android build (python.org, PEP 738) is embedded through JNI.
// tool/fetch_cpython_android.py lays out jniLibs and headers (git-ignored).
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.chithram.nova_host"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
        ndk {
            // python.org publishes aarch64 and x86_64 only: armeabi-v7a gets no plugins.
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

val prepareCpythonAndroid = tasks.register<Exec>("prepareCpythonAndroid") {
    workingDir = projectDir
    commandLine("python3", "../tool/fetch_cpython_android.py")
    inputs.file("../tool/fetch_cpython_android.py")
    inputs.dir("../../../python/nova/runtime")
    outputs.dir("src/main/jniLibs")
    outputs.dir("cpython")
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(prepareCpythonAndroid)
}

// The isolated process reads the stdlib zip and the extension modules straight from
// the native library directory, so the app must install its native libs extracted
// (AGP otherwise maps them from the APK and leaves the directory empty). The manifest
// attribute is overridden by AGP, so set the packaging option on the app module.
rootProject.findProject(":app")?.let { app ->
    app.pluginManager.withPlugin("com.android.application") {
        app.extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
            packaging.jniLibs.useLegacyPackaging = true
        }
    }
}
