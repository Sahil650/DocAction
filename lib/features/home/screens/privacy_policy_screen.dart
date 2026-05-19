import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/utils/app_localizations.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('privacy_policy')),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: isDark ? Colors.white : AppColors.primary,
        elevation: 0,
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(l10n.translate('privacy_policy'), isDark),
              _buildText(l10n.translate('privacy_intro'), isDark),
              _buildHeader(l10n.translate('privacy_h1'), isDark),
              _buildText(l10n.translate('privacy_t1'), isDark),
              _buildHeader(l10n.translate('privacy_h2'), isDark),
              _buildText(l10n.translate('privacy_t2'), isDark),
              _buildHeader(l10n.translate('privacy_h3'), isDark),
              _buildText(l10n.translate('privacy_t3'), isDark),
              _buildHeader(l10n.translate('privacy_h4'), isDark),
              _buildText(l10n.translate('privacy_t4'), isDark),
              _buildHeader(l10n.translate('privacy_h5'), isDark),
              _buildText(l10n.translate('privacy_t5'), isDark),
              _buildHeader(l10n.translate('privacy_h6'), isDark),
              _buildText(l10n.translate('privacy_t6'), isDark),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  "DocAction v1.0.0",
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildText(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14, 
        height: 1.6, 
        color: isDark ? Colors.white70 : Colors.black87
      ),
    );
  }
}
