import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../shared/widgets/responsive_layout.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';

enum FilterType { original, magic, grayscale, bw, lighting }

class ToolEditorScreen extends StatefulWidget {
  final String imagePath;
  final String title;
  final double? ratioX;
  final double? ratioY;
  final Color? backgroundColor;

  const ToolEditorScreen({
    super.key,
    required this.imagePath,
    this.title = "Photo Editor",
    this.ratioX,
    this.ratioY,
    this.backgroundColor,
  });

  @override
  State<ToolEditorScreen> createState() => _ToolEditorScreenState();
}

class _ToolEditorScreenState extends State<ToolEditorScreen> {
  late String _currentPath;
  bool _isProcessing = false;
  int _rotation = 0;
  FilterType _selectedFilter = FilterType.original;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
  }

  Future<void> _handleCrop({bool manual = false}) async {
    final l10n = AppLocalizations.of(context);
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _currentPath,
      aspectRatio: manual
          ? null
          : (widget.ratioX != null
                ? CropAspectRatio(
                    ratioX: widget.ratioX!,
                    ratioY: widget.ratioY!,
                  )
                : null),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: manual
              ? l10n.translate('manual_crop')
              : l10n.translate('fit_crop'),
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: !manual,
          aspectRatioPresets: manual
              ? [
                  CropAspectRatioPreset.original,
                  CropAspectRatioPreset.square,
                  CropAspectRatioPreset.ratio3x2,
                  CropAspectRatioPreset.ratio4x3,
                  CropAspectRatioPreset.ratio16x9,
                ]
              : [],
        ),
        IOSUiSettings(
          title: manual
              ? l10n.translate('manual_crop')
              : l10n.translate('fit_crop'),
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
        // Apply rotation
        if (_rotation != 0) {
          image = img.copyRotate(image, angle: _rotation);
        }

        // Apply filters
        if (_selectedFilter != FilterType.original) {
          if (_selectedFilter == FilterType.grayscale) {
            image = img.grayscale(image);
          } else if (_selectedFilter == FilterType.bw) {
            image = img.grayscale(image);
            image = img.contrast(image, contrast: 150);
          } else if (_selectedFilter == FilterType.magic) {
             image = img.contrast(image, contrast: 150);
          } else if (_selectedFilter == FilterType.lighting) {
             image = img.contrast(image, contrast: 130);
          }
        }

        final tempDir = await getTemporaryDirectory();
        final fileName = "edited_${DateTime.now().millisecondsSinceEpoch}.png";
        final filePath = p.join(tempDir.path, fileName);
        
        await File(filePath).writeAsBytes(img.encodePng(image));
        if (mounted) Navigator.pop(context, filePath);
      }
    } catch (e) {
      debugPrint("Editor Save Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isDark = (widget.backgroundColor ?? AppColors.darkBackground).computeLuminance() < 0.5;
    final Color contentColor = isDark ? Colors.white : AppColors.textPrimary;
    
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, color: contentColor),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: contentColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (!_isProcessing)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: _applyAndExit,
                child: Text(
                  l10n.translate('save'),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.backgroundColor ?? const Color(0xff1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Center(
                        child: _isProcessing
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : RotatedBox(
                                quarterTurns: (_rotation / 90).round(),
                                child: ColorFiltered(
                                  colorFilter: _getColorFilter(),
                                  child: Image.file(
                                    File(_currentPath),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildFilterRow(),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  ColorFilter _getColorFilter() {
    switch (_selectedFilter) {
      case FilterType.magic:
        return const ColorFilter.matrix([
          1.2, 0.1, 0.1, 0, 10,
          0.1, 1.2, 0.1, 0, 10,
          0.1, 0.1, 1.2, 0, 10,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.grayscale:
        return const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.bw:
        return const ColorFilter.matrix([
          1.5, 1.5, 1.5, 0, -150,
          1.5, 1.5, 1.5, 0, -150,
          1.5, 1.5, 1.5, 0, -150,
          0, 0, 0, 1, 0,
        ]);
      case FilterType.lighting:
        return const ColorFilter.matrix([
          1.3, 0, 0, 0, 30,
          0, 1.3, 0, 0, 30,
          0, 0, 1.3, 0, 30,
          0, 0, 0, 1, 0,
        ]);
      default:
        return const ColorFilter.mode(Colors.transparent, BlendMode.multiply);
    }
  }

  Widget _buildFilterRow() {
    final l10n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final rowHeight = screenHeight < 600 ? 90.0 : 110.0;

    return Container(
      height: rowHeight,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.black,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filterItem(
            FilterType.original,
            l10n.translate('original'),
            Icons.image_outlined,
          ),
          _filterItem(
            FilterType.magic,
            l10n.translate('magic'),
            Icons.auto_fix_high,
          ),
          _filterItem(
            FilterType.grayscale,
            l10n.translate('grayscale_filter'),
            Icons.gradient,
          ),
          _filterItem(
            FilterType.bw,
            l10n.translate('bw_filter'),
            Icons.brightness_medium,
          ),
          _filterItem(
            FilterType.lighting,
            l10n.translate('lighting_filter'),
            Icons.lightbulb_outline,
          ),
        ],
      ),
    );
  }

  Widget _filterItem(FilterType type, String label, IconData icon) {
    bool isSelected = _selectedFilter == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 85,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.accent : Colors.white10,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.accent : Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? AppColors.accent : Colors.white70,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final l10n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final verticalPadding = screenHeight < 600 ? 12.0 : 16.0;

    return Container(
      padding: EdgeInsets.fromLTRB(16, verticalPadding, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xff1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: verticalPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _toolbarItem(
                Icons.aspect_ratio,
                l10n.translate('fit_crop'),
                () => _handleCrop(manual: false),
              ),
              _toolbarItem(
                Icons.crop,
                l10n.translate('manual_crop'),
                () => _handleCrop(manual: true),
              ),
              _toolbarItem(
                Icons.rotate_right,
                l10n.translate('rotate'),
                () => setState(() => _rotation = (_rotation + 90) % 360),
              ),
              _toolbarItem(
                Icons.camera_alt_outlined,
                l10n.translate('retake'),
                () => Navigator.pop(context, "RETAKE"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
