import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/settings_service.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

enum WatermarkType { text, image }

class PdfWatermarkScreen extends StatefulWidget {
  const PdfWatermarkScreen({super.key});

  @override
  State<PdfWatermarkScreen> createState() => _PdfWatermarkScreenState();
}

class _PdfWatermarkScreenState extends State<PdfWatermarkScreen> {
  final PdfService _pdfService = PdfService();
  final StorageService _storageService = StorageService();
  AppLocalizations get l10n => AppLocalizations.of(context);

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _watermarkCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _watermarkCtrl.text = l10n.translate('confidential_label');
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _watermarkCtrl.dispose();
    super.dispose();
  }

  File? _selectedPdf;
  Uint8List? _pdfBytes;
  Uint8List? _previewBackground;
  double _pdfAspectRatio = 1 / 1.414;
  
  bool _isLoading = false;
  bool _isSaving = false;

  WatermarkType _type = WatermarkType.text;
  
  // Text state
  late TextEditingController _watermarkCtrl;
  Color _selectedColor = AppColors.primary;
  
  // Image state
  Uint8List? _watermarkImageBytes;

  // Shared state
  double _opacity = 0.3;
  WatermarkPosition _position = WatermarkPosition.diagonalCenter;
  double _textSize = 60.0;
  double _imageScale = 0.5;

  static const Color primaryGreen = AppColors.primary;
  static const Color accentAmber = Color(0xffFFC107);

  final List<Color> _colors = [
    AppColors.primary,
    const Color(0xffFFC107),
    Colors.red,
    Colors.black,
    Colors.blue,
    Colors.grey,
  ];

  Future<void> _pickDocument() async {
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
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result != null && result.files.single.path != null) {
        await _loadPdfFile(File(result.files.single.path!));
      }
    } else {
      final doc = await showModalBottomSheet<DocumentModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DocumentSelectionSheet(title: l10n.translate('add_watermark')),
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
            final tempFile = File('${tempDir.path}/temp_wm_${doc.id}.pdf');
            await tempFile.writeAsBytes(bytes);
            await _loadPdfFile(tempFile);
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('error_preparing').replaceAll('{0}', e.toString()))));
          } finally {
            setState(() => _isLoading = false);
          }
        }
      }
    }
  }

  Future<void> _loadPdfFile(File file) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final preview = await _pdfService.rasterizePdfPage(bytes, pageIndex: 0, dpi: 100);
      if (preview == null) throw Exception("Could not rasterize PDF for preview");
      final img = await decodeImageFromList(preview);
      
      setState(() {
        _selectedPdf = file;
        _pdfBytes = bytes;
        _previewBackground = preview;
        _pdfAspectRatio = img.width / img.height;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('error_loading_pdf').replaceAll('{0}', e.toString()))));
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

  Future<void> _pickWatermarkImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      final bytes = await File(result.files.single.path!).readAsBytes();
      setState(() {
        _watermarkImageBytes = bytes;
        _type = WatermarkType.image;
      });
    }
  }

  Future<void> _applyAndSave() async {
    if (_pdfBytes == null) return;
    
    final String text = _watermarkCtrl.text.trim();
    if (_type == WatermarkType.text && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('watermark_empty'))));
      return;
    }
    if (_type == WatermarkType.image && _watermarkImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('select_wm_image'))));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final finalBytes = await _pdfService.addWatermarkToPdf(
        _pdfBytes!,
        text: _type == WatermarkType.text ? text : null,
        imageBytes: _type == WatermarkType.image ? _watermarkImageBytes : null,
        position: _position,
        color: _selectedColor,
        opacity: _opacity,
        textSize: _textSize,
        imageScale: _imageScale,
      );

      final appDocDir = await getApplicationDocumentsDirectory();
      final fileName = "${l10n.translate('watermarked_doc_prefix')}_${DateTime.now().millisecondsSinceEpoch}.pdf";
      final filePath = p.join(appDocDir.path, fileName);
      await File(filePath).writeAsBytes(finalBytes);

      await _storageService.saveDocumentNamed(
        name: _selectedPdf != null ? "WM_${p.basename(_selectedPdf!.path)}" : l10n.translate('add_watermark'),
        imagePaths: [],
        pdfPath: filePath,
        pageCount: _pdfService.getPdfPageCount(finalBytes),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('saved_library_msg'))));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('error_generating_wm').replaceAll('{0}', e.toString()))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('add_watermark'),
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
            icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_pdfBytes != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _applyAndSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.check, size: 16),
                label: Text(l10n.translate('save_label')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentAmber,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveLayout(
          maxWidth: 1000,
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
              : _pdfBytes == null
                  ? _buildEmptyState()
                  : _buildEditor(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                  shape: BoxShape.circle),
              child: Icon(LucideIcons.stamp, size: 64, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.translate('stamp_doc'),
              style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.primary, fontSize: 24, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('stamp_hint'),
              style: GoogleFonts.inter(
                  color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600], fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _pickDocument,
                icon: const Icon(LucideIcons.filePlus),
                label: Text(l10n.translate('select_pdf_file')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF1F5F9),
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: AspectRatio(
              aspectRatio: _pdfAspectRatio,
              child: Container(
                decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      if (Theme.of(context).brightness == Brightness.light)
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10))
                    ]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_previewBackground != null)
                        Positioned.fill(
                            child: Image.memory(_previewBackground!,
                                fit: BoxFit.contain)),
                      Positioned.fill(
                        child: _buildPreviewOverlay(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildSettingsPanel(),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5))
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: _buildTypeToggle(
                          WatermarkType.text, l10n.translate('text_label'), LucideIcons.type, l10n)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildTypeToggle(
                          WatermarkType.image, l10n.translate('image_label'), LucideIcons.image, l10n)),
                ],
              ),
              const SizedBox(height: 24),
              if (_type == WatermarkType.text) ...[
                TextField(
                  controller: _watermarkCtrl,
                  onChanged: (v) => setState(() {}),
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                  decoration: InputDecoration(
                    labelText: l10n.translate('watermark_text_hint'),
                    labelStyle: GoogleFonts.inter(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF8FAFC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none),
                    prefixIcon: Icon(LucideIcons.pencil,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _colors
                        .map((c) => GestureDetector(
                              onTap: () => setState(() => _selectedColor = c),
                              child: Container(
                                margin: const EdgeInsets.only(right: 12),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: _selectedColor == c
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.transparent,
                                      width: 2),
                                  boxShadow: [
                                    if (_selectedColor == c)
                                      BoxShadow(
                                          color: c.withOpacity(0.3),
                                          blurRadius: 8)
                                  ],
                                ),
                                child: _selectedColor == c
                                    ? const Icon(Icons.check,
                                        size: 18, color: Colors.white)
                                    : null,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _pickWatermarkImage,
                  icon: const Icon(LucideIcons.imagePlus),
                  label: Text(_watermarkImageBytes == null
                      ? l10n.translate('select_logo')
                      : l10n.translate('change_image')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF8FAFC),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.1))),
                  ),
                ),
                if (_watermarkImageBytes != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_watermarkImageBytes!,
                          height: 60, fit: BoxFit.contain),
                    ),
                  ),
                ]
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildControlColumn(
                      l10n.translate('position_label'),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<WatermarkPosition>(
                          dropdownColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
                          isExpanded: true,
                          value: _position,
                          style: GoogleFonts.inter(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                          onChanged: (v) => setState(() => _position = v!),
                          items: [
                            DropdownMenuItem(
                                value: WatermarkPosition.diagonalCenter,
                                child: Text(l10n.translate('diagonal'))),
                            DropdownMenuItem(
                                value: WatermarkPosition.horizontalCenter,
                                child: Text(l10n.translate('center_label'))),
                            DropdownMenuItem(
                                value: WatermarkPosition.topLeft,
                                child: Text(l10n.translate('top_l'))),
                            DropdownMenuItem(
                                value: WatermarkPosition.topRight,
                                child: Text(l10n.translate('top_r'))),
                            DropdownMenuItem(
                                value: WatermarkPosition.bottomLeft,
                                child: Text(l10n.translate('bottom_l'))),
                            DropdownMenuItem(
                                value: WatermarkPosition.bottomRight,
                                child: Text(l10n.translate('bottom_r'))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildControlColumn(
                      _type == WatermarkType.text ? l10n.translate('size_label') : l10n.translate('scale_label'),
                      _buildMiniSlider(
                        _type == WatermarkType.text ? _textSize : _imageScale,
                        _type == WatermarkType.text ? 20.0 : 0.1,
                        _type == WatermarkType.text ? 120.0 : 1.0,
                        (v) => setState(() => _type == WatermarkType.text
                            ? _textSize = v
                            : _imageScale = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildControlColumn(
                "${l10n.translate('opacity_label')} (${(_opacity * 100).round()}%)",
                Slider(
                  value: _opacity,
                  min: 0.1,
                  max: 1.0,
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  onChanged: (v) => setState(() => _opacity = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle(WatermarkType type, String label, IconData icon, AppLocalizations l10n) {
    final bool isSelected = _type == type;
    return GestureDetector(
      onTap: () => setState(() => _type = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF8FAFC)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlColumn(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF8FAFC), borderRadius: BorderRadius.circular(12)),
          child: child,
        ),
      ],
    );
  }

  Widget _buildMiniSlider(double val, double min, double max, ValueChanged<double> onChanged) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: Theme.of(context).colorScheme.primary,
        inactiveTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        thumbColor: Theme.of(context).colorScheme.primary,
      ),
      child: Slider(value: val, min: min, max: max, onChanged: onChanged),
    );
  }

  Widget _buildPreviewOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double margin = constraints.maxWidth * 0.05;
        Widget content;
        if (_type == WatermarkType.text) {
          content = Text(
            _watermarkCtrl.text,
            style: TextStyle(
              color: _selectedColor,
              fontSize: _textSize * (constraints.maxWidth / 600) * 0.5,
              fontWeight: FontWeight.bold,
            ),
          );
        } else {
          if (_watermarkImageBytes == null) return const SizedBox.shrink();
          double baseWidth = (_position == WatermarkPosition.diagonalCenter || _position == WatermarkPosition.horizontalCenter) 
              ? constraints.maxWidth * 0.5 
              : constraints.maxWidth * 0.25;
          content = Image.memory(_watermarkImageBytes!, width: baseWidth * _imageScale, fit: BoxFit.contain);
        }
        
        content = Opacity(opacity: _opacity, child: content);

        switch (_position) {
          case WatermarkPosition.diagonalCenter:
            return Center(child: Transform.rotate(angle: -0.785398, child: content));
          case WatermarkPosition.horizontalCenter:
            return Center(child: content);
          case WatermarkPosition.topLeft:
            return Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.all(margin), child: content));
          case WatermarkPosition.topRight:
            return Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(margin), child: content));
          case WatermarkPosition.bottomLeft:
            return Align(alignment: Alignment.bottomLeft, child: Padding(padding: EdgeInsets.all(margin), child: content));
          case WatermarkPosition.bottomRight:
            return Align(alignment: Alignment.bottomRight, child: Padding(padding: EdgeInsets.all(margin), child: content));
        }
      }
    );
  }
}
