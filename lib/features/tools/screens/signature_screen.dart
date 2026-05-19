import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import 'signature_session_screen.dart';
import '../../scanner/screens/universal_scanner_screen.dart';
import '../../scanner/models/scanner_mode.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/utils/app_localizations.dart';

// Background processing function
Future<String> _processCapturedSignature(Map<String, dynamic> params) async {
  final String imagePath = params['imagePath'];
  final String tempDirPath = params['tempDirPath'];

  final bytes = await File(imagePath).readAsBytes();
  img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) throw Exception("Failed to decode image");

  // 1. Resize for performance (Max 1024px)
  if (decoded.width > 1024 || decoded.height > 1024) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? 1024 : null,
      height: decoded.height >= decoded.width ? 1024 : null,
    );
  }

  // 2. Enhance contrast to make the signature pop
  img.contrast(decoded, contrast: 150);

  // 3. Premium: Convert White to Alpha (Transparency)
  // We iterate through every pixel and set alpha = (255 - luminance)
  // This makes white areas transparent and dark areas opaque
  final processed = img.Image.from(decoded); // Ensure we have alpha channel
  for (final pixel in processed) {
    final l = img.getLuminance(pixel);
    // If it's very bright (near white), make it transparent
    // We use a smooth transition for better anti-aliasing
    final alpha = (255 - l).clamp(0, 255).toInt();
    pixel.a = alpha;
    
    // Optional: Boost the dark colors to pure black for a cleaner look
    if (l < 100) {
      pixel.r = 0;
      pixel.g = 0;
      pixel.b = 0;
    }
  }

  final fileName = "scanned_sig_${DateTime.now().millisecondsSinceEpoch}.png";
  final filePath = p.join(tempDirPath, fileName);
  await File(filePath).writeAsBytes(img.encodePng(processed));

  return filePath;
}

class SignatureScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  final bool isSessionMode;
  final String? initialAction; // 'draw' or 'scan'

  const SignatureScreen({
    super.key,
    this.onRefresh,
    this.isSessionMode = false,
    this.initialAction,
  });

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  late SignatureController _controller;
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;
  bool _isProcessing = false;
  bool _isNavigating = false;
  final _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _initController();
    
    if (widget.initialAction == 'scan') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanSignature();
      });
    }
  }

  void _initController() {
    _controller = SignatureController(
      penStrokeWidth: _strokeWidth,
      penColor: _selectedColor,
      exportBackgroundColor: Colors.white, // Save with white background for better visibility
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changeColor(Color color) {
    if (_selectedColor == color) return;
    setState(() {
      _selectedColor = color;
      // We don't re-init the whole controller, we just update the properties
      // if the package supports it, or we re-init with existing points.
      final points = _controller.points;
      _controller.dispose();
      _controller = SignatureController(
        penStrokeWidth: _strokeWidth,
        penColor: _selectedColor,
        exportBackgroundColor: null,
        points: points,
      );
    });
  }

  void _updateStrokeWidth(double val) {
    setState(() {
      _strokeWidth = val;
      final points = _controller.points;
      _controller.dispose();
      _controller = SignatureController(
        penStrokeWidth: _strokeWidth,
        penColor: _selectedColor,
        exportBackgroundColor: null,
        points: points,
      );
    });
  }

  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('draw_first_msg'))),
      );
      return;
    }

    if (_isNavigating) return;
    setState(() => _isProcessing = true);
    
    try {
      // Export using the background color defined in the controller
      final Uint8List? data = await _controller.toPngBytes();
      if (data != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = "sig_${DateTime.now().millisecondsSinceEpoch}.png";
        final filePath = p.join(tempDir.path, fileName);

        await File(filePath).writeAsBytes(data);

        if (widget.isSessionMode) {
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            Navigator.pop(context, {
              'path': filePath,
              'points': _controller.points,
            });
          }
          return;
        }

        final timestamp = DateTime.now()
            .toString()
            .replaceAll(RegExp(r'[:.-]'), '')
            .substring(0, 14);
        final doc = DocumentModel(
          id: const Uuid().v4(),
          name: "SIG_$timestamp",
          date: DateTime.now(),
          imagePaths: [filePath],
        );

        await _storageService.saveDocument(doc);
        widget.onRefresh?.call();

        if (mounted && !_isNavigating) {
          final l10n = AppLocalizations.of(context);
          _isNavigating = true;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.translate('sig_saved_msg'))));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("${l10n.translate('save_error_snack')}: $e")));
      }
    } finally {
      if (mounted && !_isNavigating) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _scanSignature() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UniversalScannerScreen(
          initialMode: ScannerMode.signature,
          isPickerMode: true,
        ),
      ),
    );

    String? scannedPath;
    if (result is String) {
      scannedPath = result;
    } else if (result is Map && result.containsKey('path')) {
      scannedPath = result['path'] as String?;
    }

    if (scannedPath != null && scannedPath != "RETAKE") {
      setState(() => _isProcessing = true);
      try {
        final tempDir = await getTemporaryDirectory();

        final processedPath = await compute(_processCapturedSignature, {
          'imagePath': scannedPath,
          'tempDirPath': tempDir.path,
        });

        if (mounted) {
          if (widget.isSessionMode) {
            // Return the processed signature directly to the studio
            Navigator.pop(context, {'path': processedPath});
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SignatureSessionScreen(
                initialPaths: [processedPath],
                onRefresh: widget.onRefresh,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("${l10n.translate('scan_err_msg')}: $e")));
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xffF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xffF3F4F6),
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          widget.isSessionMode ? l10n.translate('draw_signature') : l10n.translate('create_signature'),
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (!widget.isSessionMode)
            IconButton(
              onPressed: _scanSignature,
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: l10n.translate('scan_from_paper'),
            ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Grid / Paper Pattern
                      Positioned.fill(
                        child: CustomPaint(
                          painter: PaperGridPainter(),
                        ),
                      ),
                      Positioned.fill(
                        child: Signature(
                          controller: _controller,
                          backgroundColor: Colors.transparent, // Let the paper grid show through
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildControls(isTablet),
            _buildActionPanel(isTablet),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(bool isTablet) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 64 : 24,
        vertical: 12,
      ),
      child: Row(
        children: [
          _colorDot(Colors.black),
          _colorDot(Colors.blue),
          _colorDot(Colors.red),
          const Spacer(),
          Text(
            "${l10n.translate('signature_weight')}: ",
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Slider(
              value: _strokeWidth,
              min: 1,
              max: 10,
              activeColor: AppColors.primary,
              onChanged: _updateStrokeWidth,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorDot(Color color) {
    final bool isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () => _changeColor(color),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 3,
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
      ),
    );
  }

  Widget _buildActionPanel(bool isTablet) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.all(isTablet ? 48 : 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _controller.clear(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(l10n.translate('clear_all')),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _saveSignature,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.isSessionMode
                            ? l10n.translate('add_to_session')
                            : l10n.translate('save_signature'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PaperGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.05)
      ..strokeWidth = 1.0;

    // Draw horizontal lines (ruled paper look)
    const double spacing = 30.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    // Draw vertical lines (grid look)
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
