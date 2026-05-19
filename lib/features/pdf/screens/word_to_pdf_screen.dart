import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/models/document_model.dart';
import 'pdf_viewer_screen.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';

class WordToPdfScreen extends StatefulWidget {
  const WordToPdfScreen({super.key});

  @override
  State<WordToPdfScreen> createState() => _WordToPdfScreenState();
}

class _WordToPdfScreenState extends State<WordToPdfScreen> {
  final _pdfService = PdfService();
  final _storageService = StorageService();
  File? _selectedFile;
  bool _isProcessing = false;
  AppLocalizations get l10n => AppLocalizations.of(context);

  Future<void> _pickFile() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
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
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            _actionTile(
              icon: LucideIcons.uploadCloud,
              title: l10n.translate('pick_from_device'),
              subtitle: l10n.translate('pick_word_storage'),
              color: Colors.blue,
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['docx'],
                );
                if (result != null && result.files.single.path != null) {
                  setState(() {
                    _selectedFile = File(result.files.single.path!);
                  });
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _convertToPdf() async {
    if (_selectedFile == null) return;

    // Prompt for Document Name
    final nameController = TextEditingController(
      text: l10n
          .translate('word_doc_default_name')
          .replaceAll('{0}', DateTime.now().day.toString())
          .replaceAll('{1}', DateTime.now().month.toString())
          .replaceAll('{2}', DateTime.now().minute.toString()),
    );

    final String? customName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          l10n.translate('save_pdf_doc_title'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('assign_converted_name_hint'),
              style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                labelText: l10n.translate('name_label'),
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixText: ".pdf",
                suffixStyle: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.black54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('cancel_label'),
              style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              l10n.translate('convert_save_btn'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (customName == null) return;

    setState(() => _isProcessing = true);
    try {
      final pdfBytes = await _pdfService.convertWordToPdf(_selectedFile!);

      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          "${customName.replaceAll(" ", "_")}_${DateTime.now().millisecondsSinceEpoch}.pdf";
      final file = File("${appDir.path}/$fileName");
      await file.writeAsBytes(pdfBytes);

      // Register with StorageService
      final doc = DocumentModel(
        id: Uuid().v4(),
        name: customName,
        date: DateTime.now(),
        imagePaths: [],
        pdfPath: file.path,
        extractedText: l10n
            .translate('converted_from_word_log')
            .replaceAll(
              '{0}',
              _selectedFile!.path.split(Platform.pathSeparator).last,
            ),
      );

      await _storageService.saveDocument(doc);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(pdfBytes),
              title: customName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n
                  .translate('conversion_error_snack')
                  .replaceAll('{0}', e.toString()),
            ),
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
      backgroundColor: const Color(0xffF3F4F6),
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          l10n.translate('word_to_pdf'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // File Selection Area
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 60,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? AppColors.darkSurface 
                        : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _selectedFile != null
                          ? Theme.of(context).colorScheme.primary
                          : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.black12),
                      width: 2,
                      style: _selectedFile != null
                          ? BorderStyle.solid
                          : BorderStyle.none,
                    ),
                    boxShadow: [
                      if (Theme.of(context).brightness == Brightness.light)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Color(0xffE8F5E9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _selectedFile != null
                              ? LucideIcons.fileCheck
                              : LucideIcons.filePlus,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _selectedFile != null
                            ? _selectedFile!.path
                                  .split(Platform.pathSeparator)
                                  .last
                            : l10n.translate('select_word_doc'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _selectedFile != null
                              ? Theme.of(context).colorScheme.primary
                              : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedFile != null
                            ? l10n.translate('tap_to_change_file')
                            : l10n.translate('supported_format_docx'),
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Convert Button
              ElevatedButton.icon(
                onPressed: (_isProcessing || _selectedFile == null)
                    ? null
                    : _convertToPdf,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.fileText),
                label: Text(
                  _isProcessing
                      ? l10n.translate('converting_label')
                      : l10n.translate('convert_to_pdf_btn'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  disabledBackgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey.shade300,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 4,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
