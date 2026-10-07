plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.vyra.kids"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.vyra.kids"
        minSdk = 26
        targetSdk = 34
        versionCode = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull() ?: 64
        versionName = "1.0.${System.getenv("GITHUB_RUN_NUMBER") ?: "64"}"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            storeFile = file("../keystore/vyra_release.p12")
            storePassword = "vyra2026pass"
            keyAlias = "vyra_key"
            keyPassword = "vyra2026pass"
            storeType = "PKCS12"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        viewBinding = true
    }
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    
    // WorkManager for robust offline-to-online vault sync
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    
    // Coroutines & Lifecycle
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.lifecycle:lifecycle-service:2.8.4")
    
    // JSON & Networking
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Bundled Offline ML Kit (Zero-download, Hindi + English Devanagari OCR)
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")

    testImplementation("junit:junit:4.13.2")
}

