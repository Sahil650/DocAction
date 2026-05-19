import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../data/services/pdf_service.dart';
import '../../scanner/screens/universal_scanner_screen.dart';
import '../../scanner/models/scanner_mode.dart';
import 'pdf_viewer_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../core/theme/app_colors.dart';


class PdfMergeScreen extends StatefulWidget {
  const PdfMergeScreen({super.key});

  @override
  State<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _PdfMergeScreenState extends State<PdfMergeScreen> {
  // Removed hardcoded primaryGreen to use theme's primary color
  final _pdfService = PdfService();
  final _storageService = StorageService();
  final ScrollController _scrollController = ScrollController();
  final List<MergeItem> _mergePages = [];
  bool _isProcessing = false;


  Future<void> _addExternalFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: true,
      );

      if (result != null) {
        setState(() {
          for (var file in result.files) {
            if (file.path != null) {
              if (file.extension?.toLowerCase() == 'pdf') {
                // Future: extract pages from PDF
              } else {
                _mergePages.add(
                  MergeItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString() +
                        file.path!,
                    path: file.path!,
                  ),
                );
              }
            }
          }
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint("File Picker Error: $e");
    }
  }

  Future<void> _addInternalScan() async {
    final l10n = AppLocalizations.of(context);
    final DocumentModel? doc = await showModalBottomSheet<DocumentModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentSelectionSheet(
        title: l10n.translate('add_from_scan'),
      ),
    );
    
    if (doc != null) {
      setState(() {
        for (var path in doc.imagePaths) {
          _mergePages.add(
            MergeItem(
              id: DateTime.now().millisecondsSinceEpoch.toString() + path,
              path: path,
            ),
          );
        }
      });
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _addFromCamera() async {
    final List<String>? images = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const UniversalScannerScreen(
          initialMode: ScannerMode.document,
          isPickerMode: true,
        ),
      ),
    );

    if (images != null) {
      setState(() {
        for (var path in images) {
          _mergePages.add(
            MergeItem(
              id: DateTime.now().millisecondsSinceEpoch.toString() + path,
              path: path,
            ),
          );
        }
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showPreview(int initialIndex) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: _mergePages.length,
              controller: PageController(initialPage: initialIndex),
              itemBuilder: (context, index) => InteractiveViewer(
                child: Center(
                  child: Image.file(
                    File(_mergePages[index].path),
                    fit: BoxFit.contain,
                    cacheWidth: 800,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n
                        .translate('page_of')
                        .replaceAll('{0}', (initialIndex + 1).toString())
                        .replaceAll('{1}', _mergePages.length.toString()),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleFinalize() async {
    if (_mergePages.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(
      text:
          "${l10n.translate('merged_doc_prefix')}_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}",
    );

    final String? customTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          l10n.translate('finalize_pdf'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('finalize_hint'),
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: nameController,
              autofocus: true,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark 
                    ? AppColors.darkSurfaceLight 
                    : const Color(0xffF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                hintText: l10n.translate('filename_hint'),
                prefixIcon: Icon(
                  LucideIcons.fileEdit, 
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                hintStyle: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('back_label'),
              style: GoogleFonts.inter(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              l10n.translate('save_view'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (customTitle == null || customTitle.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final List<String> paths = _mergePages.map((m) => m.path).toList();
      final bytes = await _pdfService.compileImagesToPdf(paths);

      final appDir = await getApplicationDocumentsDirectory();
      final pdfDir = Directory("${appDir.path}/final_pdfs");
      if (!await pdfDir.exists()) await pdfDir.create(recursive: true);

      final internalPath = "${pdfDir.path}/$customTitle.pdf";
      await File(internalPath).writeAsBytes(bytes);

      String? publicPath;
      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (status.isGranted) {
          final downDir = Directory(
            "/storage/emulated/0/Download/DocumentScanner",
          );
          if (!await downDir.exists()) await downDir.create(recursive: true);
          publicPath = "${downDir.path}/$customTitle.pdf";
          await File(publicPath).writeAsBytes(bytes);
        }
      } else if (Platform.isIOS) {
        publicPath = internalPath;
      }

      final doc = DocumentModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: customTitle,
        date: DateTime.now(),
        imagePaths: [_mergePages.first.path],
        pdfPath: internalPath,
      );
      await _storageService.saveDocument(doc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isAndroid && publicPath != null
                  ? l10n.translate('saved_downloads')
                  : l10n.translate('saved_library'),
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
              pdfData: Future.value(bytes),
              title: customTitle,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Merge/Save Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('error_saving')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          l10n.translate('page_organizer'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_mergePages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: () => setState(() => _mergePages.clear()),
                icon: const Icon(LucideIcons.trash2,
                    color: Colors.redAccent, size: 20),
              ),
            ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _mergePages.isEmpty
                      ? _buildEmptyState()
                      : _buildPageGrid(),
                ),
                _buildControlPanel(),
              ],
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
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('arrange_pages'),
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.translate('reorder_hint'),
            style: GoogleFonts.inter(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
            child: Icon(
              LucideIcons.bookOpen,
              size: 64,
              color: Colors.grey[200],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.translate('start_adding_pages'),
            style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              l10n.translate('add_pages_hint'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount = (constraints.maxWidth / 120).floor().clamp(
          3,
          8,
        );
        return ReorderableGridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          dragStartDelay: const Duration(milliseconds: 100),
          physics: const BouncingScrollPhysics(),
          itemCount: _mergePages.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.78,
          ),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              final item = _mergePages.removeAt(oldIndex);
              _mergePages.insert(newIndex, item);
            });
            HapticFeedback.selectionClick();
          },
          itemBuilder: (context, index) {
            return _buildPageCard(index);
          },
        );
      },
    );
  }

  Widget _buildPageCard(int index) {
    final item = _mergePages[index];
    return Container(
      key: ValueKey(item.id),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurfaceLight 
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.darkBorder 
              : Colors.black.withOpacity(0.04),
        ),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _showPreview(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(item.path),
                fit: BoxFit.cover,
                cacheWidth: 250,
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.2),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      )
                    ],
                  ),
                  child: Text(
                    "${index + 1}",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => setState(() => _mergePages.removeAt(index)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        )
                      ],
                    ),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.redAccent : Colors.redAccent,
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

  Widget _buildControlPanel() {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurface 
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildActionButton(
                    icon: LucideIcons.camera,
                    label: l10n.translate('camera_label'),
                    color: const Color(0xff3B82F6),
                    onTap: _addFromCamera,
                  ),
                  const SizedBox(width: 12),
                  _buildActionButton(
                    icon: LucideIcons.library,
                    label: l10n.translate('scans_label'),
                    color: const Color(0xff10B981),
                    onTap: _addInternalScan,
                  ),
                  const SizedBox(width: 12),
                  _buildActionButton(
                    icon: LucideIcons.filePlus,
                    label: l10n.translate('files_label'),
                    color: const Color(0xffF59E0B),
                    onTap: _addExternalFile,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _mergePages.isEmpty ? null : _handleFinalize,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor: Theme.of(context).brightness == Brightness.dark 
                        ? AppColors.darkBorder 
                        : const Color(0xffF1F5F9),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    l10n.translate('finalize_doc'),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.5,
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MergeItem {
  final String id;
  final String path;
  MergeItem({required this.id, required this.path});
}
