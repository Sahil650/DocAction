import '../../../core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';

class OCRResultScreen extends StatefulWidget {
  final List<String> imagePaths;
  final String extractedText;
  final Map<String, RecognizedText>? ocrData;
  final bool isDevanagari;

  const OCRResultScreen({
    super.key,
    required this.imagePaths,
    required this.extractedText,
    this.ocrData,
    this.isDevanagari = true,
  });

  @override
  State<OCRResultScreen> createState() => _OCRResultScreenState();
}

class _OCRResultScreenState extends State<OCRResultScreen> {
  late TextEditingController _textController;
  late PageController _pageController;
  bool _isEditing = false;
  int _currentPage = 0;
  List<String> _pageTexts = [];

  @override
  void initState() {
    super.initState();
    _parseInitialText();
    _textController = TextEditingController(text: _pageTexts.isNotEmpty ? _pageTexts[0] : "");
    _pageController = PageController();
  }

  void _parseInitialText() {
    final text = widget.extractedText;
    // Split by markers like "--- PAGE 1 ---"
    final parts = text.split(RegExp(r'--- PAGE \d+ ---\n'));
    // The first part is usually empty if it starts with a marker
    _pageTexts = parts.where((p) => p.trim().isNotEmpty).toList();
    
    // If splitting failed or list is shorter than images, fill it up
    while (_pageTexts.length < widget.imagePaths.length) {
      _pageTexts.add("");
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onImagePageChanged(int index) {
    // 1. Save current edits to the list
    _pageTexts[_currentPage] = _textController.text;
    
    // 2. Update current page
    setState(() {
      _currentPage = index;
      // 3. Update text controller with new page text
      _textController.text = _pageTexts[index];
    });
  }

  String _getCombinedText() {
    // Save last page edits first
    _pageTexts[_currentPage] = _textController.text;
    
    String fullText = "";
    for (int i = 0; i < _pageTexts.length; i++) {
      fullText += "--- PAGE ${i + 1} ---\n${_pageTexts[i]}\n\n";
    }
    return fullText.trim();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _getCombinedText()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("All pages copied to clipboard")),
    );
  }

  Future<void> _exportAsSearchablePdf() async {
    if (widget.ocrData == null || widget.ocrData!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Searchable data not available")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdfService = PdfService();
      final pdfBytes = await pdfService.convertImagesAndTextToPdf(
        widget.imagePaths,
        _getCombinedText(),
      );
      
      final storageService = StorageService();
      final pdfName = "OCR_Doc_${DateTime.now().millisecondsSinceEpoch}";
      final pdfPath = await storageService.savePdf(pdfBytes, pdfName);
      
      // Save to database as a document so it appears in the main screen
      await storageService.saveDocumentNamed(
        name: "OCR Scan ${DateTime.now().day}/${DateTime.now().month}",
        imagePaths: widget.imagePaths,
        pdfPath: pdfPath,
        pageCount: widget.imagePaths.length,
        extractedText: _textController.text,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("PDF saved to Library")),
        );
        // Share it as well for convenience
        await Share.shareXFiles([XFile(pdfPath)], text: "OCR Result Document");
        Navigator.pop(context, "SUCCESS"); // Go back to main screen with SUCCESS
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error generating PDF: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isWide = ResponsiveLayout.isWide(context);

    Widget imagePreview = Stack(
      children: [
        Container(
          height: isWide ? double.infinity : screenHeight * 0.28,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onImagePageChanged,
              itemCount: widget.imagePaths.length,
              itemBuilder: (context, index) {
                return Image.file(
                  File(widget.imagePaths[index]),
                  fit: BoxFit.contain,
                  cacheWidth: 800,
                );
              },
            ),
          ),
        ),
        if (widget.imagePaths.length > 1)
          Positioned(
            top: 20,
            right: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${_currentPage + 1} / ${widget.imagePaths.length}",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );

    Widget textEditor = Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: isWide
            ? const BorderRadius.all(Radius.circular(32))
            : const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "RESULT",
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                  letterSpacing: 1.2,
                ),
              ),
              _ActionButton(
                icon: LucideIcons.copy,
                onPressed: _copyToClipboard,
                label: "Copy",
              ),
            ],
          ),
          const Divider(height: 24),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              readOnly: !_isEditing,
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: const Color(0xff1F2937),
                height: 1.5,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: "No text extracted...",
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _getCombinedText()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1A1C1E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    "SAVE AS TEXT",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _exportAsSearchablePdf,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    "EXPORT PDF",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xff111827),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Extracted Text",
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditing ? LucideIcons.check : LucideIcons.edit3,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                Expanded(flex: 2, child: imagePreview),
                Expanded(flex: 3, child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: textEditor,
                )),
              ],
            )
          : Column(
              children: [
                imagePreview,
                Expanded(child: textEditor),
              ],
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String label;

  const _ActionButton({
    required this.icon,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xff1A1C1E)),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: const Color(0xff1A1C1E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
