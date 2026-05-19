import 'dart:io';
import 'dart:ui';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class OCRService {
  TextRecognizer? _latinRecognizer;
  TextRecognizer? _devanagariRecognizer;

  Future<TextRecognizer> _getRecognizer(bool useDevanagari) async {
    if (useDevanagari) {
      _devanagariRecognizer ??= TextRecognizer(script: TextRecognitionScript.devanagiri);
      return _devanagariRecognizer!;
    } else {
      _latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      return _latinRecognizer!;
    }
  }

   Future<String> processImage(String imagePath, {bool useDevanagari = true, bool enhance = true}) async {
    String finalPath = imagePath;
    if (enhance) {
      finalPath = await _enhanceImage(imagePath);
    }
    
    final inputImage = InputImage.fromFilePath(finalPath);
    final recognizer = await _getRecognizer(useDevanagari);
    final RecognizedText recognizedText = await recognizer.processImage(inputImage);
    
    // Cleanup enhanced temp file
    if (enhance && finalPath != imagePath) {
      try {
        final file = File(finalPath);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint("OCR Cleanup Error: $e");
      }
    }
    
    return recognizedText.text;
  }

  Future<String> _enhanceImage(String imagePath) async {
    final tempDir = await getTemporaryDirectory();
    final enhancedPath = p.join(tempDir.path, "enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg");
    
    return await Isolate.run(() async {
      // Basic image enhancement for OCR
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return imagePath;

      // 1. Grayscale
      image = img.grayscale(image);
      
      // 2. Adjust contrast
      image = img.contrast(image, contrast: 120);

      // 3. Save to temp file
      await File(enhancedPath).writeAsBytes(img.encodeJpg(image, quality: 85));
      return enhancedPath;
    });
  }

  Future<RecognizedText> getRecognizedText(String imagePath, {bool useDevanagari = true, bool enhance = true}) async {
    String finalPath = imagePath;
    if (enhance) {
      finalPath = await _enhanceImage(imagePath);
    }
    final inputImage = InputImage.fromFilePath(finalPath);
    final recognizer = await _getRecognizer(useDevanagari);
    final result = await recognizer.processImage(inputImage);

    // Cleanup enhanced temp file
    if (enhance && finalPath != imagePath) {
      try {
        final file = File(finalPath);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint("OCR Cleanup Error: $e");
      }
    }
    
    return result;
  }

  Future<List<OCRBlock>> recognizeLive(String imagePath, {bool useDevanagari = true}) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizer = await _getRecognizer(useDevanagari);
    final RecognizedText recognizedText = await recognizer.processImage(inputImage);
    
    return recognizedText.blocks.map((block) {
      return OCRBlock(
        text: block.text,
        rect: block.boundingBox,
      );
    }).toList();
  }

  void dispose() {
    _latinRecognizer?.close();
    _devanagariRecognizer?.close();
  }
}

class OCRBlock {
  final String text;
  final Rect rect;

  OCRBlock({required this.text, required this.rect});
}
