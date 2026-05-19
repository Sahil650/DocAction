import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class SelectionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onMove;

  const SelectionBar({
    super.key,
    required this.selectedCount,
    required this.onClear,
    required this.onDelete,
    required this.onShare,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      height: 65,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(blurRadius: 15, color: Colors.black38, offset: Offset(0, 5))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(
              "$selectedCount Selected",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined, color: Colors.white),
              tooltip: "Share Selected",
            ),
            IconButton(
              onPressed: onMove,
              icon: const Icon(Icons.drive_file_move_outlined, color: Colors.white),
              tooltip: "Move Selected",
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: "Delete Selected",
            ),
          ],
        ),
      ),
    );
  }
}
