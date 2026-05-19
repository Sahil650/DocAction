import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/app_localizations.dart';

class PhotoViewScreen extends StatefulWidget {
  final String imagePath;

  const PhotoViewScreen({
    super.key,
    required this.imagePath,
  });

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen> {
  late String _currentPath;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Text(
          l10n.translate('view_image'),
          style: const TextStyle(color: AppColors.primary),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          key: ValueKey(_version),
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(
            File(_currentPath),
            key: ValueKey("img_$_version"),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, color: Colors.grey, size: 60),
                  const SizedBox(height: 10),
                  Text(
                    l10n.translate('error_loading_image'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
