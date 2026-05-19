import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/models/document_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/app_localizations.dart';

class DocumentListTile extends StatelessWidget {
  final DocumentModel document;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onExport;
  final VoidCallback? onMove;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const DocumentListTile({
    super.key,
    required this.document,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onDelete,
    this.onRename,
    this.onExport,
    this.onMove,
    required this.onTap,
    required this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected 
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) 
          : isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected 
            ? Theme.of(context).colorScheme.primary 
            : isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.all(8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: (document.thumbnailPaths?.isNotEmpty == true || document.imagePaths.isNotEmpty)
                ? Image.file(
                    File(document.thumbnailPaths?.isNotEmpty == true ? document.thumbnailPaths!.first : document.imagePaths.first),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    cacheWidth: 150, // Optimize memory for 56x56 logical pixel widget
                  )
                : Container(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                    child: Icon(
                      LucideIcons.fileText, 
                      color: isDark ? AppColors.darkTextSecondary : Colors.grey[400],
                      size: 24,
                    ),
                  ),
          ),
        ),
        title: Text(
          document.name,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700, 
            fontSize: 15,
            color: isDark ? Colors.white : const Color(0xff0F172A),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.calendar, 
                size: 12, 
                color: isDark ? AppColors.darkTextSecondary : Colors.grey[500]
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  DateFormat('MMM dd, yyyy').format(document.date),
                  style: GoogleFonts.plusJakartaSans(
                    color: isDark ? AppColors.darkTextSecondary : Colors.grey[600], 
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: document.pdfPath != null && document.pdfPath!.toLowerCase().endsWith('.docx')
                      ? const Color(0xff2B579A).withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${document.pageCount ?? document.imagePaths.length} Pgs",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, 
                    fontWeight: FontWeight.w800,
                    color: document.pdfPath != null && document.pdfPath!.toLowerCase().endsWith('.docx')
                        ? const Color(0xff2B579A)
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: isSelectionMode
            ? Checkbox(
                value: isSelected,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (_) => onTap(),
                shape: const CircleBorder(),
              )
            : PopupMenuButton<String>(
                icon: Icon(
                  LucideIcons.moreVertical, 
                  color: isDark ? AppColors.darkTextSecondary : Colors.grey[400],
                  size: 20,
                ),
                color: isDark ? AppColors.darkSurfaceLight : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            color: isDark ? Colors.white : Colors.black87,
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
                            color: isDark ? Colors.white : Colors.black87,
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
                            color: isDark ? Colors.white : Colors.black87,
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
              ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
  }
}
