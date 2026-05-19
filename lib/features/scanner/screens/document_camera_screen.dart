import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/edge_detector.dart';
import 'document_crop_screen.dart';

class MakeACopyCameraScreen extends StatefulWidget {
  const MakeACopyCameraScreen({super.key});

  @override
  State<MakeACopyCameraScreen> createState() => _MakeACopyCameraScreenState();
}

class _MakeACopyCameraScreenState extends State<MakeACopyCameraScreen> {
  CameraController? controller;
  List<Offset>? liveCorners;
  bool isDetecting = false;
  Timer? detectionTimer;
  FlashMode _flashMode = FlashMode.off;
  bool _isCapturing = false;
  List<Offset>? _lastStableCorners;
  bool _isAutoMode = false;
  int _stabilityCount = 0;

  bool _isCentered(List<Offset> corners) {
    // Check if corners are too close to the screen edges
    for (var corner in corners) {
      if (corner.dx < 0.05 || corner.dx > 0.95 || corner.dy < 0.05 || corner.dy > 0.95) return false;
    }
    return true;
  }

  bool _isSteady(List<Offset> newCorners) {
    if (_lastStableCorners == null || _lastStableCorners!.length != 4) return false;
    
    double totalMovement = 0;
    for (int i = 0; i < 4; i++) {
      totalMovement += (newCorners[i] - _lastStableCorners![i]).distance;
    }
    // Threshold: Average movement less than 0.02 (2% of screen)
    return (totalMovement / 4) < 0.02;
  }

  List<Offset> _stabilize(List<Offset> newCorners) {
    if (_lastStableCorners == null || _lastStableCorners!.length != newCorners.length) {
      _lastStableCorners = newCorners;
      return newCorners;
    }
    
    List<Offset> stable = [];
    for (int i = 0; i < newCorners.length; i++) {
      // SmoothedX = old * 0.7 + new * 0.3
      double sx = _lastStableCorners![i].dx * 0.7 + newCorners[i].dx * 0.3;
      double sy = _lastStableCorners![i].dy * 0.7 + newCorners[i].dy * 0.3;
      stable.add(Offset(sx, sy));
    }
    _lastStableCorners = stable;
    return stable;
  }

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  @override
  void dispose() {
    detectionTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await controller!.initialize();
    
    detectionTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!isDetecting && !_isCapturing && mounted) {
        _detectLive();
      }
    });
    
    if (mounted) setState(() {});
  }

  Future<void> _detectLive() async {
    if (controller == null || !controller!.value.isInitialized || _isCapturing || controller!.value.isTakingPicture) return;
    
    isDetecting = true;
    try {
      final image = await controller!.takePicture();
      final corners = await EdgeDetector.detectCorners(image.path);
      
      File(image.path).delete().catchError((_) {});

      if (mounted && !_isCapturing) {
        setState(() {
          if (corners != null && corners.length == 4) {
            // Check stability and centering for auto-mode
            if (_isAutoMode) {
              if (_isSteady(corners) && _isCentered(corners)) {
                _stabilityCount++;
                if (_stabilityCount >= 3) {
                  _stabilityCount = 0;
                  captureAndDetect();
                }
              } else {
                _stabilityCount = 0;
              }
            }
            
            liveCorners = _stabilize(corners);
          } else {
            liveCorners = null;
            _lastStableCorners = null;
            _stabilityCount = 0;
          }
        });
      }
    } catch (e) {
      // Ignore
    } finally {
      isDetecting = false;
    }
  }

  Future<void> _toggleFlash() async {
    if (controller == null) return;
    final nextMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await controller!.setFlashMode(nextMode);
    setState(() => _flashMode = nextMode);
  }

  Future<void> captureAndDetect() async {
    if (_isCapturing || controller == null || !controller!.value.isInitialized || controller!.value.isTakingPicture) return;
    
    setState(() => _isCapturing = true);
    
    try {
      final image = await controller!.takePicture();
      final corners = await EdgeDetector.detectCorners(image.path);

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MakeACopyCropScreen(
              imagePath: image.path,
              initialPoints: corners ?? liveCorners ?? [],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Capture failed: $e")));
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Center(
            child: AspectRatio(
              aspectRatio: 1 / controller!.value.aspectRatio,
              child: CameraPreview(controller!),
            ),
          ),
          
          
          // Live Detection Results (Optional overlay)
          if (liveCorners != null)
             Positioned.fill(
                child: CustomPaint(
                   painter: LiveCornersPainter(corners: liveCorners!),
                ),
             ),

          // Top Controls
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                ),
                IconButton(
                  onPressed: _toggleFlash,
                  icon: Icon(
                    _flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  "Align document within the frame",
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 16),
                // Auto/Manual Toggle
                GestureDetector(
                  onTap: () => setState(() => _isAutoMode = !_isAutoMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isAutoMode ? Colors.white : Colors.white24,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isAutoMode ? Icons.auto_awesome : Icons.touch_app,
                          color: _isAutoMode ? Colors.black : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isAutoMode ? "AUTO" : "MANUAL",
                          style: GoogleFonts.inter(
                            color: _isAutoMode ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: captureAndDetect,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Center(
                      child: Container(
                        height: 60,
                        width: 60,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (_isCapturing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

class LiveCornersPainter extends CustomPainter {
  final List<Offset> corners;
  LiveCornersPainter({required this.corners});
  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path()
      ..moveTo(corners[0].dx * size.width, corners[0].dy * size.height)
      ..lineTo(corners[1].dx * size.width, corners[1].dy * size.height)
      ..lineTo(corners[2].dx * size.width, corners[2].dy * size.height)
      ..lineTo(corners[3].dx * size.width, corners[3].dy * size.height)
      ..close();
    
    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }
  @override
  bool shouldRepaint(LiveCornersPainter oldDelegate) => true;
}
