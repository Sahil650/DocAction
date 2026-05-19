import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';

enum ScannerMode {
  photo,
  document,
  qrCode,
  signature,
  ocr,
}

extension ScannerModeExtension on ScannerMode {
  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (this) {
      case ScannerMode.photo: return l10n.translate('mode_photo');
      case ScannerMode.document: return l10n.translate('mode_document');
      case ScannerMode.qrCode: return l10n.translate('mode_qr');
      case ScannerMode.signature: return l10n.translate('mode_signature');
      case ScannerMode.ocr: return l10n.translate('mode_ocr');
    }
  }

  IconData get icon {
    switch (this) {
      case ScannerMode.photo: return LucideIcons.camera;
      case ScannerMode.document: return LucideIcons.fileText;
      case ScannerMode.qrCode: return LucideIcons.qrCode;
      case ScannerMode.signature: return LucideIcons.penTool;
      case ScannerMode.ocr: return LucideIcons.fileSearch;
    }
  }
}
