group = "dev.chithram.nova_host"
version = "1.0"

// Chaquopy (MIT) runs CPython 3.11 inside the Android app. Applied here, in the
// plugin's library module; the plugin artifact itself is declared (with
// `apply false`) in app/android/settings.gradle.kts.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.chaquo.python")
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
            // Python 3.11 is the newest Chaquopy Python that still has armeabi-v7a.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

chaquopy {
    defaultConfig {
        version = "3.11"
        // No pip packages and no .pyc compilation: no build Python needed.
        pyc {
            src = false
        }
    }
    sourceSets {
        getByName("main") {
            srcDir("../../../python/nova/runtime")
        }
    }
}
