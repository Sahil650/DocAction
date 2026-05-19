import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart'; // for compute
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/utils/app_localizations.dart';
import 'signature_screen.dart';
import 'tool_editor_screen.dart';

// Reuse the background processing function
Future<String> _processCapturedSignatureInternal(Map<String, dynamic> params) async {
  final String imagePath = params['imagePath'];
  final String tempDirPath = params['tempDirPath'];

  final bytes = await File(imagePath).readAsBytes();
  img.Image? decoded = img.decodeImage(bytes);
  
  if (decoded == null) throw Exception("Failed to decode image");

  if (decoded.width > 1024 || decoded.height > 1024) {
    decoded = img.copyResize(decoded, width: decoded.width > decoded.height ? 1024 : null, height: decoded.height >= decoded.width ? 1024 : null);
  }

  img.grayscale(decoded);
  img.contrast(decoded, contrast: 150);
  
  final fileName = "scanned_sig_${DateTime.now().millisecondsSinceEpoch}.png";
  final filePath = p.join(tempDirPath, fileName);
  await File(filePath).writeAsBytes(img.encodePng(decoded));
  
  return filePath;
}

class SignatureSessionScreen extends StatefulWidget {
  final List<String> initialPaths;
  final VoidCallback? onRefresh;

  const SignatureSessionScreen({
    super.key,
    required this.initialPaths,
    this.onRefresh,
  });

  @override
  State<SignatureSessionScreen> createState() => _SignatureSessionScreenState();
}

class _SignatureSessionScreenState extends State<SignatureSessionScreen> {
  late List<String> _imagePaths;
  final _storageService = StorageService();
  bool _isSaving = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _imagePaths = List.from(widget.initialPaths);
  }

  Future<void> _captureMore() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    
    if (image != null) {
      setState(() => _isProcessing = true);
      try {
        final tempDir = await getTemporaryDirectory();
        final processedPath = await compute(_processCapturedSignatureInternal, {
          'imagePath': image.path,
          'tempDirPath': tempDir.path,
        });

        setState(() {
          _imagePaths.add(processedPath);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _drawNew() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen(isSessionMode: true)),
    );

    if (path != null) {
      setState(() {
        _imagePaths.add(path);
      });
    }
  }

  Future<void> _editSignature(int index) async {
    final path = _imagePaths[index];
    final editedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ToolEditorScreen(
          imagePath: path,
          title: AppLocalizations.of(context).translate("signature_title"),
          // Use free crop for signatures
          ratioX: 0, 
          ratioY: 0,
        ),
      ),
    );

    if (editedPath != null) {
      setState(() {
        _imagePaths[index] = editedPath;
      });
    }
  }

  Future<void> _saveBatch() async {
    final l10n = AppLocalizations.of(context);
    if (_imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate("sig_min_one_snack"))));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[:.-]'), '').substring(0, 14);
      final doc = DocumentModel(
        id: const Uuid().v4(),
        name: "SIG_PACK_$timestamp",
        date: DateTime.now(),
        imagePaths: List.from(_imagePaths),
      );

      await _storageService.saveDocument(doc);
      widget.onRefresh?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate("sig_pack_saved_snack"))));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${l10n.translate('error_saving')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xffF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xffF3F4F6),
        elevation: 0,
        title: Text(AppLocalizations.of(context).translate("signature_title"), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isTablet ? 3 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.4,
              ),
              itemCount: _imagePaths.length,
              itemBuilder: (context, index) {
                return _buildSigCard(index);
              },
            ),
          ),
          _buildActionPanel(AppLocalizations.of(context)),
        ],
      ),
    );
  }

  Widget _buildSigCard(int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => _editSignature(index),
              child: Image.file(File(_imagePaths[index]), width: double.infinity, height: double.infinity, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() => _imagePaths.removeAt(index)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
              child: Text(AppLocalizations.of(context).translate("tap_to_edit"), style: const TextStyle(color: Colors.white, fontSize: 8)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionPanel(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _captureMore,
                    icon: _isProcessing 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.camera_alt_outlined),
                    label: Text(l10n.translate("scan_more")),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _drawNew,
                    icon: const Icon(Icons.draw_outlined),
                    label: Text(l10n.translate("draw_new")),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveBatch,
              icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline),
              label: Text(l10n.translate("save_sig_pack")),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
