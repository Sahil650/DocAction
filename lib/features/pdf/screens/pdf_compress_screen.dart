import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../data/services/pdf_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'pdf_viewer_screen.dart';
import '../../../core/theme/app_colors.dart';

class PdfCompressScreen extends StatefulWidget {
  const PdfCompressScreen({super.key});

  @override
  State<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends State<PdfCompressScreen> {
  static const Color accentAmber = Color(0xffFFC107); // Added a common accent
  // Removed hardcoded primaryGreen to use theme's primary color
  final _pdfService = PdfService();
  final _storageService = StorageService();

  File? _sourceFile;
  Uint8List? _sourceBytes;
  Uint8List? _compressedBytes;
  bool _isProcessing = false;
  String _selectedLevel = "Recommended";

  int _originalSize = 0;
  int _compressedSize = 0;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      setState(() {
        _sourceFile = file;
        _sourceBytes = bytes;
        _originalSize = bytes.length;
        _compressedBytes = null;
        _compressedSize = 0;
      });
    }
  }

  Future<void> _pickFromLibrary() async {
    final docs = await _storageService.loadDocuments();
    final pdfDocs = docs.where((d) => d.pdfPath != null).toList();

    final l10n = AppLocalizations.of(context);
    if (!mounted) return;
    if (pdfDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.translate('no_pdfs_library'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? AppColors.darkSurface 
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.translate('select_library'),
              style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pdfDocs.length,
                itemBuilder: (context, index) {
                  final doc = pdfDocs[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? AppColors.darkSurfaceLight 
                          : const Color(0xffF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(LucideIcons.fileText,
                            color: Colors.blueAccent, size: 20),
                      ),
                      title: Text(
                        doc.name,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700, 
                            color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        final file = File(doc.pdfPath!);
                        final bytes = await file.readAsBytes();
                        setState(() {
                          _sourceFile = file;
                          _sourceBytes = bytes;
                          _originalSize = bytes.length;
                          _compressedBytes = null;
                          _compressedSize = 0;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCompress() async {
    final l10n = AppLocalizations.of(context);
    if (_sourceBytes == null) return;

    setState(() => _isProcessing = true);
    try {
      Uint8List result;

      if (_selectedLevel == "Extreme") {
        List<String> tempPaths = [];
        final tempDir = await getTemporaryDirectory();

        const dpi = 72;
        const quality = 40;

        int pageIdx = 0;
        await for (final page in Printing.raster(
          _sourceBytes!,
          dpi: dpi.toDouble(),
        )) {
          final pngBytes = await page.toPng();
          final decoded = img.decodeImage(pngBytes);
          if (decoded != null) {
            final jpgBytes = img.encodeJpg(decoded, quality: quality);
            final path = "${tempDir.path}/comp_page_$pageIdx.jpg";
            await File(path).writeAsBytes(jpgBytes);
            tempPaths.add(path);
          }
          pageIdx++;
        }

        result = await _pdfService.compileImagesToPdf(tempPaths);
        for (var p in tempPaths) {
          try {
            await File(p).delete();
          } catch (_) {}
        }
      } else {
        result = await _pdfService.compressPdf(_sourceBytes!, _selectedLevel);
      }

      if (result.length >= _sourceBytes!.length &&
          _selectedLevel != "Extreme") {
        setState(() {
          _compressedBytes = _sourceBytes;
          _compressedSize = _sourceBytes!.length;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.translate('already_optimized'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
      } else {
        setState(() {
          _compressedBytes = result;
          _compressedSize = result.length;
        });
      }
    } catch (e) {
      debugPrint("Compression Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context);
    if (_compressedBytes == null) return;

    setState(() => _isProcessing = true);
    try {
      final name =
          "${l10n.translate('optimized_doc_prefix')}_${DateTime.now().millisecondsSinceEpoch}";
      final appDir = await getApplicationDocumentsDirectory();
      final internalPath = "${appDir.path}/final_pdfs/$name.pdf";
      final internalFile = File(internalPath);
      if (!await internalFile.parent.exists()) {
        await internalFile.parent.create(recursive: true);
      }
      await internalFile.writeAsBytes(_compressedBytes!);

      await _storageService.saveDocument(
        DocumentModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          date: DateTime.now(),
          imagePaths: [],
          pdfPath: internalPath,
        ),
      );

      if (Platform.isAndroid && await Permission.storage.request().isGranted) {
        final downDir = Directory(
          "/storage/emulated/0/Download/DocumentScanner",
        );
        if (!await downDir.exists()) await downDir.create(recursive: true);
        await File("${downDir.path}/$name.pdf").writeAsBytes(_compressedBytes!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.translate('pdf_saved_msg'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xff10B981),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(_compressedBytes),
              title: name,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.translate('compress_pdf'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 600,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_sourceFile == null)
                    _buildEmptyState(l10n)
                  else ...[
                    _buildFileCard(),
                    const SizedBox(height: 32),
                    _buildLevelSelector(l10n),
                    const SizedBox(height: 32),
                    if (_compressedSize == 0)
                      _buildActionBtn(l10n)
                    else
                      _buildResultsCard(l10n),
                  ],
                ],
              ),
            ),
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? AppColors.darkSurfaceLight
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child:
                          CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.darkSurface 
                : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              if (Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child:
              Icon(LucideIcons.zap, size: 64, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 32),
        Text(
          l10n.translate('compress_pdf_title'),
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.translate('compress_hint'),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 48),
        _sourceBtn(
          l10n.translate('from_device_label'),
          LucideIcons.uploadCloud,
          const Color(0xff3B82F6),
          _pickFile,
        ),
        const SizedBox(height: 16),
        _sourceBtn(
          l10n.translate('from_library_label'),
          LucideIcons.layoutGrid,
          Theme.of(context).colorScheme.primary,
          _pickFromLibrary,
        ),
      ],
    );
  }

  Widget _sourceBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurface 
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.fileText,
                size: 28, color: Colors.redAccent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sourceFile!.path.split(Platform.isWindows ? '\\' : '/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${(_originalSize / 1024 / 1024).toStringAsFixed(2)} MB",
                  style: GoogleFonts.inter(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _sourceFile = null),
            icon: Icon(LucideIcons.x, color: Colors.grey[400], size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            l10n.translate('compression_level'),
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        _levelItem(
          "Recommended",
          l10n.translate('recommended_level'),
          l10n.translate('recommended_desc'),
          LucideIcons.checkCircle2,
          const Color(0xff10B981),
        ),
        const SizedBox(height: 12),
        _levelItem(
          "Extreme",
          l10n.translate('extreme_level'),
          l10n.translate('extreme_desc'),
          LucideIcons.zap,
          const Color(0xffF59E0B),
        ),
        const SizedBox(height: 12),
        _levelItem(
          "Basic",
          l10n.translate('basic_level'),
          l10n.translate('basic_desc'),
          LucideIcons.minimize2,
          const Color(0xff3B82F6),
        ),
      ],
    );
  }

  Widget _levelItem(
      String id, String title, String desc, IconData icon, Color color) {
    final isSelected = _selectedLevel == id;
    return InkWell(
      onTap: () => setState(() => _selectedLevel = id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected 
              ? (Theme.of(context).brightness == Brightness.dark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.05)) 
              : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.transparent),
            width: 2,
          ),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
              )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(LucideIcons.checkCircle2, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _handleCompress,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          l10n.translate('compress_pdf').toUpperCase(),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsCard(AppLocalizations l10n) {
    final bool hasSavings = _compressedSize < _originalSize;
    final percent = ((_originalSize - _compressedSize) / _originalSize * 100)
        .toStringAsFixed(0);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.darkSurface 
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              if (Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (hasSavings ? Colors.green : Colors.amber)
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasSavings ? LucideIcons.partyPopper : LucideIcons.info,
                  color: hasSavings ? Colors.green : Colors.amber,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                hasSavings
                    ? l10n
                        .translate('saved_percent_msg')
                        .replaceAll('{0}', percent)
                    : l10n.translate('already_optimized_title'),
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (hasSavings)
                Text(
                  l10n
                      .translate('pdf_now_size')
                      .replaceAll(
                        '{0}',
                        (_compressedSize / 1024 / 1024).toStringAsFixed(2),
                      ),
                  style: GoogleFonts.inter(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (!hasSavings)
                Text(
                  l10n.translate('min_size_msg'),
                  style: GoogleFonts.inter(
                    color: Colors.amber[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? AppColors.darkSurface 
                      : const Color(0xffF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric(
                      l10n.translate('before_label'),
                      "${(_originalSize / 1024 / 1024).toStringAsFixed(2)} MB",
                    ),
                    Icon(
                      LucideIcons.arrowRight,
                      color: Colors.grey[300],
                      size: 20,
                    ),
                    _metric(
                      l10n.translate('after_label'),
                      "${(_compressedSize / 1024 / 1024).toStringAsFixed(2)} MB",
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: _handleSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
            child: Text(
              hasSavings
                  ? l10n.translate('save_optimized_pdf')
                  : l10n.translate('save_anyway'),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.grey[500],
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
