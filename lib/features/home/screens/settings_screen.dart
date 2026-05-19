import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/utils/app_localizations.dart';
import 'recycle_bin_screen.dart';
import 'privacy_policy_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  bool _isLockEnabled = false;
  int _selectedCategoryIndex = 0;
  String _appVersion = "1.0.0"; // Default fallback

  @override
  void initState() {
    super.initState();
    _isLockEnabled = _settings.appLock;
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  void _onSettingChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            LucideIcons.chevronLeft,
            color: isDark ? Colors.white : AppColors.primary,
          ),
        ),
        title: Text(
          l10n.translate('settings'),
          style: GoogleFonts.inter(
            color: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;

          if (isWide) {
            return _buildWideLayout(l10n, isDark);
          }

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildSection(l10n.translate('preferences'), [
                  _buildSettingTile(
                    icon: LucideIcons.moon,
                    title: l10n.translate('dark_mode'),
                    subtitle: _getDarkModeLabel(),
                    onTap: _showDarkModeDialog,
                  ),
                  _buildSettingTile(
                    icon: LucideIcons.languages,
                    title: l10n.translate('language'),
                    subtitle: _getLanguageLabel(),
                    onTap: _showLanguageDialog,
                  ),
                ]),
                _buildSection(l10n.translate('security'), [
                  _buildSwitchTile(
                    icon: LucideIcons.lock,
                    title: l10n.translate('app_lock'),
                    subtitle: l10n.translate('app_lock_sub'),
                    value: _isLockEnabled,
                    onChanged: (val) async {
                      await _settings.setAppLock(val);
                      setState(() => _isLockEnabled = val);
                      _showSnackBar(
                        "${l10n.translate('app_lock')} ${val ? l10n.translate('enabled') : l10n.translate('disabled')}",
                      );
                    },
                  ),
                ]),
                _buildSection(l10n.translate('exports'), [
                  _buildSettingTile(
                    icon: LucideIcons.fileType,
                    title: l10n.translate('pdf_quality'),
                    subtitle: _getPdfQualityLabel(),
                    onTap: _showPdfQualityDialog,
                  ),
                ]),
                _buildSection(l10n.translate('data_management'), [
                  _buildSettingTile(
                    icon: LucideIcons.zap,
                    title: l10n.translate('optimize_library'),
                    subtitle: l10n.translate('reclaim_storage_sub'),
                    onTap: _showOptimizationDialog,
                  ),
                  _buildSettingTile(
                    icon: LucideIcons.trash2,
                    title: l10n.translate('recycle_bin'),
                    subtitle: l10n.translate('manage_deleted_docs'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
                      );
                    },
                  ),
                ]),
                _buildSection(l10n.translate('about'), [
                  _buildSettingTile(
                    icon: LucideIcons.info,
                    title: l10n.translate('version'),
                    subtitle: _appVersion,
                  ),
                  _buildSettingTile(
                    icon: LucideIcons.shieldCheck,
                    title: l10n.translate('privacy_policy'),
                    subtitle: l10n.translate('read_terms'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideLayout(AppLocalizations l10n, bool isDark) {
    final categories = [
      {'title': l10n.translate('preferences'), 'icon': LucideIcons.settings},
      {'title': l10n.translate('security'), 'icon': LucideIcons.lock},
      {'title': l10n.translate('exports'), 'icon': LucideIcons.fileType},
      {'title': l10n.translate('data_management'), 'icon': LucideIcons.database},
      {'title': l10n.translate('about'), 'icon': LucideIcons.info},
    ];

    return Row(
      children: [
        // Master Pane: Categories
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff1A1C1E) : Colors.white,
            border: Border(
              right: BorderSide(
                color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
              ),
            ),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final isSelected = _selectedCategoryIndex == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _selectedCategoryIndex = index),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          categories[index]['icon'] as IconData,
                          size: 20,
                          color: isSelected ? AppColors.primary : Colors.grey,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          categories[index]['title'] as String,
                          style: GoogleFonts.inter(
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 15,
                            color: isSelected ? AppColors.primary : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Detail Pane: Configuration
        Expanded(
          child: Container(
            color: isDark ? const Color(0xff0F1113) : const Color(0xffF8FAFC),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: _buildDetailContent(l10n),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailContent(AppLocalizations l10n) {
    switch (_selectedCategoryIndex) {
      case 0: // Preferences
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailHeader(l10n.translate('preferences')),
            _buildSettingTile(
              icon: LucideIcons.moon,
              title: l10n.translate('dark_mode'),
              subtitle: _getDarkModeLabel(),
              onTap: _showDarkModeDialog,
            ),
            _buildSettingTile(
              icon: LucideIcons.languages,
              title: l10n.translate('language'),
              subtitle: _getLanguageLabel(),
              onTap: _showLanguageDialog,
            ),
          ],
        );
      case 1: // Security
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailHeader(l10n.translate('security')),
            _buildSwitchTile(
              icon: LucideIcons.lock,
              title: l10n.translate('app_lock'),
              subtitle: l10n.translate('app_lock_sub'),
              value: _isLockEnabled,
              onChanged: (val) async {
                await _settings.setAppLock(val);
                setState(() => _isLockEnabled = val);
                _showSnackBar(
                  "${l10n.translate('app_lock')} ${val ? l10n.translate('enabled') : l10n.translate('disabled')}",
                );
              },
            ),
          ],
        );
      case 2: // Exports
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailHeader(l10n.translate('exports')),
            _buildSettingTile(
              icon: LucideIcons.fileType,
              title: l10n.translate('pdf_quality'),
              subtitle: _getPdfQualityLabel(),
              onTap: _showPdfQualityDialog,
            ),
          ],
        );
      case 3: // Data Management
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailHeader(l10n.translate('data_management')),
            _buildSettingTile(
              icon: LucideIcons.zap,
              title: l10n.translate('optimize_library'),
              subtitle: l10n.translate('reclaim_storage_sub'),
              onTap: _showOptimizationDialog,
            ),
            _buildSettingTile(
              icon: LucideIcons.trash2,
              title: l10n.translate('recycle_bin'),
              subtitle: l10n.translate('manage_deleted_docs'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
                );
              },
            ),
          ],
        );
      case 4: // About
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailHeader(l10n.translate('about')),
            _buildSettingTile(
              icon: LucideIcons.info,
              title: l10n.translate('version'),
              subtitle: _appVersion,
            ),
            _buildSettingTile(
              icon: LucideIcons.shieldCheck,
              title: l10n.translate('privacy_policy'),
              subtitle: l10n.translate('read_terms'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                );
              },
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDetailHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32, left: 16),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              color: isDark
                  ? Colors.white54
                  : AppColors.primary.withValues(alpha: 0.5),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: Column(
            children: List.generate(children.length, (index) {
              return Column(
                children: [
                  children[index],
                  if (index < children.length - 1)
                    Divider(
                      height: 1,
                      indent: 60,
                      endIndent: 20,
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontSize: 12,
              ),
            )
          : null,
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: isDark ? Colors.white24 : Colors.grey[400],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontSize: 12,
              ),
            )
          : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String _getDarkModeLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_settings.darkMode) {
      case 0:
        return l10n.translate('sys_default');
      case 1:
        return l10n.translate('light_label');
      case 2:
        return l10n.translate('dark_label');
      default:
        return l10n.translate('sys_default');
    }
  }

  String _getLanguageLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_settings.language) {
      case 'en':
        return l10n.translate('english_label');
      case 'hi':
        return l10n.translate('hindi_label');
      default:
        return l10n.translate('english_label');
    }
  }

  String _getPdfQualityLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_settings.pdfQuality) {
      case 0:
        return l10n.translate('low_label');
      case 1:
        return l10n.translate('med_qual');
      case 2:
        return l10n.translate('high_label');
      default:
        return l10n.translate('high_label');
    }
  }

  void _showDarkModeDialog() {
    final l10n = AppLocalizations.of(context);
    _showSelectionSheet(
      title: l10n.translate('dark_mode'),
      options: [
        {"label": l10n.translate('sys_default'), "value": 0},
        {"label": l10n.translate('light_label'), "value": 1},
        {"label": l10n.translate('dark_label'), "value": 2},
      ],
      currentValue: _settings.darkMode,
      onSelected: (val) async {
        await _settings.setDarkMode(val as int);
        _onSettingChanged();
      },
    );
  }

  void _showLanguageDialog() {
    final l10n = AppLocalizations.of(context);
    _showSelectionSheet(
      title: l10n.translate('language'),
      options: [
        {"label": l10n.translate('english_label'), "value": 'en'},
        {"label": l10n.translate('hindi_label'), "value": 'hi'},
      ],
      currentValue: _settings.language,
      onSelected: (val) async {
        await _settings.setLanguage(val as String);
        _onSettingChanged();
      },
    );
  }

  void _showPdfQualityDialog() {
    final l10n = AppLocalizations.of(context);
    _showSelectionSheet(
      title: l10n.translate('pdf_quality'),
      options: [
        {"label": l10n.translate('low_label'), "value": 0},
        {"label": l10n.translate('med_qual'), "value": 1},
        {"label": l10n.translate('high_label'), "value": 2},
      ],
      currentValue: _settings.pdfQuality,
      onSelected: (val) async {
        await _settings.setPdfQuality(val as int);
        _onSettingChanged();
      },
    );
  }

  void _showSelectionSheet({
    required String title,
    required List<Map<String, dynamic>> options,
    required dynamic currentValue,
    required Function(dynamic) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((opt) {
              final isSelected = opt['value'] == currentValue;
              return ListTile(
                onTap: () {
                  onSelected(opt['value']);
                  Navigator.pop(context);
                },
                leading: Icon(
                  isSelected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  size: 20,
                ),
                title: Text(
                  opt['label'],
                  style: GoogleFonts.inter(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[700],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showOptimizationDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff1E293B)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          l10n.translate('optimize_library'),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        content: Text(
          l10n.translate('opt_desc'),
          style: GoogleFonts.inter(color: Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('cancel'),
              style: GoogleFonts.inter(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              _runOptimization();
            },
            child: Text(
              l10n.translate('optimize_now'),
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runOptimization() async {
    final storage = StorageService();
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          width: 250,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff1E293B)
                : Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.translate('optimizing_library_msg'),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.translate('do_not_close_app'),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await storage.optimizeAllExistingDocuments();
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar(l10n.translate('opt_success'));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("${l10n.translate('opt_failed')}: $e");
      }
    }
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
}
