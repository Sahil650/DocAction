import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/models/document_model.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../../data/services/pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:doc_scanner_app/core/theme/app_colors.dart';

class DocumentCard extends StatelessWidget {
  static final PdfService _pdfService = PdfService();

  final DocumentModel document;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onExport;
  final VoidCallback? onMove;
  final VoidCallback? onProtect;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isGrid;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static final Map<String, int> _pageCountCache = {};

  const DocumentCard({
    super.key,
    required this.document,
    this.onDelete,
    this.onRename,
    this.onExport,
    this.onMove,
    this.onProtect,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isGrid = true,
    this.onTap,
    this.onLongPress,
  });

  Future<String> _getPageCountText(AppLocalizations l10n) async {
    // 1. Check scanned images first
    if (document.imagePaths.isNotEmpty) {
      return "${document.imagePaths.length} ${l10n.translate('pages')}";
    }

    // 2. Check cached value
    if (_pageCountCache.containsKey(document.id)) {
      final cached = _pageCountCache[document.id]!;
      if (cached == -1) return l10n.translate('protected');
      return "$cached ${l10n.translate('pages')}";
    }

    // 3. Use stored value if valid
    if (document.pageCount != null && document.pageCount! > 0) {
      return "${document.pageCount} ${l10n.translate('pages')}";
    }

    // 4. Fallback for PDF imports missing metadata
    if (document.pdfPath != null) {
      try {
        final file = File(document.pdfPath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (_pdfService.isPdfEncrypted(bytes)) {
            _pageCountCache[document.id] = -1;
            return l10n.translate('protected');
          }
          final count = _pdfService.getPdfPageCount(bytes);
          _pageCountCache[document.id] = count;
          return "$count ${l10n.translate('pages')}";
        }
      } catch (e) {
        return "PDF";
      }
    }

    return "0 ${l10n.translate('pages')}";
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth;
            final titleFontSize = (cardWidth * 0.1).clamp(12.0, 16.0);
            final subtitleFontSize = (cardWidth * 0.07).clamp(9.0, 12.0);
            final padding = (cardWidth * 0.08).clamp(8.0, 16.0);
            final headerHeight = (cardWidth * 0.9).clamp(100.0, 160.0);

            return GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                height: isGrid ? null : 100,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(isGrid ? 28 : 20),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white10 
                            : Colors.black.withValues(alpha: 0.05),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: [
                    if (Theme.of(context).brightness == Brightness.light)
                      BoxShadow(
                        blurRadius: isGrid ? 24 : 12,
                        color: Colors.black.withValues(alpha: 0.06),
                        offset: Offset(0, isGrid ? 8 : 4),
                      ),
                  ],
                ),
                child: isGrid 
                  ? _buildGridContent(context, cardWidth, titleFontSize, subtitleFontSize, padding, l10n)
                  : _buildListContent(context, cardWidth, titleFontSize, subtitleFontSize, padding, l10n),
              ),
            );
          },
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
  }

  Widget _buildGridContent(BuildContext context, double cardWidth, double titleFontSize, double subtitleFontSize, double padding, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(
                    (cardWidth * 0.1).clamp(10.0, 20.0),
                  ),
                ),
                child: _buildFileTypeIcon(cardWidth, l10n),
              ),
              if (document.pdfPath != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: document.pdfPath!.toLowerCase().endsWith('.docx')
                            ? [const Color(0xff2B579A), const Color(0xff1E3A63)]
                            : [const Color(0xffE11D48), const Color(0xff9F1239)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      document.pdfPath!.toLowerCase().endsWith('.docx')
                          ? "DOCX"
                          : "PDF",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              if (isSelectionMode)
                Positioned(
                  top: cardWidth * 0.04,
                  left: cardWidth * 0.04,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xff0B3D2E)
                          : Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : Icons.add_rounded,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xff0B3D2E),
                        size: (cardWidth * 0.12).clamp(14.0, 18.0),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: padding,
              vertical: padding * 0.5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: padding * 0.2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        document.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white 
                              : const Color(0xff0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    _buildPopupMenu(context, cardWidth, l10n),
                  ],
                ),
                FutureBuilder<String>(
                  future: _getPageCountText(l10n),
                  initialData:
                      "${document.pageCount ?? document.imagePaths.length} ${l10n.translate('pages')}",
                  builder: (context, snapshot) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return Text(
                      "${snapshot.data} • ${DateFormat('MMM dd').format(document.date)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: isDark ? AppColors.darkTextSecondary : const Color(0xff64748B),
                        fontSize: subtitleFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListContent(BuildContext context, double cardWidth, double titleFontSize, double subtitleFontSize, double padding, AppLocalizations l10n) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildFileTypeIcon(cardWidth * 0.8, l10n),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                FutureBuilder<String>(
                  future: _getPageCountText(l10n),
                  initialData: "${document.pageCount ?? document.imagePaths.length} ${l10n.translate('pages')}",
                  builder: (context, snapshot) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return Text(
                      "${snapshot.data} • ${DateFormat('MMM dd, yyyy').format(document.date)}",
                      style: GoogleFonts.plusJakartaSans(
                        color: isDark ? AppColors.darkTextSecondary : const Color(0xff64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (isSelectionMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xff0B3D2E) : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSelected ? Icons.check : Icons.add,
                size: 20,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          )
        else
          _buildPopupMenu(context, cardWidth, l10n),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildPopupMenu(BuildContext context, double cardWidth, AppLocalizations l10n) {
    final iconSize = (cardWidth * 0.12).clamp(14.0, 20.0);
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: iconSize,
        color: Theme.of(context).colorScheme.primary,
      ),
      onSelected: (value) {
        if (value == 'rename') {
          onRename?.call();
        } else if (value == 'export') {
          onExport?.call();
        } else if (value == 'move') {
          onMove?.call();
        } else if (value == 'delete') {
          onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(LucideIcons.edit3, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 12),
              Text(
                l10n.translate('rename'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              const Icon(LucideIcons.share, size: 18, color: Colors.greenAccent),
              const SizedBox(width: 12),
              Text(
                l10n.translate('export'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'move',
          child: Row(
            children: [
              const Icon(LucideIcons.folderInput, size: 18, color: Colors.orangeAccent),
              const SizedBox(width: 12),
              Text(
                l10n.translate('move'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(LucideIcons.trash2, size: 18, color: Colors.redAccent),
              const SizedBox(width: 12),
              Text(
                l10n.translate('delete'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderIcon(double height) {
    return Container(
      height: height,
      color: Colors.grey.withValues(alpha: 0.1),
      child: const Center(
        child: Icon(Icons.description, size: 40, color: Colors.grey),
      ),
    );
  }

  Widget _buildFileTypeIcon(double cardWidth, AppLocalizations l10n) {
    return FutureBuilder<bool>(
      future: _checkIfEncrypted(),
      builder: (context, snapshot) {
        final isEncrypted = snapshot.data ?? false;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        IconData iconData = LucideIcons.fileText;
        Color accentColor = const Color(0xff0B3D2E);
        String label = l10n.translate('document_tag');

        if (isEncrypted) {
          iconData = LucideIcons.lock;
          accentColor = const Color(0xffE11D48);
          label = l10n.translate('encrypted_tag');
        } else if (document.pdfPath != null) {
          if (document.pdfPath!.toLowerCase().endsWith('.docx')) {
            iconData = LucideIcons.fileText;
            accentColor = const Color(0xff2B579A);
            label = "DOCX";
          } else {
            iconData = LucideIcons.fileText;
            accentColor = const Color(0xffE11D48);
            label = "PDF";
          }
        } else if (document.imagePaths.isNotEmpty) {
          iconData = LucideIcons.camera;
          accentColor = const Color(0xff0B3D2E);
          label = l10n.translate('scan_tag');
        }

        // If it's a scan with images, show the first image as thumbnail
        if (!isEncrypted && document.imagePaths.isNotEmpty) {
          return SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.file(
              File(document.thumbnailPaths?.isNotEmpty == true
                  ? document.thumbnailPaths!.first
                  : document.imagePaths.first),
              fit: BoxFit.cover,
              cacheWidth: 400, // Forces Flutter to decode massive images down to a smaller size, saving huge amounts of RAM
              errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(cardWidth, iconData, accentColor, label, isDark),
            ),
          );
        }

        return _buildFallbackIcon(cardWidth, iconData, accentColor, label, isDark);
      },
    );
  }

  Widget _buildFallbackIcon(double cardWidth, IconData iconData, Color accentColor, String label, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark 
            ? [accentColor.withValues(alpha: 0.15), accentColor.withValues(alpha: 0.05)]
            : [accentColor.withValues(alpha: 0.08), accentColor.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.05,
            child: Icon(iconData, size: cardWidth * 0.8, color: accentColor),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white70,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  iconData,
                  color: accentColor,
                  size: (cardWidth * 0.22).clamp(28.0, 48.0),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: (cardWidth * 0.045).clamp(8.0, 10.0),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Future<bool> _checkIfEncrypted() async {
    if (document.pdfPath == null) return false;
    final file = File(document.pdfPath!);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    return _pdfService.isPdfEncrypted(bytes);
  }
}
