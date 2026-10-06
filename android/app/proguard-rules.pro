# Flutter's Gradle plugin adds this file to the release build type by itself.

# LiteRT-LM reaches its Kotlin classes from JNI (GemmaBridge).
-keep class com.google.ai.edge.litertlm.** { *; }
