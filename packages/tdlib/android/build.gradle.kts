// FFI plugin shim: it holds no code, it only packages the prebuilt
// libtdjson.so files from src/main/jniLibs/<abi>/ into the app
// (fetched by tool/fetch_tdlib.py).
plugins {
    id("com.android.library")
}

group = "dev.chithram.tdlib"
version = "1.0"

android {
    namespace = "dev.chithram.tdlib"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}
