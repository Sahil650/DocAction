import 'package:flutter/material.dart';
import '../models/scanner_mode.dart';

class ScannerHeader extends StatelessWidget {
  final ScannerMode currentMode;
  final bool isFlashOn;
  final VoidCallback onBack;
  final VoidCallback onToggleFlash;
  final bool useDevanagari;
  final VoidCallback? onToggleOcrLanguage;
  final bool isBatchMode;
  final VoidCallback? onToggleBatchMode;
  final VoidCallback? onCancelReplace;

  const ScannerHeader({
    super.key,
    required this.currentMode,
    required this.isFlashOn,
    required this.onBack,
    required this.onToggleFlash,
    this.useDevanagari = true,
    this.onToggleOcrLanguage,
    this.isBatchMode = false,
    this.onToggleBatchMode,
    this.onCancelReplace,
    this.onDone,
  });

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 10,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const Spacer(),
          if (currentMode == ScannerMode.ocr && onToggleOcrLanguage != null)
            TextButton.icon(
              onPressed: onToggleOcrLanguage,
              icon: const Icon(Icons.language, size: 16, color: Colors.white),
              label: Text(
                useDevanagari ? "HINDI" : "ENGLISH",
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          if (onCancelReplace != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: onCancelReplace,
                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                label: const Text(
                  "CANCEL REPLACE",
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          IconButton(
            onPressed: onToggleFlash,
            icon: Icon(
              isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
              size: 24,
            ),
          ),
          if (onDone != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: onDone,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  "DONE",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
