import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/models/document_model.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../core/theme/app_colors.dart';

class PdfToImageScreen extends StatefulWidget {
  const PdfToImageScreen({super.key});

  @override
  State<PdfToImageScreen> createState() => _PdfToImageScreenState();
}

class _PdfToImageScreenState extends State<PdfToImageScreen> {
  final _pdfService = PdfService();
  final _storageService = StorageService();
  File? _selectedFile;
  bool _isProcessing = false;
  double _progress = 0.0;
  String _currentStatus = "";
  double _selectedDpi = 150.0;
  AppLocalizations get l10n => AppLocalizations.of(context);

  Future<void> _showSourceSelector() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.darkSurface 
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l10n.translate('select_source'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            _selectionItem(
              icon: LucideIcons.fileSearch,
              title: l10n.translate('from_device'),
              sub: l10n.translate('from_device_sub'),
              color: Colors.blue,
              onTap: () => Navigator.pop(context, 'device'),
            ),
            const SizedBox(height: 16),
            _selectionItem(
              icon: LucideIcons.library,
              title: l10n.translate('from_library'),
              sub: l10n.translate('from_library_sub'),
              color: Theme.of(context).colorScheme.primary,
              onTap: () => Navigator.pop(context, 'library'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selection == 'device') {
      _pickFile();
    } else if (selection == 'library') {
      _pickFromLibrary();
    }
  }

  Widget _selectionItem({
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? (Theme.of(context).brightness == Brightness.dark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.05)) 
              : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : color.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
      });
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _pickFromLibrary() async {
    final dynamic result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentSelectionSheet(
        title: l10n.translate('select_pdf_doc'),
        onlyPdfs: true,
      ),
    );

    if (result is DocumentModel && result.pdfPath != null) {
      String finalPath = result.pdfPath!;
      if (!finalPath.startsWith('/') && !finalPath.contains(':')) {
        final appDir = await getApplicationDocumentsDirectory();
        finalPath = "${appDir.path}/$finalPath";
      }
      setState(() {
        _selectedFile = File(finalPath);
      });
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _convertPdfToImages() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _currentStatus = l10n.translate('init_conversion');
    });

    try {
      final pdfBytes = await _selectedFile!.readAsBytes();
      final appDir = await getApplicationDocumentsDirectory();
      final String docDirName =
          "PDF_Images_${DateTime.now().millisecondsSinceEpoch}";
      final Directory exportDir = Directory(
        "${appDir.path}/Extracted_Images/$docDirName",
      );

      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      int pageCount = 0;
      List<String> imagePaths = [];

      final stream = _pdfService.rasterizePdfToImages(
        pdfBytes,
        dpi: _selectedDpi,
      );

      await for (final pngBytes in stream) {
        pageCount++;
        final String fileName = "page_$pageCount.png";
        final File imgFile = File("${exportDir.path}/$fileName");
        await imgFile.writeAsBytes(pngBytes);
        imagePaths.add(imgFile.path);

        setState(() {
          _currentStatus = l10n.translate('extracted_page').replaceAll('{0}', pageCount.toString());
        });
      }

      final doc = DocumentModel(
        id: const Uuid().v4(),
        name:
            l10n.translate('images_from_label').replaceAll('{0}', _selectedFile!.path.split(Platform.pathSeparator).last),
        date: DateTime.now(),
        imagePaths: imagePaths,
        extractedText: l10n.translate('extracted_images_count_log').replaceAll('{0}', pageCount.toString()),
      );

      await _storageService.saveDocument(doc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.translate('extract_success_snack').replaceAll('{0}', pageCount.toString()),
            ),
            backgroundColor: const Color(0xff10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('extract_error_snack').replaceAll('{0}', e.toString())),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.translate('pdf_to_image'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // File Selection
                    GestureDetector(
                      onTap: _isProcessing ? null : _showSourceSelector,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 48,
                          horizontal: 24,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? AppColors.darkSurface 
                              : Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            if (Theme.of(context).brightness == Brightness.light)
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF3F4F6),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                _selectedFile != null
                                    ? LucideIcons.fileCheck
                                    : LucideIcons.filePlus,
                                size: 40,
                                color: _selectedFile != null
                                    ? const Color(0xff10B981)
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _selectedFile != null
                                  ? _selectedFile!.path
                                        .split(Platform.pathSeparator)
                                        .last
                                  : l10n.translate('select_pdf_doc'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.translate('extract_photos_hint'),
                              style: TextStyle(
                                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500],
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_selectedFile != null && !_isProcessing) ...[
                      const SizedBox(height: 32),
                      _buildQualitySelector(),
                    ],

                    if (_isProcessing) ...[
                      const SizedBox(height: 64),
                      CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _currentStatus,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: ElevatedButton.icon(
                onPressed: (_isProcessing || _selectedFile == null)
                    ? null
                    : _convertPdfToImages,
                icon: const Icon(LucideIcons.image),
                label: Text(
                  l10n.translate('extract_as_images'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('extraction_quality'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _qualityCard(l10n.translate('standard_label'), 72.0, l10n.translate('fast_conversion')),
            const SizedBox(width: 12),
            _qualityCard(l10n.translate('hd_label'), 150.0, l10n.translate('great_balance')),
            const SizedBox(width: 12),
            _qualityCard(l10n.translate('ultra_label'), 300.0, l10n.translate('print_ready')),
          ],
        ),
      ],
    );
  }

  Widget _qualityCard(String label, double dpi, String sub) {
    bool isSelected = _selectedDpi == dpi;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedDpi = dpi),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.transparent : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.black12),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Theme.of(context).colorScheme.onPrimary : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 8,
                  color: isSelected ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7) : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
