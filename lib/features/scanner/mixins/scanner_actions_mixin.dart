import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scanner_mode.dart';
import '../../../data/models/photo_size_model.dart';
import '../../../data/services/scanner_service.dart';
import '../../tools/screens/tool_editor_screen.dart';
// import '../../tools/screens/id_photo_session_screen.dart';
// import '../../tools/screens/ocr_result_screen.dart';
import '../screens/document_crop_screen.dart';

mixin ScannerActionsMixin<T extends StatefulWidget> on State<T> {
  // These will be provided by the Host state or other mixins
  bool get isInitialized;
  dynamic get cameraController; // Can be CameraController?

  Future<void> handleGalleryImport({
    required ScannerMode currentMode,
    required List<PhotoSizeModel> photoSizes,
    required int selectedPhotoSizeIndex,
    required bool isOcrHindi,
    required bool isPickerMode,
    required Function(String) onImageAdded,
    required Function() onOpenSession,
  }) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null && mounted) {
      HapticFeedback.lightImpact();

      switch (currentMode) {
        case ScannerMode.document:
          final corners = await ScannerService.detectDocument(image.path);
          if (mounted) {
            final processedPath = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => MakeACopyCropScreen(
                  imagePath: image.path,
                  initialPoints: corners ?? [],
                ),
              ),
            );
            if (processedPath != null) {
              onImageAdded(processedPath);
              onOpenSession();
            }
          }
          break;

        case ScannerMode.photo:
          final size = photoSizes[selectedPhotoSizeIndex];
          if (mounted) {
            final editedPath = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => ToolEditorScreen(
                  imagePath: image.path,
                  title: "Photo Editor",
                  ratioX: size.width,
                  ratioY: size.height,
                ),
              ),
            );
            if (editedPath != null) {
              onImageAdded(editedPath);
              onOpenSession();
            }
          }
          break;

        case ScannerMode.ocr:
          // OCR specific logic handled in main for state access
          break;
        default:
          break;
      }
    }
  }
}
