import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("RELEASE_KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("RELEASE_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("RELEASE_KEY_PASSWORD")

val releaseSigningConfigured =
    !releaseKeystorePath.isNullOrBlank() &&
    !releaseKeystorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

val isReleaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

val androidNdkVersion = flutter.ndkVersion

val libcxxAbiToNdkTriple = mapOf(
    "armeabi-v7a" to "arm-linux-androideabi",
    "arm64-v8a" to "aarch64-linux-android",
    "x86_64" to "x86_64-linux-android",
)

val flutterNativeAssetsJniLibsDir =
    rootProject.projectDir.parentFile.resolve("build/native_assets/android/jniLibs/lib")

fun Project.resolveAndroidSdkDir(): File {
    val envSdkDir = sequenceOf("ANDROID_SDK_ROOT", "ANDROID_HOME")
        .mapNotNull { System.getenv(it) }
        .firstOrNull { it.isNotBlank() }
    if (envSdkDir != null) {
        return file(envSdkDir)
    }

    val localProperties = rootProject.file("local.properties")
    if (localProperties.exists()) {
        val properties = Properties().apply {
            localProperties.inputStream().use(::load)
        }
        val sdkDir = properties.getProperty("sdk.dir")?.takeIf { it.isNotBlank() }
        if (sdkDir != null) {
            return file(sdkDir)
        }
    }

    throw org.gradle.api.GradleException(
        "Android SDK directory not found. Set ANDROID_SDK_ROOT or sdk.dir in local.properties.",
    )
}

val ensureBundledLibCppShared by tasks.registering {
    inputs.property("androidNdkVersion", androidNdkVersion)
    inputs.property("libcxxAbiToNdkTriple", libcxxAbiToNdkTriple)
    outputs.dir(flutterNativeAssetsJniLibsDir)

    doLast {
        val sdkDir = project.resolveAndroidSdkDir()
        val ndkDir = sdkDir.resolve("ndk").resolve(androidNdkVersion)
        val prebuiltDir = ndkDir.resolve("toolchains/llvm/prebuilt")
        val sysrootLibDir = prebuiltDir.listFiles()
            ?.asSequence()
            ?.map { it.resolve("sysroot/usr/lib") }
            ?.firstOrNull(File::exists)
            ?: throw org.gradle.api.GradleException(
                "Could not locate the Android NDK sysroot in $prebuiltDir",
            )

        val outputRoot = flutterNativeAssetsJniLibsDir
        libcxxAbiToNdkTriple.forEach { (abi, ndkTriple) ->
            val sourceLib = sysrootLibDir.resolve(ndkTriple).resolve("libc++_shared.so")
            if (!sourceLib.exists()) {
                throw org.gradle.api.GradleException(
                    "Could not locate libc++_shared.so for $abi at $sourceLib",
                )
            }

            val destinationDir = outputRoot.resolve(abi).apply { mkdirs() }
            sourceLib.copyTo(destinationDir.resolve("libc++_shared.so"), overwrite = true)
        }
    }
}

tasks.matching { it.name.startsWith("packJniLibsflutterBuild") }.configureEach {
    finalizedBy(ensureBundledLibCppShared)
}

tasks.matching {
    it.name.startsWith("merge") &&
        (it.name.endsWith("JniLibFolders") || it.name.endsWith("NativeLibs"))
}.configureEach {
    dependsOn(ensureBundledLibCppShared)
}

android {
    namespace = "moe.matthew.mekuru"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = androidNdkVersion

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
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword!!
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else if (isReleaseBuildRequested) {
                throw org.gradle.api.GradleException(
                    "Release signing is not configured. Set RELEASE_KEYSTORE_PATH, RELEASE_KEYSTORE_PASSWORD, RELEASE_KEY_ALIAS, and RELEASE_KEY_PASSWORD."
                )
            }
        }
    }
}

flutter {
    source = "../.."
}
