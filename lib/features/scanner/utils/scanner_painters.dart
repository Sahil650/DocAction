import 'package:flutter/material.dart';

class LiveQuadPainter extends CustomPainter {
  final List<Offset> corners;
  final double animationValue; 
  final double stabilityProgress; // 0.0 to 1.0

  LiveQuadPainter({
    required this.corners,
    this.animationValue = 0.0,
    this.stabilityProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final primaryColor = Color.lerp(
      Colors.white.withOpacity(0.4), 
      Colors.white, 
      stabilityProgress
    )!;

    final path = Path();
    path.moveTo(corners[0].dx * size.width, corners[0].dy * size.height);
    for (int i = 1; i < 4; i++) {
      path.lineTo(corners[i].dx * size.width, corners[i].dy * size.height);
    }
    path.close();

    // 1. Draw Fill (Opacity increases with stability)
    if (stabilityProgress > 0.1) {
      final fillPaint = Paint()
        ..color = Colors.white.withOpacity(0.15 * stabilityProgress)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    // 2. Draw Main Glow Border
    final paint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.0 + (1.5 * stabilityProgress)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Subtle glow effect
    if (stabilityProgress > 0.5) {
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    
    canvas.drawPath(path, paint);

    // 3. Draw Inner White Highlight
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.3 + (0.4 * stabilityProgress))
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, innerPaint);

    // Draw Clean Corner Handles
    for (var corner in corners) {
      final pos = Offset(corner.dx * size.width, corner.dy * size.height);
      
      // Simple Black Border for handle
      canvas.drawCircle(pos, 7, Paint()..color = Colors.black.withOpacity(0.3));
      
      // Handle White Circle
      canvas.drawCircle(pos, 5, Paint()..color = Colors.white);
      
      // Black Inner Dot
      canvas.drawCircle(pos, 2, Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(covariant LiveQuadPainter oldDelegate) => true;
}

class CameraShutterPainter extends CustomPainter {
  final double progress; // 0.0 (open) to 1.0 (closed)

  CameraShutterPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.longestSide / 1.1;
    final currentRadius = maxRadius * (1.1 - progress);

    final bgPaint = Paint()..color = Colors.black;

    // Draw outer boundary
    Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: currentRadius.clamp(0, maxRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, bgPaint);

    // Draw Shutter Blades (Iris)
    if (progress > 0.01) {
      final bladePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;

      const blades = 8;
      for (int i = 0; i < blades; i++) {
        final angle = (i * 2 * 3.14159 / blades) + (progress * 0.5);
        
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        canvas.translate(-center.dx, -center.dy);
        canvas.drawCircle(
          center,
          currentRadius,
          bladePaint,
        ); // Simple circle for now to mask
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CameraShutterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
