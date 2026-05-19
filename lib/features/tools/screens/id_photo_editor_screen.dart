import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../data/models/photo_size_model.dart';
import '../../../shared/utils/app_localizations.dart';

class IdPhotoEditorScreen extends StatefulWidget {
  final String imagePath;
  final PhotoSizeModel size;

  const IdPhotoEditorScreen({
    super.key,
    required this.imagePath,
    required this.size,
  });

  @override
  State<IdPhotoEditorScreen> createState() => _IdPhotoEditorScreenState();
}

class _IdPhotoEditorScreenState extends State<IdPhotoEditorScreen> {
  late String _currentPath;
  bool _isProcessing = false;
  int _rotation = 0;
  bool _isGrayscale = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
  }

  Future<void> _handleCrop({bool manual = false}) async {
    final l10n = AppLocalizations.of(context);
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _currentPath,
      aspectRatio: manual ? null : CropAspectRatio(
        ratioX: widget.size.width,
        ratioY: widget.size.height,
      ),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: manual ? l10n.translate('manual_crop') : l10n.translate('crop_to_size').replaceFirst('{0}', widget.size.name),
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: manual ? CropAspectRatioPreset.original : CropAspectRatioPreset.original,
          lockAspectRatio: !manual,
          aspectRatioPresets: manual ? [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ] : [],
        ),
        IOSUiSettings(
          title: manual ? l10n.translate('manual_crop') : l10n.translate('crop_to_size').replaceFirst('{0}', widget.size.name),
          aspectRatioLockEnabled: !manual,
        ),
      ],
    );

    if (croppedFile != null) {
      setState(() {
        _currentPath = croppedFile.path;
      });
    }
  }

  Future<void> _applyAndExit() async {
    setState(() => _isProcessing = true);
    try {
      final bytes = await File(_currentPath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      if (image != null) {
        // Apply Rotation
        if (_rotation != 0) {
          image = img.copyRotate(image, angle: _rotation);
        }
        
        // Apply Grayscale
        if (_isGrayscale) {
          image = img.grayscale(image);
        }

        final tempDir = await getTemporaryDirectory();
        final newPath = p.join(tempDir.path, "id_edited_${DateTime.now().millisecondsSinceEpoch}.jpg");
        await File(newPath).writeAsBytes(img.encodeJpg(image));
        
        if (mounted) {
          Navigator.pop(context, newPath);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${l10n.translate('error_saving')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(l10n.translate("photo_editor"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isProcessing)
            TextButton(
              onPressed: _applyAndExit,
              child: Text(l10n.translate("apply_label"), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: _isProcessing 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : RotatedBox(
                        quarterTurns: (_rotation / 90).round(),
                        child: ColorFiltered(
                          colorFilter: _isGrayscale 
                            ? const ColorFilter.matrix([
                                0.2126, 0.7152, 0.0722, 0, 0,
                                0.2126, 0.7152, 0.0722, 0, 0,
                                0.2126, 0.7152, 0.0722, 0, 0,
                                0,      0,      0,      1, 0,
                              ])
                            : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                          child: Image.file(File(_currentPath), fit: BoxFit.contain),
                        ),
                      ),
                ),
              ],
            ),
          ),
          _buildToolbar(l10n),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xff1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _toolbarItem(Icons.aspect_ratio, l10n.translate("size_crop"), () => _handleCrop(manual: false)),
            _toolbarItem(Icons.crop, l10n.translate("manual_crop"), () => _handleCrop(manual: true)),
            _toolbarItem(Icons.rotate_right, l10n.translate("rotate_label"), () {
              setState(() => _rotation = (_rotation + 90) % 360);
            }),
            _toolbarItem(
              _isGrayscale ? Icons.color_lens : Icons.color_lens_outlined, 
              l10n.translate("grayscale_label"), 
              () => setState(() => _isGrayscale = !_isGrayscale)
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
