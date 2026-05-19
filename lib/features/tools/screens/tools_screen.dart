import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../pdf/screens/pdf_merge_screen.dart';
import '../../pdf/screens/pdf_split_screen.dart';
import '../../pdf/screens/pdf_organize_screen.dart';
import '../../pdf/screens/pdf_compress_screen.dart';
import '../../pdf/screens/pdf_repair_screen.dart';
import '../../pdf/screens/image_to_pdf_screen.dart';
import '../../pdf/screens/text_to_pdf_screen.dart';
import '../../pdf/screens/word_to_pdf_screen.dart';
import '../../pdf/screens/pdf_to_image_screen.dart';
import '../../pdf/screens/pdf_to_word_screen.dart';
import '../../pdf/screens/pdf_edit_screen.dart';
import '../../pdf/screens/pdf_watermark_screen.dart';
import '../../pdf/screens/pdf_page_numbering_screen.dart';
import '../../pdf/screens/pdf_sign_screen.dart';
import '../../pdf/screens/pdf_password_screen.dart';
import '../../pdf/screens/pdf_unlock_screen.dart';
import '../../scanner/screens/universal_scanner_screen.dart';
import '../../scanner/models/scanner_mode.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/settings_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';

class ToolsScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  const ToolsScreen({super.key, this.onRefresh});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  final _pdfService = PdfService();
  bool _isNavigating = false;

  static const Color primaryGreen = AppColors.primary;
  static const Color accentAmber = Color(0xffFFC107);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_ToolCategory> getLocalizedCategories(AppLocalizations l10n) => [
    _ToolCategory(
      l10n.translate('organize_pdf'),
      [primaryGreen, const Color(0xff1E2760)],
      [
        _ToolItem(
          'merge',
          LucideIcons.merge,
          l10n.translate('merge_title'),
          l10n.translate('merge_sub'),
        ),
        _ToolItem(
          'split',
          LucideIcons.scissors,
          l10n.translate('split_title'),
          l10n.translate('split_sub'),
        ),
        _ToolItem(
          'reorder',
          LucideIcons.layers,
          l10n.translate('reorder_title'),
          l10n.translate('reorder_sub'),
        ),
      ],
    ),
    _ToolCategory(
      l10n.translate('optimize_pdf'),
      [primaryGreen, const Color(0xff3A4A9C)],
      [
        _ToolItem(
          'compress',
          LucideIcons.shrink,
          l10n.translate('compress_title'),
          l10n.translate('compress_sub'),
        ),
        _ToolItem(
          'repair',
          LucideIcons.wrench,
          l10n.translate('repair_title'),
          l10n.translate('repair_sub'),
        ),
      ],
    ),
    _ToolCategory(
      l10n.translate('convert_pdf'),
      [primaryGreen, const Color(0xff4555A8)],
      [
        _ToolItem(
          'img_to_pdf',
          LucideIcons.fileType,
          l10n.translate('img_to_pdf_title'),
          l10n.translate('img_to_pdf_sub'),
        ),
        _ToolItem(
          'txt_to_pdf',
          LucideIcons.type,
          l10n.translate('txt_to_pdf_title'),
          l10n.translate('txt_to_pdf_sub'),
        ),
        _ToolItem(
          'word_to_pdf',
          LucideIcons.fileText,
          l10n.translate('word_to_pdf_title'),
          l10n.translate('word_to_pdf_sub'),
        ),
        _ToolItem(
          'pdf_to_img',
          LucideIcons.image,
          l10n.translate('pdf_to_img_title'),
          l10n.translate('pdf_to_img_sub'),
        ),
        _ToolItem(
          'pdf_to_word',
          LucideIcons.fileText,
          l10n.translate('pdf_to_word'),
          l10n.translate('any_to_word_desc'),
        ),
      ],
    ),
    _ToolCategory(
      l10n.translate('edit_pdf_cat'),
      [primaryGreen, const Color(0xff5060B5)],
      [
        _ToolItem(
          'edit_pdf',
          LucideIcons.edit3,
          l10n.translate('edit_pdf_title'),
          l10n.translate('edit_pdf_sub'),
        ),
        _ToolItem(
          'watermark',
          LucideIcons.stamp,
          l10n.translate('watermark_title'),
          l10n.translate('watermark_sub'),
        ),
        _ToolItem(
          'page_num',
          LucideIcons.hash,
          l10n.translate('page_num_title'),
          l10n.translate('page_num_sub'),
        ),
      ],
    ),
    _ToolCategory(
      l10n.translate('security_cat'),
      [primaryGreen, const Color(0xff3A4A9C)],
      [
        _ToolItem(
          'password',
          LucideIcons.lock,
          l10n.translate('password_title'),
          l10n.translate('password_sub'),
        ),
        _ToolItem(
          'unlock',
          LucideIcons.unlock,
          l10n.translate('unlock_title'),
          l10n.translate('unlock_sub'),
        ),
        _ToolItem(
          'sign_pdf',
          LucideIcons.penTool,
          l10n.translate('sign_pdf_title'),
          l10n.translate('sign_pdf_sub'),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<_ToolCategory> filteredCategories = getLocalizedCategories(l10n)
        .map((cat) {
          final List<_ToolItem> filteredTools = cat.tools.where((tool) {
            final String searchLower = _searchQuery.toLowerCase();
            return tool.label.toLowerCase().contains(searchLower) ||
                tool.sub.toLowerCase().contains(searchLower) ||
                cat.title.toLowerCase().contains(searchLower);
          }).toList();
          return _ToolCategory(cat.title, cat.gradient, filteredTools);
        })
        .where((cat) => cat.tools.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ResponsiveLayout(
        maxWidth: 1200,
        child: Column(
          children: [
            _buildTopSearchBar(l10n),
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  if (filteredCategories.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptySearch(l10n),
                    )
                  else
                    ...filteredCategories.expand((cat) => [
                          // Category Header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: primaryGreen,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    cat.title.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white54
                                          : const Color(0xff1E293B)
                                              .withValues(alpha: 0.4),
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Category Grid
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                mainAxisExtent: 165,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) =>
                                    _buildToolCard(context, cat.tools[index]),
                                childCount: cat.tools.length,
                              ),
                            ),
                          ),
                        ]),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSearchBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff334155)
              : const Color(0xffF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.02),
          ),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(
                LucideIcons.search,
                color: primaryGreen.withValues(alpha: 0.5),
                size: 20,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                ),
                decoration: InputDecoration(
                  hintText: l10n.translate('search_tool_hint'),
                  hintStyle: GoogleFonts.inter(
                    color: Colors.grey[500],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = "");
                },
                icon: const Icon(LucideIcons.x, color: Colors.grey, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(BuildContext context, _ToolItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.03),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _handleToolTap(context, item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryGreen.withValues(alpha: 0.12),
                        primaryGreen.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : primaryGreen,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.sub,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySearch(AppLocalizations l10n) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Icon(LucideIcons.searchX, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            l10n.translate('no_tools_found'),
            style: GoogleFonts.inter(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToolTap(BuildContext context, _ToolItem item) async {
    Future<void> navigateTo(Widget screen) async {
      if (!mounted || _isNavigating) return;

      setState(() => _isNavigating = true);
      try {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        );
      } finally {
        if (mounted) {
          setState(() => _isNavigating = false);
          if (widget.onRefresh != null) widget.onRefresh!();
        }
      }
    }

    switch (item.key) {
      case 'merge':
        await navigateTo(const PdfMergeScreen());
        break;
      case 'split':
        await navigateTo(const PdfSplitScreen());
        break;
      case 'reorder':
        await navigateTo(const PdfOrganizeScreen());
        break;
      case 'compress':
        await navigateTo(const PdfCompressScreen());
        break;
      case 'repair':
        await navigateTo(const PdfRepairScreen());
        break;
      case 'img_to_pdf':
        await navigateTo(const ImageToPdfScreen());
        break;
      case 'word_to_pdf':
        await navigateTo(const WordToPdfScreen());
        break;
      case 'pdf_to_word':
        await navigateTo(const PdfToWordScreen());
        break;
      case 'txt_to_pdf':
        await navigateTo(const TextToPdfScreen());
        break;
      case 'edit_pdf':
        await navigateTo(const PdfEditScreen());
        break;
      case 'watermark':
        await navigateTo(const PdfWatermarkScreen());
        break;
      case 'page_num':
        await navigateTo(const PdfPageNumberingScreen());
        break;
      case 'sign_pdf':
        await _showSignPdfSelection(context);
        break;
      case 'pdf_to_img':
        await navigateTo(const PdfToImageScreen());
        break;
      case 'password':
        await navigateTo(const PdfPasswordScreen());
        break;
      case 'unlock':
        await navigateTo(const PdfUnlockScreen());
        break;
      case 'ocr':
        await navigateTo(const UniversalScannerScreen(initialMode: ScannerMode.ocr));
        break;
      default:
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${item.label} ${l10n.translate('coming_soon')}"),
            ),
          );
        }
    }
  }

  Future<void> _showSignPdfSelection(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l10n.translate('select_source'),
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            _selectionItem(
              icon: LucideIcons.fileSearch,
              title: l10n.translate('from_device'),
              sub: l10n.translate('from_device_sub'),
              color: Colors.blue,
              onTap: () => Navigator.pop(context, 'device'),
            ),
            const SizedBox(height: 16),
            _selectionItem(
              icon: LucideIcons.library,
              title: l10n.translate('from_library'),
              sub: l10n.translate('from_library_sub'),
              color: Theme.of(context).colorScheme.primary,
              onTap: () => Navigator.pop(context, 'library'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selection == null) return;

    Future<void> openSignScreen(File file) async {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfSignScreen(initialFile: file)),
      );
      widget.onRefresh?.call();
    }

    if (selection == 'device') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        await openSignScreen(File(result.files.single.path!));
      }
    } else if (selection == 'library') {
      final doc = await showModalBottomSheet<DocumentModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) =>
            DocumentSelectionSheet(title: l10n.translate('sign_pdf_title')),
      );
      if (doc != null) {
        if (doc.pdfPath != null) {
          await openSignScreen(File(doc.pdfPath!));
        } else if (doc.imagePaths.isNotEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                const Center(child: CircularProgressIndicator()),
          );
          try {
            final quality = SettingsService().pdfQuality;
            final bytes = await _pdfService.compileImagesToPdf(
              doc.imagePaths,
              quality: quality,
            );
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/temp_sign_${doc.id}.pdf');
            await tempFile.writeAsBytes(bytes);
            if (mounted) Navigator.pop(context);
            await openSignScreen(tempFile);
          } catch (e) {
            if (mounted) Navigator.pop(context);
            if (mounted) {
              final l10n = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("${l10n.translate('error_prefix')}: $e"),
                ),
              );
            }
          }
        }
      }
    }
  }

  Widget _selectionItem({
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Theme.of(context).colorScheme.primary,
        ),
      ),
      subtitle: Text(
        sub,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: Colors.grey,
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _ToolCategory {
  final String title;
  final List<Color> gradient;
  final List<_ToolItem> tools;
  _ToolCategory(this.title, this.gradient, this.tools);
}

class _ToolItem {
  final String key;
  final IconData icon;
  final String label;
  final String sub;
  _ToolItem(this.key, this.icon, this.label, this.sub);
}
