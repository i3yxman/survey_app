// android/settings.gradle.kts

import org.gradle.api.initialization.resolve.RepositoriesMode

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
        // 插件用的仓库
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// 👉 关键新增：让依赖解析“更信任项目里的 repositories（build.gradle.kts）”
dependencyResolutionManagement {
    // 默认是 PREFER_SETTINGS / FAIL_ON_PROJECT_REPOS，
    // 我们改成 PREFER_PROJECT，让 android/build.gradle.kts 里的 repositories 合法
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)

    repositories {
        google()
        mavenCentral()
        // 如果以后需要加其他仓库（比如公司内网 Nexus），也写在这里
        // maven("https://your.internal.repo")
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")