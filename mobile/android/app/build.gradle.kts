plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes only from the owner's key supplied through environment
// variables. No keystore or password is stored in the repository.
val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "dev.personalagent.personal_assistant"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.personalagent.personal_assistant"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(checkNotNull(releaseKeystorePath))
                storePassword = checkNotNull(releaseStorePassword)
                keyAlias = checkNotNull(releaseKeyAlias)
                keyPassword = checkNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            // Never silently produce a debug-signed release APK.
            signingConfig = signingConfigs.getByName("release")
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

// Build the local, offline Rust search library for the Android ABIs used by
// the API 36 emulator and ARM64 phone releases. No generated .so is committed.
val rustSearchDir = project.file("../../rust/local_search")
val rustJniLibsDir = project.file("src/main/jniLibs")
val buildRustLocalSearch = tasks.register<Exec>("buildRustLocalSearch") {
    workingDir = rustSearchDir
    environment("CARGO_BUILD_JOBS", "2")
    commandLine(
        "cargo", "ndk",
        "--platform", "26",
        "-t", "arm64-v8a",
        "-t", "x86_64",
        "-o", rustJniLibsDir.absolutePath,
        "build", "--release",
    )
    inputs.files(fileTree(rustSearchDir) { exclude("target/**") })
    outputs.files(
        file("src/main/jniLibs/arm64-v8a/libpersonal_local_search.so"),
        file("src/main/jniLibs/x86_64/libpersonal_local_search.so"),
    )
}
tasks.named("preBuild") {
    dependsOn(buildRustLocalSearch)
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
}
