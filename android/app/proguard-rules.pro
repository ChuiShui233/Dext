-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }

-keep class com.chuishui.Dext.MainApplication { *; }
-keep class com.chuishui.Dext.MainActivity { *; }

-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback {
    <init>(...);
}

-keep class kotlin.Metadata { *; }

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keepclasseswithmembernames class * {
    native <methods>;
}

-keep class com.sbo.radioplayer.** { *; }

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.tasks.**
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }


-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

-assumenosideeffects class kotlinx.coroutines.debug.internal.DebugProbesKt {
    public static *** probeCoroutineCreated(...);
    public static *** probeCoroutineResumed(...);
    public static *** probeCoroutineSuspended(...);
}
-dontwarn kotlinx.coroutines.debug.**
-dontnote kotlinx.coroutines.debug.**

-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    public static void check*(...);
    public static void throw*(...);
}

-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

-assumenosideeffects class kotlin.jvm.internal.DebugMetadata {
    *;
}
