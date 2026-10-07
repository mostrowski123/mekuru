# Flutter release builds run R8. These libraries construct their Java classes
# from JNI (FindClass/GetMethodID by name), which R8 cannot see; without these
# rules a release build aborts in OrtSession.getInputInfo with
# NoSuchMethodError ai.onnxruntime.NodeInfo.<init> the moment a scan starts.
-keep class ai.onnxruntime.** { *; }
-keep class org.opencv.** { *; }
# JNI entry points are resolved by name from libmekuru_ocr_detector.so.
-keep class moe.matthew.mekuru.ocr.ComicTextDetectorNative { *; }
