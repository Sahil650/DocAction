import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

mixin ScannerCameraMixin<T extends StatefulWidget> on State<T> {
  CameraController? cameraController;
  List<CameraDescription>? cameras;
  bool isInitialized = false;
  bool isFlashOn = false;

  // Zoom & Focus
  double minZoom = 1.0;
  double maxZoom = 1.0;
  double currentZoom = 1.0;
  double baseZoom = 1.0;
  Offset? focusPoint;
  Timer? focusTimer;

  Future<void> initializeCamera({
    required ResolutionPreset resolution,
    required ImageFormatGroup androidFormat,
    required ImageFormatGroup iosFormat,
    Function()? onReady,
  }) async {
    try {
      cameras = await availableCameras();
      if (cameras != null && cameras!.isNotEmpty) {
        cameraController = CameraController(
          cameras![0],
          resolution,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? androidFormat : iosFormat,
        );

        await cameraController!.initialize();
        
        minZoom = await cameraController!.getMinZoomLevel();
        maxZoom = await cameraController!.getMaxZoomLevel();
        currentZoom = minZoom;

        if (mounted) {
          setState(() => isInitialized = true);
          onReady?.call();
        }
      }
    } catch (e) {
      debugPrint("Camera Initialization Error: $e");
    }
  }

  Future<void> disposeStandardCamera() async {
    if (cameraController != null) {
      if (cameraController!.value.isStreamingImages) {
        await cameraController!.stopImageStream();
      }
      await cameraController!.dispose();
      cameraController = null;
      if (mounted) setState(() => isInitialized = false);
    }
  }

  Future<void> toggleFlash() async {
    if (!isInitialized || cameraController == null) return;

    HapticFeedback.lightImpact();
    try {
      final newFlashMode = isFlashOn ? FlashMode.off : FlashMode.torch;
      await cameraController!.setFlashMode(newFlashMode);
      if (mounted) setState(() => isFlashOn = !isFlashOn);
    } catch (e) {
      debugPrint("Flash Error: $e");
    }
  }

  Future<void> setZoom(double zoom) async {
    if (cameraController == null) return;
    double newZoom = zoom.clamp(minZoom, maxZoom);
    if (newZoom != currentZoom) {
      currentZoom = newZoom;
      await cameraController!.setZoomLevel(currentZoom);
      if (mounted) setState(() {});
    }
  }

  Future<void> handleFocus(Offset localPosition, Size previewSize) async {
    if (cameraController == null) return;

    final focusPointRelative = Offset(
      localPosition.dx / previewSize.width,
      localPosition.dy / previewSize.height,
    );

    try {
      if (mounted) {
        setState(() {
          focusPoint = localPosition;
          focusTimer?.cancel();
          focusTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => focusPoint = null);
          });
        });
      }

      await cameraController!.setFocusPoint(focusPointRelative);
      await cameraController!.setExposurePoint(focusPointRelative);
    } catch (e) {
      debugPrint("Focus Error: $e");
    }
  }
}
