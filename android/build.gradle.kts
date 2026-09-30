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

// Some plugins declare a compileSdk lower than what their transitive dependencies require.
// gradle.afterProject fires after each project finishes its own configuration, so it
// runs after the module has set its compileSdk and we can safely override it.
gradle.afterProject {
    extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
        // sound_effect 0.1.3 declares compileSdk 35 but flutter_plugin_android_lifecycle requires 36+.
        val minRequired = 36
        if ((compileSdk ?: 0) < minRequired) compileSdk = minRequired
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
