import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing material from a file on a developer machine, or the environment on a
// runner. Never from the repository: android/.gitignore already excludes
// key.properties and every keystore extension, and nothing here would put one
// there anyway.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, variable: String): String? =
    keyProperties.getProperty(property) ?: System.getenv(variable)

val releaseKeystore = signingValue("storeFile", "CAELO_KEYSTORE")

android {
    namespace = "team.gdb.caelo"
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
        applicationId = "team.gdb.caelo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Pinned rather than inherited from flutter.minSdkVersion. The core's
        // .so is built against this exact API by caelo-core's build-so.sh, and
        // a Flutter upgrade that moved the default would leave a library that
        // fails to load on the oldest devices we still claim to support — and
        // only on those.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseKeystore != null) {
                storeFile = file(releaseKeystore)
                storePassword = signingValue("storePassword", "CAELO_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "CAELO_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "CAELO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Falling back to the debug key rather than failing, so that anyone
            // who clones this can build and run a release build without being
            // handed a private key first. An open-source project that cannot be
            // built by a stranger is not really open.
            //
            // The fallback announces itself, and the release workflow refuses to
            // run without the real keystore, because the danger is not building
            // a debug-signed APK -- it is publishing one. Android will not update
            // an installation across a change of signing key, so an APK released
            // by accident under the debug key strands everyone who installed it:
            // they have to uninstall, losing whatever the app was holding, and
            // there is no way to fix it from our side afterwards.
            signingConfig = if (releaseKeystore != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Caelo: no release keystore, signing with the debug key. " +
                    "Fine for local use; see docs/signing.md before publishing."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
