import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'dart:math';

class ScannerService {
  /// REAL-TIME AR DETECTOR (Extracts edges natively from raw Y-Plane video frame)
  static Future<List<cv.Point>?> detectRealtime(
    int width,
    int height,
    Uint8List yPlaneBytes,
    int sensorOrientation,
  ) async {
    return await compute((params) {
      final w = params['w'] as int;
      final h = params['h'] as int;
      final bytes = params['bytes'] as Uint8List;
      final rotation = params['rot'] as int;

      // Ensure dimensions are greater than 0
      if (w <= 0 || h <= 0 || bytes.isEmpty) return null;

      // EXTREME PERFORMANCE FIX: Native C++ Pointer Buffer Allocation
      // Avoids millions of generic Dart integers by pushing raw bytes straight directly to C++ memory
      final ffi.Pointer<ffi.Uint8> pointer = calloc<ffi.Uint8>(bytes.length);
      final nativeList = pointer.asTypedList(bytes.length);
      nativeList.setAll(0, bytes);

      var gray = cv.Mat.fromBuffer(
        h,
        w,
        cv.MatType.CV_8UC1,
        pointer.cast<ffi.Void>(),
      );

      // Rotate image horizontally/vertically to match phone UI orientation
      if (rotation == 90 || rotation == 270) {
        gray = cv.rotate(
          gray,
          rotation == 90
              ? cv.ROTATE_90_CLOCKWISE
              : cv.ROTATE_90_COUNTERCLOCKWISE,
        );
      } else if (rotation == 180) {
        gray = cv.rotate(gray, cv.ROTATE_180);
      }

      // 1. Calculate ratio to shrink for SPEED and accuracy
      final double ratio = gray.rows / 300.0;
      if (ratio <= 0) {
        calloc.free(pointer);
        return null;
      }

      final int newWidth = (gray.cols / ratio).round();
      final resized = cv.resize(gray, (newWidth, 300));

      // 2. Preprocess (Bilateral Filter + Adaptive Canny)
      // Bilateral filter preserves edges better than Gaussian Blur
      final blurred = cv.bilateralFilter(resized, 5, 50, 50);
      final edged = cv.canny(blurred, 50, 120);

      // Morphological Dilation to thicken edges and close gaps
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      final closed = cv.dilate(edged, kernel, iterations: 1);

      // 3. Contour Detection
      final (contours, _) = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      final sortedContours = contours.toList()
        ..sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));

      List<cv.Point>? finalPoints;
      for (int i = 0; i < sortedContours.length && i < 3; i++) {
        final contour = sortedContours[i];
        final peri = cv.arcLength(contour, true);
        // Using 0.02 instead of 0.03 for more precision on corners
        final approx = cv.approxPolyDP(contour, 0.02 * peri, true);

        // Found 4 points with a decent size area?
        if (approx.length == 4 &&
            cv.contourArea(approx) > (300 * newWidth * 0.05)) {
          final pts = approx
              .toList()
              .map(
                (p) => cv.Point((p.x * ratio).round(), (p.y * ratio).round()),
              )
              .toList();
          finalPoints = _reorderPoints(pts);
          break;
        }
      }

      // Free Native Memory explicitly to avoid C++ memory leaks!
      calloc.free(pointer);
      return finalPoints;
    }, {'w': width, 'h': height, 'bytes': yPlaneBytes, 'rot': sensorOrientation});
  }

  /// Detects the corners of a document in an image.
  /// Returns a list of 4 points (top-left, top-right, bottom-right, bottom-left).
  static Future<List<cv.Point>?> detectDocument(String imagePath) async {
    return await compute((path) {
      final img = cv.imread(path);
      if (img.isEmpty) return null;

      // 1. Calculate ratio and resize for better edge detection
      // High-resolution images have too much noise; downscaling makes edge detection highly accurate.
      final double ratio = img.rows / 500.0;
      final int newWidth = (img.cols / ratio).round();
      final resized = cv.resize(img, (newWidth, 500));

      // 2. Preprocess
      final gray = cv.cvtColor(resized, cv.COLOR_BGR2GRAY);

      // Apply a bilateral filter instead of generic blur to preserve edges while removing noise
      final blurred = cv.bilateralFilter(gray, 9, 75, 75);

      // Boost contrast slightly before Canny
      final edged = cv.canny(blurred, 30, 100);

      // Morphological operations to close any gaps in the document edges
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      final closed = cv.dilate(edged, kernel, iterations: 1);

      // 3. Find Contours
      final (contours, _) = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );

      // 4. Find Largest Quadrilateral
      final sortedContours = contours.toList()
        ..sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));

      for (int i = 0; i < sortedContours.length && i < 5; i++) {
        final contour = sortedContours[i];
        final peri = cv.arcLength(contour, true);
        final approx = cv.approxPolyDP(contour, 0.02 * peri, true);

        if (approx.length == 4) {
          // Found it! Scale points back to original high-res image size
          final pts = approx
              .toList()
              .map(
                (p) => cv.Point((p.x * ratio).round(), (p.y * ratio).round()),
              )
              .toList();
          return _reorderPoints(pts);
        }
      }

      return null;
    }, imagePath);
  }

  /// Reorders points to [Top-Left, Top-Right, Bottom-Right, Bottom-Left]
  static List<cv.Point> _reorderPoints(List<cv.Point> pts) {
    if (pts.length != 4) return pts;

    // Sum and Difference are common ways to find TL/BR and TR/BL
    final sortedBySum = List<cv.Point>.from(pts)
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));

    final tl = sortedBySum.first;
    final br = sortedBySum.last;

    final remaining = pts.where((p) => p != tl && p != br).toList();
    remaining.sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));

    final bl = remaining.first;
    final tr = remaining.last;

    return [tl, tr, br, bl];
  }

  static double _distance(cv.Point p1, cv.Point p2) {
    return sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2));
  }

  /// Processes the document: warps perspective and applies filters.
  static Future<String?> processDocument(
    String sourcePath,
    List<cv.Point> corners, {
    String filter = 'none',
  }) async {
    return await compute((params) async {
      final path = params['path'] as String;
      final pts = params['corners'] as List<cv.Point>;
      final filterType = params['filter'] as String;

      final img = cv.imread(path);
      if (img.isEmpty) return null;

      // 1. Perspective Transform
      // Calculate target size (max width/height)
      final tl = pts[0];
      final tr = pts[1];
      final br = pts[2];
      final bl = pts[3];

      final widthA = _distance(br, bl);
      final widthB = _distance(tr, tl);
      final maxWidth = widthA.clamp(widthB, 99999).toInt();

      final heightA = _distance(tr, br);
      final heightB = _distance(tl, bl);
      final maxHeight = heightA.clamp(heightB, 99999).toInt();

      final dstPoints = [
        cv.Point(0, 0),
        cv.Point(maxWidth - 1, 0),
        cv.Point(maxWidth - 1, maxHeight - 1),
        cv.Point(0, maxHeight - 1),
      ];

      final M = cv.getPerspectiveTransform(
        cv.VecPoint.fromList(pts),
        cv.VecPoint.fromList(dstPoints),
      );
      var warped = cv.warpPerspective(img, M, (maxWidth, maxHeight));

      // 2. Apply Filters
      switch (filterType) {
        case 'grayscale':
          warped = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
          break;
        case 'magic':
          // Enhance contrast and brightness
          final gray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
          warped = cv.adaptiveThreshold(
            gray,
            255,
            cv.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv.THRESH_BINARY,
            11,
            2,
          );
          break;
        case 'contrast':
          final gray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
          cv.equalizeHist(gray); // Simple enhancement
          warped = gray;
          break;
      }

      // 3. Save to temp
      final tempDir = Directory.systemTemp;
      final targetPath = p.join(
        tempDir.path,
        "PROC_${DateTime.now().millisecondsSinceEpoch}.jpg",
      );
      cv.imwrite(targetPath, warped);

      return targetPath;
    }, {'path': sourcePath, 'corners': corners, 'filter': filter});
  }



  /// Suggests a smart name for a document based on timestamp
  static Future<String> getSmartName(String imagePath) async {
    final now = DateTime.now();
    return "Scan_${now.day}${now.month}_${now.hour}${now.minute}";
  }
}
