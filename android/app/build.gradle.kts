plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "moe.matthew.mekuru"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "moe.matthew.mekuru"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (System.getenv("RELEASE_KEYSTORE_PATH") != null) {
            create("release") {
                storeFile = file(System.getenv("RELEASE_KEYSTORE_PATH")!!)
                storePassword = System.getenv("RELEASE_KEYSTORE_PASSWORD")!!
                keyAlias = System.getenv("RELEASE_KEY_ALIAS")!!
                keyPassword = System.getenv("RELEASE_KEY_PASSWORD")!!
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("RELEASE_KEYSTORE_PATH") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
