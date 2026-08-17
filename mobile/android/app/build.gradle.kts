import java.util.Properties

// Release signing credentials, kept out of the repository.
//
// `key.properties` is gitignored and holds the keystore path and passwords.
// Absent -- on a fresh clone, or in CI -- the release build falls back to the
// debug key so `flutter build apk` still works for anyone who only wants to
// run the app. What it must never do is silently produce a *publishable*
// artifact signed with a key every Android SDK install shares.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // Reads android/app/google-services.json and generates the resources the
    // Firebase SDKs look up at runtime.
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.akshayag.safeher"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // The app's permanent identity on Android. `com.example.*` is the
        // reserved sample prefix and Play rejects it outright; this form is
        // derived from the GitHub account that owns the project, which is the
        // convention when no domain is owned and is provably not someone
        // else's. Changing this after publishing creates a different app, not
        // a renamed one, so it is effectively permanent.
        applicationId = "io.github.akshayag.safeher"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // Resolved against `android/`, not `android/app/`. Gradle's
                // module-level `file()` would look inside app/, which is not
                // where key.properties itself lives -- so a relative path that
                // reads as obviously correct ("safeher-release.jks", next to
                // the properties file naming it) would silently not be found.
                // Absolute paths pass through unchanged.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The debug keystore ships with the Android SDK: same bytes, same
            // password ("android"), on every machine on Earth. Signing a
            // release with it means the signature proves nothing -- anyone can
            // build an update a phone will accept as yours -- and Play rejects
            // such uploads outright.
            //
            // When key.properties is absent the build still works, so a fresh
            // clone can run the app; it just cannot produce something
            // publishable. The warning below is there so that fact is never a
            // surprise at upload time.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "SafeHer: android/key.properties not found -- signing the " +
                        "release build with the shared debug key. This APK is " +
                        "for local testing only and cannot be published."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
