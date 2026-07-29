import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: reads android/key.properties (gitignored) when present, so
// CI/devs can produce a Play-ready signed build. Falls back to the debug
// keystore when absent (so `flutter build apk` still works out of the box).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Google Maps Android key — read from the project's .env (same GOOGLE_MAPS_API_KEY
// the web app uses) and injected as a manifest placeholder, so the key is never
// hardcoded or committed. Empty when .env is absent (map tiles just won't load).
val dotenvProperties = Properties()
val dotenvFile = rootProject.file("../.env")
if (dotenvFile.exists()) {
    dotenvFile.inputStream().use { dotenvProperties.load(it) }
}
val mapsApiKey = (dotenvProperties["GOOGLE_MAPS_API_KEY"] as String?)?.trim() ?: ""

android {
    namespace = "com.exploreros.explorer_os_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.exploreros.explorer_os_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Supplied to the Google Maps meta-data in AndroidManifest.xml.
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real release keystore when configured (key.properties);
            // otherwise sign with debug keys so builds still succeed for testing.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
