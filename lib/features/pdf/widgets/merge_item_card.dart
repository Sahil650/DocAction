import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/services/pdf_service.dart';

class MergeItemCard extends StatelessWidget {
  final MergeItemSource item;
  final VoidCallback onDelete;

  const MergeItemCard({
    super.key,
    required this.item,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Reorder Handle Icon
            const Icon(Icons.drag_indicator_rounded, color: Colors.black26),
            const SizedBox(width: 8),
            
            // Thumbnail
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xffF3F4F6),
                borderRadius: BorderRadius.circular(12),
                image: (item.isInternalScan && item.imagePaths != null && item.imagePaths!.isNotEmpty)
                  ? DecorationImage(
                      image: FileImage(File(item.imagePaths!.first)),
                      fit: BoxFit.cover,
                    )
                  : null,
              ),
              child: (!item.isInternalScan || item.imagePaths == null || item.imagePaths!.isEmpty)
                ? Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent.withOpacity(0.5), size: 24)
                : null,
            ),
            const SizedBox(width: 16),
            
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSourceBadge(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${item.pageCount} Pages",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            
            // Delete Action
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: item.isInternalScan ? Colors.blueAccent.withOpacity(0.1) : Colors.orangeAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        item.isInternalScan ? "SCAN" : "FILE",
        style: TextStyle(
          color: item.isInternalScan ? Colors.blueAccent : Colors.orangeAccent,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
