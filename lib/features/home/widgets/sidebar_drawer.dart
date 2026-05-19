import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/services/auth_service.dart';
import '../../auth/screens/login_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/recycle_bin_screen.dart';
import '../screens/recent_documents_screen.dart';
import '../../../core/theme/app_colors.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';

class SidebarDrawer extends StatefulWidget {
  final Function(int)? onNavigate;
  final bool isPermanent;
  
  const SidebarDrawer({
    super.key, 
    this.onNavigate,
    this.isPermanent = false,
  });

  @override
  State<SidebarDrawer> createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<SidebarDrawer> {
  final _authService = AuthService();
  String _displayName = "";
  String? _profilePicturePath;
  String _email = "";

  String get _fullProfileImageUrl {
    if (_profilePicturePath == null) return '';
    String path = _profilePicturePath!;
    if (path.startsWith('http://127.0.0.1:5000')) {
      return path.replaceFirst('http://127.0.0.1:5000', _authService.baseUrl);
    } else if (path.startsWith('/uploads')) {
      return '${_authService.baseUrl}$path';
    }
    return path;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final loggedIn = await _authService.isLoggedIn();
    if (!loggedIn) {
      if (mounted) {
        setState(() {
          _email = "";
          _displayName = "";
        });
      }
      return;
    }

    final profile = await _authService.getProfile();
    final prefs = await SharedPreferences.getInstance();

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      setState(() {
        if (profile != null && profile['email'] != null) {
          _email = profile['email'];
          if (profile['name'] != null && profile['name'].toString().isNotEmpty) {
            _displayName = profile['name'];
          } else {
            _displayName = prefs.getString('display_name_$_email') ?? l10n.translate('user_label');
          }
          if (profile['profile_picture_url'] != null && profile['profile_picture_url'].toString().isNotEmpty) {
            _profilePicturePath = profile['profile_picture_url'];
          } else {
            _profilePicturePath = prefs.getString('profile_picture_path_$_email');
          }
        } else {
          _email = "";
          _displayName = "";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final String firstLetter =
        _email.isNotEmpty && 
        _email != l10n.translate('not_logged_in') && 
        _email != l10n.translate('loading')
        ? _email[0].toUpperCase()
        : 'U';

    final drawerContent = Column(
      children: [
        _buildHeader(context, firstLetter),
        SizedBox(height: 20.h),
        _buildMenuItem(
          context,
          icon: LucideIcons.home,
          title: l10n.translate('my_documents'),
          onTap: () {
            if (!widget.isPermanent) Navigator.pop(context);
            if (widget.onNavigate != null) {
              widget.onNavigate!(0);
            }
          },
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.history,
          title: l10n.translate('recent_scans'),
          onTap: () {
            if (!widget.isPermanent) Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RecentDocumentsScreen(),
              ),
            );
          },
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.trash2,
          title: l10n.translate('recycle_bin'),
          onTap: () {
            if (!widget.isPermanent) Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
            );
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
          child: Divider(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05), thickness: 1.h),
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.settings,
          title: l10n.translate('settings'),
          onTap: () {
            if (!widget.isPermanent) Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
        const Spacer(),
        _email.isEmpty 
        ? _buildMenuItem(
          context,
          icon: LucideIcons.logIn,
          title: l10n.translate('login_signup'),
          onTap: () async {
            if (!widget.isPermanent) Navigator.pop(context);
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
            _loadProfile();
          },
        )
        : _buildMenuItem(
          context,
          icon: LucideIcons.logOut,
          title: l10n.translate('logout'),
          isDestructive: true,
          onTap: () async {
            if (!widget.isPermanent) Navigator.pop(context);
            await _authService.logout();
            _loadProfile();
          },
        ),
        SizedBox(height: 40.h),
      ],
    );

    if (widget.isPermanent) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: drawerContent,
      );
    }

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : Colors.transparent,
          width: 1.w,
        ),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(30.r),
          bottomRight: Radius.circular(30.r),
        ),
      ),
      child: drawerContent,
    );
  }

  Widget _buildHeader(BuildContext context, String firstLetter) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24.w, 60.h, 24.w, 32.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: Theme.of(context).brightness == Brightness.dark 
              ? [AppColors.darkSurface, AppColors.darkSurfaceLight]
              : [AppColors.primaryDark, AppColors.primary],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(35.r),
          bottomRight: Radius.circular(35.r),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(4.r),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 38.r,
              backgroundColor: Colors.white,
              backgroundImage: _profilePicturePath != null
                  ? (_fullProfileImageUrl.startsWith('http')
                      ? NetworkImage(_fullProfileImageUrl) as ImageProvider
                      : FileImage(File(_profilePicturePath!)))
                  : null,
              child: _profilePicturePath == null
                  ? Text(
                      firstLetter,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32.sp,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : null,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            _displayName.isEmpty ? l10n.translate('guest_user') : _displayName,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            _email.isEmpty ? l10n.translate('sign_in_to_sync') : _email,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDestructive 
        ? Theme.of(context).colorScheme.error 
        : (isDark ? Colors.white70 : Theme.of(context).colorScheme.primary);
    
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 4.h),
      onTap: onTap,
      leading: Icon(icon, color: color, size: 22.sp),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          color: color,
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
    );
  }
}

