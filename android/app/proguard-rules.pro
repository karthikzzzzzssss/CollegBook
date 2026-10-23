# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# ---- App rules (release builds run R8 with minifyEnabled true) ----

# Keep readable crash stack traces; Play uses the uploaded mapping.txt to deobfuscate.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Generic signatures / inner classes are needed by Gson TypeToken and Retrofit.
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*

# Gson maps JSON by field name via reflection. Not every model field has
# @SerializedName, so keep the whole Model package (incl. nested classes) unrenamed.
-keep class com.minibrain.collegebook.Model.** { *; }

# Gson TypeToken anonymous subclasses (e.g. new TypeToken<...>() {}).
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Retrofit service interfaces.
-keep,allowobfuscation interface com.minibrain.collegebook.APIServices.API

# Razorpay Checkout (per Razorpay integration docs).
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}

# Agora RTC SDK (uses JNI callbacks into Java).
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Release builds: strip debug/verbose/info logs so nothing sensitive can reach
# logcat on users' phones. Errors/warnings stay for crash diagnosis (they never include tokens).
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static boolean isLoggable(java.lang.String, int);
}
