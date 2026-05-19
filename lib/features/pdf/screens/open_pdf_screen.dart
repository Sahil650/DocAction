import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import 'pdf_viewer_screen.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';


class OpenPdfScreen extends StatefulWidget {
  const OpenPdfScreen({super.key});

  @override
  State<OpenPdfScreen> createState() => _OpenPdfScreenState();
}

class _OpenPdfScreenState extends State<OpenPdfScreen> {
  final _storageService = StorageService();
  bool _isLoading = false;
  AppLocalizations get l10n => AppLocalizations.of(context);

  Future<void> _handleOpenExternal() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfViewerScreen(
                pdfData: Future.value(bytes),
                title: result.files.single.name,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("File Picker Error: $e");
    }
  }

  Future<void> _handleOpenInternal() async {
    final docs = await _storageService.loadDocuments();
    if (docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('no_scans_found')),
          ),
        );
      }
      return;
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurface 
            : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.translate('internal_library'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                          image: doc.imagePaths.isNotEmpty
                              ? DecorationImage(
                                  image: FileImage(File(doc.imagePaths.first)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: doc.imagePaths.isEmpty
                            ? const Icon(
                                Icons.description_outlined,
                                color: Colors.white24,
                              )
                            : null,
                      ),
                      title: Text(
                        doc.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        "${doc.imagePaths.length} ${l10n.translate('pages_label')} • ${doc.date.day}/${doc.date.month}",
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _compileAndOpen(doc);
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
  }

  Future<void> _compileAndOpen(DocumentModel doc) async {
    setState(() => _isLoading = true);
    try {
      final pdf = pw.Document();
      for (final path in doc.imagePaths) {
        final bytes = await File(path).readAsBytes();
        final image = pw.MemoryImage(bytes);
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }
      final pdfBytes = await pdf.save();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(pdfBytes),
              title: doc.name,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Compilation Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          l10n.translate('open_pdf'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('choose_doc_source'),
                  style: TextStyle(
                    height: 1.1,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.translate('open_pdf_hint'),
                  style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 48),

                _buildSourceOption(
                  title: l10n.translate('phone_storage'),
                  subtitle: l10n.translate('phone_storage_hint'),
                  icon: Icons.phone_android_rounded,
                  color: Colors.orangeAccent,
                  onTap: _handleOpenExternal,
                ),
                const SizedBox(height: 16),
                _buildSourceOption(
                  title: l10n.translate('internal_scans'),
                  subtitle: l10n.translate('internal_scans_hint'),
                  icon: Icons.folder_shared_rounded,
                  color: Colors.blueAccent,
                  onTap: _handleOpenInternal,
                ),
              ],
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceOption({
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
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
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
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.black45),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.black12,
            ),
          ],
        ),
      ),
    );
  }
}
