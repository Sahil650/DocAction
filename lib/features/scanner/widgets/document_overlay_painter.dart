import 'package:flutter/material.dart';

/// Paints a quadrilateral overlay representing detected document corners
/// on top of the camera preview.
class DocumentOverlayPainter extends CustomPainter {
  final List<Offset> corners; // Normalized coordinates (0-1)
  final Size previewSize;
  final bool isStable;
  final Color? color;

  DocumentOverlayPainter({
    required this.corners,
    required this.previewSize,
    this.isStable = true,
    this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty || corners.length != 4) return;

    // Convert normalized coordinates to screen coordinates
    // Camera preview typically uses cover fit, so we need to handle aspect ratio
    final screenRatio = size.width / size.height;
    final cameraRatio = previewSize.width / previewSize.height;

    double scaleX, scaleY, offsetX, offsetY;

    if (cameraRatio > screenRatio) {
      // Width fits, height has letterbox
      scaleX = size.width / previewSize.width;
      scaleY = scaleX;
      offsetY = (size.height - previewSize.height * scaleY) / 2;
      offsetX = 0;
    } else {
      // Height fits, width has letterbox
      scaleY = size.height / previewSize.height;
      scaleX = scaleY;
      offsetX = (size.width - previewSize.width * scaleX) / 2;
      offsetY = 0;
    }

    // Scale corners to screen space
    final screenCorners = corners.map((c) {
      return Offset(
        offsetX + c.dx * previewSize.width * scaleX,
        offsetY + c.dy * previewSize.height * scaleY,
      );
    }).toList();

    // Create the polygon path
    final path = Path();
    path.moveTo(screenCorners[0].dx, screenCorners[0].dy);
    for (int i = 1; i < 4; i++) {
      path.lineTo(screenCorners[i].dx, screenCorners[i].dy);
    }
    path.close();

    // Draw fill
    final fillPaint = Paint()
      ..color = (color ?? Colors.white).withValues(alpha: isStable ? 0.15 : 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = (color ?? Colors.white)
      ..strokeWidth = isStable ? 3.0 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, borderPaint);

    // Draw corner points
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;

    for (final corner in screenCorners) {
      canvas.drawCircle(corner, isStable ? 6.0 : 4.0, cornerPaint);

      final innerPaint = Paint()
        ..color = (color ?? Colors.white)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(corner, isStable ? 3.0 : 2.0, innerPaint);
    }

    // Draw guide lines (optional - helps with alignment)
    if (!isStable) {
      _drawGuides(canvas, screenCorners, size);
    }
  }

  void _drawGuides(Canvas canvas, List<Offset> corners, Size size) {
    final guidePaint = Paint()
      ..color = (color ?? Colors.white).withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw diagonal lines
    canvas.drawLine(corners[0], corners[2], guidePaint);
    canvas.drawLine(corners[1], corners[3], guidePaint);
  }

  @override
  bool shouldRepaint(covariant DocumentOverlayPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.isStable != isStable ||
        oldDelegate.previewSize != previewSize;
  }
}

/// Painter for the capture frame/guide overlay
class CaptureGuidePainter extends CustomPainter {
  final double margin; // Margin from edge (0.0-0.5)

  CaptureGuidePainter({this.margin = 0.1});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * margin,
      size.height * margin,
      size.width * (1 - 2 * margin),
      size.height * (1 - 2 * margin),
    );

    // Draw semi-transparent overlay outside the guide
    final outerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(outerPath, outerPaint);

    // Draw corner markers
    final markerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final markerLength = size.shortestSide * 0.08;

    // Top-Left
    canvas.drawLine(
      Offset(rect.left, rect.top + markerLength),
      Offset(rect.left, rect.top),
      markerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + markerLength, rect.top),
      markerPaint,
    );

    // Top-Right
    canvas.drawLine(
      Offset(rect.right, rect.top + markerLength),
      Offset(rect.right, rect.top),
      markerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right - markerLength, rect.top),
      markerPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(rect.left, rect.bottom - markerLength),
      Offset(rect.left, rect.bottom),
      markerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + markerLength, rect.bottom),
      markerPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(rect.right, rect.bottom - markerLength),
      Offset(rect.right, rect.bottom),
      markerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right - markerLength, rect.bottom),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CaptureGuidePainter oldDelegate) {
    return oldDelegate.margin != margin;
  }
}
