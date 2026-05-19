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
import 'package:image_picker/image_picker.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../data/models/document_model.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';


class PdfPasswordScreen extends StatefulWidget {
  final DocumentModel? initialDocument;
  const PdfPasswordScreen({super.key, this.initialDocument});

  @override
  State<PdfPasswordScreen> createState() => _PdfPasswordScreenState();
}

class _PdfPasswordScreenState extends State<PdfPasswordScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();
  AppLocalizations get l10n => AppLocalizations.of(context);

  File? _selectedFile;
  Uint8List? _workingBytes; // Raw unencrypted bytes to work with
  String? _generatedName;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updateStrength);

    if (widget.initialDocument != null) {
      _loadInitialDocument();
    }
  }

  Future<void> _loadInitialDocument() async {
    if (widget.initialDocument?.pdfPath != null) {
      final file = File(widget.initialDocument!.pdfPath!);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();

        if (_pdfService.isPdfEncrypted(bytes)) {
          _handleProtectedFile(file, bytes);
        } else {
          setState(() {
            _selectedFile = file;
            _workingBytes = bytes;
          });
        }
      }
    }
  }

  Future<void> _pickFromPhotos() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() => _isProcessing = true);
      try {
        final List<String> paths = images.map((e) => e.path).toList();
        final pdfBytes = await _pdfService.compileImagesToPdf(paths);

        setState(() {
          _workingBytes = pdfBytes;
          _generatedName =
              "Gallery_Scan_${DateTime.now().millisecondsSinceEpoch}";
          // Create a dummy file object for basename resolution
          _selectedFile = File("$_generatedName.pdf");
        });
      } catch (e) {
        _showError("${l10n.translate('error_prefix')}: $e");
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isProcessing = false;
  bool _showPassword = false;
  double _strength = 0;
  String _strengthLabel = "None";
  Color _strengthColor = Colors.grey;

  Widget _buildSecurityHeader() {
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
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.shieldCheck,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('lock_document'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('encryption_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _updateStrength() {
    String pass = _passwordController.text;
    if (pass.isEmpty) {
      setState(() {
        _strength = 0;
        _strengthLabel = l10n.translate('strength_none');
        _strengthColor = Colors.grey;
      });
      return;
    }

    double s = 0;
    if (pass.length >= 6) s += 0.25;
    if (pass.length >= 10) s += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(pass)) s += 0.15;
    if (RegExp(r'[0-9]').hasMatch(pass)) s += 0.15;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pass)) s += 0.2;

    setState(() {
      _strength = s;
      if (s < 0.3) {
        _strengthLabel = l10n.translate('weak_label');
        _strengthColor = Colors.red;
      } else if (s < 0.7) {
        _strengthLabel = l10n.translate('medium_label');
        _strengthColor = Colors.orange;
      } else {
        _strengthLabel = l10n.translate('strong_label');
        _strengthColor = Colors.green;
      }
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();

      if (_pdfService.isPdfEncrypted(bytes)) {
        _handleProtectedFile(file, bytes);
      } else {
        setState(() {
          _selectedFile = file;
          _workingBytes = bytes;
        });
      }
    }
  }

  Future<void> _handleProtectedFile(File file, Uint8List bytes) async {
    final TextEditingController currentPassController = TextEditingController();

    final bool? unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.lock, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Text(l10n.translate('file_locked'), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.translate('file_protected_msg'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 20),
              TextField(
                controller: currentPassController,
                obscureText: true,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: l10n.translate('enter_password_hint'),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.translate('cancel_label').toUpperCase()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(l10n.translate('unlock_label')),
          ),
        ],
      ),
    );

    if (unlocked == true) {
      setState(() => _isProcessing = true);
      final decrypted = await _pdfService.decryptPdf(
        bytes,
        currentPassController.text,
      );
      setState(() => _isProcessing = false);

      if (decrypted != null) {
        setState(() {
          _selectedFile = file;
          _workingBytes = decrypted;
        });
        _showSuccess(l10n.translate('pdf_unlocked_success'));
      } else {
        _showError(l10n.translate('incorrect_password'));
      }
    }
  }

  Future<String?> _showRenameDialog(String initialName) async {
    final TextEditingController nameController = TextEditingController(
      text: initialName,
    );
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          l10n.translate('save_protected_pdf'),
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.translate('protected_name_hint')),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                hintText: l10n.translate('enter_name'),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel_label').toUpperCase()),
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
            child: Text(l10n.translate('save_securely')),
          ),
        ],
      ),
    );
  }

  Future<void> _protectPdf() async {
    if (_workingBytes == null) {
      _showError(l10n.translate('select_pdf_error'));
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showError(l10n.translate('enter_password_error'));
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      _showError(l10n.translate('passwords_mismatch'));
      return;
    }

    // Step 1: Prompt for Renaming
    final String baseDefault = p.basenameWithoutExtension(_selectedFile!.path);
    final String defaultName = baseDefault;
    final String? finalName = await _showRenameDialog(defaultName);

    if (finalName == null || finalName.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      // Step 2: Encrypt the working bytes (which are unencrypted now)
      final encryptedBytes = await _pdfService.protectPdf(
        _workingBytes!,
        _passwordController.text,
      );

      final appDocDir = await getApplicationDocumentsDirectory();
      final String fileName = finalName.endsWith('.pdf')
          ? finalName
          : "$finalName.pdf";
      final filePath = p.join(appDocDir.path, fileName);

      await File(filePath).writeAsBytes(encryptedBytes);

      await _storageService.saveDocumentNamed(
        name: p.basenameWithoutExtension(fileName),
        imagePaths: [],
        pdfPath: filePath,
        pageCount: _pdfService.getPdfPageCount(_workingBytes!),
      );

      if (mounted) {
        _showSuccess(
          l10n.translate('pdf_protected_success').replaceAll('{0}', finalName),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showError("${l10n.translate('error_prefix')}: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
    );
  }

  Future<void> _pickFromGallery() async {
    final DocumentModel? picked = await showModalBottomSheet<DocumentModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          DocumentSelectionSheet(title: l10n.translate('select_scans')),
    );

    if (picked != null) {
      if (picked.pdfPath != null) {
        final file = File(picked.pdfPath!);
        final bytes = await file.readAsBytes();

        if (_pdfService.isPdfEncrypted(bytes)) {
          await _handleProtectedFile(file, bytes);
        } else {
          setState(() {
            _selectedFile = file;
            _workingBytes = bytes;
          });
        }
      } else if (picked.imagePaths.isNotEmpty) {
        setState(() => _isProcessing = true);
        try {
          final pdfBytes =
              await _pdfService.compileImagesToPdf(picked.imagePaths);
          setState(() {
            _workingBytes = pdfBytes;
            _generatedName = picked.name;
            // Create a dummy file object for basename resolution
            _selectedFile = File("${picked.name}.pdf");
          });
        } catch (e) {
          _showError("${l10n.translate('error_prefix')}: $e");
        } finally {
          setState(() => _isProcessing = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          l10n.translate('protect_pdf'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
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
              _buildSecurityHeader(),
              const SizedBox(height: 24),
              if (_selectedFile == null)
                _buildSelectionOptions()
              else
                _buildSelectedFileInfo(),
              if (_selectedFile != null) ...[
                const SizedBox(height: 24),
                _buildPasswordSection(),
                const SizedBox(height: 32),
                _buildActionButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionOptions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSelectionCard(
                icon: LucideIcons.filePlus,
                title: l10n.translate('from_device'),
                subtitle: l10n.translate('browse_files'),
                onTap: _pickFile,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSelectionCard(
                icon: LucideIcons.image,
                title: l10n.translate('from_library'),
                subtitle: l10n.translate('system_photos'),
                onTap: _pickFromPhotos,
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSelectionCard(
          icon: LucideIcons.layers,
          title: l10n.translate('my_scans'),
          subtitle: l10n.translate('internal_app_scans'),
          onTap: _pickFromGallery,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildSelectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500], fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileInfo() {
    return Container(
      width: double.infinity,
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
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(LucideIcons.fileCheck, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(_selectedFile!.path),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "${((_workingBytes?.length ?? 0) / 1024).toStringAsFixed(1)} KB",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              _selectedFile = null;
              _workingBytes = null;
            }),
            icon: const Icon(
              LucideIcons.xCircle,
              color: Colors.redAccent,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('set_password'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              hintText: l10n.translate('enter_password_hint'),
              prefixIcon: Icon(LucideIcons.lock, size: 20, color: Theme.of(context).colorScheme.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildStrengthIndicator(),
          const SizedBox(height: 20),
          Text(
            l10n.translate('confirm_password'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              hintText: l10n.translate('confirm_password'),
              prefixIcon: Icon(LucideIcons.shield, size: 20, color: Theme.of(context).colorScheme.primary),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrengthIndicator() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _strength,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n
                  .translate('strength_label')
                  .replaceAll('{0}', _strengthLabel),
              style: TextStyle(
                color: _strengthColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              l10n.translate('min_chars_hint'),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _protectPdf,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 5,
          shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.4),
        ),
        child: _isProcessing
            ? const CircularProgressIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.lock),
                  const SizedBox(width: 12),
                  Text(
                    l10n.translate('protect_pdf_now'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
