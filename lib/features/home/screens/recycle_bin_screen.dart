import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import 'document_detail_screen.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  final StorageService _storageService = StorageService();
  List<DocumentModel> _deletedDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeletedDocs();
  }

  Future<void> _loadDeletedDocs() async {
    setState(() => _isLoading = true);
    final docs = await _storageService.loadDeletedDocuments();
    setState(() {
      _deletedDocs = docs;
      _isLoading = false;
    });
  }

  Future<void> _restoreDoc(String id) async {
    await _storageService.restoreDocument(id);
    _loadDeletedDocs();
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      _showSnackBar(l10n.translate('doc_restored'));
    }
  }

  Future<void> _permanentlyDelete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      title: l10n.translate('perm_delete'),
      message: l10n.translate('undone_msg'),
      confirmLabel: l10n.translate('delete'),
      isDestructive: true,
    );

    if (confirmed == true) {
      await _storageService.permanentlyDeleteDocument(id);
      _loadDeletedDocs();
    }
  }

  Future<void> _emptyBin() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      title: l10n.translate('empty_bin_title'),
      message: l10n.translate('empty_bin_msg'),
      confirmLabel: l10n.translate('empty_bin_title'),
      isDestructive: true,
    );

    if (confirmed == true) {
      await _storageService.clearRecycleBin();
      _loadDeletedDocs();
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.translate('cancel'),
              style: GoogleFonts.inter(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red[700] : AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const primaryColor = AppColors.primary;

    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(LucideIcons.chevronLeft, color: primaryColor),
        ),
        title: Text(
          l10n.translate('recycle_bin'),
          style: GoogleFonts.inter(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          if (_deletedDocs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Icon(LucideIcons.trash2, color: Colors.red[700], size: 22),
                onPressed: _emptyBin,
                tooltip: l10n.translate('empty_bin_title'),
              ),
            ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: _isLoading
            ? ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 20),
                itemCount: 10,
                itemBuilder: (context, index) => const ListTileSkeleton(),
              )
            : _deletedDocs.isEmpty
                ? _buildEmptyState()
                : _buildList(),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(LucideIcons.trash2, size: 64, color: Colors.grey[300]),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.translate('bin_empty_state'),
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('deleted_items_hint'),
            style: GoogleFonts.inter(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    const primaryColor = AppColors.primary;
    return ListView.builder(
      itemCount: _deletedDocs.length,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final doc = _deletedDocs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DocumentDetailScreen(document: doc),
                ),
              );
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(LucideIcons.fileText, color: primaryColor, size: 24),
            ),
            title: Text(
              doc.name,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: primaryColor,
              ),
            ),
            subtitle: Text(
              DateFormat('MMM d, yyyy • hh:mm a').format(doc.date),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(LucideIcons.moreVertical, color: Colors.grey[400], size: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 4,
              offset: const Offset(0, 40),
              onSelected: (value) {
                if (value == 'restore') _restoreDoc(doc.id);
                if (value == 'delete') _permanentlyDelete(doc.id);
              },
              itemBuilder: (context) {
                final l10n = AppLocalizations.of(context);
                return [
                  PopupMenuItem(
                    value: 'restore',
                    child: Row(
                      children: [
                        const Icon(LucideIcons.refreshCw, size: 18, color: primaryColor),
                        const SizedBox(width: 12),
                        Text(
                          l10n.translate('restore'),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
                        const SizedBox(width: 12),
                        Text(
                          l10n.translate('delete_forever'),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ),
        );
      },
    );
  }
}
