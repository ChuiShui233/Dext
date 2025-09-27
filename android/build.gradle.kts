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
        classpath("com.android.tools.build:gradle:8.1.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:${project.extra["kotlin_version"]}")
    }
}

// 注册构建完成监听器
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
}