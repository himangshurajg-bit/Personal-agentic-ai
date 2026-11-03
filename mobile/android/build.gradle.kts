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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// local_auth_android 1.0.56 still pins Robolectric 4.15.1, whose SDK metadata
// parser rejects API 36 test manifests. Keep only that dependency's generated
// unit-test package at API 35 until its test harness supports API 36; the app
// itself continues to target SDK 36.
subprojects {
    if (name == "local_auth_android") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                testOptions.targetSdk = 35
            }
        }
    }
}
