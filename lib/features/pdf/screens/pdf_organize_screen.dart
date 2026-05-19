import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'pdf_viewer_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../data/services/pdf_service.dart';

class PdfOrganizeScreen extends StatefulWidget {
  final File? initialFile;
  const PdfOrganizeScreen({super.key, this.initialFile});

  @override
  State<PdfOrganizeScreen> createState() => _PdfOrganizeScreenState();
}

class _PdfOrganizeScreenState extends State<PdfOrganizeScreen> {
  // Removed hardcoded primaryGreen to use theme's primary color
  static const Color accentAmber = Color(0xffFFC107);

  final _pdfService = PdfService();
  final _storageService = StorageService();
  final ScrollController _scrollController = ScrollController();
  AppLocalizations get l10n => AppLocalizations.of(context);

  final Map<String, Uint8List> _sourceBytesMap = {};
  final Map<String, String> _sourceNames = {};

  bool _isProcessing = false;
  bool _isLoadingPages = false;

  List<PageItem> _pages = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _loadPdf(widget.initialFile!);
    }
  }

  Future<void> _loadPdf(File file, {bool isAppend = false}) async {
    setState(() => _isLoadingPages = true);
    try {
      final bytes = await file.readAsBytes();

      if (_pdfService.isPdfEncrypted(bytes)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.translate('pdf_locked_error'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        }
        return;
      }

      final sourceId =
          "${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}";
      final sourceName = file.path.split(Platform.isWindows ? '\\' : '/').last;

      _sourceBytesMap[sourceId] = bytes;
      _sourceNames[sourceId] = sourceName;

      final sf.PdfDocument doc = sf.PdfDocument(inputBytes: bytes);
      final List<int> originalRotations = [];
      for (int i = 0; i < doc.pages.count; i++) {
        int angle = 0;
        final rotation = doc.pages[i].rotation;
        if (rotation == sf.PdfPageRotateAngle.rotateAngle90) {
          angle = 90;
        } else if (rotation == sf.PdfPageRotateAngle.rotateAngle180)
          angle = 180;
        else if (rotation == sf.PdfPageRotateAngle.rotateAngle270)
          angle = 270;
        originalRotations.add(angle);
      }
      doc.dispose();

      List<PageItem> newPages = [];
      int pageIdx = 0;

      await for (final page in Printing.raster(bytes, dpi: 100)) {
        final png = await page.toPng();
        newPages.add(
          PageItem(
            id: "${sourceId}_$pageIdx",
            sourceId: sourceId,
            sourcePageIndex: pageIdx,
            thumbnail: png,
            rotation: originalRotations[pageIdx],
          ),
        );
        pageIdx++;

        if (pageIdx % 5 == 0) {
          setState(() {
            if (isAppend) {
              _pages = [..._pages, ...newPages.sublist(newPages.length - 5)];
            } else {
              _pages = List.from(newPages);
            }
          });
        }
      }

      setState(() {
        if (isAppend) {
          final addedCount = _pages.where((p) => p.sourceId == sourceId).length;
          if (addedCount < newPages.length) {
            _pages.addAll(newPages.sublist(addedCount));
          }
        } else {
          _pages = newPages;
        }
      });
    } catch (e) {
      debugPrint("Load PDF Error: $e");
    } finally {
      setState(() => _isLoadingPages = false);
    }
  }

  void _rotatePage(int index) {
    setState(() {
      final page = _pages[index];
      final nextRotation = (page.rotation + 90) % 360;
      _pages[index] = PageItem(
        id: page.id,
        sourceId: page.sourceId,
        sourcePageIndex: page.sourcePageIndex,
        thumbnail: page.thumbnail,
        rotation: nextRotation,
      );
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _handleSave() async {
    if (_pages.isEmpty) return;

    final nameController = TextEditingController(
      text:
          "${l10n.translate('organized_doc_prefix')}_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}",
    );

    final String? customTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          l10n.translate('save_document'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkSurfaceLight
                    : const Color(0xffF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                hintText: l10n.translate('filename_hint'),
                prefixIcon: Icon(
                  LucideIcons.fileEdit,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('cancel_label'),
              style: GoogleFonts.inter(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              l10n.translate('save_label'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (customTitle == null || customTitle.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final sf.PdfDocument outputDoc = sf.PdfDocument();

      // Map to cache opened source documents during the save process
      final Map<String, sf.PdfDocument> openedDocs = {};

      try {
        for (var pageItem in _pages) {
          if (!openedDocs.containsKey(pageItem.sourceId)) {
            final sourceBytes = _sourceBytesMap[pageItem.sourceId];
            if (sourceBytes != null) {
              openedDocs[pageItem.sourceId] = sf.PdfDocument(
                inputBytes: sourceBytes,
              );
            }
          }

          final sourceDoc = openedDocs[pageItem.sourceId];
          if (sourceDoc != null) {
            final sourcePage = sourceDoc.pages[pageItem.sourcePageIndex];

            // In Syncfusion, to have per-page size, use sections
            final sf.PdfSection section = outputDoc.sections!.add();
            section.pageSettings.size = sourcePage.size;
            section.pageSettings.margins.all = 0; // Remove default margins

            final sf.PdfPage newPage = section.pages.add();

            // Apply rotation
            if (pageItem.rotation == 90) {
              newPage.rotation = sf.PdfPageRotateAngle.rotateAngle90;
            } else if (pageItem.rotation == 180)
              newPage.rotation = sf.PdfPageRotateAngle.rotateAngle180;
            else if (pageItem.rotation == 270)
              newPage.rotation = sf.PdfPageRotateAngle.rotateAngle270;
            else
              newPage.rotation = sf.PdfPageRotateAngle.rotateAngle0;

            final sf.PdfTemplate template = sourcePage.createTemplate();
            newPage.graphics.drawPdfTemplate(template, Offset.zero);
          }
        }
      } finally {
        // Dispose all cached source documents
        for (var doc in openedDocs.values) {
          doc.dispose();
        }
      }

      final List<int> pdfBytes = await outputDoc.save();
      outputDoc.dispose();

      final appDir = await getApplicationDocumentsDirectory();
      final finalPath = "${appDir.path}/final_pdfs/$customTitle.pdf";
      final file = File(finalPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(pdfBytes);

      if (Platform.isAndroid) {
        if (await Permission.storage.request().isGranted) {
          final downDir = Directory(
            "/storage/emulated/0/Download/DocumentScanner",
          );
          if (!await downDir.exists()) await downDir.create(recursive: true);
          await File("${downDir.path}/$customTitle.pdf").writeAsBytes(pdfBytes);
        }
      }

      final doc = DocumentModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: customTitle,
        date: DateTime.now(),
        imagePaths: [],
        pdfPath: finalPath,
      );
      await _storageService.saveDocument(doc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.translate('pdf_composition_saved'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xff10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(Uint8List.fromList(pdfBytes)),
              title: customTitle,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save Organized PDF Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showAddOptions({bool isAppend = false}) async {
    bool isActionTaken = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.translate('select_source'),
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            _actionTile(
              icon: LucideIcons.uploadCloud,
              title: l10n.translate('pick_from_device'),
              subtitle: l10n.translate('pick_pdf_storage'),
              color: const Color(0xff3B82F6),
              onTap: () async {
                if (isActionTaken) return;
                isActionTaken = true;
                Navigator.pop(context);
                _pickFromDevice(isAppend: isAppend);
              },
            ),
            const SizedBox(height: 16),
            _actionTile(
              icon: LucideIcons.library,
              title: l10n.translate('pick_from_library'),
              subtitle: l10n.translate('choose_scanned_docs'),
              color: const Color(0xff10B981),
              onTap: () async {
                if (isActionTaken) return;
                isActionTaken = true;
                Navigator.pop(context);
                _pickFromLibrary(isAppend: isAppend);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkSurface
                    : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  if (Theme.of(context).brightness == Brightness.light)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: Icon(
                LucideIcons.files,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.translate('multi_file_organize'),
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('organize_hint'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : Colors.grey[600],
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            _sourceButton(
              l10n.translate('pick_from_device').toUpperCase(),
              LucideIcons.upload,
              const Color(0xff3B82F6),
              () => _pickFromDevice(),
            ),
            const SizedBox(height: 16),
            _sourceButton(
              l10n.translate('pick_from_library').toUpperCase(),
              LucideIcons.library,
              const Color(0xff10B981),
              () => _pickFromLibrary(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromDevice({bool isAppend = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      _loadPdf(File(result.files.single.path!), isAppend: isAppend);
    }
  }

  Future<void> _pickFromLibrary({bool isAppend = false}) async {
    final docs = await _storageService.loadDocuments();
    if (docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('no_scans_found'))),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('select_document'),
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        image: doc.thumbnailPaths != null && doc.thumbnailPaths!.isNotEmpty
                            ? DecorationImage(
                                image: FileImage(File(doc.thumbnailPaths!.first)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (doc.thumbnailPaths == null || doc.thumbnailPaths!.isEmpty)
                          ? Icon(LucideIcons.file, color: Colors.grey[400])
                          : null,
                    ),
                    title: Text(
                      doc.name,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      "${doc.pageCount ?? doc.imagePaths.length} ${l10n.translate('pages_label')}",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      _processLibraryDoc(doc, isAppend: isAppend);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processLibraryDoc(DocumentModel doc, {bool isAppend = false}) async {
    setState(() => _isLoadingPages = true);
    try {
      File? pdfFile;
      if (doc.pdfPath != null && File(doc.pdfPath!).existsSync()) {
        pdfFile = File(doc.pdfPath!);
      } else if (doc.imagePaths.isNotEmpty) {
        // Compile to PDF on the fly
        final bytes = await _pdfService.compileImagesToPdf(doc.imagePaths);
        final tempDir = await getTemporaryDirectory();
        final tempPath = "${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.pdf";
        pdfFile = File(tempPath);
        await pdfFile.writeAsBytes(bytes);
      }

      if (pdfFile != null) {
        await _loadPdf(pdfFile, isAppend: isAppend);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('no_pdf_error'))),
          );
        }
      }
    } catch (e) {
      debugPrint("Process Library Doc Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingPages = false);
    }
  }


  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurface
              : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBorder
                : color.withValues(alpha: 0.1),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkBorder
                  : Colors.grey[300],
              size: 18,
            ),
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
        centerTitle: true,
        title: Text(
          l10n.translate('organize_combine'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            LucideIcons.chevronLeft,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        actions: [
          if (_pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _isProcessing ? null : _handleSave,
                child: Text(
                  l10n.translate('save_label'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: _isProcessing
                        ? Colors.grey
                        : (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.primaryLight
                              : accentAmber),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Stack(
          children: [
            if (_pages.isEmpty && !_isLoadingPages)
              _buildEmptyState()
            else
              Column(
                children: [
                  _buildStatusHeader(),
                  Expanded(
                    child: AbsorbPointer(
                      absorbing: _isLoadingPages || _isProcessing,
                      child: _buildOrganizeGrid(),
                    ),
                  ),
                ],
              ),
            if (_isProcessing || _isLoadingPages)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.1),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkSurface
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          if (_isLoadingPages) ...[
                            const SizedBox(height: 16),
                            Text(
                              l10n.translate('processing'),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton:
          _pages.isNotEmpty && !_isLoadingPages && !_isProcessing
          ? FloatingActionButton.extended(
              onPressed: () => _showAddOptions(isAppend: true),
              backgroundColor: Theme.of(context).colorScheme.primary,
              elevation: 4,
              icon: Icon(
                LucideIcons.plus,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              label: Text(
                l10n.translate('add_pdf'),
                style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.info,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('drag_interleave_hint'),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n
                  .translate('pages_files_count')
                  .replaceAll('{0}', _pages.length.toString())
                  .replaceAll('{1}', _sourceBytesMap.length.toString()),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizeGrid() {
    return ReorderableGridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: _pages.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          final item = _pages.removeAt(oldIndex);
          _pages.insert(newIndex, item);
        });
        HapticFeedback.mediumImpact();
      },
      itemBuilder: (context, index) {
        final page = _pages[index];
        return _buildPageCard(page, index);
      },
    );
  }

  Widget _buildPageCard(PageItem page, int index) {
    return Material(
      key: ValueKey(page.id),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurfaceLight
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBorder
                : Colors.black.withOpacity(0.04),
          ),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RotatedBox(
                quarterTurns: page.rotation ~/ 90,
                child: Image.memory(
                  page.thumbnail,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              // Gradient Overlay for readability
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black38
                        : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(
                      LucideIcons.rotateCcw,
                      size: 14,
                      color: Colors.white,
                    ),
                    onPressed: () => _rotatePage(index),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black38
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${index + 1}",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.gripHorizontal,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: () => setState(() => _pages.removeAt(index)),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      size: 10,
                      color: Colors.redAccent,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _rotatePage(index),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.rotateCw,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (_sourceNames[page.sourceId] != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 36,
                  child: Text(
                    _sourceNames[page.sourceId]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class PageItem {
  final String id;
  final String sourceId;
  final int sourcePageIndex;
  final Uint8List thumbnail;
  final int rotation; // 0, 90, 180, 270

  PageItem({
    required this.id,
    required this.sourceId,
    required this.sourcePageIndex,
    required this.thumbnail,
    this.rotation = 0,
  });
}
