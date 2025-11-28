// android/build.gradle.kts
import org.gradle.api.Project
import org.gradle.api.Task
import org.gradle.api.execution.TaskExecutionListener
import org.gradle.api.tasks.TaskState
import org.gradle.kotlin.dsl.extra
import com.android.build.gradle.LibraryExtension

buildscript {
    extra["kotlin_version"] = "2.1.0"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:${project.extra["kotlin_version"]}")
    }
}

gradle.buildFinished {
    if (failure == null) {
        println("\n----------------------------------------")
        println("|   Thank you for building!             |")
        println("|   Build completed successfully!       |")
        println("----------------------------------------")
    }
}

rootProject.buildDir = file("../build")
subprojects {
    buildDir = file("${rootProject.buildDir.path}/${project.name}")
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://mvn.getui.com/nexus/content/repositories/releases/")
        }
    }
}

// Inject namespace for legacy Android library modules that miss it (AGP 8+ requirement)
subprojects {
    if (name == "uni_links") {
        plugins.withId("com.android.library") {
            // Configure the Android Library extension to set the required namespace
            extensions.configure<LibraryExtension>("android") {
                namespace = "name.avioli.unilinks"
            }
        }
    }
    if (name == "clipboard_watcher") {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryExtension>("android") {
                namespace = "clipboard.watcher"
            }
        }
        
        // 自动修复 AndroidManifest.xml
        tasks.register("fixClipboardWatcherManifest") {
            doLast {
                val manifestFile = file("${project.projectDir}/src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    var content = manifestFile.readText()
                    if (content.contains("package=\"clipboard.watcher\"")) {
                        content = content.replace("""package="clipboard.watcher"""", "")
                        manifestFile.writeText(content)
                        println("Fixed clipboard_watcher AndroidManifest.xml")
                    }
                }
            }
        }
        
        tasks.configureEach {
            if (name.contains("process") && name.contains("Manifest")) {
                dependsOn("fixClipboardWatcherManifest")
            }
        }
    }
}