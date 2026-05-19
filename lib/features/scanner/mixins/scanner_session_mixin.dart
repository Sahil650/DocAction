import 'package:flutter/material.dart';
import '../models/scanner_mode.dart';
import '../../../data/services/image_optimization_service.dart';

mixin ScannerSessionMixin<T extends StatefulWidget> on State<T> {
  final List<String> photoSessionImages = [];
  final List<String> docSessionImages = [];
  final List<String> sigSessionImages = [];
  final List<String> ocrSessionImages = [];
  
  final Map<String, String> sessionThumbnails = {};
  final _optService = ImageOptimizationService();
  
  int? insertionIndex;
  int? replacementIndex;

  Future<void> addToSession(String path, ScannerMode currentMode) async {
    if (path == "RETAKE") return;

    // Pre-generate thumbnail to avoid massive 12MP resizing on the UI thread
    if (!sessionThumbnails.containsKey(path)) {
      try {
        final thumb = await _optService.generateThumbnail(path);
        if (mounted) {
          setState(() {
            sessionThumbnails[path] = thumb;
          });
        }
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      final targetList = getSessionList(currentMode);
      
      if (replacementIndex != null && replacementIndex! < targetList.length) {
        targetList[replacementIndex!] = path;
        replacementIndex = null; // Reset after one replacement
      } else if (insertionIndex != null && insertionIndex! < targetList.length) {
        targetList.insert(insertionIndex!, path);
        insertionIndex = insertionIndex! + 1;
      } else {
        targetList.add(path);
      }
    });
  }

  List<String> getSessionList(ScannerMode mode) {
    switch (mode) {
      case ScannerMode.document:
        return docSessionImages;
      case ScannerMode.photo:
        return photoSessionImages;
      case ScannerMode.signature:
        return sigSessionImages;
      case ScannerMode.ocr:
        return ocrSessionImages;
      default:
        return [];
    }
  }

  void clearSession(ScannerMode mode) {
    setState(() {
      getSessionList(mode).clear();
    });
  }

  void updateSessionList(ScannerMode mode, List<String> newList) {
    setState(() {
      final targetList = getSessionList(mode);
      targetList.clear();
      targetList.addAll(newList);
    });
  }
}
