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

val mecabHookLibcxxAliases = mapOf(
    "armv7a-linux-androideabi" to "arm-linux-androideabi",
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

fun Project.resolveAndroidNdkSysrootLibDir(): File {
    val sdkDir = resolveAndroidSdkDir()
    val ndkDir = sdkDir.resolve("ndk").resolve(androidNdkVersion)
    val prebuiltDir = ndkDir.resolve("toolchains/llvm/prebuilt")
    return prebuiltDir.listFiles()
        ?.asSequence()
        ?.map { it.resolve("sysroot/usr/lib") }
        ?.firstOrNull(File::exists)
        ?: throw org.gradle.api.GradleException(
            "Could not locate the Android NDK sysroot in $prebuiltDir",
        )
}

fun Project.resolveInstalledAndroidNdkSysrootLibDirs(): List<File> {
    val ndkRootDir = resolveAndroidSdkDir().resolve("ndk")
    return ndkRootDir.listFiles()
        ?.asSequence()
        ?.filter(File::isDirectory)
        ?.flatMap { ndkDir ->
            val prebuiltDir = ndkDir.resolve("toolchains/llvm/prebuilt")
            prebuiltDir.listFiles()
                ?.asSequence()
                ?.map { it.resolve("sysroot/usr/lib") }
                ?: emptySequence()
        }
        ?.filter(File::exists)
        ?.toList()
        ?: emptyList()
}

val ensureMecabHookLibCppAliases by tasks.registering {
    inputs.property("mecabHookLibcxxAliases", mecabHookLibcxxAliases)

    doLast {
        val sysrootLibDirs = project.resolveInstalledAndroidNdkSysrootLibDirs()
        if (sysrootLibDirs.isEmpty()) {
            throw org.gradle.api.GradleException(
                "Could not locate any installed Android NDK sysroot directories under the Android SDK.",
            )
        }

        // Upstream mecab_for_dart expects the ARMv7 runtime under the clang target triple,
        // but some NDK installs only ship the actual file under arm-linux-androideabi.
        sysrootLibDirs.forEach { sysrootLibDir ->
            mecabHookLibcxxAliases.forEach { (expectedTriple, actualTriple) ->
                val expectedLib = sysrootLibDir.resolve(expectedTriple).resolve("libc++_shared.so")
                if (expectedLib.exists()) {
                    return@forEach
                }

                val actualLib = sysrootLibDir.resolve(actualTriple).resolve("libc++_shared.so")
                if (!actualLib.exists()) {
                    throw org.gradle.api.GradleException(
                        "Could not locate libc++_shared.so for $actualTriple at $actualLib",
                    )
                }

                expectedLib.parentFile.mkdirs()
                actualLib.copyTo(expectedLib, overwrite = true)
            }
        }
    }
}

val ensureBundledLibCppShared by tasks.registering {
    inputs.property("androidNdkVersion", androidNdkVersion)
    inputs.property("libcxxAbiToNdkTriple", libcxxAbiToNdkTriple)
    outputs.dir(flutterNativeAssetsJniLibsDir)

    doLast {
        val sysrootLibDir = project.resolveAndroidNdkSysrootLibDir()

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

tasks.matching { it.name.startsWith("compileFlutterBuild") }.configureEach {
    dependsOn(ensureMecabHookLibCppAliases)
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

dependencies {
    implementation("com.github.ankidroid:Anki-Android:v2.17.4")
}

flutter {
    source = "../.."
}
