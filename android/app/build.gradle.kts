import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        load(FileInputStream(localPropertiesFile))
    }
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

val mapsApiKey = localProperties.getProperty("MAPS_API_KEY", "")
val debugAdmobAppId = "ca-app-pub-3940256099942544~3347511713"
val releaseAdmobAppId = localProperties.getProperty("ADMOB_APP_ID", "")
val effectiveReleaseAdmobAppId =
    releaseAdmobAppId.ifBlank { debugAdmobAppId }
val hasReleaseSigning =
    keystoreProperties.getProperty("storeFile")?.isNotBlank() == true &&
    keystoreProperties.getProperty("storePassword")?.isNotBlank() == true &&
    keystoreProperties.getProperty("keyAlias")?.isNotBlank() == true &&
    keystoreProperties.getProperty("keyPassword")?.isNotBlank() == true

android {
    namespace = "com.evranger.ev_router_app2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        }
    }

    defaultConfig {
        applicationId = "com.evranger.ev_router_app2"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
        manifestPlaceholders["admobAppId"] = effectiveReleaseAdmobAppId
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["admobAppId"] = debugAdmobAppId
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (!hasReleaseSigning) {
                throw GradleException(
                    "Release signing is not configured. Create android/key.properties with the upload keystore credentials."
                )
            }
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("com.google.android.play:core:1.10.3")
}

flutter {
    source = "../.."
}
