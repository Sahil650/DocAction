import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../data/models/scan_result_model.dart';
import '../../../core/theme/app_colors.dart';

class QrResultScreen extends StatelessWidget {
  final ScanResultModel result;

  const QrResultScreen({super.key, required this.result});

  bool _isUrl(String data) {
    final uri = Uri.tryParse(data.trim());
    return uri != null && (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https'));
  }

  Future<void> _handleAction(BuildContext context) async {
    final data = result.data.trim();

    if (result.type == 'URL' || _isUrl(data)) {
      final uri = Uri.parse(data.startsWith('http') ? data : 'https://$data');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate("could_not_open_link"))),
          );
        }
      }
    } else if (result.type == 'EMAIL') {
      final uri = Uri.parse("mailto:$data");
      await launchUrl(uri);
    } else if (result.type == 'PHONE') {
      final uri = Uri.parse("tel:$data");
      await launchUrl(uri);
    } else {
      // Default: Copy to clipboard
      await Clipboard.setData(ClipboardData(text: data));
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate("text_copied_snack"))),
        );
      }
    }
  }

  Future<void> _searchOnWeb(String data) async {
    final uri = Uri.parse("https://www.google.com/search?q=${Uri.encodeComponent(data)}");
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String data = result.data.trim();
    final bool isUrlDetected = result.type == 'URL' || _isUrl(data);
    
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 360;

    // Primary Action Logic
    final String actionLabel = isUrlDetected 
      ? l10n.translate("open_link") 
      : (result.type == 'PHONE' 
          ? l10n.translate("call_label") 
          : (result.type == 'EMAIL' 
              ? l10n.translate("send_email") 
              : l10n.translate("copy_label")));
    
    final IconData actionIcon = isUrlDetected 
      ? Icons.open_in_new_rounded 
      : (result.type == 'PHONE' 
          ? Icons.phone_rounded 
          : (result.type == 'EMAIL' 
              ? Icons.email_rounded 
              : Icons.content_copy_rounded));

    final bool isPrimaryCopy = !isUrlDetected && result.type != 'PHONE' && result.type != 'EMAIL';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : const Color(0xffF3F4F6),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.translate("scan_result"),
          style: GoogleFonts.inter(
            color: isDark ? Colors.white : AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.primary),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => Share.share(result.data),
            tooltip: l10n.translate("share_label"),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 700,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Result Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        border: isDark ? Border.all(color: AppColors.darkBorder) : null,
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: (isDark ? AppColors.accent : AppColors.primary).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getFormatIcon(result.format),
                              color: isDark ? AppColors.accent : AppColors.primary,
                              size: isSmallScreen ? 32 : 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            result.format.replaceAll('_', ' '),
                            style: GoogleFonts.inter(
                              color: isDark ? AppColors.darkTextSecondary : Colors.grey[500],
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Scrollable data area if text is very long
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(
                                result.data,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: isSmallScreen ? 18 : 22,
                                  color: isDark ? Colors.white : AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            height: 1,
                            color: isDark ? AppColors.darkBorder : Colors.black.withOpacity(0.05),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: isDark ? AppColors.darkTextSecondary.withOpacity(0.4) : Colors.grey[400],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('MMM dd, yyyy • hh:mm a').format(result.timestamp),
                                style: GoogleFonts.inter(
                                  color: isDark ? AppColors.darkTextSecondary.withOpacity(0.4) : Colors.grey[400],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Sticky Bottom Actions
            Container(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Primary Action Button
                  ElevatedButton.icon(
                    onPressed: () => _handleAction(context),
                    icon: Icon(actionIcon, color: Colors.black, size: 20),
                    label: Text(
                      actionLabel.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size(double.infinity, 60),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                  
                  // Secondary Actions (Search Web always, Copy if not primary)
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _secondaryButton(
                          context,
                          icon: Icons.public_rounded,
                          label: l10n.translate("search_web"),
                          onTap: () => _searchOnWeb(result.data),
                          isDark: isDark,
                        ),
                      ),
                      if (!isPrimaryCopy) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _secondaryButton(
                            context,
                            icon: Icons.content_copy_rounded,
                            label: l10n.translate("copy_label"),
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: result.data));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.translate("text_copied_snack"))),
                              );
                            },
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: isDark ? Colors.white : AppColors.primary),
      label: Text(
        label,
        style: GoogleFonts.inter(
          color: isDark ? Colors.white : AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.primary.withOpacity(0.1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  IconData _getFormatIcon(String format) {
    if (format.contains('QR')) return Icons.qr_code_2_rounded;
    return Icons.barcode_reader;
  }
}
