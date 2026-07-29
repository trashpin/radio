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

    // Some older Flutter plugins (e.g. file_picker 3.x) declare `package` in
    // their AndroidManifest but no `namespace`, which AGP 8 requires. Inject one
    // from the manifest package (via reflection, so this root script needs no
    // AGP types). Registered BEFORE evaluationDependsOn so it isn't too late.
    afterEvaluate {
        val ext = extensions.findByName("android") ?: return@afterEvaluate
        val getNamespace = ext.javaClass.methods.firstOrNull { it.name == "getNamespace" }
        val current = getNamespace?.invoke(ext) as String?
        if (current == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            val pkg = if (manifest.exists()) {
                Regex("package=\"(.+?)\"").find(manifest.readText())?.groupValues?.get(1)
            } else null
            val namespace = pkg ?: "com.exploreros." + project.name.replace(Regex("[-.]"), "_")
            ext.javaClass.methods
                .firstOrNull { it.name == "setNamespace" && it.parameterCount == 1 }
                ?.invoke(ext, namespace)
        }
    }

    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
