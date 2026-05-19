import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/folder_model.dart';
import '../../../shared/utils/app_localizations.dart';

class FolderCard extends StatelessWidget {
  final FolderModel folder;
  final int documentCount;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const FolderCard({
    super.key,
    required this.folder,
    required this.documentCount,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    // Professional color palette matching DocumentCard
    final Color baseColor = Theme.of(context).brightness == Brightness.dark 
        ? Colors.white54 
        : const Color(0xff475569);
    final Color accentColor = Theme.of(context).brightness == Brightness.dark 
        ? Colors.white 
        : const Color(0xff1e293b);
    final Color backgroundColor = Theme.of(context).brightness == Brightness.dark 
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)
        : const Color(0xfff8fafc);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // Adaptive scaling based on card width
        final iconSize = (cardWidth * 0.4).clamp(28.0, 60.0);
        final titleFontSize = (cardWidth * 0.1).clamp(12.0, 15.0);
        final subtitleFontSize = (cardWidth * 0.08).clamp(9.0, 11.0);
        final padding = (cardWidth * 0.08).clamp(8.0, 14.0);
        final borderRadius = (cardWidth * 0.1).clamp(10.0, 20.0);

        return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected 
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) 
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                if (Theme.of(context).brightness == Brightness.light)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Visual Area
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    color: backgroundColor,
                    child: Center(
                      child: Icon(
                        Icons.folder_open_rounded,
                        size: iconSize,
                        color: baseColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                // Bottom Content Area
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(height: padding * 0.2),
                        Flexible(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: titleFontSize,
                                    color: accentColor,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              isSelectionMode
                                ? Checkbox(
                                    value: isSelected,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    onChanged: (_) => onTap(),
                                    shape: const CircleBorder(),
                                  )
                                : _buildPopupMenu(cardWidth),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Flexible(
                          child: Text(
                            "$documentCount ${documentCount == 1 ? AppLocalizations.of(context).translate('item_label').toUpperCase() : AppLocalizations.of(context).translate('items_label').toUpperCase()}",
                            style: TextStyle(
                              fontSize: subtitleFontSize * 0.9,
                              color: baseColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    )
.animate().fadeIn(duration: 300.ms).slideY(
          begin: 0.1,
          end: 0,
          curve: Curves.easeOut,
        );
  }

  Widget _buildPopupMenu(double cardWidth) {
    final iconSize = (cardWidth * 0.12).clamp(14.0, 20.0);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: iconSize, color: Colors.grey[400]),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'rename') onRename();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 16),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).translate('rename'), style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red[400]),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).translate('delete'),
                style: TextStyle(fontSize: 13, color: Colors.red[400]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
