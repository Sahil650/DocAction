import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:doc_scanner_app/core/theme/app_colors.dart';
import '../utils/edge_detector.dart';
import 'document_edit_screen.dart';

class MakeACopyCropScreen extends StatefulWidget {
  final String imagePath;
  final List<Offset> initialPoints;
  final bool isSessionMode;

  const MakeACopyCropScreen({
    super.key,
    required this.imagePath,
    required this.initialPoints,
    this.isSessionMode = false,
  });

  @override
  State<MakeACopyCropScreen> createState() => _MakeACopyCropScreenState();
}

class _MakeACopyCropScreenState extends State<MakeACopyCropScreen> {
  late List<Offset> points;
  bool isProcessing = false;
  Size? imageSize;
  Size? displaySize;
  List<Offset>? _detectedNormalizedPoints;

  @override
  void initState() {
    super.initState();
    points = [];
    _getImageSize();
  }

  Future<void> _getImageSize() async {
    final imageProvider = FileImage(File(widget.imagePath));
    final completer = Completer<Size>();
    late ImageStreamListener listener;
    final stream = imageProvider.resolve(const ImageConfiguration());
    
    listener = ImageStreamListener((ImageInfo info, bool _) {
      if (!completer.isCompleted) {
        completer.complete(Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ));
      }
      stream.removeListener(listener);
    }, onError: (dynamic exception, StackTrace? stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(exception, stackTrace);
      }
      stream.removeListener(listener);
    });
    
    stream.addListener(listener);
    final size = await completer.future;
    
    List<Offset>? detected;
    if (widget.initialPoints.isEmpty) {
      detected = await EdgeDetector.detectCorners(widget.imagePath);
    }

    if (mounted) {
      setState(() {
        imageSize = size;
        _detectedNormalizedPoints = detected;
      });
    }
  }

  Future<void> _rotateSource() async {
    setState(() => isProcessing = true);
    try {
      final rotatedPath = await EdgeDetector.applyFilter(widget.imagePath, 'rotate');
      // We need to replace the image path. Since it's a final field in widget, 
      // we'll just navigate to a new instance of this screen with the rotated path.
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MakeACopyCropScreen(
              imagePath: rotatedPath,
              initialPoints: const [],
              isSessionMode: widget.isSessionMode,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> confirmCrop() async {
    if (displaySize == null) return;
    
    setState(() => isProcessing = true);
    try {
      // Normalize points back to [0, 1]
      final normalizedPoints = points.map((p) => Offset(p.dx / displaySize!.width, p.dy / displaySize!.height)).toList();

      final result = await EdgeDetector.warpPerspective(widget.imagePath, normalizedPoints);
      if (mounted) {
        final resultPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => MakeACopyEditScreen(
              imagePath: result,
              isSessionMode: widget.isSessionMode,
            ),
          ),
        );
        
        if (mounted && resultPath != null) {
          Navigator.pop(context, resultPath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (imageSize == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "ADJUST CORNERS",
          style: GoogleFonts.inter(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 14,
          ),
        ),
        actions: [
          if (!isProcessing) ...[
            IconButton(
              onPressed: _rotateSource,
              icon: const Icon(LucideIcons.rotateCw, color: Color(0xFF475569), size: 20),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: confirmCrop,
                child: Text(
                  "DONE",
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ]
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.black.withValues(alpha: 0.05), height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Account for the 20px margin on all sides (40px total)
          final double availableWidth = constraints.maxWidth - 40;
          final double availableHeight = constraints.maxHeight - 40;

          // Calculate display size keeping aspect ratio
          final double ratio = imageSize!.width / imageSize!.height;
          double dWidth = availableWidth;
          double dHeight = dWidth / ratio;

          if (dHeight > availableHeight) {
            dHeight = availableHeight;
            dWidth = dHeight * ratio;
          }

          displaySize = Size(dWidth, dHeight);

          // Scale normalized initial points to display size ONCE
          if (points.isEmpty) {
            final List<Offset> sourcePoints = widget.initialPoints.isNotEmpty 
                ? widget.initialPoints 
                : (_detectedNormalizedPoints ?? []);

            if (sourcePoints.isNotEmpty) {
              points = sourcePoints.map((p) => Offset(p.dx * dWidth, p.dy * dHeight)).toList();
            }
          }

          // Fallback if no corners detected
          if (points.isEmpty) {
            points = [
              Offset(dWidth * 0.1, dHeight * 0.1),
              Offset(dWidth * 0.9, dHeight * 0.1),
              Offset(dWidth * 0.9, dHeight * 0.9),
              Offset(dWidth * 0.1, dHeight * 0.9),
            ];
          }

          return Center(
            child: Container(
              width: dWidth,
              height: dHeight,
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: QuadPainter(points: points),
                      ),
                    ),
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx - 18,
                        top: points[index].dy - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newX = points[index].dx + details.delta.dx;
                              double newY = points[index].dy + details.delta.dy;
                              newX = newX.clamp(0.0, dWidth);
                              newY = newY.clamp(0.0, dHeight);
                              points[index] = Offset(newX, newY);
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class QuadPainter extends CustomPainter {
  final List<Offset> points;

  QuadPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(QuadPainter oldDelegate) => true;
}
