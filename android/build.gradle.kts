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

// --- CORRECTEUR DE COMPATIBILITÉ GRADLE 8+ ---
subprojects {
    // On utilise 'plugins.withType' pour intervenir dès que le plugin Android est appliqué
    plugins.withType<com.android.build.gradle.api.AndroidBasePlugin> {
        val android = extensions.getByType<com.android.build.gradle.BaseExtension>()

        // 1. Force le Namespace si absent
        if (android.namespace == null) {
            android.namespace = "id.kakzaki.blue_thermal_printer"
        }

        // 2. Nettoyage du Manifest (Suppression de l'attribut package)
        android.sourceSets.getByName("main") {
            val manifestFile = manifest.srcFile
            if (manifestFile.exists()) {
                val content = manifestFile.readText()
                if (content.contains("package=")) {
                    val updatedContent = content.replace(Regex("""package="[^"]*""""), "")
                    // On crée un fichier temporaire pour ne pas modifier le cache Pub directement
                    val tempDir = File(project.buildDir, "intermediates/fixed_manifests")
                    tempDir.mkdirs()
                    val tempManifest = File(tempDir, "AndroidManifest.xml")
                    tempManifest.writeText(updatedContent)
                    manifest.srcFile(tempManifest)
                }
            }
        }
    }
}
// ---------------------------------------------

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}