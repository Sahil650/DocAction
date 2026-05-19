import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

mixin ScannerQrMixin<T extends StatefulWidget> on State<T> {
  MobileScannerController? mobileScannerController;
  bool isQrEngineInitialized = false;
  String? qrResult;

  Future<void> initializeMobileScanner(bool isFlashOn) async {
    mobileScannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: isFlashOn,
    );
    if (mounted) {
      setState(() {
        isQrEngineInitialized = true;
      });
    }
  }

  Future<void> disposeMobileScanner() async {
    mobileScannerController?.dispose();
    mobileScannerController = null;
    if (mounted) {
      setState(() {
        isQrEngineInitialized = false;
      });
    }
  }

  void resetQrResult() {
    setState(() => qrResult = null);
  }
}
