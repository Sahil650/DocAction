import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/pdf_service.dart';
import '../../../shared/utils/app_localizations.dart';
import 'pdf_viewer_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';

enum SplitMode { custom, extractAll, fixed }

class PdfSplitScreen extends StatefulWidget {
  final File? initialFile;
  const PdfSplitScreen({super.key, this.initialFile});

  @override
  State<PdfSplitScreen> createState() => _PdfSplitScreenState();
}

class _PdfSplitScreenState extends State<PdfSplitScreen> {
  final _pdfService = PdfService();
  final _storageService = StorageService();

  File? _sourceFile;
  int _pageCount = 0;
  bool _isProcessing = false;
  SplitMode _mode = SplitMode.custom;

  final List<RangeItem> _ranges = [RangeItem(start: 1, end: 1)];

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _loadFileInfo(widget.initialFile!);
    }
  }

  @override
  void dispose() {
    for (var range in _ranges) {
      range.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFileInfo(File file) async {
    try {
      final bytes = await file.readAsBytes();
      
      if (_pdfService.isPdfEncrypted(bytes)) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.translate('pdf_locked_error'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
        return;
      }

      final sf.PdfDocument doc = sf.PdfDocument(inputBytes: bytes);
      final count = doc.pages.count;
      doc.dispose();

      setState(() {
        _sourceFile = file;
        _pageCount = count;
        _ranges[0].update(1, count);
      });
    } catch (e) {
      debugPrint("Error loading file info: $e");
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        _loadFileInfo(File(result.files.single.path!));
      }
    } catch (e) {
      debugPrint("File Picker Error: $e");
    }
  }

  Future<void> _pickDocument() async {
    final l10n = AppLocalizations.of(context);
    final docs = await _storageService.loadDocuments();
    final pdfDocs = docs.where((d) => d.pdfPath != null).toList();

    if (!mounted) return;

    if (pdfDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.translate('no_pdfs_found'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? AppColors.darkSurface 
          : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.translate('select_library'),
                style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: pdfDocs.length,
                  itemBuilder: (context, index) {
                    final doc = pdfDocs[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? AppColors.darkSurfaceLight 
                            : AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.fileText,
                              color: Colors.redAccent, size: 20),
                        ),
                        title: Text(
                          doc.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          "${l10n.translate('pages_count').replaceAll('{0}', doc.imagePaths.length.toString())} • ${doc.date.day}/${doc.date.month}/${doc.date.year}",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500],
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _loadFileInfo(File(doc.pdfPath!));
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addRange() {
    setState(() {
      _ranges.add(RangeItem(start: 1, end: _pageCount));
    });
    HapticFeedback.lightImpact();
  }

  void _removeRange(int index) {
    if (_ranges.length > 1) {
      _ranges[index].dispose();
      setState(() => _ranges.removeAt(index));
    }
  }

  Future<void> _handleSplit() async {
    if (_sourceFile == null) return;
    final l10n = AppLocalizations.of(context);

    setState(() => _isProcessing = true);
    try {
      final bytes = await _sourceFile!.readAsBytes();

      final String baseName = _sourceFile!.path
          .split(Platform.isWindows ? '\\' : '/')
          .last
          .replaceAll('.pdf', '');

      List<PdfRangeSelection> selections = [];

      if (_mode == SplitMode.custom) {
        for (final r in _ranges) {
          selections.add(
            PdfRangeSelection(
              start: r.start,
              end: r.end,
              label:
                  "${baseName}_${l10n.translate('page_prefix')}_${r.start}-${r.end}",
            ),
          );
        }
      } else if (_mode == SplitMode.extractAll) {
        for (int i = 1; i <= _pageCount; i++) {
          selections.add(
            PdfRangeSelection(
              start: i,
              end: i,
              label: "${l10n.translate('page_prefix')}_$i",
            ),
          );
        }
      }

      final splitParts = await _pdfService.splitPdfByRanges(bytes, selections);

      if (splitParts.length == 1) {
        await _saveSingleResult(
          splitParts.first['bytes'],
          splitParts.first['name'],
          l10n,
        );
      } else {
        await _saveMultipleResults(splitParts, baseName, l10n);
      }
    } catch (e) {
      debugPrint("Split Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${l10n.translate('error_saving')}: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveSingleResult(
    Uint8List bytes,
    String name,
    AppLocalizations l10n,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final internalPath = "${appDir.path}/final_pdfs/$name.pdf";
    final internalFile = File(internalPath);
    if (!await internalFile.parent.exists()) {
      await internalFile.parent.create(recursive: true);
    }
    await internalFile.writeAsBytes(bytes);

    final doc = DocumentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      date: DateTime.now(),
      imagePaths: [],
      pdfPath: internalPath,
    );
    await _storageService.saveDocument(doc);

    if (Platform.isAndroid) {
      if (await Permission.storage.request().isGranted) {
        final downDir = Directory(
          "/storage/emulated/0/Download/DocumentScanner",
        );
        if (!await downDir.exists()) await downDir.create(recursive: true);
        await File("${downDir.path}/$name.pdf").writeAsBytes(bytes);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.translate('split_successful'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xff10B981),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PdfViewerScreen(pdfData: Future.value(bytes), title: name),
        ),
      );
    }
  }

  Future<void> _saveMultipleResults(
    List<Map<String, dynamic>> parts,
    String baseName,
    AppLocalizations l10n,
  ) async {
    final zipBytes = await _pdfService.createZipArchive(parts);

    if (Platform.isAndroid) {
      if (await Permission.storage.request().isGranted) {
        final downDir = Directory(
          "/storage/emulated/0/Download/DocumentScanner",
        );
        if (!await downDir.exists()) await downDir.create(recursive: true);
        await File(
          "${downDir.path}/${baseName}_Split.zip",
        ).writeAsBytes(zipBytes);
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final internalZipPath = "${appDir.path}/final_pdfs/${baseName}_Split.zip";
    final internalFile = File(internalZipPath);
    if (!await internalFile.parent.exists()) {
      await internalFile.parent.create(recursive: true);
    }
    await internalFile.writeAsBytes(zipBytes);

    final doc = DocumentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: "${l10n.translate('split_batch_prefix')}: $baseName",
      date: DateTime.now(),
      imagePaths: [],
      pdfPath: internalZipPath,
    );
    await _storageService.saveDocument(doc);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.translate('extracted_multiple'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xff10B981),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.translate('split_pdf'),
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
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 600,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_sourceFile == null)
                    _buildEmptyState()
                  else
                    _buildFileDetails(),
                  const SizedBox(height: 32),
                  if (_sourceFile != null) ...[
                    _buildModeSelector(l10n),
                    const SizedBox(height: 24),
                    if (_mode == SplitMode.custom) _buildCustomRanges(l10n),
                    if (_mode == SplitMode.extractAll)
                      _buildExtractAllInfo(l10n),
                    const SizedBox(height: 40),
                    _buildFinalActionButton(l10n),
                  ],
                ],
              ),
            ),
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? AppColors.darkSurfaceLight
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child:
                          CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        const SizedBox(height: 12),
        _selectionCard(
          title: l10n.translate('select_device'),
          subtitle: l10n.translate('select_device_sub'),
          icon: LucideIcons.uploadCloud,
          color: AppColors.primary,
          onTap: _pickFile,
        ),
        const SizedBox(height: 16),
        _selectionCard(
          title: l10n.translate('select_app'),
          subtitle: l10n.translate('select_app_sub'),
          icon: LucideIcons.layoutGrid,
          color: Theme.of(context).colorScheme.primary,
          onTap: _pickDocument,
        ),
      ],
    );
  }

  Widget _selectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.darkSurface 
              : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey[300], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFileDetails() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurface 
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.1)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
            )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.fileText,
                size: 28, color: Colors.redAccent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sourceFile!.path.split(Platform.isWindows ? '\\' : '/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n
                      .translate('pages_count')
                      .replaceAll('{0}', _pageCount.toString()),
                  style: GoogleFonts.inter(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _sourceFile = null),
            child: Text(
              l10n.translate('change_label'),
              style: GoogleFonts.inter(
                color: Colors.blueAccent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurfaceLight 
            : const Color(0xffF1F5F9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _modeButton(l10n.translate('by_range'), SplitMode.custom),
          _modeButton(l10n.translate('extract_all'), SplitMode.extractAll),
        ],
      ),
    );
  }

  Widget _modeButton(String label, SplitMode mode) {
    final isSelected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected 
                ? (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white) 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected && Theme.of(context).brightness == Brightness.light
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: isSelected ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500]),
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomRanges(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            l10n.translate('page_ranges'),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...List.generate(
          _ranges.length,
          (index) => _buildRangeRow(index, l10n),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _addRange,
            icon: const Icon(LucideIcons.plusCircle, size: 18),
            label: Text(
              l10n.translate('add_new_range'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRangeRow(int index, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? AppColors.darkSurface 
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  if (Theme.of(context).brightness == Brightness.light)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                    )
                ],
              ),
              child: Row(
                children: [
                  Text(
                    l10n.translate('from_label'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      controller: _ranges[index].startController,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onChanged: (v) =>
                          _ranges[index].start = int.tryParse(v) ?? 1,
                    ),
                  ),
                  Container(
                    height: 24,
                    width: 1,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : const Color(0xffF1F5F9),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  Text(
                    l10n.translate('to_label'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      controller: _ranges[index].endController,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onChanged: (v) =>
                          _ranges[index].end = int.tryParse(v) ?? _pageCount,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_ranges.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                onPressed: () => _removeRange(index),
                icon: const Icon(LucideIcons.trash2,
                    color: Colors.redAccent, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExtractAllInfo(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurface 
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Row(
        children: [
          Icon(LucideIcons.zap, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              l10n.translate('zip_hint'),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalActionButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _handleSplit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          _mode == SplitMode.extractAll
              ? l10n.translate('extract_all_zip')
              : l10n.translate('split_pdf').toUpperCase(),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class RangeItem {
  int start;
  int end;
  late TextEditingController startController;
  late TextEditingController endController;

  RangeItem({required this.start, required this.end}) {
    startController = TextEditingController(text: start.toString());
    endController = TextEditingController(text: end.toString());
  }

  void update(int s, int e) {
    start = s;
    end = e;
    startController.text = s.toString();
    endController.text = e.toString();
  }

  void dispose() {
    startController.dispose();
    endController.dispose();
  }
}
