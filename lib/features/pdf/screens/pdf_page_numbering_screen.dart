import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/settings_service.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class PdfPageNumberingScreen extends StatefulWidget {
  const PdfPageNumberingScreen({super.key});

  @override
  State<PdfPageNumberingScreen> createState() => _PdfPageNumberingScreenState();
}

class _PdfPageNumberingScreenState extends State<PdfPageNumberingScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  AppLocalizations get l10n => AppLocalizations.of(context);

  File? _selectedPdf;
  Uint8List? _pdfBytes;
  Uint8List? _previewImage;
  double _pdfAspectRatio = 1 / 1.414;
  int _totalPages = 0;

  bool _isLoading = false;
  bool _isSaving = false;

  // --- User Settings ---
  PageNumberPosition _position = PageNumberPosition.bottomCenter;
  String _format = "Page {n} of {total}";
  Color _color = Colors.black;
  double _fontSize = 12.0;
  bool _skipFirstPage = false;

  static const _brandColor = AppColors.primary;

  final _formats = const [
    "Page {n} of {total}",
    "{n} / {total}",
    "Page {n}",
    "{n}",
  ];

  final _colors = const [
    Color(0xFF000000),
    Color(0xFF555555),
    Color(0xFF1565C0),
    Color(0xFFD32F2F),
    Color(0xFF2E7D32),
  ];

  // ─── File Picking ─────────────────────────────────────────────

  Future<void> _pickSource() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12, borderRadius: BorderRadius.circular(2))),
              Text(l10n.translate('select_source'), style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 32),
               _selectionItem(icon: LucideIcons.fileSearch, title: l10n.translate('select_device'), sub: l10n.translate('select_device_sub'), color: Colors.blue, onTap: () => Navigator.pop(context, 'device')),
              const SizedBox(height: 16),
              _selectionItem(icon: LucideIcons.library, title: l10n.translate('select_app'), sub: l10n.translate('select_app_sub'), color: Theme.of(context).colorScheme.primary, onTap: () => Navigator.pop(context, 'library')),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (selection == null) return;

    if (selection == 'device') {
      await _pickPdf();
    } else {
      final doc = await showModalBottomSheet<DocumentModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DocumentSelectionSheet(title: l10n.translate('page_numbering')),
      );
      if (doc != null) {
        if (doc.pdfPath != null) {
          await _loadPdfFile(File(doc.pdfPath!));
        } else if (doc.imagePaths.isNotEmpty) {
          setState(() => _isLoading = true);
          try {
            final quality = SettingsService().pdfQuality;
            final bytes = await _pdfService.compileImagesToPdf(doc.imagePaths, quality: quality);
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/temp_num_${doc.id}.pdf');
            await tempFile.writeAsBytes(bytes);
            await _loadPdfFile(tempFile);
          } catch (e) {
            _showSnack("${l10n.translate('error_prefix')}: $e");
          } finally {
            setState(() => _isLoading = false);
          }
        }
      }
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    await _loadPdfFile(File(result.files.single.path!));
  }

  Future<void> _loadPdfFile(File file) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final count = _pdfService.getPdfPageCount(bytes);
      final preview = await _pdfService.rasterizePdfPage(bytes, pageIndex: 0, dpi: 100);

      if (preview == null) throw Exception("Cannot preview this PDF");
      final decoded = await decodeImageFromList(preview);

      setState(() {
        _selectedPdf = file;
        _pdfBytes = bytes;
        _previewImage = preview;
        _pdfAspectRatio = decoded.width / decoded.height;
        _totalPages = count;
      });
    } catch (e) {
      _showSnack("${l10n.translate('error_prefix')}: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _selectionItem({required IconData icon, required String title, required String sub, required Color color, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.withOpacity(0.1))),
      leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      subtitle: Text(sub, style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600])),
      trailing: const Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey),
    );
  }

  // ─── Save ─────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_pdfBytes == null) return;
    
    // Show rename dialog first
    final defaultName = _selectedPdf != null 
        ? "Num_${p.basenameWithoutExtension(_selectedPdf!.path)}" 
        : l10n.translate('numbered_doc_prefix');
    
    final TextEditingController nameCtrl = TextEditingController(text: defaultName);
    
    final customName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        title: Text(l10n.translate('save_to_library'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.translate('assign_converted_name_hint'), style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: l10n.translate('filename_hint'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.translate('cancel_btn'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
            child: Text(l10n.translate('save_label')),
          ),
        ],
      ),
    );

    if (customName == null || customName.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final numbered = await _pdfService.addPageNumbersToPdf(
        _pdfBytes!,
        format: _format,
        position: _position,
        color: _color,
        fontSize: _fontSize,
        startNumber: 1,
        skipFirstPage: _skipFirstPage,
      );

      final dir = await getApplicationDocumentsDirectory();
      final name = "${customName}_${DateTime.now().millisecondsSinceEpoch}.pdf";
      final path = p.join(dir.path, name);
      await File(path).writeAsBytes(numbered);

      await _storageService.saveDocumentNamed(
        name: customName,
        imagePaths: [],
        pdfPath: path,
        pageCount: _pdfService.getPdfPageCount(numbered),
      );

      if (mounted) {
        _showSnack(l10n.translate('numbered_pdf_saved'), success: true);
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack("${l10n.translate('error_prefix')}: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? _brandColor : null,
    ));
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
            : _pdfBytes == null
                ? _buildEmpty()
                : _buildEditor(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      surfaceTintColor: Theme.of(context).appBarTheme.surfaceTintColor,
      elevation: 0.5,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.primary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        l10n.translate('page_numbering'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      actions: [
        if (_pdfBytes != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(l10n.translate('apply_label')),
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Empty State ──────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.hash, size: 48, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.translate('add_page_numbers'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('page_numbering_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pickSource,
              icon: const Icon(LucideIcons.filePlus),
              label: Text(l10n.translate('select_pdf_file')),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Editor ───────────────────────────────────────────────────

  Widget _buildEditor() {
    return Column(
      children: [
        // ── Preview area: full page always visible, no scrolling ──
        Expanded(
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xFFEBEDF0),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: AspectRatio(
                aspectRatio: _pdfAspectRatio,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      if (Theme.of(context).brightness == Brightness.light)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        if (_previewImage != null)
                          Positioned.fill(
                            child: Image.memory(_previewImage!, fit: BoxFit.fill),
                          ),
                        Positioned.fill(child: _buildOverlay()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Settings Panel ──
        _buildSettings(),
      ],
    );
  }

  // ─── Preview Overlay ──────────────────────────────────────────

  Widget _buildOverlay() {
    if (_skipFirstPage) {
      return Container(
        color: Colors.white.withOpacity(0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.eyeOff, size: 28, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[400]),
              const SizedBox(height: 6),
              Text(
                l10n.translate('cover_page_no_number'),
                style: TextStyle(fontSize: 11, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500], fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final text = _format
        .replaceAll("{n}", "1")
        .replaceAll("{total}", _totalPages.toString());

    return LayoutBuilder(builder: (ctx, box) {
      final label = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: _color,
            fontSize: _fontSize * (box.maxWidth / 400).clamp(0.6, 1.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      final m = box.maxWidth * 0.05;

      Alignment align;
      switch (_position) {
        case PageNumberPosition.topLeft:
          align = Alignment.topLeft;
          break;
        case PageNumberPosition.topCenter:
          align = Alignment.topCenter;
          break;
        case PageNumberPosition.topRight:
          align = Alignment.topRight;
          break;
        case PageNumberPosition.bottomLeft:
          align = Alignment.bottomLeft;
          break;
        case PageNumberPosition.bottomCenter:
          align = Alignment.bottomCenter;
          break;
        case PageNumberPosition.bottomRight:
          align = Alignment.bottomRight;
          break;
      }

      return Padding(
        padding: EdgeInsets.all(m),
        child: Align(alignment: align, child: label),
      );
    });
  }

  // ─── Settings Panel ───────────────────────────────────────────

  Widget _buildSettings() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.45,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Position selector ──
                _buildPositionSection(),
                const SizedBox(height: 20),

                // ── Format chips ──
                _label(l10n.translate('format_label')),
                const SizedBox(height: 8),
                _buildFormatChips(),
                const SizedBox(height: 20),

                // ── Color + Size row ──
                _buildStyleRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Position Section ─────────────────────────────────────────

  Widget _buildPositionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label(l10n.translate('position_label')),
            const Spacer(),
            _buildSkipToggle(),
          ],
        ),
        const SizedBox(height: 10),
        _buildPositionPicker(),
      ],
    );
  }

  Widget _buildPositionPicker() {
    // 3x2 mini-page grid
    final labels = [
      [l10n.translate('top_left'), l10n.translate('top_center'), l10n.translate('top_right')],
      [l10n.translate('bottom_left'), l10n.translate('bottom_center'), l10n.translate('bottom_right')],
    ];
    const positions = [
      [PageNumberPosition.topLeft, PageNumberPosition.topCenter, PageNumberPosition.topRight],
      [PageNumberPosition.bottomLeft, PageNumberPosition.bottomCenter, PageNumberPosition.bottomRight],
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: List.generate(2, (row) {
          return Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 4),
            child: Row(
              children: List.generate(3, (col) {
                final pos = positions[row][col];
                final sel = _position == pos;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: col == 0 ? 0 : 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _position = pos),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 38,
                        decoration: BoxDecoration(
                          color: sel ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFE0E0E0)),
                            width: sel ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          labels[row][col],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: sel ? Theme.of(context).colorScheme.onPrimary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600]),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSkipToggle() {
    return GestureDetector(
      onTap: () => setState(() => _skipFirstPage = !_skipFirstPage),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _skipFirstPage ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xFFF4F5F7)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _skipFirstPage ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 14,
              color: _skipFirstPage ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey),
            ),
            const SizedBox(width: 5),
            Text(
              l10n.translate('skip_cover'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _skipFirstPage ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Format Chips ─────────────────────────────────────────────

  Widget _buildFormatChips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _formats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _formats[i];
          final sel = _format == f;
          final preview = f
              .replaceAll("{n}", "1")
              .replaceAll("{total}", _totalPages > 0 ? "$_totalPages" : "10");
          return GestureDetector(
            onTap: () => setState(() => _format = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Colors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFE0E0E0)),
                ),
              ),
              child: Text(
                preview,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sel ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Style Row (Color + Size) ────────────────────────────────

  Widget _buildStyleRow() {
    return Row(
      children: [
        // Color circles
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(l10n.translate('color_label')),
              const SizedBox(height: 8),
              Row(
                children: _colors.map((c) {
                  final sel = _color == c;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[300]!),
                          width: sel ? 2.5 : 1,
                        ),
                      ),
                      child: sel
                          ? Icon(Icons.check, size: 13,
                              color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // Font size
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(l10n.translate('size_label')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${_fontSize.toInt()}pt",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 70,
                    height: 24,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        thumbColor: Theme.of(context).colorScheme.primary,
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[300],
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _fontSize,
                        min: 8,
                        max: 24,
                        onChanged: (v) => setState(() => _fontSize = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    );
  }
}
