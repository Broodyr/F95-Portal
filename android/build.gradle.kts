allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_avif_android 3.1.0 predates AGP 8 / Kotlin 2: it declares Java 11
// without a Kotlin jvmTarget (now a build error), and it ships the same
// plugin stub as both a .java and a .kt file (now a redeclaration error).
// Pin the target and compile only the Java copy (the .java can't be filtered
// out of the Kotlin task's interop analysis, but the .kt can be excluded).
subprojects {
    if (name == "flutter_avif_android") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            exclude("**/FlutterAvifPlugin.kt")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
