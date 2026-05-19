import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'tool_editor_screen.dart';
import '../../../data/models/document_model.dart';
import '../../../data/models/photo_size_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/image_optimization_service.dart';
import '../../../shared/utils/app_localizations.dart';

class IdPhotoSessionScreen extends StatefulWidget {
  final PhotoSizeModel size;
  final String? initialImagePath;
  final List<String>? initialImagePaths;
  final bool fromCameraHub;
  final bool isPickerMode;
  final String? currentMode;

  const IdPhotoSessionScreen({
    super.key,
    required this.size,
    this.initialImagePath,
    this.initialImagePaths,
    this.fromCameraHub = false,
    this.isPickerMode = false,
    this.currentMode,
  });

  @override
  State<IdPhotoSessionScreen> createState() => _IdPhotoSessionScreenState();
}

class _IdPhotoSessionScreenState extends State<IdPhotoSessionScreen> {
  final List<String> _imagePaths = [];
  final Map<String, String> _thumbnails = {};
  final _storageService = StorageService();
  final _optService = ImageOptimizationService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _imagePaths.add(widget.initialImagePath!);
    }
    if (widget.initialImagePaths != null) {
      _imagePaths.addAll(widget.initialImagePaths!);
    }
    _generateMissingThumbnails();
  }

  Future<void> _generateMissingThumbnails() async {
    for (var path in List.from(_imagePaths)) {
      if (!_thumbnails.containsKey(path)) {
        try {
          final thumb = await _optService.generateThumbnail(path);
          if (mounted) {
            setState(() {
              _thumbnails[path] = thumb;
            });
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _addPhoto() async {
    Navigator.pop(context, {"action": "CAPTURE_MORE", "updatedList": _imagePaths});
  }

  Future<void> _openEditor(int index) async {
    final path = _imagePaths[index];
    
    final editedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ToolEditorScreen(
          imagePath: path,
          title: AppLocalizations.of(context).translate("photo_editor"),
          ratioX: widget.size.width.toDouble(),
          ratioY: widget.size.height.toDouble(),
        ),
      ),
    );

    if (editedPath == "RETAKE") {
      if (mounted) {
        Navigator.pop(context, {
          "action": "REPLACE",
          "index": index,
          "updatedList": _imagePaths,
        });
      }
      return;
    }

    if (editedPath != null) {
      setState(() {
        _imagePaths[index] = editedPath;
        _thumbnails.remove(path); // remove old thumbnail so new one is generated
      });
      _generateMissingThumbnails();
    }
  }

  Future<void> _saveSession() async {
    // If in picker mode, just return the paths
    if (widget.isPickerMode) {
      Navigator.pop(context, _imagePaths);
      return;
    }

    final l10n = AppLocalizations.of(context);
    final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[:.-]'), '').substring(0, 14);
    
    String prefix = "PHOTO";
    if (widget.currentMode == "document") prefix = "DOC";
    if (widget.currentMode == "signature") prefix = "SIG";
    
    final defaultName = "${prefix}_$timestamp";

    final String? customName = await _showNamingDialog(defaultName);
    if (customName == null || customName.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final doc = DocumentModel(
        id: const Uuid().v4(),
        name: customName.trim(),
        date: DateTime.now(),
        imagePaths: List.from(_imagePaths),
      );

      await _storageService.saveDocument(doc);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate("photos_saved_home"))),
        );
        // Pop with "SUCCESS" to tell parent we saved successfully
        Navigator.of(context).pop("SUCCESS");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${l10n.translate('error_saving')}: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _showNamingDialog(String initialName) async {
    final TextEditingController controller = TextEditingController(text: initialName);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(context).translate("rename_doc"), 
          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).translate("enter_name"),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black, width: 1.5),
            ),
          ),
          autofocus: true,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).translate("cancel"), 
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("SAVE", 
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.translate("session_organizer"), 
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.black),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context, _imagePaths),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 1000,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final crossAxisCount = isWide ? 4 : 2;

            return Column(
              children: [
                Expanded(
                  child: ReorderableGridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _imagePaths.length,
                    itemBuilder: (context, index) {
                      return _buildPhotoCard(index);
                    },
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        final path = _imagePaths.removeAt(oldIndex);
                        _imagePaths.insert(newIndex, path);
                      });
                    },
                  ),
                ),
                _buildActionPanel(l10n),
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _buildPhotoCard(int index) {
    final path = _imagePaths[index];
    return Container(
      key: ValueKey(path),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey(_imagePaths[index]), // Required for ReorderableGrid
                onTap: () => _openEditor(index),
                child: Image.file(
                  File(_thumbnails[_imagePaths[index]] ?? _imagePaths[index]), 
                  fit: BoxFit.cover, 
                  width: double.infinity, 
                  height: double.infinity
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Retake/Replace Button
                  _buildCardAction(
                    icon: Icons.refresh_rounded,
                    color: Colors.white,
                    onTap: () => Navigator.pop(context, {
                      "action": "REPLACE",
                      "index": index,
                      "updatedList": _imagePaths,
                    }),
                  ),
                  // Delete Button
                  _buildCardAction(
                    icon: Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    onTap: () => setState(() => _imagePaths.removeAt(index)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardAction({required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildActionPanel(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _addPhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(l10n.translate("capture_more"), style: const TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 56),
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSession,
              icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(widget.isPickerMode ? Icons.done_all_rounded : Icons.check_circle_outline),
              label: Text(l10n.translate(widget.isPickerMode ? "done_btn" : "save_exit"), 
                style: const TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 56),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
