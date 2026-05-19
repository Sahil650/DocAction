import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../data/models/document_model.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class PdfUnlockScreen extends StatefulWidget {
  const PdfUnlockScreen({super.key});

  @override
  State<PdfUnlockScreen> createState() => _PdfUnlockScreenState();
}

class _PdfUnlockScreenState extends State<PdfUnlockScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  
  File? _selectedFile;
  Uint8List? _unlockedBytes; 
  bool _isProcessing = false;
  final TextEditingController _passwordController = TextEditingController();
  AppLocalizations get l10n => AppLocalizations.of(context);

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      
      if (!_pdfService.isPdfEncrypted(bytes)) {
        _showError(l10n.translate('not_protected_error'));
        return;
      }

      setState(() {
        _selectedFile = file;
        _unlockedBytes = null;
        _passwordController.clear();
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final DocumentModel? picked = await showModalBottomSheet<DocumentModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentSelectionSheet(title: l10n.translate('select_protected_scan')),
    );

    if (picked != null && picked.pdfPath != null) {
      final file = File(picked.pdfPath!);
      final bytes = await file.readAsBytes();
      
      if (!_pdfService.isPdfEncrypted(bytes)) {
        _showError(l10n.translate('not_protected_error'));
        return;
      }

      setState(() {
        _selectedFile = file;
        _unlockedBytes = null;
        _passwordController.clear();
      });
    }
  }

  Future<void> _unlockPdf() async {
    if (_selectedFile == null || _passwordController.text.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final bytes = await _selectedFile!.readAsBytes();
      final decrypted = await _pdfService.decryptPdf(bytes, _passwordController.text);
      
      if (decrypted != null) {
        setState(() {
          _unlockedBytes = decrypted;
        });
        _showSuccess(l10n.translate('pdf_unlocked_success'));
      } else {
        _showError(l10n.translate('incorrect_password_try_again'));
      }
    } catch (e) {
      _showError(l10n.translate('unlock_failed').replaceAll('{0}', e.toString()));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveUnlockedPdf() async {
    if (_unlockedBytes == null) return;

    final String baseName = p.basenameWithoutExtension(_selectedFile!.path);
    final String defaultName = "${baseName}_${l10n.translate('unlocked_label')}";
    
    final String? finalName = await _showRenameDialog(defaultName);
    if (finalName == null || finalName.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final String fileName = finalName.endsWith('.pdf') ? finalName : "$finalName.pdf";
      final filePath = p.join(appDocDir.path, fileName);
      
      await File(filePath).writeAsBytes(_unlockedBytes!);

      await _storageService.saveDocumentNamed(
        name: p.basenameWithoutExtension(fileName),
        imagePaths: [],
        pdfPath: filePath,
        pageCount: _pdfService.getPdfPageCount(_unlockedBytes!), 
      );

      if (mounted) {
        _showSuccess("${l10n.translate('saved_as')} $fileName");
        Navigator.pop(context);
      }
    } catch (e) {
      _showError("${l10n.translate('save_failed')}: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<String?> _showRenameDialog(String initialName) async {
    final TextEditingController nameController = TextEditingController(text: initialName);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(l10n.translate('save_unlocked_pdf'), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.translate('save_unprotected_hint')),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.translate('enter_name'),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.translate('cancel_label').toUpperCase())),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l10n.translate('save_now')),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.primary));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(l10n.translate('unlock_pdf'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          child: Column(
            children: [
              _buildUnlockHeader(),
              const SizedBox(height: 24),
              if (_selectedFile == null) _buildSelectionOptions() else _buildFileStatusArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(LucideIcons.unlock, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 16),
          Text(l10n.translate('remove_protection'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            l10n.translate('unlock_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionOptions() {
    return Row(
      children: [
        Expanded(
          child: _buildSelectionCard(
            icon: LucideIcons.fileSearch,
            title: l10n.translate('from_device'),
            subtitle: l10n.translate('browse_files'),
            onTap: _pickFile,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSelectionCard(
            icon: LucideIcons.layers,
            title: l10n.translate('my_scans'),
            subtitle: l10n.translate('app_gallery'),
            onTap: _pickFromGallery,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500], fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileStatusArea() {
    return Column(
      children: [
        _buildFileInfoBox(),
        const SizedBox(height: 24),
        if (_unlockedBytes == null) _buildUnlockForm() else _buildSaveAction(),
      ],
    );
  }

  Widget _buildFileInfoBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: Icon(_unlockedBytes == null ? LucideIcons.lock : LucideIcons.unlock, color: Colors.orangeAccent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.basename(_selectedFile!.path), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(_unlockedBytes == null ? l10n.translate('encrypted_doc') : l10n.translate('unlocked_ready'), style: TextStyle(color: _unlockedBytes == null ? Colors.orange : Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _selectedFile = null), 
            icon: const Icon(LucideIcons.xCircle, color: Colors.redAccent, size: 20)
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: l10n.translate('enter_password_to_unlock'),
              prefixIcon: Icon(LucideIcons.key, size: 20, color: Theme.of(context).colorScheme.primary),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _unlockPdf,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isProcessing ? const CircularProgressIndicator(color: Colors.white) : Text(l10n.translate('verify_password'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveAction() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _saveUnlockedPdf,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 5,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.download),
            const SizedBox(width: 12),
            Text(
              l10n.translate('save_unprotected_copy'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
