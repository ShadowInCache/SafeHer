pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    // 4.3.15 was what `flutterfire configure` pinned; 4.5.0 is the version
    // current Firebase Android setup docs specify, and is the one tested
    // against Android Gradle Plugin 8.x.
    id("com.google.gms.google-services") version("4.5.0") apply false
    // Crashlytics is not declared here: the plugin was applied without
    // `firebase_crashlytics` ever being added to pubspec.yaml, so it had no SDK
    // to pair with. Re-add both together if crash reporting is wanted.
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
