import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/models/pdf_annotation.dart';

class SignatureOverlay extends StatelessWidget {
  final PdfAnnotation annotation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Function(PdfAnnotation) onUpdate;

  const SignatureOverlay({
    super.key,
    required this.annotation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    const double handleMargin = 20.0;
    
    return Positioned(
      left: annotation.position.dx - handleMargin,
      top: annotation.position.dy - handleMargin,
      width: annotation.width + (handleMargin * 2),
      height: annotation.height + (handleMargin * 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The actual draggable content area
          Positioned(
            left: handleMargin,
            top: handleMargin,
            width: annotation.width,
            height: annotation.height,
            child: GestureDetector(
              onTap: onTap,
              onPanUpdate: (details) {
                onUpdate(annotation.copyWith(
                  position: annotation.position + details.delta,
                ));
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? Colors.blue.withOpacity(0.8) : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _buildContent(),
              ),
            ),
          ),

          // Selection UI (Handles) - outside the content area but inside the larger parent
          if (isSelected) ...[
            // Delete button
            Positioned(
              top: handleMargin - 12,
              right: handleMargin - 12,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
            
            // Resize Handle (Bottom Right)
            Positioned(
              bottom: handleMargin - 8,
              right: handleMargin - 8,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  final double ratio = annotation.width / annotation.height;
                  
                  double newWidth = (annotation.width + details.delta.dx).clamp(40.0, 500.0);
                  double newHeight = (annotation.height + details.delta.dy).clamp(20.0, 500.0);

                  // Enforce aspect ratio for specific types
                  if (annotation.type == AnnotationType.signature || annotation.type == AnnotationType.image) {
                    // Lock to width-based height for predictable resizing
                    newHeight = newWidth / ratio;
                    
                    // Re-clamp and adjust width if height went out of bounds
                    if (newHeight < 20.0) {
                      newHeight = 20.0;
                      newWidth = newHeight * ratio;
                    } else if (newHeight > 500.0) {
                      newHeight = 500.0;
                      newWidth = newHeight * ratio;
                    }
                  }

                  onUpdate(annotation.copyWith(width: newWidth, height: newHeight));
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.maximize2, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (annotation.type == AnnotationType.image && annotation.content != null) {
      return Image.file(
        File(annotation.content!),
        width: annotation.width,
        height: annotation.height,
        fit: BoxFit.contain,
      );
    } else if (annotation.type == AnnotationType.signature && annotation.points != null) {
      return CustomPaint(
        size: Size(annotation.width, annotation.height),
        painter: PathPainter(
          points: annotation.points!,
          color: annotation.color,
          strokeWidth: annotation.strokeWidth,
          bounds: Rect.fromLTWH(0, 0, annotation.width, annotation.height),
        ),
      );
    } else if (annotation.type == AnnotationType.text && annotation.content != null) {
      return Center(
        child: Text(
          annotation.content!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: annotation.color,
            fontSize: annotation.fontSize,
            fontWeight: annotation.isBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: annotation.isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }
    return const SizedBox();
  }
}

class PathPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final Rect bounds;

  PathPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.bounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Calculate scaling to fit points into bounds
    // Assuming points are normalized to (0,0) in PdfSignScreen
    double minX = points.where((p) => !p.dx.isNaN).map((p) => p.dx).reduce(math.min);
    double maxX = points.where((p) => !p.dx.isNaN).map((p) => p.dx).reduce(math.max);
    double minY = points.where((p) => !p.dy.isNaN).map((p) => p.dy).reduce(math.min);
    double maxY = points.where((p) => !p.dy.isNaN).map((p) => p.dy).reduce(math.max);

    double scaleX = size.width / (maxX - minX + 0.0001);
    double scaleY = size.height / (maxY - minY + 0.0001);
    double scale = math.min(scaleX, scaleY);

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i+1];
      if (p1.dx.isNaN || p2.dx.isNaN) continue;
      
      canvas.drawLine(
        Offset(p1.dx * scale, p1.dy * scale),
        Offset(p2.dx * scale, p2.dy * scale),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
