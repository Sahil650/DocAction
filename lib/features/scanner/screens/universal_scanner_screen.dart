import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    hide Barcode;
import 'package:image_picker/image_picker.dart';
import 'package:vibration/vibration.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import '../utils/one_euro_filter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/scanner_mode.dart';
import '../../../data/models/photo_size_model.dart';
import '../../../data/models/scan_result_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/ocr_service.dart';

import '../../tools/screens/tool_editor_screen.dart';
import '../../tools/screens/id_photo_session_screen.dart';
import '../../tools/screens/signature_screen.dart';
import '../../tools/screens/qr_result_screen.dart';
import '../utils/edge_detector.dart';
import 'document_crop_screen.dart';
import 'document_edit_screen.dart';
import 'ocr_result_screen.dart';

import '../utils/scanner_painters.dart';
import '../utils/one_euro_filter.dart';
import '../mixins/scanner_camera_mixin.dart';
import '../mixins/scanner_session_mixin.dart';
import '../mixins/scanner_qr_mixin.dart';
import '../widgets/scanner_header.dart';
import '../widgets/scanner_bottom_area.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/qr_result_card.dart';

class UniversalScannerScreen extends StatefulWidget {
  final ScannerMode initialMode;
  final bool isPickerMode;
  final bool shouldNavigateToPreview;

  const UniversalScannerScreen({
    super.key,
    this.initialMode = ScannerMode.document,
    this.isPickerMode = false,
    this.shouldNavigateToPreview = true,
  });

  @override
  State<UniversalScannerScreen> createState() => _UniversalScannerScreenState();
}

class _UniversalScannerScreenState extends State<UniversalScannerScreen>
    with
        TickerProviderStateMixin,
        ScannerCameraMixin,
        ScannerSessionMixin,
        ScannerQrMixin {
  final _storageService = StorageService();
  late ScannerMode _currentMode;
  AppLocalizations get l10n => AppLocalizations.of(context);

  final _barcodeScanner = BarcodeScanner();
  Timer? _detectionTimer;

  bool _isProcessing = false;
  final _ocrService = OCRService();




  late AnimationController _qrAnimationController;
  late AnimationController _shutterController;
  late Animation<double> _shutterAnimation;
  bool _showShutter = false;

  // Real-time OCR visuals
  List<OCRBlock>? _liveTextBlocks;
  late AnimationController _scanningLineController;
  late Animation<double> _scanningLinePosition;
  final bool _isSavingSession = false;

  bool _isProcessingFrame = false;
  final ValueNotifier<List<Offset>?> _liveCornersNotifier = ValueNotifier<List<Offset>?>(null);
  final ValueNotifier<double> _stabilityProgressNotifier = ValueNotifier<double>(0.0);
  final CornerSmoother _cornerSmoother = CornerSmoother(minCutoff: 0.8, beta: 0.08);
  int _consecutiveDetections = 0;
  bool _isAutoMode = false;
  int _stabilityCount = 0;

  bool _isCentered(List<Offset> corners) {
    for (var corner in corners) {
      if (corner.dx < 0.05 || corner.dx > 0.95 || corner.dy < 0.05 || corner.dy > 0.95) return false;
    }
    return true;
  }

  bool _isSteady(List<Offset> newCorners) {
    final currentCorners = _liveCornersNotifier.value;
    if (currentCorners == null || currentCorners.length != 4) return false;
    double totalMovement = 0;
    for (int i = 0; i < 4; i++) {
      totalMovement += (newCorners[i] - currentCorners[i]).distance;
    }
    // Threshold: Average movement less than 0.04 (4% of screen) - more lenient
    return (totalMovement / 4) < 0.04;
  }

  List<PhotoSizeModel> _getLocalizedPhotoSizes(AppLocalizations l10n) => [
    PhotoSizeModel(
      name: l10n.translate('passport'),
      width: 35,
      height: 45,
      unit: "mm",
    ),
    PhotoSizeModel(
      name: l10n.translate('visa_us'),
      width: 2,
      height: 2,
      unit: "in",
    ),
  ];
  final int _selectedPhotoSizeIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;

    _qrAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _shutterAnimation = CurvedAnimation(
      parent: _shutterController,
      curve: Curves.easeInOutQuart,
    );

    _scanningLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _scanningLinePosition = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanningLineController, curve: Curves.easeInOut),
    );





    if (_currentMode == ScannerMode.qrCode) {
      initializeMobileScanner(isFlashOn);
      _qrAnimationController.repeat(reverse: true);
    } else {
      _initMainCamera();
    }
  }



  Future<void> _initMainCamera() async {
    await initializeCamera(
      resolution: ResolutionPreset.medium,
      androidFormat: ImageFormatGroup.yuv420,
      iosFormat: ImageFormatGroup.bgra8888,
      onReady: () {
        if (_currentMode == ScannerMode.document || _currentMode == ScannerMode.ocr) {
          _startRealtimeDetection();
          _scanningLineController.repeat(reverse: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _ocrService.dispose();
    _barcodeScanner.close();
    _qrAnimationController.dispose();
    _shutterController.dispose();
    _scanningLineController.dispose();
    super.dispose();
  }

  // --- CORE LOGIC ---

  void _onModeChanged(ScannerMode mode) {
    if (_currentMode != mode) {
      final bool wasQr = _currentMode == ScannerMode.qrCode;
      final bool isQr = mode == ScannerMode.qrCode;

      _animateShutter(() async {
        setState(() {
          _currentMode = mode;
          _liveCornersNotifier.value = null;
          qrResult = null;
        });

        if (isQr) {
          await disposeStandardCamera();
          await initializeMobileScanner(isFlashOn);
          _qrAnimationController.repeat(reverse: true);
        } else if (wasQr) {
          _qrAnimationController.stop();
          await disposeMobileScanner();
          await _initMainCamera();
        } else if (!isInitialized) {
          await _initMainCamera();
        } else {
          if (mode == ScannerMode.document) {
            _consecutiveDetections = 0;
            _startRealtimeDetection();
            _scanningLineController.repeat(reverse: true);
          } else if (mode == ScannerMode.ocr) {
            _startRealtimeDetection();
            _scanningLineController.repeat(reverse: true);
          } else {
             _detectionTimer?.cancel();
             _scanningLineController.stop();
          }
        }
      });
    }
  }

  Future<void> _animateShutter(FutureOr<void> Function() midwayAction) async {
    HapticFeedback.mediumImpact();
    setState(() => _showShutter = true);
    await _shutterController.forward();
    await midwayAction();
    await Future.delayed(const Duration(milliseconds: 150));
    await _shutterController.reverse();
    setState(() => _showShutter = false);
  }

  double _calculateQuadArea(List<Offset> points) {
    if (points.length != 4) return 0.0;
    // Shoelace formula for area
    double area = 0;
    for (int i = 0; i < 4; i++) {
      int next = (i + 1) % 4;
      area += points[i].dx * points[next].dy;
      area -= points[next].dx * points[i].dy;
    }
    return (area.abs() / 2.0);
  }

  void _startRealtimeDetection() {
    if (cameraController == null || !isInitialized) return;
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      if (_isProcessingFrame || !mounted || _isProcessing || 
          cameraController == null || !cameraController!.value.isInitialized || 
          cameraController!.value.isTakingPicture) return;
      if (_currentMode != ScannerMode.document && _currentMode != ScannerMode.ocr) return;
      
      _isProcessingFrame = true;
      try {
        final image = await cameraController!.takePicture();
        if (_currentMode == ScannerMode.document) {
          final points = await EdgeDetector.detectCorners(image.path);
          if (mounted && _currentMode == ScannerMode.document && !_isProcessing) {
            final area = points != null ? _calculateQuadArea(points) : 0.0;
            // Strict area check (15% - 95% of screen) + null check
            if (points == null || area < 0.15 || area > 0.95) {
              _liveCornersNotifier.value = null;
              _stabilityProgressNotifier.value = 0.0;
              _consecutiveDetections = 0;
            } else {
              _consecutiveDetections++;
              if (_consecutiveDetections >= 1) {
                // Apply Professional Smoothing (One Euro Filter)
                final previousCorners = _liveCornersNotifier.value;
                final List<double> flattened = points.expand((p) => [p.dx, p.dy]).toList();
                final List<double> smoothedFlat = _cornerSmoother.filter(flattened);
                
                final List<Offset> smoothed = [];
                for (int i = 0; i < 8; i += 2) {
                  smoothed.add(Offset(smoothedFlat[i], smoothedFlat[i+1]));
                }
                
                // Auto-Capture logic
                if (_isAutoMode) {
                  // Use smoothed points for stability check to reduce false resets
                  if (_isSteady(smoothed) && _isCentered(smoothed)) {
                    _stabilityCount++;
                    _stabilityProgressNotifier.value = _stabilityCount / 4.0; // Increased to 4 frames for better precision
                    if (_stabilityCount >= 4) {
                      _stabilityCount = 0;
                      _stabilityProgressNotifier.value = 0.0;
                      _isProcessing = true; 
                      await _handleDocumentCapture();
                    }
                  } else {
                    if (_stabilityCount > 0) _stabilityCount--; // Degrade slowly instead of instant reset
                    _stabilityProgressNotifier.value = _stabilityCount / 4.0;
                  }
                }

                _liveCornersNotifier.value = smoothed;
              } else {
                _liveCornersNotifier.value = points;
                _stabilityCount = 0;
                _stabilityProgressNotifier.value = 0.0;
              }
            }
          }
        } else if (_currentMode == ScannerMode.ocr) {
          final blocks = await _ocrService.recognizeLive(image.path, useDevanagari: true);
          if (mounted && _currentMode == ScannerMode.ocr && !_isProcessing) {
            setState(() {
              _liveTextBlocks = blocks;
            });
          }
        }
        await File(image.path).delete();
      } catch (e) {
        debugPrint("Real-time Detection Error: $e");
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  // --- CAPTURE HANDLERS ---

  Future<void> _handleCapture() async {
    switch (_currentMode) {
      case ScannerMode.document:
        _handleDocumentCapture();
        break;
      case ScannerMode.photo:
        _handlePhotoCapture();
        break;
      case ScannerMode.signature:
        _handleSignatureScanCapture();
        break;
      case ScannerMode.ocr:
        _handleOcrCapture();
        break;
      default:
        break;
    }
  }

  Future<void> _handleDocumentCapture() async {
    if (!isInitialized || cameraController == null || cameraController!.value.isTakingPicture) return;
    
    // Stop detection during capture to prevent lag and clear old overlay
    _detectionTimer?.cancel();
    _liveCornersNotifier.value = null; 
    setState(() => _isProcessing = true);
    HapticFeedback.heavyImpact();
    
    try {
      final image = await cameraController!.takePicture();
      final corners = await EdgeDetector.detectCorners(image.path);
      
      if (mounted) {
        final processedPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => MakeACopyCropScreen(
              imagePath: image.path,
              initialPoints: corners ?? [],
              isSessionMode: true,
            ),
          ),
        );
        
        if (processedPath != null && processedPath != "RETAKE") {
          addToSession(processedPath, ScannerMode.document);
        }
      }
    } catch (e) {
      debugPrint("Doc Capture Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      if (_currentMode == ScannerMode.document) {
        _startRealtimeDetection();
      }
    }
  }

  Future<void> _handleOcrCapture() async {
    if (!isInitialized || cameraController == null) return;
    HapticFeedback.lightImpact();
    try {
      final image = await cameraController!.takePicture();
      addToSession(image.path, ScannerMode.ocr);
    } catch (e) {
      debugPrint("OCR Capture Error: $e");
    }
  }

  Future<void> _handlePhotoCapture() async {
    if (!isInitialized || cameraController == null) return;
    HapticFeedback.mediumImpact();
    try {
      final image = await cameraController!.takePicture();
      final size = _getLocalizedPhotoSizes(l10n)[_selectedPhotoSizeIndex];
      if (mounted) {
        final editedPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => ToolEditorScreen(
              imagePath: image.path,
              title: l10n.translate('photo_editor'),
              ratioX: size.width,
              ratioY: size.height,
            ),
          ),
        );
        if (editedPath != null && editedPath != "RETAKE") {
          addToSession(editedPath, _currentMode);
          _openPhotoSession();
        }
      }
    } catch (e) {
      debugPrint("Photo Error: $e");
    }
  }





  Future<void> _handleSignatureScanCapture() async {
    if (!isInitialized || cameraController == null) return;
    setState(() => _isProcessing = true);
    try {
      final image = await cameraController!.takePicture();
      final bytes = await File(image.path).readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded != null && mounted) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        double cropW = (320 / screenWidth) * decoded.width;
        double cropH = (180 / screenHeight) * decoded.height;
        decoded = img.copyCrop(
          decoded,
          x: ((decoded.width - cropW) / 2).toInt(),
          y: ((decoded.height - cropH) / 2).toInt(),
          width: cropW.toInt(),
          height: cropH.toInt(),
        );
        img.grayscale(decoded);
        img.contrast(decoded, contrast: 150);
        final path = p.join(
          (await getTemporaryDirectory()).path,
          "sig_${DateTime.now().millisecondsSinceEpoch}.png",
        );
        await File(path).writeAsBytes(img.encodePng(decoded));
        _handleSignaturePostProcess(path, l10n.translate('scanned_sig'));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleSignaturePostProcess(String path, String label) async {
    final editedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ToolEditorScreen(
          imagePath: path,
          title: label,
          ratioX: 3.0,
          ratioY: 1.0,
          backgroundColor: Colors.white, // Always use white for signatures in editor
        ),
      ),
    );
    if (editedPath != null && editedPath != "RETAKE" && mounted) {
      if (widget.isPickerMode) {
        Navigator.pop(context, [editedPath]);
      } else {
        addToSession(editedPath, _currentMode);
      }
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    bool isEngineReady = _currentMode == ScannerMode.qrCode
        ? isQrEngineInitialized
        : isInitialized;
    if (!isEngineReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraEngine(),
          if (_isProcessing || _isSavingSession) _buildProcessingOverlay(),
          ValueListenableBuilder<List<Offset>?>(
            valueListenable: _liveCornersNotifier,
            builder: (context, corners, child) {
              String label = corners != null ? "READY TO CAPTURE" : "";
              if (replacementIndex != null) {
                label = "REPLACING PHOTO ${replacementIndex! + 1}";
              }
              return ScannerOverlay(
                currentMode: _currentMode,
                signatureFrame: _buildSignatureFrame(),
                qrViewfinder: _buildQrViewfinder(),
                documentLabel: label,
              );
            },
          ),
          ScannerHeader(
            currentMode: _currentMode,
            isFlashOn: isFlashOn,
            onBack: () => Navigator.pop(context),
            onToggleFlash: toggleFlash,
            isBatchMode: true,
            onToggleBatchMode: null,
            onCancelReplace: replacementIndex != null 
              ? () => setState(() => replacementIndex = null) 
              : null,
            onDone: null,
          ),
          if (_currentMode == ScannerMode.qrCode && qrResult != null)
            QrResultCard(
              qrResult: qrResult,
              onClose: resetQrResult,
              onSave: (res) {},
            ),
          ScannerBottomArea(
            key: ValueKey("session_${getSessionList(_currentMode).length}_${getSessionList(_currentMode).lastOrNull}"),
            currentMode: _currentMode,
            currentSessionList: List.from(getSessionList(_currentMode)),
            sessionThumbnails: sessionThumbnails,
            onCapture: _handleCapture,
            onGalleryImport: _handleGalleryImport,
            onOpenSession: _currentMode == ScannerMode.ocr ? _handleOcrProceed : _openPhotoSession,
            onDrawSignature: _openDigitalSignature,
            onImportSignature: _handleSignatureGalleryImport,
            onModeChanged: _onModeChanged,
            isAutoMode: _isAutoMode,
            onToggleAutoMode: () => setState(() => _isAutoMode = !_isAutoMode),
          ),
          if (_currentMode == ScannerMode.ocr) const SizedBox.shrink(),
          if (_showShutter) _buildShutterEffect(),
        ],
      ),
    );
  }



  Future<void> _handleOcrProceed() async {
     final sessionList = getSessionList(ScannerMode.ocr);
     if (sessionList.isEmpty) return;
     
     setState(() => _isProcessing = true);
     try {
       String fullText = "";
       Map<String, RecognizedText> ocrData = {};
       
       for (int i = 0; i < sessionList.length; i++) {
         final path = sessionList[i];
         final result = await _ocrService.getRecognizedText(path, useDevanagari: true);
         ocrData[path] = result;
         fullText += "--- PAGE ${i + 1} ---\n${result.text}\n\n";
       }
       
        if (mounted) {
          final result = await Navigator.push<dynamic>(
            context,
            MaterialPageRoute(
              builder: (_) => OCRResultScreen(
                imagePaths: sessionList,
                extractedText: fullText.trim(),
                ocrData: ocrData,
                isDevanagari: true,
              ),
            ),
          );

          if (result != null && mounted) {
            if (result is String && result != "SUCCESS") {
              // It was text data
              final storageService = StorageService();
              await storageService.saveDocumentNamed(
                name: "OCR Text ${DateTime.now().day}/${DateTime.now().month}",
                imagePaths: sessionList,
                extractedText: result,
                pageCount: sessionList.length,
              );
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("OCR Text saved to Library")),
              );
            }
            
            // In all success cases (Text saved or PDF saved), go back to dashboard
            Navigator.pop(context, true); 
          }
        }
     } finally {
       if (mounted) setState(() => _isProcessing = false);
     }
  }


  Widget _buildCameraEngine() {
    return Center(
      child: _currentMode == ScannerMode.qrCode
          ? (isQrEngineInitialized && mobileScannerController != null
                ? RepaintBoundary(
                    child: MobileScanner(
                      controller: mobileScannerController!,
                      onDetect: _onBarcodeDetected,
                    ),
                  )
                : const CircularProgressIndicator(color: Colors.white))
          : (isInitialized && cameraController != null
                ? AspectRatio(
                    aspectRatio: 1 / cameraController!.value.aspectRatio,
                    child: Stack(
                      children: [
                        RepaintBoundary(
                          child: GestureDetector(
                            onScaleStart: (details) => baseZoom = currentZoom,
                            onScaleUpdate: (details) =>
                                setZoom(baseZoom * details.scale),
                            onTapDown: (details) => handleFocus(
                              details.localPosition,
                              MediaQuery.of(context).size,
                            ),
                            child: CameraPreview(cameraController!),
                          ),
                        ),
                        if (focusPoint != null)
                          Positioned(
                            left: focusPoint!.dx - 35,
                            top: focusPoint!.dy - 35,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.accent,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        if (currentZoom > minZoom)
                          Positioned(
                            bottom: 120,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${currentZoom.toStringAsFixed(1)}x",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Document Tracking Overlay (High Performance)
                        if (_currentMode == ScannerMode.document || _currentMode == ScannerMode.ocr)
                          ValueListenableBuilder<List<Offset>?>(
                            valueListenable: _liveCornersNotifier,
                            builder: (context, corners, child) {
                              if (corners == null) return const SizedBox.shrink();
                              return ValueListenableBuilder<double>(
                                valueListenable: _stabilityProgressNotifier,
                                builder: (context, progress, child) {
                                  return AnimatedBuilder(
                                    animation: _scanningLineController,
                                    builder: (context, _) => Positioned.fill(
                                      child: CustomPaint(
                                        painter: LiveQuadPainter(
                                          corners: corners,
                                          animationValue: _scanningLinePosition.value,
                                          stabilityProgress: progress,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(color: Colors.white)),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black45,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                Text(
                  _isSavingSession
                      ? l10n.translate('saving')
                      : l10n.translate('processing'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShutterEffect() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _shutterAnimation,
        builder: (context, child) => Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _shutterAnimation.value * 15,
                sigmaY: _shutterAnimation.value * 15,
              ),
              child: Container(
                color: Colors.black.withValues(
                  alpha: _shutterAnimation.value * 0.3,
                ),
              ),
            ),
            CustomPaint(
              painter: CameraShutterPainter(progress: _shutterAnimation.value),
            ),
          ],
        ),
      ),
    );
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (qrResult != null) return;
    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final code = barcodes.first.displayValue;
      if (code != null) {
        Vibration.vibrate(duration: 50);
        setState(() => qrResult = code);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrResultScreen(
              result: ScanResultModel(
                id: Uuid().v4(),
                data: code,
                format: barcodes.first.format.name,
                type: "TEXT",
                timestamp: DateTime.now(),
              ),
            ),
          ),
        ).then((_) => setState(() => qrResult = null));
      }
    }
  }



  Future<void> _handleGalleryImport() async {
    // If OCR mode, go straight to system gallery as requested
    if (_currentMode == ScannerMode.ocr) {
      _importFromSystemGallery();
      return;
    }

    // For other modes, show Source Selector
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: Text(l10n.translate('gallery')),
              onTap: () {
                Navigator.pop(context);
                _importFromSystemGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present, color: Colors.white),
              title: Text(l10n.translate('files')),
              onTap: () {
                Navigator.pop(context);
                _importFromFiles();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty && mounted) {
          final path = result.files.first.path;
          if (path != null) _processImportedFile(path);
      }
    } catch (e) {
      debugPrint('File Import Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _importFromSystemGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage();
      
      if (images.isNotEmpty && mounted) {
        for (final image in images) {
          // Process each image. Note: For modes requiring interaction (crop/edit), 
          // this will open them sequentially as one is finished.
          await _processImportedFile(image.path);
        }
      }
    } catch (e) {
      debugPrint('Gallery Import Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }


  Future<void> _processImportedFile(String path) async {
    if (!mounted) return;
    
    if (_currentMode == ScannerMode.document) {
      final corners = await EdgeDetector.detectCorners(path);
      if (mounted) {
        final processedPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => MakeACopyCropScreen(
              imagePath: path,
              initialPoints: corners ?? [],
              isSessionMode: true,
            ),
          ),
        );
        if (processedPath != null) addToSession(processedPath, _currentMode);
      }
    } else if (_currentMode == ScannerMode.photo) {
      final size = _getLocalizedPhotoSizes(l10n)[_selectedPhotoSizeIndex];
      if (mounted) {
        final editedPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => ToolEditorScreen(
              imagePath: path,
              title: l10n.translate('photo_editor'),
              ratioX: size.width,
              ratioY: size.height,
            ),
          ),
        );
        if (editedPath != null) {
          addToSession(editedPath, _currentMode);
          _openPhotoSession();
        }
      }
    } else if (_currentMode == ScannerMode.ocr) {
      addToSession(path, ScannerMode.ocr);
    }
  }

  Future<void> _openPhotoSession() async {
    final currentList = getSessionList(_currentMode);
    if (currentList.isEmpty) return;

    /*
    if (_currentMode == ScannerMode.document || _currentMode == ScannerMode.signature) {
      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentSessionScreen(
            initialImagePaths: List.from(currentList),
            onSessionUpdated: (updatedList) {
              updateSessionList(_currentMode, updatedList);
            },
          ),
        ),
      );
      if (result == "SUCCESS") {
        clearSession(_currentMode);
        if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
      }
      return;
    }
    */

    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IdPhotoSessionScreen(
          size: PhotoSizeModel(
            name: l10n.translate('photo_session_label'),
            width: 4,
            height: 6,
            unit: "ratio",
          ),
          initialImagePaths: List.from(currentList),
          fromCameraHub: true,
          isPickerMode: widget.isPickerMode,
          currentMode: _currentMode.name,
        ),
      ),
    );
    if (result == "SUCCESS") {
      clearSession(_currentMode);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } else if (result is List<String>) {
      updateSessionList(_currentMode, result);
      if (widget.isPickerMode && mounted) {
        Navigator.pop(context, result);
      }
    } else if (result is Map && result["action"] == "CAPTURE_MORE") {
      updateSessionList(_currentMode, result["updatedList"] as List<String>);
    } else if (result is Map && result["action"] == "REPLACE") {
      updateSessionList(_currentMode, result["updatedList"] as List<String>);
      setState(() {
        replacementIndex = result["index"] as int?;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Replacing photo ${replacementIndex! + 1}",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.grey[900],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleSignatureGalleryImport() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _isProcessing = true);
      try {
        final bytes = await File(file.path).readAsBytes();
        img.Image? decoded = img.decodeImage(bytes);
        if (decoded != null) {
          img.grayscale(decoded);
          img.contrast(decoded, contrast: 150);
          final path = p.join(
            (await getTemporaryDirectory()).path,
            "sig_${DateTime.now().millisecondsSinceEpoch}.png",
          );
          await File(path).writeAsBytes(img.encodePng(decoded));
          _handleSignaturePostProcess(path, l10n.translate('imported_sig'));
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _openDigitalSignature() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignatureScreen(isSessionMode: true, onRefresh: () {}),
      ),
    );

    String? resultPath;
    if (result is String) {
      resultPath = result;
    } else if (result is Map && result.containsKey('path')) {
      resultPath = result['path'] as String?;
    }

    if (resultPath != null) {
      if (widget.isPickerMode) {
        Navigator.pop(context, [resultPath]);
      } else {
        addToSession(resultPath, _currentMode);
      }
    }
  }




  Widget _buildSignatureFrame() {
    final screenWidth = MediaQuery.of(context).size.width;
    final boxWidth = screenWidth * 0.85;
    final boxHeight = boxWidth * (180 / 320);

    return Stack(
      children: [
        Center(
          child: Container(
            width: boxWidth,
            height: boxHeight,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 250,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              l10n.translate('place_sig_msg'),
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

  Widget _buildQrViewfinder() {
    final screenWidth = MediaQuery.of(context).size.width;
    final boxSize = screenWidth * 0.75;

    return Stack(
      children: [
        // Semi-transparent backdrop with a hole
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Center(
                child: Container(
                  width: boxSize,
                  height: boxSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ],
          ),
        ),
        Center(
          child: SizedBox(
            width: boxSize,
            height: boxSize,
            child: Stack(
              children: [
                // Premium Corners
                CustomPaint(
                  size: Size(boxSize, boxSize),
                  painter: QrCornerPainter(
                    color: Colors.white,
                    strokeWidth: 4,
                    radius: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height * 0.5 + (boxSize / 2) + 30,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.translate('center_qr_msg'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class QrCornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  QrCornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const cornerLength = 40.0;

    // Top Left
    path.moveTo(0, cornerLength);
    path.lineTo(0, radius);
    path.arcToPoint(Offset(radius, 0), radius: Radius.circular(radius));
    path.lineTo(cornerLength, 0);

    // Top Right
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - radius, 0);
    path.arcToPoint(
      Offset(size.width, radius),
      radius: Radius.circular(radius),
    );
    path.lineTo(size.width, cornerLength);

    // Bottom Right
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height - radius);
    path.arcToPoint(
      Offset(size.width - radius, size.height),
      radius: Radius.circular(radius),
    );
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom Left
    path.moveTo(cornerLength, size.height);
    path.lineTo(radius, size.height);
    path.arcToPoint(
      Offset(0, size.height - radius),
      radius: Radius.circular(radius),
    );
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);

    // Add glowing effect
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

