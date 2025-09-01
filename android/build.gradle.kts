// android/build.gradle.kts
import org.gradle.api.Project
import org.gradle.api.Task
import org.gradle.api.execution.TaskExecutionListener
import org.gradle.api.tasks.TaskState
import org.gradle.kotlin.dsl.extra

buildscript {
    extra["kotlin_version"] = "1.9.22"
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