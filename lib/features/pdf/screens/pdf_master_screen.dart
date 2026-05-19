import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/word_service.dart';
import 'package:path_provider/path_provider.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../core/theme/app_colors.dart';

class PdfMasterScreen extends StatefulWidget {
  const PdfMasterScreen({super.key});

  @override
  State<PdfMasterScreen> createState() => _PdfMasterScreenState();
}

class _PdfMasterScreenState extends State<PdfMasterScreen> {
  final _storageService = StorageService();
  final _pdfService = PdfService();
  final _wordService = WordService();
  bool _isLoading = false;
  AppLocalizations get l10n => AppLocalizations.of(context);

  String? _extractedText;
  String? _sourceFileName;
  int? _pageCount;
  Uint8List? _wordBytes;

  // Removed hardcoded primaryGreen and accentAmber

  Future<void> _showSourceSelector() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
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
                style: GoogleFonts.inter(
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
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.darkSurfaceLight 
              : color.withValues(alpha: 0.05),
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
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    sub,
                    style: GoogleFonts.inter(
                      color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
                      fontSize: 12,
                    ),
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
      _handlePdfToText(
        forcedPath: result.files.single.path!,
        forcedName: result.files.single.name,
      );
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
      _handlePdfToText(
        forcedPath: finalPath,
        forcedName: result.name,
      );
    }
  }

  Future<void> _handlePdfToText({
    required String forcedPath,
    required String forcedName,
  }) async {
    try {
      setState(() {
        _isLoading = true;
        _extractedText = null;
        _sourceFileName = forcedName;
        _wordBytes = null;
      });

      final bytes = await File(forcedPath).readAsBytes();
      final text = await _pdfService.extractTextWithOcrFallback(bytes);
      final count = _pdfService.getPdfPageCount(bytes);
      
      Uint8List? wordBytes;
      if (text.isNotEmpty) {
        wordBytes = await _wordService.createDocxFromText(text);
      }

      setState(() {
        _extractedText = text.isEmpty
            ? l10n.translate('no_text_extracted')
            : text;
        _pageCount = count;
        _wordBytes = wordBytes;
        _isLoading = false;
      });
      HapticFeedback.lightImpact();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${l10n.translate('extraction_error')}: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _saveExtraction() async {
    if (_extractedText == null) return;

    final nameController = TextEditingController(
      text:
          "${l10n.translate('extracted_doc_prefix')}_${_sourceFileName?.replaceAll('.pdf', '') ?? DateTime.now().millisecondsSinceEpoch}",
    );

    final String? customName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.translate('save_extraction'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: l10n.translate('doc_name_label'),
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
            hintText: l10n.translate('filename_hint'),
            hintStyle: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.transparent,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('cancel').toUpperCase(),
              style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              l10n.translate('save').toUpperCase(),
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (customName == null || customName.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final fileName = "${customName.replaceAll(' ', '_')}.docx";
      final doc = DocumentModel(
        id: const Uuid().v4(),
        name: customName,
        date: DateTime.now(),
        imagePaths: [],
        extractedText: _extractedText,
        pageCount: _pageCount,
        pdfPath: fileName,
      );
      final appDir = await getApplicationDocumentsDirectory();
      final finalFile = File("${appDir.path}/$fileName");
      if (_wordBytes != null) {
        await finalFile.writeAsBytes(_wordBytes!);
      }

      await _storageService.saveDocument(doc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('save_success')),
            backgroundColor: const Color(0xff10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _extractedText = null;
          _sourceFileName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${l10n.translate('error_saving')}: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          l10n.translate('pdf_to_text'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Stack(
          children: [
            _extractedText == null ? _buildInitialState() : _buildResultState(),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.1),
                  child: Center(
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('pdf_text_extractor'),
            style: GoogleFonts.inter(
              height: 1.1,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('pdf_to_text_desc'),
            style: GoogleFonts.inter(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 48),
          _buildActionCard(
            title: l10n.translate('select_pdf'),
            subtitle: l10n.translate('pick_pdf_hint'),
            icon: LucideIcons.fileSearch,
            color: Colors.blueAccent,
            onTap: _showSourceSelector,
          ),
        ],
      ),
    );
  }

  Widget _buildResultState() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.fileText,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _sourceFileName ?? l10n.translate('document_label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, 
                      color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _extractedText = null),
                icon: const Icon(LucideIcons.x, color: Colors.grey, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: SelectableText(
                _extractedText!,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  height: 1.8,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Theme.of(context).colorScheme.primary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
        Container(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _extractedText!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.translate('copied_to_clipboard')),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    HapticFeedback.mediumImpact();
                  },
                  icon: const Icon(LucideIcons.copy, size: 18),
                  label: Text(
                    l10n.translate('copy_label'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 64),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveExtraction,
                  icon: const Icon(LucideIcons.save, size: 18),
                  label: Text(
                    l10n.translate('save_label').toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(0, 64),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
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
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 13, 
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500], 
                        fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Colors.grey[300], size: 20),
          ],
        ),
      ),
    );
  }
}
