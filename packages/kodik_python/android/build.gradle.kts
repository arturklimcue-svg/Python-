plugins {
    id("com.android.library")
    id("com.chaquo.python") version "17.0.0"
}

group = "com.arturklimcue.kodik_python"
version = "0.0.1"

android {
    namespace = "com.arturklimcue.kodik_python"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

chaquopy {
    defaultConfig {
        version = "3.12"
        // Отключаем байткод-компиляцию: тогда на машине сборки не нужен
        // Python, а код скомпилируется на устройстве при первом запуске.
        pyc {
            src = false
            pip = false
            stdlib = false
        }
    }
}

// Приложение собирается fat-APK, а Python есть только под arm64.
// Ограничиваем ABI, чтобы не тащить лишние мегабайты. Если DSL отличается,
// просто предупреждаем: тогда на других ABI сработает встроенный движок.
gradle.projectsEvaluated {
    try {
        val app = rootProject.findProject(":app")
        val androidExt = app?.extensions?.findByName("android")
        val defaultConfig = androidExt?.javaClass
            ?.getMethod("getDefaultConfig")?.invoke(androidExt)
        val ndk = defaultConfig?.javaClass
            ?.getMethod("getNdk")?.invoke(defaultConfig)
        @Suppress("UNCHECKED_CAST")
        val filters = ndk?.javaClass
            ?.getMethod("getAbiFilters")?.invoke(ndk) as? MutableSet<Any>
        if (filters != null) {
            filters.clear()
            filters.add("arm64-v8a")
        }
    } catch (t: Throwable) {
        logger.warn("kodik_python: не удалось ограничить ABI: ${t.message}")
    }
}
