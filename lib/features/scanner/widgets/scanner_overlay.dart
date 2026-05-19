import 'package:flutter/material.dart';
import '../models/scanner_mode.dart';

class ScannerOverlay extends StatelessWidget {
  final ScannerMode currentMode;
  final Widget? signatureFrame;
  final Widget? qrViewfinder;
  final String? documentLabel;

  const ScannerOverlay({
    super.key,
    required this.currentMode,
    this.signatureFrame,
    this.qrViewfinder,
    this.documentLabel,
  });

  @override
  Widget build(BuildContext context) {
    switch (currentMode) {
      case ScannerMode.signature:
        return signatureFrame ?? const SizedBox.shrink();
      case ScannerMode.qrCode:
        return qrViewfinder ?? const SizedBox.shrink();
      case ScannerMode.document:
      case ScannerMode.ocr:
        return DocumentGuideOverlay(label: documentLabel);
      default:
        return const SizedBox.shrink();
    }
  }
}

class DocumentGuideOverlay extends StatelessWidget {
  final String? label;
  const DocumentGuideOverlay({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        Positioned(
          bottom: 250,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              label ?? "ALIGN DOCUMENT WITHIN FRAME",
              style: TextStyle(
                color: Colors.white,
                fontSize: screenWidth < 360 ? 11 : 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
