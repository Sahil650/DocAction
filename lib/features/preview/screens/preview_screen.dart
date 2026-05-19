import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/screens/photo_view_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../scanner/screens/universal_scanner_screen.dart';
import '../../../shared/utils/app_localizations.dart';

class PreviewScreen extends StatefulWidget {
  final List<String> images;

  const PreviewScreen({
    super.key,
    required this.images,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final _storageService = StorageService();
  late List<String> _imagePaths;
  final Map<String, int> _rotationVersions = {};
  final Set<String> _processingPaths = {};

  @override
  void initState() {
    super.initState();
    _imagePaths = List<String>.from(widget.images);
  }

  Future<void> _saveDocument() async {
    try {
      final document = DocumentModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: "Scan_${DateTime.now().hour}${DateTime.now().minute}${DateTime.now().second}",
        date: DateTime.now(),
        imagePaths: _imagePaths,
      );

      await _storageService.saveDocument(document);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Document saved successfully!")),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving document: $e")),
        );
      }
    }
  }

  Future<void> _rotateImage(int index) async {
    final path = _imagePaths[index];
    final file = File(path);
    
    setState(() {
      _processingPaths.add(path);
    });

    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image != null) {
        final rotated = img.copyRotate(image, angle: 90);
        await file.writeAsBytes(img.encodeJpg(rotated));
        
        // Clear cache for this specific file
        final imageProvider = FileImage(file);
        await imageProvider.evict();

        setState(() {
          _rotationVersions[path] = (_rotationVersions[path] ?? 0) + 1;
        });
      }
    } catch (e) {
      debugPrint("Rotation error: $e");
    } finally {
      setState(() {
        _processingPaths.remove(path);
      });
    }
  }

  Future<void> _addPage() async {
    final List<String>? newImages = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const UniversalScannerScreen(shouldNavigateToPreview: false),
      ),
    );

    if (newImages != null && newImages.isNotEmpty) {
      setState(() {
        _imagePaths.addAll(newImages);
      });
    }
  }

  void _moveUp(int index) {
    if (index > 0) {
      setState(() {
        final item = _imagePaths.removeAt(index);
        _imagePaths.insert(index - 1, item);
      });
    }
  }

  void _moveDown(int index) {
    if (index < _imagePaths.length - 1) {
      setState(() {
        final item = _imagePaths.removeAt(index);
        _imagePaths.insert(index + 1, item);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xffF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: AppColors.primary,
        ),
        title: Text(
          l10n.translate('manage_document'),
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _addPage,
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: l10n.translate('add_page'),
          ),
        ],
      ),
      body: _imagePaths.isEmpty
          ? Center(
              child: Text(l10n.translate('no_scanned_images')),
            )
          : ResponsiveLayout(
              maxWidth: 1200,
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = (constraints.maxWidth / 350).floor();
                        final isWide = crossAxisCount > 1;

                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 450,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 20,
                            childAspectRatio: isWide ? 1.0 : 0.85,
                          ),
                          itemCount: _imagePaths.length,
                          itemBuilder: (context, index) {
                            String path = _imagePaths[index];
                            if (path.startsWith("file://")) {
                              path = Uri.parse(path).toFilePath();
                            }
                            final file = File(path);

                            return Container(
                              key: UniqueKey(),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 10,
                                    color: Colors.black12,
                                  )
                                ],
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(16),
                                          ),
                                          child: GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => PhotoViewScreen(
                                                    imagePath: path,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                Image.file(
                                                  file,
                                                  key: ValueKey(path + (_rotationVersions[path] ?? 0).toString()),
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      color: Colors.grey[200],
                                                      child: const Center(
                                                        child: Icon(Icons.broken_image, size: 60, color: Colors.grey),
                                                      ),
                                                    );
                                                  },
                                                ),
                                                if (_processingPaths.contains(path))
                                                  Container(
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    color: Colors.black26,
                                                    child: const Center(
                                                      child: CircularProgressIndicator(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 10,
                                          right: 10,
                                          child: Column(
                                            children: [
                                              if (index > 0)
                                                _circleButton(
                                                  icon: Icons.arrow_upward,
                                                  onPressed: () => _moveUp(index),
                                                ),
                                              if (index < _imagePaths.length - 1)
                                                const SizedBox(height: 8),
                                              if (index < _imagePaths.length - 1)
                                                _circleButton(
                                                  icon: Icons.arrow_downward,
                                                  onPressed: () => _moveDown(index),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        Text(
                                          "${l10n.translate('page_prefix')} ${index + 1}",
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          onPressed: () => _rotateImage(index),
                                          icon: const Icon(Icons.rotate_right, color: AppColors.primary, size: 20),
                                          tooltip: l10n.translate('rotate'),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _imagePaths.removeAt(index);
                                            });
                                          },
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          tooltip: l10n.translate('remove_page'),
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _imagePaths.isEmpty ? null : _saveDocument,
                          child: Text(
                            l10n.translate('save_document'),
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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

  Widget _circleButton({required IconData icon, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
    );
  }
}
