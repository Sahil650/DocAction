import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/pdf_annotation.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/utils/app_localizations.dart';

// ─── Resize Corner Enum ───────────────────────────────────────────────────────
enum ResizeCorner { topLeft, topRight, bottomLeft, bottomRight }

class PdfEditScreen extends StatefulWidget {
  final File? initialFile;
  const PdfEditScreen({super.key, this.initialFile});

  @override
  State<PdfEditScreen> createState() => _PdfEditScreenState();
}

class _PdfEditScreenState extends State<PdfEditScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  AppLocalizations get l10n => AppLocalizations.of(context);

  Uint8List? _pdfBytes;
  List<Uint8List> _pageImages = [];
  int _currentPageIndex = 0;
  bool _isLoading = false;
  bool _isSaving = false;

  // Annotations stored per page
  final Map<int, List<PdfAnnotation>> _annotations = {};

  // Tool State
  AnnotationType _activeTool = AnnotationType.hand;
  Color _activeColor = Colors.black;
  double _activeStrokeWidth = 2.0;
  double _activeOpacity = 1.0;
  int _toolbarTab = 0; // 0: Annotate, 1: Shapes, 2: Insert

  // Selection State
  String? _selectedAnnotationId;
  bool _isDraggingHandle = false;
  Offset? _lastTapPosition; // For text placement in onTap

  // Freehand Drawing State
  List<Offset>? _currentPath;

  // Shape Drag-to-Draw State
  Offset? _shapeStartPoint;
  Offset? _shapeCurrentPoint;

  // Undo/Redo History
  final List<Map<int, List<PdfAnnotation>>> _history = [];
  final List<Map<int, List<PdfAnnotation>>> _redoStack = [];

  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _loadPdf(widget.initialFile!);
    } else {
      _pickPdf();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ─── History Management ───────────────────────────────────────────────────

  void _pushHistory() {
    final snapshot = _annotations.map(
      (k, v) => MapEntry(k, v.map((a) => a).toList()),
    );
    _history.add(snapshot);
    if (_history.length > 50) _history.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_history.isEmpty) return;
    final current = _annotations.map(
      (k, v) => MapEntry(k, v.map((a) => a).toList()),
    );
    _redoStack.add(current);
    setState(() {
      final prev = _history.removeLast();
      _annotations.clear();
      _annotations.addAll(prev);
      _selectedAnnotationId = null;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final current = _annotations.map(
      (k, v) => MapEntry(k, v.map((a) => a).toList()),
    );
    _history.add(current);
    setState(() {
      final next = _redoStack.removeLast();
      _annotations.clear();
      _annotations.addAll(next);
      _selectedAnnotationId = null;
    });
  }

  // ─── PDF Loading / Saving ─────────────────────────────────────────────────

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      _loadPdf(File(result.files.single.path!));
    } else {
      if (widget.initialFile == null && mounted) {
        Navigator.pop(context);
      }
    }
  }


  Future<void> _loadPdf(File file) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final imagesList = <Uint8List>[];
      await for (final page in _pdfService.rasterizePdfToImages(
        bytes,
        dpi: 150,
      )) {
        imagesList.add(page);
        if (imagesList.length == 1) {
          setState(() {
            _pdfBytes = bytes;
            _pageImages = imagesList;
          });
        }
      }
      setState(() {
        _pdfBytes = bytes;
        _pageImages = imagesList;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${l10n.translate('error_saving')}: $e")),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPdfFromBytes(Uint8List bytes) async {
    final imagesList = <Uint8List>[];
    await for (final page in _pdfService.rasterizePdfToImages(
      bytes,
      dpi: 150,
    )) {
      imagesList.add(page);
    }
    setState(() {
      _pdfBytes = bytes;
      _pageImages = imagesList;
      _isLoading = false;
    });
  }

  Future<void> _savePdf() async {
    if (_pdfBytes == null) return;

    final String defaultName = widget.initialFile != null
        ? "${l10n.translate('edited_prefix')}_${p.basenameWithoutExtension(widget.initialFile!.path)}"
        : l10n.translate('edited_doc_default');

    final TextEditingController nameController = TextEditingController(
      text: defaultName,
    );

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text(
          l10n.translate('save_document'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: l10n.translate('document_name'),
            labelStyle: const TextStyle(color: Colors.white54),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.translate('cancel_label'),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.translate('save_label'),
              style: const TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || nameController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      Size? renderedSize;
      final RenderBox? renderBox =
          _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) renderedSize = renderBox.size;

      final editedBytes = await _pdfService.applyAnnotationsToPdf(
        _pdfBytes!,
        _annotations,
        renderedSize: renderedSize,
      );

      final appDocDir = await getApplicationDocumentsDirectory();
      String safeName = nameController.text.trim();
      if (!safeName.toLowerCase().endsWith('.pdf')) {
        safeName += '.pdf';
      }
      final filePath = p.join(appDocDir.path, safeName);
      await File(filePath).writeAsBytes(editedBytes);

      await _storageService.saveDocumentNamed(
        name: nameController.text.trim(),
        imagePaths: [],
        pdfPath: filePath,
        pageCount: _pageImages.length,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('pdf_saved_library'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${l10n.translate('error_saving')}: $e")),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ─── Annotation Management ────────────────────────────────────────────────

  bool _isShapeTool(AnnotationType t) =>
      t == AnnotationType.rectangle ||
      t == AnnotationType.circle ||
      t == AnnotationType.line ||
      t == AnnotationType.arrow;

  void _onPanStart(DragStartDetails details) {
    if (_activeTool == AnnotationType.pen ||
        _activeTool == AnnotationType.highlighter) {
      setState(() {
        _currentPath = [details.localPosition];
        _selectedAnnotationId = null;
      });
    } else if (_isShapeTool(_activeTool)) {
      setState(() {
        _shapeStartPoint = details.localPosition;
        _shapeCurrentPoint = details.localPosition;
        _selectedAnnotationId = null;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentPath != null) {
      // Create a NEW list reference on every event.
      // If we called _currentPath!.add() (mutation), the painter's
      // shouldRepaint() would see old.points == points (same object)
      // and skip every repaint → stroke only appears on finger-lift.
      setState(() => _currentPath = [..._currentPath!, details.localPosition]);
    } else if (_shapeStartPoint != null) {
      setState(() => _shapeCurrentPoint = details.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentPath != null) {
      _finalizeFreehandPath();
    } else if (_shapeStartPoint != null) {
      _finalizeShape();
    }
  }

  void _finalizeFreehandPath() {
    if (_currentPath == null || _currentPath!.isEmpty) return;

    List<Offset> pts = List.from(_currentPath!);

    // Adobe-style horizontal snap for Highlighter
    if (_activeTool == AnnotationType.highlighter && pts.length > 5) {
      final startY = pts.first.dy;
      final avg = pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length;
      final variance =
          pts.map((p) => (p.dy - avg).abs()).reduce((a, b) => a + b) /
          pts.length;
      if (variance < 15.0) {
        pts = pts.map((p) => Offset(p.dx, startY)).toList();
      }
    }

    // Compute bounding box
    double minX = pts.first.dx, maxX = pts.first.dx;
    double minY = pts.first.dy, maxY = pts.first.dy;
    for (final pt in pts) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }

    _pushHistory();
    final id = Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: _activeTool,
      position: Offset(minX, minY),
      color: _activeColor,
      points: pts,
      width: (maxX - minX).clamp(20, 1000),
      height: (maxY - minY).clamp(20, 1000),
      strokeWidth: _activeTool == AnnotationType.highlighter
          ? 20.0
          : _activeStrokeWidth,
      opacity: _activeTool == AnnotationType.highlighter ? 0.5 : _activeOpacity,
    );

    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _currentPath = null;
      _activeTool = AnnotationType.hand; // Auto-switch
    });
  }

  void _finalizeShape() {
    if (_shapeStartPoint == null || _shapeCurrentPoint == null) return;

    final start = _shapeStartPoint!;
    final end = _shapeCurrentPoint!;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;

    if (dx.abs() < 5 && dy.abs() < 5) {
      setState(() {
        _shapeStartPoint = null;
        _shapeCurrentPoint = null;
      });
      return;
    }

    final left = math.min(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final width = dx.abs().clamp(10.0, 1000.0);
    final height = dy.abs().clamp(10.0, 1000.0);

    _pushHistory();
    final id = Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: _activeTool,
      position: Offset(left, top),
      color: _activeColor,
      width: width,
      height: height,
      strokeWidth: _activeStrokeWidth,
      opacity: _activeOpacity,
    );

    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _shapeStartPoint = null;
      _shapeCurrentPoint = null;
      _selectedAnnotationId = id;
      _activeTool = AnnotationType.hand; // Auto-switch
    });
  }

  // ─── Text Annotation ──────────────────────────────────────────────────────

  void _addTextAnnotation(Offset pos) {
    if (_pdfBytes == null) return;
    _pushHistory();
    final id = Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: AnnotationType.text,
      position: pos,
      color: _activeColor,
      content: "Text",
      width: 180,
      height: 50,
      fontSize: 16,
      opacity: _activeOpacity,
    );
    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
    });
    _editText(ann);
    setState(() => _activeTool = AnnotationType.hand);
  }

  void _editText(PdfAnnotation ann) {
    final controller = TextEditingController(text: ann.content);
    double fontSize = ann.fontSize;
    bool isBold = ann.isBold;
    bool isItalic = ann.isItalic;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C2E),
          title: Text(
            l10n.translate('edit_text_title'),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.translate('enter_text'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.format_size,
                    color: Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: fontSize.clamp(8.0, 72.0),
                      min: 8,
                      max: 72,
                      divisions: 32,
                      label: "${fontSize.round()}pt",
                      activeColor: Colors.blueAccent,
                      onChanged: (v) => setDs(() => fontSize = v),
                    ),
                  ),
                  Text(
                    "${fontSize.round()}pt",
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _styleToggle(
                    "B",
                    isBold,
                    () => setDs(() => isBold = !isBold),
                    bold: true,
                  ),
                  const SizedBox(width: 12),
                  _styleToggle(
                    "I",
                    isItalic,
                    () => setDs(() => isItalic = !isItalic),
                    italic: true,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l10n.translate('cancel_btn'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () {
                _pushHistory();
                setState(() {
                  final list = _annotations[_currentPageIndex]!;
                  final idx = list.indexWhere((e) => e.id == ann.id);
                  if (idx >= 0) {
                    list[idx] = ann.copyWith(
                      content: controller.text,
                      fontSize: fontSize,
                      isBold: isBold,
                      isItalic: isItalic,
                    );
                  }
                });
                Navigator.pop(context);
              },
              child: Text(
                l10n.translate('apply_label'),
                style: const TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _styleToggle(
    String label,
    bool active,
    VoidCallback onTap, {
    bool bold = false,
    bool italic = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 38,
        decoration: BoxDecoration(
          color: active ? Colors.blueAccent : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontSize: 17,
          ),
        ),
      ),
    );
  }

  // ─── Insert Helpers ───────────────────────────────────────────────────────

  void _addDateAnnotation() {
    final now = DateTime.now();
    final label = "${now.day}/${now.month}/${now.year}";
    _pushHistory();
    final id = Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: AnnotationType.text,
      position: const Offset(60, 120),
      color: _activeColor,
      content: label,
      width: 160,
      height: 36,
      fontSize: 14,
    );
    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
      _activeTool = AnnotationType.hand;
    });
  }

  void _addCheckAnnotation() {
    _pushHistory();
    final id = Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: AnnotationType.text,
      position: const Offset(60, 160),
      color: Colors.green,
      content: "✓",
      width: 48,
      height: 48,
      fontSize: 32,
    );
    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
      _activeTool = AnnotationType.hand;
    });
  }

  Future<void> _addImageAnnotation() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;
    _pushHistory();
    final id = Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: AnnotationType.image, // Use image type, not text
      position: const Offset(60, 200),
      color: Colors.transparent,
      content: result.files.single.path!, // Store the actual file path
      width: 220,
      height: 165,
    );
    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
      _activeTool = AnnotationType.hand;
    });
  }

  // ─── Signature Pad ────────────────────────────────────────────────────────

  void _showSignaturePad() {
    List<List<Offset>> strokesBuffer = [];
    List<Offset>? currentStroke;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMs) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade100, width: 1.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      label: Text(l10n.translate('clear_btn')),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: () => setMs(() => strokesBuffer.clear()),
                    ),
                    Text(
                      l10n.translate('add_signature'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (strokesBuffer.isNotEmpty) {
                          _addSignatureAnnotation(strokesBuffer);
                        }
                      },
                      child: Text(
                        l10n.translate('done_btn'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Canvas — NO box border, just clean white space ───────
              Expanded(
                child: Stack(
                  children: [
                    // White canvas
                    Positioned.fill(
                      child: GestureDetector(
                        onPanStart: (d) => setMs(() {
                          currentStroke = [d.localPosition];
                          strokesBuffer.add(currentStroke!);
                        }),
                        // Fix mutation bug: create new list ref so painter repaints live
                        onPanUpdate: (d) => setMs(() {
                          if (currentStroke != null) {
                            currentStroke = [
                              ...currentStroke!,
                              d.localPosition,
                            ];
                            strokesBuffer[strokesBuffer.length - 1] =
                                currentStroke!;
                          }
                        }),
                        onPanEnd: (_) => setMs(() => currentStroke = null),
                        child: CustomPaint(
                          painter: SignatureCanvasPainter(
                            strokes: strokesBuffer,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                    // Dashed "Sign here" baseline — decorative only, no border box
                    Positioned(
                      bottom: 90,
                      left: 32,
                      right: 32,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit,
                            color: Colors.blueAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CustomPaint(
                              painter: _DashedLinePainter(),
                              size: const Size(double.infinity, 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // "Sign here" hint — only shows when no strokes yet
                    if (strokesBuffer.isEmpty)
                      Center(
                        child: Text(
                          l10n.translate('sign_here_msg'),
                          style: const TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 22,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addSignatureAnnotation(List<List<Offset>> strokes) {
    // Encode multi-stroke with NaN sentinel separators
    final allPts = <Offset>[];
    for (int i = 0; i < strokes.length; i++) {
      if (i > 0) allPts.add(const Offset(double.nan, double.nan));
      allPts.addAll(strokes[i]);
    }

    final valid = allPts.where((p) => !p.dx.isNaN).toList();
    if (valid.isEmpty) return;

    double minX = valid.first.dx, maxX = valid.first.dx;
    double minY = valid.first.dy, maxY = valid.first.dy;
    for (final pt in valid) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }

    _pushHistory();
    final id = Uuid().v4();

    // ── CRITICAL: normalize points to (0,0) origin ──────────────────────────
    // Points were drawn in signature-pad local space (e.g. x:50–300, y:80–200).
    // If we store them raw and render with offset=ann.position (PDF coords),
    //   adjusted = pt - ann.position  e.g. (150,80) - (60,220) = (90,-140)
    // → negative Y → strokes fly far outside the bounding box.
    // By subtracting (minX,minY) we shift every point to (0,0)…(w,h) local
    // space. DrawingPainter is then called with offset=null so it draws them
    // directly without any further subtraction. ✓
    final normalizedPts = allPts.map((pt) {
      if (pt.dx.isNaN) return pt; // Preserve NaN separators
      return Offset(pt.dx - minX, pt.dy - minY); // Shift to (0,0) origin
    }).toList();

    final ann = PdfAnnotation(
      id: id,
      type: AnnotationType.signature,
      position: const Offset(60, 220), // PDF canvas placement (drag to move)
      color: Colors.black,
      points: normalizedPts, // LOCAL (0,0)–(w,h) coordinates
      width: math.max(50.0, maxX - minX),
      height: math.max(20.0, maxY - minY),
      strokeWidth: 2.5,
      opacity: 1.0,
    );

    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
      _activeTool = AnnotationType.hand;
    });
  }

  // ─── Color Picker ─────────────────────────────────────────────────────────

  void _showColorPicker() {
    final colors = [
      Colors.black,
      Colors.white,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.brown,
      Colors.grey,
      const Color(0xFF00BCD4),
      const Color(0xFF4CAF50),
      const Color(0xFFFFEB3B),
      const Color(0xFFFF5722),
      const Color(0xFF3F51B5),
      const Color(0xFFE91E63),
      const Color(0xFF009688),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('select_color'),
              style: GoogleFonts.inter(
                color: primaryGreen,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: colors
                  .map(
                    (c) => GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _pushHistory();
                          setState(() {
                            _activeColor = c;
                            if (_selectedAnnotationId != null) {
                              final list = _annotations[_currentPageIndex];
                              if (list != null) {
                                final idx = list.indexWhere(
                                  (a) => a.id == _selectedAnnotationId,
                                );
                                if (idx >= 0) {
                                  list[idx] = list[idx].copyWith(color: c);
                                }
                              }
                            }
                          });
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: c.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: _activeColor == c
                                ? accentAmber
                                : Colors.grey.withOpacity(0.1),
                            width: _activeColor == c ? 4 : 1,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static const Color primaryGreen = AppColors.primary;
  static const Color accentAmber = Color(0xffFFC107);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    PdfAnnotation? selectedAnn;
    if (_selectedAnnotationId != null) {
      final page = _annotations[_currentPageIndex];
      if (page != null) {
        try {
          selectedAnn = page.firstWhere((a) => a.id == _selectedAnnotationId);
        } catch (_) {}
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.translate('edit_pdf'),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              LucideIcons.undo,
              color: _history.isEmpty ? Colors.white24 : Colors.white,
              size: 20,
            ),
            onPressed: _history.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: Icon(
              LucideIcons.redo,
              color: _redoStack.isEmpty ? Colors.white24 : Colors.white,
              size: 20,
            ),
            onPressed: _redoStack.isEmpty ? null : _redo,
          ),
          if (_pdfBytes != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _savePdf,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.check, size: 16),
                label: Text(l10n.translate('save_label').toUpperCase()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentAmber,
                  foregroundColor: primaryGreen,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveLayout(
          maxWidth: 800,
          child: Column(
            children: [
              if (_pdfBytes != null) _buildToolbar(selectedAnn),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: primaryGreen),
                      )
                    : _pdfBytes == null
                    ? _buildEmptyState()
                    : _buildEditorCanvas(),
              ),
              if (_pdfBytes != null) _buildPageSelector(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.fileEdit,
                size: 64,
                color: primaryGreen,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.translate('pro_editor'),
              style: GoogleFonts.inter(
                color: primaryGreen,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('pro_editor_hint'),
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _pickPdf,
                icon: const Icon(LucideIcons.filePlus),
                label: Text(l10n.translate('select_pdf_to_edit')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Toolbar ──────────────────────────────────────────────────────────────

  Widget _buildToolbar(PdfAnnotation? selectedAnn) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab row
          Row(
            children: [
              _tabBtn(0, l10n.translate('annotate')),
              _tabBtn(1, l10n.translate('shapes')),
              _tabBtn(2, l10n.translate('insert')),
              const Spacer(),
              // Color dot
              GestureDetector(
                onTap: _showColorPicker,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _activeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: _activeColor.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    LucideIcons.palette,
                    size: 14,
                    color: _activeColor.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
              // Rotate
              IconButton(
                icon: const Icon(
                  LucideIcons.rotateCcw,
                  color: primaryGreen,
                  size: 18,
                ),
                onPressed: () async {
                  setState(() => _isLoading = true);
                  final rotated = await _pdfService.rotatePage(
                    _pdfBytes!,
                    _currentPageIndex,
                  );
                  _loadPdfFromBytes(rotated);
                },
              ),
            ],
          ),
          // Tool buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: _buildToolRow(),
          ),
          // Stroke / Opacity controls
          if (_activeTool == AnnotationType.pen ||
              _activeTool == AnnotationType.highlighter)
            _buildStrokeControls(),
          // Font controls for selected text
          if (selectedAnn != null && selectedAnn.type == AnnotationType.text)
            _buildTextControls(selectedAnn),
          // Selection banner
          if (_selectedAnnotationId != null) _buildSelectionBanner(),
        ],
      ),
    );
  }

  Widget _tabBtn(int index, String label) {
    final active = _toolbarTab == index;
    return GestureDetector(
      onTap: () => setState(() => _toolbarTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? accentAmber : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: active ? primaryGreen : Colors.grey,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildToolRow() {
    switch (_toolbarTab) {
      case 0:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _toolIcon(
              AnnotationType.hand,
              LucideIcons.hand,
              l10n.translate('hand_tool'),
            ),
            _toolIcon(
              AnnotationType.text,
              LucideIcons.type,
              l10n.translate('text_tool'),
            ),
            _toolIcon(
              AnnotationType.pen,
              LucideIcons.penTool,
              l10n.translate('pen_tool'),
            ),
            _toolIcon(
              AnnotationType.highlighter,
              LucideIcons.highlighter,
              l10n.translate('highlight_tool'),
            ),
            _toolIcon(
              AnnotationType.eraser,
              Icons.auto_fix_high,
              l10n.translate('eraser_tool'),
            ),
          ],
        );
      case 1:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _toolIcon(
              AnnotationType.rectangle,
              LucideIcons.square,
              l10n.translate('rect_label'),
            ),
            _toolIcon(
              AnnotationType.circle,
              LucideIcons.circle,
              l10n.translate('circle_label'),
            ),
            _toolIcon(
              AnnotationType.line,
              LucideIcons.minus,
              l10n.translate('line_label'),
            ),
            _toolIcon(
              AnnotationType.arrow,
              Icons.arrow_forward,
              l10n.translate('arrow_label'),
            ),
          ],
        );
      case 2:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _insertBtn(
              Icons.draw_outlined,
              l10n.translate('signature_label'),
              _showSignaturePad,
            ),
            _insertBtn(
              Icons.calendar_today_outlined,
              l10n.translate('date_label'),
              _addDateAnnotation,
            ),
            _insertBtn(
              Icons.check_box_outlined,
              l10n.translate('checkmark_label'),
              _addCheckAnnotation,
            ),
            _insertBtn(
              Icons.image_outlined,
              l10n.translate('image_label'),
              _addImageAnnotation,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _toolIcon(AnnotationType type, IconData icon, String label) {
    final sel = _activeTool == type;
    return GestureDetector(
      onTap: () => setState(() => _activeTool = type),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sel ? primaryGreen.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: sel ? primaryGreen : Colors.grey[600],
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: sel ? primaryGreen : Colors.grey[600],
              fontSize: 10,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _insertBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xffF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primaryGreen, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.grey[600],
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrokeControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Text(
            l10n.translate('size_upper'),
            style: GoogleFonts.inter(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          _thickOption(2.0, "S"),
          _thickOption(5.0, "M"),
          _thickOption(10.0, "L"),
          _thickOption(18.0, "XL"),
          const SizedBox(width: 16),
          Text(
            l10n.translate('opacity_upper'),
            style: GoogleFonts.inter(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Slider(
              value: _activeOpacity,
              min: 0.1,
              max: 1.0,
              activeColor: primaryGreen,
              inactiveColor: primaryGreen.withOpacity(0.1),
              onChanged: (v) => setState(() => _activeOpacity = v),
            ),
          ),
          Text(
            "${(_activeOpacity * 100).round()}%",
            style: GoogleFonts.inter(
              color: primaryGreen,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thickOption(double w, String label) {
    final sel = _activeStrokeWidth == w;
    return GestureDetector(
      onTap: () => setState(() => _activeStrokeWidth = w),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? primaryGreen : const Color(0xffF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: sel ? Colors.white : primaryGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTextControls(PdfAnnotation ann) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          const Icon(LucideIcons.type, color: Colors.grey, size: 16),
          Expanded(
            child: Slider(
              value: ann.fontSize.clamp(8.0, 72.0),
              min: 8,
              max: 72,
              activeColor: primaryGreen,
              inactiveColor: primaryGreen.withOpacity(0.1),
              onChanged: (v) {
                setState(() {
                  final list = _annotations[_currentPageIndex]!;
                  final idx = list.indexWhere((e) => e.id == ann.id);
                  if (idx >= 0) list[idx] = ann.copyWith(fontSize: v);
                });
              },
            ),
          ),
          _miniToggle("B", ann.isBold, () {
            _pushHistory();
            setState(() {
              final list = _annotations[_currentPageIndex]!;
              final idx = list.indexWhere((a) => a.id == ann.id);
              if (idx >= 0) list[idx] = ann.copyWith(isBold: !ann.isBold);
            });
          }, bold: true),
          const SizedBox(width: 6),
          _miniToggle("I", ann.isItalic, () {
            _pushHistory();
            setState(() {
              final list = _annotations[_currentPageIndex]!;
              final idx = list.indexWhere((e) => e.id == ann.id);
              if (idx >= 0) list[idx] = ann.copyWith(isItalic: !ann.isItalic);
            });
          }, italic: true),
        ],
      ),
    );
  }

  Widget _miniToggle(
    String label,
    bool active,
    VoidCallback onTap, {
    bool bold = false,
    bool italic = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 32,
        decoration: BoxDecoration(
          color: active ? accentAmber : const Color(0xffF8FAFC),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: active ? primaryGreen : primaryGreen,
            fontWeight: bold ? FontWeight.w900 : FontWeight.bold,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: primaryGreen.withOpacity(0.05),
      child: Row(
        children: [
          const Icon(LucideIcons.mousePointer2, color: primaryGreen, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('editing_selected'),
              style: GoogleFonts.inter(
                color: primaryGreen,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              _pushHistory();
              setState(() {
                _annotations[_currentPageIndex]?.removeWhere(
                  (a) => a.id == _selectedAnnotationId,
                );
                _selectedAnnotationId = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                LucideIcons.trash2,
                color: Colors.red,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Canvas ───────────────────────────────────────────────────────────────

  Widget _buildEditorCanvas() {
    if (_pageImages.isEmpty) return const SizedBox.shrink();

    final isDrawing =
        _activeTool == AnnotationType.pen ||
        _activeTool == AnnotationType.highlighter ||
        _isShapeTool(_activeTool);

    return Center(
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.5,
        maxScale: 4.0,
        panEnabled:
            (_activeTool == AnnotationType.hand ||
                _activeTool == AnnotationType.eraser) &&
            !_isDraggingHandle,
        scaleEnabled:
            (_activeTool == AnnotationType.hand ||
                _activeTool == AnnotationType.eraser) &&
            !_isDraggingHandle,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Container(
            key: _canvasKey,
            margin: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black45)],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _lastTapPosition = d.localPosition,
              // When draw tools active: onTap=null removes TapRecognizer from arena
              // so PanRecognizer wins INSTANTLY → live stroke preview with no delay.
              // When hand/eraser/text mode: onTap handles deselection & text placement.
              onTap: isDrawing
                  ? null
                  : () {
                      if (_activeTool == AnnotationType.text &&
                          _lastTapPosition != null) {
                        _addTextAnnotation(_lastTapPosition!);
                      } else if (_selectedAnnotationId != null) {
                        setState(() => _selectedAnnotationId = null);
                      }
                    },
              onPanStart: isDrawing ? _onPanStart : null,
              onPanUpdate: isDrawing ? _onPanUpdate : null,
              onPanEnd: isDrawing ? _onPanEnd : null,
              child: Stack(
                children: [
                  Image.memory(
                    _pageImages[_currentPageIndex],
                    fit: BoxFit.contain,
                  ),
                  // Annotation overlays
                  ...(_annotations[_currentPageIndex] ?? []).map(
                    (ann) => _buildAnnotationWidget(ann),
                  ),
                  // Live freehand path
                  if (_currentPath != null)
                    CustomPaint(
                      painter: DrawingPainter(
                        points: _currentPath!,
                        color: _activeColor,
                        strokeWidth: _activeStrokeWidth,
                        isHighlighter:
                            _activeTool == AnnotationType.highlighter,
                        opacity: _activeOpacity,
                      ),
                    ),
                  // Shape preview during drag
                  if (_shapeStartPoint != null && _shapeCurrentPoint != null)
                    CustomPaint(
                      painter: ShapePreviewPainter(
                        start: _shapeStartPoint!,
                        end: _shapeCurrentPoint!,
                        type: _activeTool,
                        color: _activeColor,
                        strokeWidth: _activeStrokeWidth,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Annotation Widget ────────────────────────────────────────────────────

  Widget _buildAnnotationWidget(PdfAnnotation ann) {
    final isSelected = _selectedAnnotationId == ann.id;
    final isEraser = _activeTool == AnnotationType.eraser;

    return Positioned(
      left: ann.position.dx,
      top: ann.position.dy,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (isEraser) {
                _pushHistory();
                setState(
                  () => _annotations[_currentPageIndex]?.removeWhere(
                    (a) => a.id == ann.id,
                  ),
                );
              } else {
                setState(() => _selectedAnnotationId = ann.id);
              }
            },
            onDoubleTap: () {
              if (ann.type == AnnotationType.text) _editText(ann);
            },
            onPanStart: isEraser
                ? null
                : (_) {
                    _pushHistory();
                  },
            onPanUpdate: isEraser
                ? null
                : (details) {
                    setState(() {
                      final list = _annotations[_currentPageIndex]!;
                      final idx = list.indexWhere((a) => a.id == ann.id);
                      if (idx < 0) return;
                      final old = list[idx];
                      final scale = _transformationController.value
                          .getMaxScaleOnAxis();
                      final delta = details.delta / scale;
                      final newPos = old.position + delta;
                      List<Offset>? newPts = old.points;
                      // Only shift absolute points (Pen/Highlighter). Signature points are local (0,0) so they move automatically with the box position.
                      if (old.points != null &&
                          (old.type == AnnotationType.pen ||
                              old.type == AnnotationType.highlighter)) {
                        newPts = old.points!
                            .map((pt) => pt.dx.isNaN ? pt : pt + delta)
                            .toList();
                      }
                      list[idx] = old.copyWith(
                        position: newPos,
                        points: newPts,
                      );
                      _selectedAnnotationId = ann.id;
                    });
                  },
            child: Opacity(
              opacity: ann.opacity,
              child: SizedBox(
                width: ann.width,
                height: ann.height,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected ? accentAmber : Colors.transparent,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: accentAmber.withOpacity(0.4),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: _renderAnnotationBody(ann),
                ),
              ),
            ),
          ),
          if (isSelected) ...[
            _buildHandle(
              top: -24,
              left: -24,
              icon: LucideIcons.maximize2,
              color: primaryGreen,
              onDrag: (d) =>
                  _handleResize(ann, d, corner: ResizeCorner.topLeft),
            ),
            _buildHandle(
              top: -24,
              right: -24,
              icon: LucideIcons.trash2,
              color: Colors.redAccent,
              onTap: () {
                _pushHistory();
                setState(() {
                  _annotations[_currentPageIndex]?.removeWhere(
                    (a) => a.id == ann.id,
                  );
                  _selectedAnnotationId = null;
                });
              },
            ),
            _buildHandle(
              bottom: -24,
              left: -24,
              icon: LucideIcons.maximize2,
              color: primaryGreen,
              onDrag: (d) =>
                  _handleResize(ann, d, corner: ResizeCorner.bottomLeft),
            ),
            _buildHandle(
              bottom: -24,
              right: -24,
              icon: LucideIcons.maximize2,
              color: primaryGreen,
              onDrag: (d) =>
                  _handleResize(ann, d, corner: ResizeCorner.bottomRight),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHandle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required IconData icon,
    required Color color,
    Function(Offset)? onDrag,
    VoidCallback? onTap,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: onDrag != null
            ? (_) => setState(() => _isDraggingHandle = true)
            : null,
        onPanEnd: onDrag != null
            ? (_) => setState(() => _isDraggingHandle = false)
            : null,
        onPanCancel: onDrag != null
            ? () => setState(() => _isDraggingHandle = false)
            : null,
        onPanUpdate: onDrag != null ? (d) => onDrag(d.delta) : null,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(blurRadius: 8, color: color.withOpacity(0.3)),
              ],
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _handleResize(
    PdfAnnotation ann,
    Offset delta, {
    ResizeCorner corner = ResizeCorner.bottomRight,
  }) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final d = delta / scale;

    // ── Determine how width/height/position change per corner ──
    // The "opposite" corner is always fixed.
    //   bottomRight → top-left is fixed → only size grows
    //   bottomLeft  → top-right is fixed → left edge moves, width shrinks
    //   topRight    → bottom-left is fixed → top edge moves, height shrinks
    //   topLeft     → bottom-right is fixed → both edges move
    double dw, dh, dpx, dpy;
    switch (corner) {
      case ResizeCorner.bottomRight:
        dw = d.dx;
        dh = d.dy;
        dpx = 0;
        dpy = 0;
        break;
      case ResizeCorner.bottomLeft:
        dw = -d.dx;
        dh = d.dy;
        dpx = d.dx;
        dpy = 0;
        break;
      case ResizeCorner.topRight:
        dw = d.dx;
        dh = -d.dy;
        dpx = 0;
        dpy = d.dy;
        break;
      case ResizeCorner.topLeft:
        dw = -d.dx;
        dh = -d.dy;
        dpx = d.dx;
        dpy = d.dy;
        break;
    }

    setState(() {
      final list = _annotations[_currentPageIndex]!;
      final idx = list.indexWhere((a) => a.id == ann.id);
      if (idx < 0) return;
      final old = list[idx];

      final newW = (old.width + dw).clamp(20.0, 1200.0);
      final newH = (old.height + dh).clamp(20.0, 1200.0);
      final newPos = Offset(old.position.dx + dpx, old.position.dy + dpy);

      if (old.type == AnnotationType.text) {
        // Text: resize the box (width + height). Font size stays.
        list[idx] = old.copyWith(position: newPos, width: newW, height: newH);
      } else if (old.type == AnnotationType.rectangle ||
          old.type == AnnotationType.circle) {
        list[idx] = old.copyWith(position: newPos, width: newW, height: newH);
      } else if (old.type == AnnotationType.line ||
          old.type == AnnotationType.arrow) {
        list[idx] = old.copyWith(position: newPos, width: newW, height: newH);
      } else if (old.type == AnnotationType.image) {
        list[idx] = old.copyWith(position: newPos, width: newW, height: newH);
      } else if (old.type == AnnotationType.pen ||
          old.type == AnnotationType.highlighter) {
        if (old.width < 1 || old.height < 1 || old.points == null) return;

        // Scale points proportionally. Anchor = the FIXED corner.
        final Offset anchorPt;
        switch (corner) {
          case ResizeCorner.bottomRight:
            anchorPt = old.position; // top-left stays
            break;
          case ResizeCorner.bottomLeft:
            anchorPt = Offset(
              old.position.dx + old.width,
              old.position.dy,
            ); // top-right stays
            break;
          case ResizeCorner.topRight:
            anchorPt = Offset(
              old.position.dx,
              old.position.dy + old.height,
            ); // bottom-left stays
            break;
          case ResizeCorner.topLeft:
            anchorPt =
                old.position +
                Offset(old.width, old.height); // bottom-right stays
            break;
        }

        final scaleX = newW / old.width;
        final scaleY = newH / old.height;

        final newPts = old.points!.map((pt) {
          if (pt.dx.isNaN) return pt; // Keep NaN separators for multi-stroke
          return Offset(
            anchorPt.dx + (pt.dx - anchorPt.dx) * scaleX,
            anchorPt.dy + (pt.dy - anchorPt.dy) * scaleY,
          );
        }).toList();

        list[idx] = old.copyWith(
          position: newPos,
          points: newPts,
          width: newW,
          height: newH,
        );
      } else if (old.type == AnnotationType.signature) {
        if (old.width < 1 || old.height < 1 || old.points == null) return;

        final scaleX = newW / old.width;
        final scaleY = newH / old.height;

        // Signature points are perfectly localized to (0,0) -> (width, height).
        // Since `newPos` perfectly absorbs the absolute translation of whichever
        // corner is dragged, we only need to scale the local points by the ratio.
        final newPts = old.points!.map((pt) {
          if (pt.dx.isNaN) return pt;
          return Offset(pt.dx * scaleX, pt.dy * scaleY);
        }).toList();

        list[idx] = old.copyWith(
          position: newPos,
          points: newPts,
          width: newW,
          height: newH,
        );
      }
    });
  }

  // ─── Annotation Body Renderer ─────────────────────────────────────────────

  Widget _renderAnnotationBody(PdfAnnotation ann) {
    final c = ann.type == AnnotationType.highlighter
        ? ann.color.withOpacity(0.5)
        : ann.color;

    switch (ann.type) {
      case AnnotationType.text:
        return Text(
          ann.content ?? "",
          style: TextStyle(
            color: c,
            fontSize: ann.fontSize,
            fontWeight: ann.isBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: ann.isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        );

      case AnnotationType.rectangle:
        return Container(
          width: ann.width,
          height: ann.height,
          decoration: BoxDecoration(
            border: Border.all(color: c, width: ann.strokeWidth),
          ),
        );

      case AnnotationType.circle:
        return Container(
          width: ann.width,
          height: ann.height,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c, width: ann.strokeWidth),
          ),
        );

      case AnnotationType.highlighter:
        return Container(width: ann.width, height: ann.height, color: c);

      case AnnotationType.pen:
        return CustomPaint(
          size: Size(ann.width, ann.height),
          painter: DrawingPainter(
            points: ann.points ?? [],
            color: c,
            strokeWidth: ann.strokeWidth,
            offset: ann.position, // Pen points are in PDF canvas space
            opacity: ann.opacity,
          ),
        );

      case AnnotationType.signature:
        // Points are already normalized to (0,0)–(width,height) local space.
        // Pass offset: null so DrawingPainter does NOT subtract anything.
        return CustomPaint(
          size: Size(ann.width, ann.height),
          painter: DrawingPainter(
            points: ann.points ?? [],
            color: c,
            strokeWidth: ann.strokeWidth,
            offset: null, // No subtraction — use normalized coords directly
            opacity: ann.opacity,
          ),
        );

      case AnnotationType.image:
        if (ann.content != null) {
          final f = File(ann.content!);
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              f,
              width: ann.width,
              height: ann.height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: ann.width,
                height: ann.height,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          );
        }
        return Container(
          width: ann.width,
          height: ann.height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image, color: Colors.grey),
        );

      case AnnotationType.line:
      case AnnotationType.arrow:
        return CustomPaint(
          size: Size(ann.width, ann.height),
          painter: ShapePainter(ann: ann),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Page Selector ────────────────────────────────────────────────────────

  Widget _buildPageSelector() {
    if (_pageImages.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: primaryGreen),
            onPressed: _currentPageIndex > 0
                ? () => setState(() => _currentPageIndex--)
                : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              l10n
                  .translate('page_of')
                  .replaceFirst('{0}', '${_currentPageIndex + 1}')
                  .replaceFirst('{1}', '${_pageImages.length}'),
              style: GoogleFonts.inter(
                color: primaryGreen,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight, color: primaryGreen),
            onPressed: _currentPageIndex < _pageImages.length - 1
                ? () => setState(() => _currentPageIndex++)
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────────

/// Smooth Bezier stroke painter for Pen, Highlighter, and Signature.
class DrawingPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isHighlighter;
  final Offset? offset;
  final double opacity;

  DrawingPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isHighlighter = false,
    this.offset,
    this.opacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = isHighlighter
          ? color.withOpacity(0.45)
          : color.withOpacity(opacity)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool startNew = true;

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      if (pt.dx.isNaN || pt.dy.isNaN) {
        startNew = true;
        continue;
      }
      final adjusted = offset != null ? pt - offset! : pt;

      if (startNew) {
        path.moveTo(adjusted.dx, adjusted.dy);
        startNew = false;
      } else {
        // Smooth Bezier using midpoints
        if (i + 1 < points.length && !points[i + 1].dx.isNaN) {
          final next = offset != null ? points[i + 1] - offset! : points[i + 1];
          final mid = Offset(
            (adjusted.dx + next.dx) / 2,
            (adjusted.dy + next.dy) / 2,
          );
          path.quadraticBezierTo(adjusted.dx, adjusted.dy, mid.dx, mid.dy);
        } else {
          path.lineTo(adjusted.dx, adjusted.dy);
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DrawingPainter old) =>
      old.points != points ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Painter for Line and Arrow shapes.
class ShapePainter extends CustomPainter {
  final PdfAnnotation ann;
  const ShapePainter({required this.ann});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ann.color.withOpacity(ann.opacity)
      ..strokeWidth = ann.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const start = Offset.zero;
    final end = Offset(size.width, size.height);

    canvas.drawLine(start, end, paint);

    if (ann.type == AnnotationType.arrow) {
      _drawArrowhead(canvas, start, end, paint);
    }
  }

  void _drawArrowhead(Canvas canvas, Offset start, Offset end, Paint paint) {
    const sz = 14.0;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - sz * math.cos(angle - math.pi / 6),
        end.dy - sz * math.sin(angle - math.pi / 6),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - sz * math.cos(angle + math.pi / 6),
        end.dy - sz * math.sin(angle + math.pi / 6),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}

/// Live preview of a shape being drawn by dragging.
class ShapePreviewPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final AnnotationType type;
  final Color color;
  final double strokeWidth;

  const ShapePreviewPainter({
    required this.start,
    required this.end,
    required this.type,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.75)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final left = math.min(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final w = (end.dx - start.dx).abs();
    final h = (end.dy - start.dy).abs();
    final rect = Rect.fromLTWH(left, top, w, h);

    switch (type) {
      case AnnotationType.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case AnnotationType.circle:
        canvas.drawOval(rect, paint);
        break;
      case AnnotationType.line:
        canvas.drawLine(start, end, paint);
        break;
      case AnnotationType.arrow:
        canvas.drawLine(start, end, paint);
        const sz = 14.0;
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        final path = Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            end.dx - sz * math.cos(angle - math.pi / 6),
            end.dy - sz * math.sin(angle - math.pi / 6),
          )
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            end.dx - sz * math.cos(angle + math.pi / 6),
            end.dy - sz * math.sin(angle + math.pi / 6),
          );
        canvas.drawPath(path, paint);
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}

/// Signature pad canvas painter (multi-stroke).
class SignatureCanvasPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const SignatureCanvasPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      path.moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length - 1; i++) {
        final mid = Offset(
          (stroke[i].dx + stroke[i + 1].dx) / 2,
          (stroke[i].dy + stroke[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  // Always repaint — list contents change even when the ref changes
  bool shouldRepaint(covariant SignatureCanvasPainter old) => true;
}

/// Dashed baseline painter for the signature pad.
class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBBCCEE)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashW = 8.0;
    const gapW = 5.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashW, 0), paint);
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
