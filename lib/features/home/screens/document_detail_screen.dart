import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/document_model.dart';
import '../../../shared/screens/photo_view_screen.dart';
import '../../pdf/screens/pdf_viewer_screen.dart';
import '../../pdf/screens/pdf_split_screen.dart';
import '../../../data/services/pdf_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'package:printing/printing.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/shimmer_loader.dart';

class DocumentDetailScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final PdfService _pdfService = PdfService();
  bool _isRasterizing = false;
  bool _isEncrypted = false;
  bool _isUnlocked = false;
  final List<Uint8List> _rasterizedPages = [];
  final TextEditingController _passwordController = TextEditingController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkEncryption();
  }

  Future<void> _checkEncryption() async {
    if (widget.document.pdfPath != null &&
        widget.document.pdfPath!.toLowerCase().endsWith('.pdf')) {
      final bytes = await File(widget.document.pdfPath!).readAsBytes();
      if (_pdfService.isPdfEncrypted(bytes)) {
        setState(() {
          _isEncrypted = true;
          _isUnlocked = false;
        });
      } else {
        _loadPdfPages();
      }
    }
  }

  Uint8List? _decryptedBytes;

  Future<void> _unlockAndLoad() async {
    final bytes = await File(widget.document.pdfPath!).readAsBytes();
    final decrypted = await _pdfService.decryptPdf(
      bytes,
      _passwordController.text,
    );

    if (decrypted != null) {
      _decryptedBytes = decrypted;
      setState(() {
        _isUnlocked = true;
        _isEncrypted = false;
      });
      _loadPdfPages(data: decrypted);
    } else {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate("incorrect_password_try_again")),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadPdfPages({Uint8List? data}) async {
    setState(() {
      _isRasterizing = true;
      _rasterizedPages.clear();
    });
    try {
      final bytes = data ?? await File(widget.document.pdfPath!).readAsBytes();
      await for (final pageBytes in _pdfService.rasterizePdfToImages(
        bytes,
        dpi: 140, // Slightly higher for premium feel
      )) {
        if (!mounted) break;
        setState(() {
          _rasterizedPages.add(pageBytes);
        });
      }
    } catch (e) {
      debugPrint("Error rasterizing PDF: $e");
    } finally {
      if (mounted) setState(() => _isRasterizing = false);
    }
  }

  Future<void> _shareFile(BuildContext context) async {
    String? path;
    Uint8List? explicitData;

    if (widget.document.pdfPath != null) {
      path = widget.document.pdfPath!;
    } else {
      final pdf = pw.Document();
      for (final imagePath in widget.document.imagePaths) {
        final image = pw.MemoryImage(File(imagePath).readAsBytesSync());
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/${widget.document.name}.pdf");
      await file.writeAsBytes(await pdf.save());
      path = file.path;
    }

    if (explicitData != null) {
      await Printing.sharePdf(
        bytes: explicitData,
        filename: "${widget.document.name}.pdf",
      );
    } else if (path != null) {
      final l10n = AppLocalizations.of(context);
      await Share.shareXFiles([
        XFile(path),
      ], text: '${l10n.translate("check_out_doc")}: ${widget.document.name}');
    }
  }

  void _openPdfViewer(BuildContext context) {
    if (widget.document.pdfPath == null) return;

    final Future<Uint8List> data = _decryptedBytes != null
        ? Future.value(_decryptedBytes!)
        : File(widget.document.pdfPath!).readAsBytes();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfViewerScreen(pdfData: data, title: widget.document.name),
      ),
    );
  }

  void _splitPdf(BuildContext context) {
    if (widget.document.pdfPath == null) return;

    final File file = File(widget.document.pdfPath!);

    if (_isEncrypted && !_isUnlocked) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PdfSplitScreen(initialFile: file)),
    );
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const primaryColor = Color(0xff0B3D2E);

    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(LucideIcons.chevronLeft, color: primaryColor),
        ),
        title: Text(
          widget.document.name,
          style: GoogleFonts.plusJakartaSans(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (widget.document.pdfPath != null &&
              !widget.document.pdfPath!.toLowerCase().endsWith('.docx') &&
              !_isEncrypted) ...[
            IconButton(
              onPressed: () => _splitPdf(context),
              icon: const Icon(
                LucideIcons.scissors,
                color: Colors.orange,
                size: 20,
              ),
              tooltip: l10n.translate("split_pdf_tooltip"),
            ),
            IconButton(
              onPressed: () => _openPdfViewer(context),
              icon: const Icon(LucideIcons.eye, color: Colors.blue, size: 20),
              tooltip: l10n.translate("open_pdf_tooltip"),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => _shareFile(context),
              icon: const Icon(LucideIcons.share2, color: primaryColor, size: 20),
              tooltip: l10n.translate("share_doc_tooltip"),
            ),
          ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 1400,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;

            final bool hasImages = widget.document.imagePaths.isNotEmpty;
            final bool hasText = widget.document.extractedText != null;
            final bool hasFile = widget.document.pdfPath != null;
            final bool isDocx =
                hasFile &&
                widget.document.pdfPath!.toLowerCase().endsWith('.docx');
            final bool isPdf =
                hasFile &&
                widget.document.pdfPath!.toLowerCase().endsWith('.pdf');
            final bool isWordsOnly = isDocx && !hasImages && !hasText;

            final totalPreviewItems =
                (hasText ? 1 : 0) +
                (hasImages ? widget.document.imagePaths.length : 0) +
                (isPdf && !hasImages ? _rasterizedPages.length : 0) +
                (isWordsOnly ? 1 : 0);

            if (_isEncrypted) {
              return _buildLockedUI(l10n);
            }

            if (_isRasterizing && _rasterizedPages.isEmpty) {
              return GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 450,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 24,
                  childAspectRatio: 0.75,
                ),
                itemCount: 6,
                itemBuilder: (context, index) => const DocumentCardSkeleton(),
              );
            }

            if (isWide) {
              return _buildWideLayout(l10n, totalPreviewItems, hasText, hasImages, isPdf, isWordsOnly);
            }

            return GridView.builder(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 450,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: 0.75,
              ),
              itemCount: totalPreviewItems,
              itemBuilder: (context, index) {
                return _buildItemForIndex(index, l10n, hasText, hasImages, isPdf, isWordsOnly, false);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout(
    AppLocalizations l10n,
    int totalItems,
    bool hasText,
    bool hasImages,
    bool isPdf,
    bool isWordsOnly,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Sidebar: Thumbnails
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(
                color: Colors.black.withValues(alpha: 0.05),
              ),
            ),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            itemCount: totalItems,
            itemBuilder: (context, index) {
              final isSelected = _selectedIndex == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 140,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xff0B3D2E).withValues(alpha: 0.05) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xff0B3D2E) : Colors.black.withValues(alpha: 0.05),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Opacity(
                        opacity: isSelected ? 1.0 : 0.7,
                        child: _buildItemForIndex(index, l10n, hasText, hasImages, isPdf, isWordsOnly, true),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Right Main Area: Preview
        Expanded(
          child: Container(
            color: const Color(0xffF8FAFC),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: _buildMainPreview(l10n, hasText, hasImages, isPdf, isWordsOnly),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemForIndex(int index, AppLocalizations l10n, bool hasText, bool hasImages, bool isPdf, bool isWordsOnly, bool isThumbnail) {
    if (isWordsOnly && index == 0) {
      return _buildWordPreview(l10n, isThumbnail: isThumbnail);
    }

    if (hasText && index == 0) {
      return _buildTextCard(l10n, isThumbnail: isThumbnail);
    }

    int dataIndex = index - (hasText ? 1 : 0);

    if (hasImages) {
      return _buildImageCard(
        widget.document.imagePaths[dataIndex],
        dataIndex,
        l10n,
        isThumbnail: isThumbnail,
      );
    } else if (isPdf && dataIndex < _rasterizedPages.length) {
      return _buildPdfPageCard(
        _rasterizedPages[dataIndex],
        dataIndex,
        l10n,
        isThumbnail: isThumbnail,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildMainPreview(AppLocalizations l10n, bool hasText, bool hasImages, bool isPdf, bool isWordsOnly) {
    if (isWordsOnly && _selectedIndex == 0) {
      return _buildWordPreview(l10n);
    }

    if (hasText && _selectedIndex == 0) {
      return _buildTextCard(l10n);
    }

    int dataIndex = _selectedIndex - (hasText ? 1 : 0);

    if (hasImages && dataIndex < widget.document.imagePaths.length) {
      final path = widget.document.imagePaths[dataIndex];
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
      );
    } else if (isPdf && dataIndex < _rasterizedPages.length) {
      final bytes = _rasterizedPages[dataIndex];
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildLockedUI(AppLocalizations l10n) {
    const primaryColor = Color(0xff0B3D2E);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.lock, color: primaryColor, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.translate('protected_doc'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('protected_doc_msg'),
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.grey[600],
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                onSubmitted: (_) => _unlockAndLoad(),
                decoration: InputDecoration(
                  hintText: l10n.translate('enter_password_error'),
                  filled: true,
                  fillColor: const Color(0xffF1F5F9),
                  prefixIcon: Icon(
                    LucideIcons.shieldCheck,
                    color: primaryColor.withValues(alpha: 0.5),
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _unlockAndLoad,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    l10n.translate('unlock_label'),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordPreview(AppLocalizations l10n, {bool isThumbnail = false}) {
    if (isThumbnail) {
      return Container(
        color: const Color(0xff2B579A).withValues(alpha: 0.1),
        child: const Center(child: Icon(LucideIcons.fileText, color: Color(0xff2B579A), size: 32)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xff2B579A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.fileText,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.translate('microsoft_word_label'),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xff2B579A).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.fileSearch,
                      color: Color(0xff2B579A),
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    widget.document.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xff0B3D2E),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.translate('editable_word_doc_label'),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.grey[500],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => _shareFile(context),
                      icon: const Icon(LucideIcons.share2, size: 18),
                      label: Text(l10n.translate('share_to_edit_label')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff2B579A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCard(AppLocalizations l10n, {bool isThumbnail = false}) {
    const primaryColor = Color(0xff0B3D2E);
    if (isThumbnail) {
      return Container(
        color: primaryColor.withValues(alpha: 0.05),
        child: const Center(child: Icon(LucideIcons.text, color: primaryColor, size: 32)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.text, color: primaryColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    l10n.translate('extracted_data_label'),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.copy,
                  size: 20,
                  color: primaryColor.withValues(alpha: 0.6),
                ),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: widget.document.extractedText!),
                  );
                  _showSnackBar(l10n.translate("text_copied_snack"));
                },
              ),
            ],
          ),
          const Divider(height: 32),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(
                widget.document.extractedText!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.black.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(String path, int index, AppLocalizations l10n, {bool isThumbnail = false}) {
    if (isThumbnail) {
      return Image.file(File(path), fit: BoxFit.cover, cacheWidth: 300);
    }
    return _buildBaseCard(
      child: Image.file(File(path), fit: BoxFit.contain, cacheWidth: 800),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PhotoViewScreen(imagePath: path)),
      ),
      label: "${l10n.translate("page_prefix")} ${index + 1}",
    );
  }

  Widget _buildPdfPageCard(Uint8List bytes, int index, AppLocalizations l10n, {bool isThumbnail = false}) {
    if (isThumbnail) {
      return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 300);
    }
    return _buildBaseCard(
      child: Image.memory(bytes, fit: BoxFit.contain, cacheWidth: 800),
      onTap: () => _openPdfViewer(context),
      label: "${l10n.translate("page_prefix")} ${index + 1}",
    );
  }

  Widget _buildBaseCard({
    required Widget child,
    required VoidCallback onTap,
    required String label,
  }) {
    const primaryColor = Color(0xff0B3D2E);
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  color: const Color(0xffF8FAFC),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: primaryColor,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xff0B3D2E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
