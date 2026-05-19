# Custom ProGuard rules for Edge Detection (OpenCV)
-keep class org.opencv.** { *; }
-keep class com.neura.edgedetection.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class io.flutter.plugins.** { *; }

# ONNX Runtime
-keep class com.microsoft.onnxruntime.** { *; }

# ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.ml.** { *; }
-keep class com.google.android.gms.tflite.** { *; }

# General Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.engine.FlutterJNI
-dontwarn io.flutter.plugins.**
