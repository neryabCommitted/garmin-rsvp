// AGP 9 deprecates BaseExtension (used below to reach the plugin `android {}`
// blocks); it still works and the build script compiles with warnings-as-errors,
// so suppress at file scope until the AGP-9 CommonExtension migration is done.
@file:Suppress("DEPRECATION")

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Story 2.3 Task 8: receive_sharing_intent (and similar plugins) compile Java to
// 11 while Kotlin targets 17, producing an "Inconsistent JVM-target" build
// failure. The app module is already 17/17; bump each plugin module's Android
// compileOptions to 17 so AGP wires its JavaCompile task to match Kotlin's 17.
// (KasemJaffer/receive_sharing_intent#326,#344)
subprojects {
    // :app is evaluated early (via evaluationDependsOn above) and is already
    // 17/17, so skip it; defer the fix to the still-unevaluated plugin modules
    // (their build.gradle sets Java 11, which we override to 17 afterEvaluate).
    if (!state.executed) {
        afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                val android = ext as com.android.build.gradle.BaseExtension
                android.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
                // file_picker pins compileSdk 34, but its transitive
                // flutter_plugin_android_lifecycle requires >=36. Align plugins
                // to the app's compileSdk (36).
                android.compileSdkVersion(36)
            }
            // watch_connectivity_garmin compiles Kotlin to the 1.8 default while
            // its Java is 17 (the inverse of the receive_sharing_intent case
            // above) — again tripping "Inconsistent JVM-target". Pin every plugin
            // module's Kotlin compile task to 17 so it matches its Java target.
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
