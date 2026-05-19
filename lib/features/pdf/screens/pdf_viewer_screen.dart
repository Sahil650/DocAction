import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class PdfViewerScreen extends StatelessWidget {
  final Future<Uint8List> pdfData;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.pdfData,
    required this.title,
  });

  static const Color accentAmber = Color(0xffFFC107);

  Future<void> _handleShare(Uint8List data) async {
    try {
      final tempDir = await getTemporaryDirectory();
      // Sanitize title to remove invalid filename characters like /
      final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempFile = File('${tempDir.path}/$sanitizedTitle.pdf');
      await tempFile.writeAsBytes(data);
      
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        subject: title,
        text: 'Sharing $title document',
      );
    } catch (e) {
      debugPrint("Sharing Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        centerTitle: true,
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          FutureBuilder<Uint8List>(
            future: pdfData,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                  icon: Icon(LucideIcons.share2, color: Theme.of(context).colorScheme.primary),
                  onPressed: () => _handleShare(snapshot.data!),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PdfPreview(
        build: (format) => pdfData,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        maxPageWidth: 700,
        initialPageFormat: PdfPageFormat.a4,
        pdfFileName: "${title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf",
        useActions: true,
        onShared: (context) async {
          final data = await pdfData;
          await _handleShare(data);
        },
        loadingWidget: Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        ),
        previewPageMargin: const EdgeInsets.symmetric(
          vertical: 24,
          horizontal: 16,
        ),
      ),
    );
  }
}
