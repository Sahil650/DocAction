import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../data/models/pdf_annotation.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/signature_service.dart';
import '../widgets/signature_overlay.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../tools/screens/signature_screen.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class PdfSignScreen extends StatefulWidget {
  final File initialFile;
  const PdfSignScreen({super.key, required this.initialFile});

  @override
  State<PdfSignScreen> createState() => _PdfSignScreenState();
}

class _PdfSignScreenState extends State<PdfSignScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  final SignatureService _signatureService = SignatureService();
  AppLocalizations get l10n => AppLocalizations.of(context);

  Uint8List? _pdfBytes;
  List<Uint8List> _pageImages = [];
  List<Size> _pageSizes = [];
  int _currentPageIndex = 0;
  bool _isLoading = false;
  bool _isSaving = false;

  final Map<int, List<PdfAnnotation>> _annotations = {};
  String? _selectedAnnotationId;

  // History for Undo/Redo
  final List<Map<int, List<PdfAnnotation>>> _history = [];
  final List<Map<int, List<PdfAnnotation>>> _redoStack = [];

  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadPdf(widget.initialFile);
  }

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
    final current = _annotations.map((k, v) => MapEntry(k, v.map((a) => a).toList()));
    _redoStack.add(current);
    setState(() {
      final prev = _history.removeLast();
      _annotations.clear();
      _annotations.addAll(prev);
      _selectedAnnotationId = null;
    });
  }

  Future<void> _loadPdf(File file) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final imagesList = <Uint8List>[];
      final sizesList = <Size>[];

      // Get page sizes for accurate mapping
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: bytes);
      for (int i = 0; i < document.pages.count; i++) {
        sizesList.add(document.pages[i].size);
      }
      document.dispose();

      await for (final page in _pdfService.rasterizePdfToImages(bytes, dpi: 150)) {
        imagesList.add(page);
        if (imagesList.length == 1) {
          setState(() {
            _pdfBytes = bytes;
            _pageImages = imagesList;
            _pageSizes = sizesList;
          });
        }
      }
      setState(() {
        _pdfBytes = bytes;
        _pageImages = imagesList;
        _pageSizes = sizesList;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${l10n.translate('error_loading')}: $e")));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSignedPdf() async {
    if (_pdfBytes == null) return;

    // 1. Instantly clean up UI for a professional "Saving" look
    setState(() {
      _selectedAnnotationId = null;
    });

    // 2. Ask for a filename
    final customName = await _showRenameDialog();
    if (customName == null) return; // User cancelled

    setState(() => _isSaving = true);
    
    try {
      Size? renderedSize;
      final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) renderedSize = renderBox.size;

      final editedBytes = await _pdfService.applyAnnotationsToPdf(
        _pdfBytes!, _annotations, renderedSize: renderedSize,
      );

      final appDocDir = await getApplicationDocumentsDirectory();
      // Ensure the name ends with .pdf
      String finalName = customName.trim();
      if (!finalName.toLowerCase().endsWith(".pdf")) {
        finalName = "$finalName.pdf";
      }
      
      final filePath = p.join(appDocDir.path, finalName);
      await File(filePath).writeAsBytes(editedBytes);

      await _storageService.saveDocumentNamed(
        name: p.basenameWithoutExtension(finalName),
        imagePaths: [],
        pdfPath: filePath,
        pageCount: _pageImages.length,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate("doc_signed_saved_snack"))));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${l10n.translate('error_saving')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _showRenameDialog() async {
    final l10n = AppLocalizations.of(context);
    final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[:.-]'), '').substring(0, 14);
    final defaultName = "${l10n.translate('signed_doc_prefix')}_${p.basenameWithoutExtension(widget.initialFile.path)}_$timestamp";
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.translate("save_doc_as"), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate("enter_signed_pdf_name"), style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.translate("filename_hint"),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: Icon(LucideIcons.fileText, size: 20, color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate("cancel_btn"))),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) Navigator.pop(ctx, controller.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(l10n.translate("save_label")),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignResult(Map<String, dynamic>? result) async {
    if (result != null) {
      if (result['path'] != null) {
        await _signatureService.saveSignature(result['path']);
        _addSignature(result['path']);
      } else if (result['points'] != null) {
        _addSignature(null, points: result['points'] as List<Offset>);
      }
    }
  }

  void _addSignature(String? path, {List<Offset>? points}) {
    _pushHistory();
    final id = const Uuid().v4();
    
    PdfAnnotation ann;
    if (points != null) {
      // Normalize points for signature
      double minX = points.where((p) => !p.dx.isNaN).map((p) => p.dx).reduce(math.min);
      double minY = points.where((p) => !p.dy.isNaN).map((p) => p.dy).reduce(math.min);
      final normalized = points.map((p) => p.dx.isNaN ? p : Offset(p.dx - minX, p.dy - minY)).toList();
      
      ann = PdfAnnotation(
        id: id,
        type: AnnotationType.signature,
        position: const Offset(50, 100),
        color: Colors.black,
        points: normalized,
        width: 150,
        height: 80,
        strokeWidth: 3.0,
      );
    } else {
      ann = PdfAnnotation(
        id: id,
        type: AnnotationType.image,
        position: const Offset(50, 100),
        color: Colors.transparent,
        content: path!,
        width: 150,
        height: 80,
      );
    }

    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
    });
  }

  void _addDate() {
    _pushHistory();
    final now = DateTime.now();
    final dateStr = "${now.day}/${now.month}/${now.year}";
    final id = const Uuid().v4();
    final ann = PdfAnnotation(
      id: id,
      type: AnnotationType.text,
      position: const Offset(50, 200),
      color: Colors.black,
      content: dateStr,
      width: 120,
      height: 30,
      fontSize: 16,
    );
    setState(() {
      _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
      _selectedAnnotationId = id;
    });
  }

  void _addText() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        title: Text(l10n.translate("enter_text"), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        content: TextField(controller: controller, autofocus: true, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate("cancel_btn"))),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _pushHistory();
                final id = const Uuid().v4();
                final ann = PdfAnnotation(
                  id: id,
                  type: AnnotationType.text,
                  position: const Offset(50, 250),
                  color: Colors.black,
                  content: controller.text,
                  width: 150,
                  height: 40,
                  fontSize: 18,
                );
                setState(() {
                  _annotations.putIfAbsent(_currentPageIndex, () => []).add(ann);
                  _selectedAnnotationId = id;
                });
              }
              Navigator.pop(ctx);
            },
            child: Text(l10n.translate("add_btn")),
          ),
        ],
      ),
    );
  }

  void _showSignatureLibrary() async {
    final saved = await _signatureService.getSavedSignatures();
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.translate("my_signatures"), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(builder: (_) => const SignatureScreen(isSessionMode: true, initialAction: 'scan')),
                    );
                    _handleSignResult(result);
                  },
                  icon: Icon(LucideIcons.camera, color: Theme.of(context).colorScheme.primary),
                  tooltip: l10n.translate("scan_paper_tool"),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(builder: (_) => const SignatureScreen(isSessionMode: true, initialAction: 'draw')),
                    );
                    _handleSignResult(result);
                  },
                  icon: const Icon(Icons.folder, size: 18),
                  label: Text(l10n.translate("draw_new")),
                )
              ],
            ),
            const SizedBox(height: 16),
            if (saved.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(l10n.translate("no_saved_signatures"), style: const TextStyle(color: Colors.grey)),
                ),
              )
            else
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: saved.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, index) {
                    final path = saved[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _addSignature(path);
                      },
                      child: Container(
                        width: 180,
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.white,
                        ),
                        child: Stack(
                          children: [
                            Center(child: Image.file(File(path), fit: BoxFit.contain)),
                            Positioned(
                              top: 4, right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                onPressed: () {
                                  _signatureService.deleteSignature(path);
                                  Navigator.pop(ctx);
                                  _showSignatureLibrary(); // Refresh
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(l10n.translate("sign_document"), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        actions: [
          if (_history.isNotEmpty)
            IconButton(icon: const Icon(LucideIcons.undo), onPressed: _undo),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSignedPdf,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l10n.translate("done_btn")),
            ),
          ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: (_pageImages.isEmpty || _pageSizes.isEmpty)
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              // Calculate display dimensions to match PDF aspect ratio
                              final pdfSize = _pageSizes[_currentPageIndex];
                              final maxWidth = math.min(constraints.maxWidth - 48, 800.0);
                              final scale = maxWidth / pdfSize.width;
                              final displayWidth = maxWidth;
                              final displayHeight = pdfSize.height * scale;
  
                              return SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 3.0,
                                    child: Container(
                                      width: displayWidth,
                                      height: displayHeight,
                                      key: _canvasKey,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.9) : Colors.white,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          )
                                        ],
                                      ),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          // PDF Page Image - fits perfectly in the sized Container
                                          Image.memory(
                                            _pageImages[_currentPageIndex],
                                            width: displayWidth,
                                            height: displayHeight,
                                            fit: BoxFit.fill,
                                          ),
                                          
                                          // Annotations Layer
                                          if (_annotations[_currentPageIndex] != null)
                                            ..._annotations[_currentPageIndex]!.map((ann) {
                                              return SignatureOverlay(
                                                annotation: ann,
                                                isSelected: _selectedAnnotationId == ann.id,
                                                onTap: () => setState(() => _selectedAnnotationId = ann.id),
                                                onDelete: () {
                                                  _pushHistory();
                                                  setState(() {
                                                    _annotations[_currentPageIndex]!.removeWhere((a) => a.id == ann.id);
                                                    _selectedAnnotationId = null;
                                                  });
                                                },
                                                onUpdate: (updatedAnn) {
                                                  setState(() {
                                                    final idx = _annotations[_currentPageIndex]!.indexWhere((a) => a.id == ann.id);
                                                    if (idx != -1) _annotations[_currentPageIndex]![idx] = updatedAnn;
                                                  });
                                                },
                                              );
                                            }),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  _buildToolbar(),
                ],
              ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            const BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _toolItem(LucideIcons.penTool, l10n.translate("sign_label"), Colors.blue, _showSignatureLibrary),
            _toolItem(LucideIcons.type, l10n.translate("text_label"), Colors.orange, _addText),
            _toolItem(LucideIcons.calendar, l10n.translate("date_label"), Colors.green, _addDate),
            const VerticalDivider(width: 20, indent: 10, endIndent: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toolItem(Icons.folder, l10n.translate("prev_label"), Colors.grey, _currentPageIndex > 0 ? () => setState(() => _currentPageIndex--) : null),
                const SizedBox(width: 12),
                Text(
                  "${_currentPageIndex + 1} / ${_pageImages.length}",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                _toolItem(LucideIcons.chevronRight, l10n.translate("next_label"), Colors.grey, _currentPageIndex < _pageImages.length - 1 ? () => setState(() => _currentPageIndex++) : null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolItem(IconData icon, String label, Color color, VoidCallback? onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: onTap == null ? Colors.grey : color),
          onPressed: onTap,
        ),
        Text(label, style: TextStyle(fontSize: 10, color: onTap == null ? Colors.grey : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.black54))),
      ],
    );
  }
}
