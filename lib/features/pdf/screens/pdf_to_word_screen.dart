import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/word_service.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../core/theme/app_colors.dart';

class PdfToWordScreen extends StatefulWidget {
  const PdfToWordScreen({super.key});

  @override
  State<PdfToWordScreen> createState() => _PdfToWordScreenState();
}

class _PdfToWordScreenState extends State<PdfToWordScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  AppLocalizations get l10n => AppLocalizations.of(context);

  bool _isLoading = false;
  Uint8List? _wordBytes;
  String? _extractedText;
  int _pageCount = 0;
  String? _sourceFileName;

  // Removed hardcoded primaryGreen

  Future<void> _showSourceSelector() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkBorder
                      : Colors.black12,
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : Colors.grey[600],
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
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      _handleFileToWord(
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
        title: l10n.translate('select_doc_library'),
        onlyPdfs: false,
      ),
    );

    if (result is DocumentModel) {
      String? finalPath = result.pdfPath;
      if (finalPath != null &&
          !finalPath.startsWith('/') &&
          !finalPath.contains(':')) {
        final appDir = await getApplicationDocumentsDirectory();
        finalPath = "${appDir.path}/$finalPath";
      }

      // Fallback to first image if no PDF/Word path exists
      if (finalPath == null && result.imagePaths.isNotEmpty) {
        finalPath = result.imagePaths.first;
      }

      if (finalPath != null) {
        _handleFileToWord(forcedPath: finalPath, forcedName: result.name);
      }
    }
  }

  Future<void> _handleFileToWord({
    required String forcedPath,
    required String forcedName,
  }) async {
    try {
      setState(() {
        _isLoading = true;
        _sourceFileName = forcedName;
        _wordBytes = null;
      });

      final extension = forcedPath.toLowerCase().split('.').last;
      Uint8List? docxBytes;
      int count = 1;

      String? extractedText;
      if (extension == 'pdf') {
        final pdfBytes = await File(forcedPath).readAsBytes();
        extractedText = await _pdfService.extractTextWithOcrFallback(pdfBytes);
        count = _pdfService.getPdfPageCount(pdfBytes);
      } else if (extension == 'jpg' ||
          extension == 'jpeg' ||
          extension == 'png') {
        throw Exception(l10n.translate('image_to_word_unsupported') ?? "Image to Word requires OCR, which is removed.");
      } else if (extension == 'txt') {
        extractedText = await File(forcedPath).readAsString();
      } else if (extension == 'docx') {
        docxBytes = await File(forcedPath).readAsBytes();
        extractedText = l10n.translate('word_doc_no_preview');
      }

      if (docxBytes == null && extractedText != null) {
        docxBytes = await WordService().createDocxFromText(extractedText);
      }

      setState(() {
        _wordBytes = docxBytes;
        _extractedText = extractedText;
        _pageCount = count;
        _isLoading = false;
      });

      _showSuccessSnackbar(l10n.translate('conversion_success'));
      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar(
        l10n
            .translate('conversion_error_snack')
            .replaceAll('{0}', e.toString()),
      );
    }
  }

  Future<void> _saveAndShare() async {
    if (_wordBytes == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          "${_sourceFileName?.replaceAll(RegExp(r'\.(pdf|jpg|jpeg|png|txt|docx)$', caseSensitive: false), '') ?? l10n.translate('converted_label')}.docx";
      final file = File("${tempDir.path}/$fileName");
      await file.writeAsBytes(_wordBytes!);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: l10n.translate('converted_word_doc'));
    } catch (e) {
      _showErrorSnackbar(
        l10n.translate('share_error_snack').replaceAll('{0}', e.toString()),
      );
    }
  }

  Future<void> _saveToApp(String customName) async {
    if (_wordBytes == null) return;
    setState(() => _isLoading = true);
    try {
      final String cleanName = customName.trim().isEmpty
          ? (_sourceFileName?.replaceAll(
                  RegExp(
                    r'\.(pdf|jpg|jpeg|png|txt|docx)$',
                    caseSensitive: false,
                  ),
                  '',
                ) ??
                l10n.translate('converted_label'))
          : customName;

      final fileName =
          "${cleanName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.docx";
      final appDir = await getApplicationDocumentsDirectory();
      final finalFile = File("${appDir.path}/$fileName");
      await finalFile.writeAsBytes(_wordBytes!);

      final doc = DocumentModel(
        id: const Uuid().v4(),
        name: cleanName,
        date: DateTime.now(),
        imagePaths: [],
        pdfPath: fileName,
        pageCount: _pageCount,
      );

      await _storageService.saveDocument(doc);

      setState(() => _isLoading = false);
      _showSuccessSnackbar(l10n.translate('saved_to_app_snack'));
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar(
        l10n.translate('error_saving_snack').replaceAll('{0}', e.toString()),
      );
    }
  }

  Future<void> _showRenameDialog() async {
    final String initialName =
        _sourceFileName?.replaceAll(
          RegExp(r'\.(pdf|jpg|jpeg|png|txt|docx)$', caseSensitive: false),
          '',
        ) ??
        l10n.translate('converted_label');
    final TextEditingController controller = TextEditingController(
      text: initialName,
    );

    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.translate('save_to_library'),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('doc_name_label'),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: l10n.translate('filename_hint'),
                hintStyle: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white24
                      : Colors.black26,
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkSurfaceLight
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('cancel'),
              style: GoogleFonts.inter(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              l10n.translate('save_label'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _saveToApp(newName);
    }
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xff10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            LucideIcons.chevronLeft,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          l10n.translate('pdf_to_word'), // Use standard label
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
            _wordBytes == null ? _buildInitialState() : _buildResultState(),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.1),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
            l10n.translate('pdf_to_word'),
            style: GoogleFonts.inter(
              height: 1.1,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('any_to_word_desc'),
            style: GoogleFonts.inter(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : Colors.grey[600],
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 48),
          _buildActionCard(
            title: l10n.translate('select_file'),
            subtitle: l10n.translate('pick_file_hint'),
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurfaceLight
                          : const Color(0xffE0F2FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.fileCheck,
                      color: Colors.blue,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.translate('conversion_complete'),
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${l10n.translate('source_file')}: $_sourceFileName",
                  style: GoogleFonts.inter(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkTextSecondary
                        : Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                if (_extractedText != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.translate('text_preview'),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _extractedText!),
                          );
                          _showSuccessSnackbar(
                            l10n.translate('copied_to_clipboard'),
                          );
                        },
                        icon: const Icon(LucideIcons.copy, size: 16),
                        label: Text(l10n.translate('copy_label')),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurface
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : Colors.grey[200]!,
                      ),
                    ),
                    child: Text(
                      _extractedText ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.grey[800],
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: _saveAndShare,
                icon: const Icon(LucideIcons.share2),
                label: Text(
                  l10n.translate('share_word_doc'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _showRenameDialog,
                icon: const Icon(LucideIcons.download),
                label: Text(
                  l10n.translate('save_to_library'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _wordBytes = null),
                child: Text(
                  l10n.translate('convert_another'),
                  style: GoogleFonts.inter(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
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
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurface
              : Colors.white,
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : Colors.grey[500],
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
