import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// The Worker's address and its SYNC_TOKEN live in the gitignored android/local.properties:
//   VOZ_URL=https://your-worker.workers.dev
//   VOZ_TOKEN=...
// Left out, the screensaver shows the built-in phrases and whatever it last cached.
val local = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.reader()?.use { load(it) }
}

android {
    namespace = "com.vozlocal.screensaver"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.vozlocal.screensaver"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
        buildConfigField("String", "VOZ_URL", "\"${local.getProperty("VOZ_URL", "")}\"")
        buildConfigField("String", "VOZ_TOKEN", "\"${local.getProperty("VOZ_TOKEN", "")}\"")
    }

    // The Chrome new tab's logic, phrases and font ship as they are in chrome/extension, the single source.
    sourceSets["main"].assets.srcDirs("../../chrome/extension/lib", "../../chrome/extension/data", "../../chrome/extension/fonts")

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Serves the bundled page from a real https origin, so its ES modules and localStorage work.
    implementation("androidx.webkit:webkit:1.12.1")
}
