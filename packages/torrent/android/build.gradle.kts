// FFI plugin shim: it holds no code, it only packages the prebuilt
// libchithram_torrent.so files from src/main/jniLibs/<abi>/ into the app.
plugins {
    id("com.android.library")
}

group = "dev.chithram.torrent"
version = "1.0"

android {
    namespace = "dev.chithram.torrent"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
