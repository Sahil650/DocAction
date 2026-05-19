import 'package:flutter/material.dart';
import '../../../data/models/folder_model.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../shared/utils/app_localizations.dart';

class FolderListTile extends StatelessWidget {
  final FolderModel folder;
  final int documentCount;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const FolderListTile({
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
    final folderColor = Color(
      int.tryParse(folder.color.replaceFirst('0x', ''), radix: 16) ??
          0xff3B82F6,
    ).withValues(alpha: 1.0);

    return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xff0B3D2E).withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isSelected 
              ? Border.all(color: const Color(0xff0B3D2E), width: 1.5)
              : Border.all(color: Colors.transparent, width: 1.5),
            boxShadow: [
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: folderColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder, color: folderColor, size: 28),
            ),
            title: Text(
              folder.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xff1F2937),
              ),
            ),
            subtitle: Text(
              "$documentCount ${documentCount == 1 ? AppLocalizations.of(context).translate('item_label') : AppLocalizations.of(context).translate('items_label')}",
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            trailing: isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    activeColor: const Color(0xff0B3D2E),
                    onChanged: (_) => onTap(),
                    shape: const CircleBorder(),
                  )
                : _buildPopupMenu(),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
  }

  Widget _buildPopupMenu() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[400]),
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
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).translate('rename'), style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).translate('delete'),
                style: TextStyle(fontSize: 14, color: Colors.red[400]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
