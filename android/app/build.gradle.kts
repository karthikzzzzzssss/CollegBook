plugins {
    id("com.android.application")
    // google-services.json is the native app's (com.minibrain.collegebook).
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.minibrain.collegebook"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // The mentor incoming-call screens are the native app's own (view binding, BuildConfig).
    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    // The native app ships Agora's basic SDK (full-rtc-basic), without the optional
    // extensions; the Flutter plugin brings the full SDK. Leave out the extensions the
    // app never enables (~35 MB per ABI).
    packaging {
        jniLibs {
            excludes += listOf(
                "lib/*/libagora_lip_sync_extension.so",
                "lib/*/libagora_clear_vision_extension.so",
                "lib/*/libagora_spatial_audio_extension.so",
                "lib/*/libagora_ai_noise_suppression_extension.so",
                "lib/*/libagora_ai_noise_suppression_ll_extension.so",
                "lib/*/libagora_ai_echo_cancellation_extension.so",
                "lib/*/libagora_ai_echo_cancellation_ll_extension.so",
                "lib/*/libagora_segmentation_extension.so",
                "lib/*/libagora_face_capture_extension.so",
                "lib/*/libagora_face_detection_extension.so",
                "lib/*/libagora_audio_beauty_extension.so",
                "lib/*/libagora_content_inspect_extension.so",
                "lib/*/libagora_video_quality_analyzer_extension.so",
                "lib/*/libagora_video_av1_encoder_extension.so",
                "lib/*/libagora_video_av1_decoder_extension.so",
                "lib/*/libagora_screen_capture_extension.so",
            )
        }
    }

    defaultConfig {
        applicationId = "com.minibrain.collegebook"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the debug key until the Play Store keystore is configured.
            signingConfig = signingConfigs.getByName("debug")
            // The native app's R8 rules (Gson models, Retrofit API, Agora, Razorpay).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    // FileProvider for sharing choice-list downloads on Android 7-9.
    implementation("androidx.core:core-ktx:1.13.1")

    // Mentor incoming calls, as in the native app (same libraries and versions).
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity:1.13.0")
    implementation("com.google.android.material:material:1.14.0")
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    implementation("com.squareup.retrofit2:retrofit:3.0.0")
    implementation("com.squareup.retrofit2:converter-gson:3.0.0")
    implementation("com.google.code.gson:gson:2.13.2")
}
