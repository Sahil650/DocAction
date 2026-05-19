import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import '../../../data/models/document_model.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/pdf_service.dart';
import 'pdf_viewer_screen.dart';
import '../../scanner/models/scanner_mode.dart';
import '../../scanner/screens/universal_scanner_screen.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/document_selection_sheet.dart';

class ConversionItem {
  final String id;
  String originalPath;
  String? editedPath;

  String get displayPath => editedPath ?? originalPath;

  ConversionItem({
    required this.id,
    required this.originalPath,
    this.editedPath,
  });
}

class ImageToPdfScreen extends StatefulWidget {
  const ImageToPdfScreen({super.key});

  @override
  State<ImageToPdfScreen> createState() => _ImageToPdfScreenState();
}

class _ImageToPdfScreenState extends State<ImageToPdfScreen> {
  final _pdfService = PdfService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();
  AppLocalizations get l10n => AppLocalizations.of(context);

  final List<ConversionItem> _items = [];
  bool _isProcessing = false;
  PdfPageFormat _selectedFormat = PdfPageFormat.a4;
  bool _isAutoFormat = true;

  Future<void> _pickFromGallery() async {
    final List<XFile> images = await _imagePicker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        for (var img in images) {
          _items.add(
            ConversionItem(
              id: "${DateTime.now().millisecondsSinceEpoch}_${img.name}",
              originalPath: img.path,
            ),
          );
        }
      });
    }
  }

  Future<void> _pickFromCamera() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
    );
    if (image != null) {
      _addImagesToList([image.path]);
    }
  }

  Future<void> _pickFromDocumentScanner() async {
    final List<String>? results = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const UniversalScannerScreen(
          isPickerMode: true,
          initialMode: ScannerMode.document,
        ),
      ),
    );

    if (results != null && results.isNotEmpty) {
      _addImagesToList(results);
    }
  }

  void _addImagesToList(List<String> paths) {
    setState(() {
      for (var path in paths) {
        _items.add(
          ConversionItem(
            id: "${DateTime.now().millisecondsSinceEpoch}_${_items.length}",
            originalPath: path,
          ),
        );
      }
    });
  }

  void _showSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBorder
                    : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l10n.translate('add_images'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _selectorItem(
                  l10n.translate('gallery_label'),
                  LucideIcons.image,
                  Colors.blueAccent,
                  () {
                    Navigator.pop(context);
                    _pickFromGallery();
                  },
                ),
                _selectorItem(
                  l10n.translate('scanner_label'),
                  LucideIcons.scan,
                  Theme.of(context).colorScheme.primary,
                  () {
                    Navigator.pop(context);
                    _pickFromDocumentScanner();
                  },
                ),
                _selectorItem(
                  l10n.translate('camera_label'),
                  LucideIcons.camera,
                  Colors.pinkAccent,
                  () {
                    Navigator.pop(context);
                    _pickFromCamera();
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Icon(
                LucideIcons.library,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                l10n.translate('pick_from_library'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickFromLibrary();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _selectorItem(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromLibrary() async {
    final l10n = AppLocalizations.of(context);
    final dynamic result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentSelectionSheet(
        title: l10n.translate('select_images_library'),
      ),
    );

    if (result is DocumentModel && result.imagePaths.isNotEmpty) {
      setState(() {
        for (var path in result.imagePaths) {
          _items.add(
            ConversionItem(
              id: "${DateTime.now().millisecondsSinceEpoch}_${_items.length}_${path.split('/').last}",
              originalPath: path,
            ),
          );
        }
      });
      HapticFeedback.mediumImpact();
    } else if (result is DocumentModel && result.imagePaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('no_images_in_doc')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _editImage(int index) async {
    final item = _items[index];
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: item.displayPath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n.translate('edit_page'),
          toolbarColor: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkSurface
              : AppColors.primary,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Theme.of(context).colorScheme.primary,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(title: l10n.translate('edit_page')),
      ],
    );

    if (croppedFile != null) {
      setState(() {
        _items[index].editedPath = croppedFile.path;
      });
    }
  }

  Future<void> _handleGenerate() async {
    if (_items.isEmpty) return;

    // 1. Ask for Filename
    final TextEditingController nameController = TextEditingController(
      text:
          "${l10n.translate('image_pdf_prefix')}_${DateTime.now().millisecondsSinceEpoch}",
    );

    final bool? shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('save_pdf')),
        content: TextField(
          controller: nameController,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
          decoration: InputDecoration(
            labelText: l10n.translate('doc_name_label'),
            hintText: l10n.translate('filename_hint'),
            labelStyle: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : Colors.black54,
            ),
            hintStyle: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white24
                  : Colors.black26,
            ),
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
            ),
            child: Text(
              l10n.translate('convert_label'),
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    setState(() => _isProcessing = true);

    try {
      final List<String> finalPaths = _items.map((i) => i.displayPath).toList();
      final Uint8List pdfBytes = await _pdfService.compileImagesToPdf(
        finalPaths,
        format: _isAutoFormat ? null : _selectedFormat,
      );

      final appDir = await getApplicationDocumentsDirectory();
      final finalPath = "${appDir.path}/converts/${nameController.text}.pdf";
      final file = File(finalPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(pdfBytes);

      // Save to library
      await _storageService.saveDocument(
        DocumentModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: nameController.text,
          date: DateTime.now(),
          imagePaths: [],
          pdfPath: finalPath,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('pdf_gen_success'))),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(pdfBytes),
              title: nameController.text,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${l10n.translate('error_saving')}: $e")),
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
        title: Text(
          l10n.translate('image_to_pdf'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            LucideIcons.chevronLeft,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _items.clear()),
              icon: const Icon(Icons.folder, color: Colors.redAccent),
            ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 1000,
        child: Stack(
          children: [
            Column(
              children: [
                _buildConfigBar(),
                Expanded(
                  child: _items.isEmpty
                      ? _buildEmptyState()
                      : _buildImageGrid(),
                ),
                if (_items.isNotEmpty) _buildBottomBar(),
              ],
            ),
            if (_isProcessing)
              Container(
                color: Colors.black45,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.white,
      child: Row(
        children: [
          Text(
            l10n.translate('page_size'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : Colors.black87,
            ),
          ),
          const SizedBox(width: 10),
          _formatChip(
            l10n.translate('auto_label'),
            _isAutoFormat,
            () => setState(() => _isAutoFormat = true),
          ),
          _formatChip(
            "A4",
            !_isAutoFormat && _selectedFormat == PdfPageFormat.a4,
            () {
              setState(() {
                _isAutoFormat = false;
                _selectedFormat = PdfPageFormat.a4;
              });
            },
          ),
          _formatChip(
            "Letter",
            !_isAutoFormat && _selectedFormat == PdfPageFormat.letter,
            () {
              setState(() {
                _isAutoFormat = false;
                _selectedFormat = PdfPageFormat.letter;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _formatChip(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? Colors.white : Colors.black,
          ),
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
          color: isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : const Color(0xffF3F4F6),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.image,
            size: 80,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white12
                : Colors.black12,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.translate('no_images_selected'),
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : Colors.black45,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 40),
          _sourceBtn(
            l10n.translate('add_from_gallery'),
            LucideIcons.image,
            Colors.blueAccent,
            _pickFromGallery,
          ),
          const SizedBox(height: 16),
          _sourceBtn(
            l10n.translate('add_from_camera'),
            LucideIcons.camera,
            Colors.pinkAccent,
            _pickFromCamera,
          ),
          const SizedBox(height: 16),
          _sourceBtn(
            l10n.translate('add_from_library'),
            LucideIcons.library,
            Theme.of(context).colorScheme.primary,
            _pickFromLibrary,
          ),
        ],
      ),
    );
  }

  Widget _sourceBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 250,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount = (constraints.maxWidth / 150).floor().clamp(
          2,
          6,
        );
        return ReorderableGridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
            childAspectRatio: 0.75,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return _buildImageCard(item, index);
          },
          onReorder: (oldIndex, newIndex) {
            setState(() {
              final item = _items.removeAt(oldIndex);
              _items.insert(newIndex, item);
            });
          },
        );
      },
    );
  }

  Widget _buildImageCard(ConversionItem item, int index) {
    return Container(
      key: ValueKey(item.id),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurfaceLight
            : Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(item.displayPath), fit: BoxFit.cover),
            // Index Badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${index + 1}",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Delete Button (Top Right - More Prominent)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _items.removeAt(index)),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkSurface
                        : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.x,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
            // Edit Overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Center(
                  child: GestureDetector(
                    onTap: () => _editImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.edit3,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            const BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n
                      .translate('images_selected_count')
                      .replaceAll('{0}', _items.length.toString()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
                IconButton(
                  onPressed: _showSourceSelector,
                  icon: Icon(
                    Icons.folder,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleGenerate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  l10n.translate('generate_pdf'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
