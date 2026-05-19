import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'pdf_service.dart';

class ImageOptimizationService {
  final PdfService _pdfService = PdfService();

  /// Optimizes an image and generates a thumbnail in one pass to save CPU/Memory.
  Future<Map<String, String>> processImage(String originalPath) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final optName = "opt_$timestamp.jpg";
    final thumbName = "thumb_$timestamp.jpg";
    final optPath = p.join(appDocDir.path, optName);
    final thumbPath = p.join(appDocDir.path, thumbName);

    return await Isolate.run(() async {
      final bytes = await File(originalPath).readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return {'optimized': originalPath, 'thumbnail': originalPath};
      }

      // 1. Generate Optimized Image (max 2000px)
      img.Image optimized = image;
      if (image.width > 2000 || image.height > 2000) {
        optimized = img.copyResize(
          image,
          width: image.width > image.height ? 2000 : null,
          height: image.height >= image.width ? 2000 : null,
          interpolation: img.Interpolation.linear,
        );
      }
      final optBytes = img.encodeJpg(optimized, quality: 75);
      await File(optPath).writeAsBytes(optBytes);

      // 2. Generate Thumbnail (max 250px) from the ALREADY DECODED image
      final thumbnail = img.copyResize(
        image,
        width: image.width > image.height ? 250 : null,
        height: image.height >= image.width ? 250 : null,
        interpolation: img.Interpolation.linear,
      );
      final thumbBytes = img.encodeJpg(thumbnail, quality: 60);
      await File(thumbPath).writeAsBytes(thumbBytes);

      // 3. Cleanup original if it's a temporary file
      try {
        if (originalPath.contains('cache') || originalPath.contains('tmp')) {
          final originalFile = File(originalPath);
          if (await originalFile.exists()) {
            await originalFile.delete();
          }
        }
      } catch (_) {}

      return {'optimized': optPath, 'thumbnail': thumbPath};
    });
  }

  /// Compresses an image to a standard resolution (max 2000px) and quality (75%).
  Future<String> optimizeImage(String originalPath) async {
    final result = await processImage(originalPath);
    return result['optimized']!;
  }

  /// Generates a tiny thumbnail (max 250px) for fast grid previews.
  Future<String> generateThumbnail(String imagePath) async {
    final result = await processImage(imagePath);
    return result['thumbnail']!;
  }
  Future<String?> generatePdfThumbnail(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final pageImage = await _pdfService.rasterizePdfPage(
        bytes,
        pageIndex: 0,
        dpi: 100,
      );

      if (pageImage == null) return null;

      final appDocDir = await getApplicationDocumentsDirectory();
      final fileName = "thumb_pdf_${DateTime.now().microsecondsSinceEpoch}.jpg";
      final thumbPath = p.join(appDocDir.path, fileName);

      await File(thumbPath).writeAsBytes(pageImage);
      return thumbPath;
    } catch (_) {
      return null;
    }
  }
}
