import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../auth/screens/login_screen.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  final Function(int)? onNavigate;
  
  const ProfileScreen({super.key, this.onNavigate});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _storageService = StorageService();
  Map<String, dynamic>? _userProfile;
  int _documentCount = 0;
  String _storageUsed = "0 MB";
  bool _isLoading = true;
  String _displayName = "User";
  bool _displayNameInitialized = false;
  String? _profilePicturePath;

  String get _userKey => _userProfile?['email'] ?? '';

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
    setState(() => _isLoading = true);
    final profile = await _authService.getProfile();
    final docs = await _storageService.loadDocuments();
    final totalBytes = await _storageService.getTotalStorageUsed();
    final prefs = await SharedPreferences.getInstance();
    
    String storageFormatted;
    if (totalBytes < 1024 * 1024) {
      storageFormatted = "${(totalBytes / 1024).toStringAsFixed(1)} KB";
    } else {
      storageFormatted = "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }

    if (mounted) {
      setState(() {
        _userProfile = profile;
        _documentCount = docs.length;
        _storageUsed = storageFormatted;
        
        if (profile != null && profile['email'] != null) {
          final userKey = profile['email'];
          // Prefer backend data, fallback to local if backend is empty
          if (profile['name'] != null && profile['name'].toString().isNotEmpty) {
            _displayName = profile['name'];
            _displayNameInitialized = true;
          } else {
            final savedName = prefs.getString('display_name_$userKey');
            if (savedName != null) {
              _displayName = savedName;
              _displayNameInitialized = true;
            }
          }
          
          if (profile['profile_picture_url'] != null && profile['profile_picture_url'].toString().isNotEmpty) {
            _profilePicturePath = profile['profile_picture_url'];
          } else {
            _profilePicturePath = prefs.getString('profile_picture_path_$userKey');
          }
        } else {
          _profilePicturePath = null;
        }
        
        _isLoading = false;
      });
    }
  }

  void _showEditProfileOptions() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(l10n.translate('change_name')),
                onTap: () {
                  Navigator.pop(context);
                  _editDisplayName();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(l10n.translate('choose_profile_pic')),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfilePicture();
                },
              ),
              if (_profilePicturePath != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(l10n.translate('remove_profile_pic'), style: const TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    if (_userKey.isNotEmpty) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('profile_picture_path_$_userKey');
                      setState(() => _profilePicturePath = null);
                    }
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickProfilePicture() async {
    final l10n = AppLocalizations.of(context);
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null && mounted && _userKey.isNotEmpty) {
        // Crop the picked image
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: l10n.translate('crop_profile_pic'),
              toolbarColor: AppColors.primary,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              hideBottomControls: false,
              aspectRatioPresets: [
                CropAspectRatioPreset.square,
              ],
            ),
            IOSUiSettings(
              title: l10n.translate('crop_profile_pic'),
              aspectRatioLockEnabled: true,
            ),
          ],
        );

        if (croppedFile != null && mounted) {
          // Show saving indicator
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('saving') ?? 'Saving...')),
          );
          
          final result = await _authService.uploadProfilePicture(File(croppedFile.path));
          
          if (mounted) {
            if (result['success']) {
              final newUrl = result['profile_picture_url'];
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('profile_picture_path_$_userKey', newUrl);
              setState(() {
                _profilePicturePath = newUrl;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.translate('profile_pic_updated'))),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result['message'] ?? l10n.translate('failed_pick_image'))),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('failed_pick_image'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isLoggedIn = _userProfile != null;

    return ResponsiveLayout(
      maxWidth: 800,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (isLoggedIn)
              _buildUserInfo(_userProfile!['email'], l10n)
            else
              _buildLoginPrompt(l10n),
            const SizedBox(height: 40),
            _buildOption(
              Icons.storage_outlined,
              l10n.translate('storage'),
              l10n.translate('storage_usage_label')
                  .replaceFirst('{0}', _storageUsed)
                  .replaceFirst('{1}', '2 GB'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.translate('storage_usage')),
                    content: Text(
                      '${l10n.translate('local_storage')}: $_storageUsed\n${l10n.translate('cloud_storage')}: ${l10n.translate('not_configured')}\n\n${l10n.translate('space_left_msg')}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.translate('ok_btn')),
                      ),
                    ],
                  ),
                );
              },
            ),
            _buildOption(
              Icons.history,
              l10n.translate('scanning_history'),
              l10n.translate('docs_scanned_count').replaceFirst('{0}', '$_documentCount'),
              onTap: () {
                if (widget.onNavigate != null) {
                  widget.onNavigate!(0); // Navigate to Home tab
                }
              },
            ),
            const SizedBox(height: 20),
            _buildOption(
              Icons.help_outline,
              l10n.translate('help_support'),
              "",
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.translate('help_support')),
                    content: Text(l10n.translate('contact_us_msg')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.translate('close')),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (isLoggedIn)
              _buildOption(
                Icons.logout,
                l10n.translate('logout'),
                "",
                color: Colors.redAccent,
                onTap: () async {
                  await _authService.logout();
                  _loadProfile();
                },
              )
            else
              _buildOption(
                Icons.login,
                l10n.translate('login'),
                l10n.translate('login_subtitle'),
                color: AppColors.primary,
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                  if (result == true && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.translate('login_success'))),
                    );
                  }
                  _loadProfile();
                },
              ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Future<void> _editDisplayName() async {
    final l10n = AppLocalizations.of(context);
    final TextEditingController controller = TextEditingController(text: _displayName);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.translate('edit_profile_name')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: l10n.translate('enter_your_name'),
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                Navigator.pop(context, text.isNotEmpty ? text : null);
              },
              child: Text(l10n.translate('save')),
            ),
          ],
        );
      },
    );

    if (newName != null && newName != _displayName && mounted && _userKey.isNotEmpty) {
      final result = await _authService.updateProfile(newName);
      
      if (mounted) {
        if (result['success']) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('display_name_$_userKey', newName);
          setState(() {
            _displayName = newName;
            _displayNameInitialized = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('profile_name_updated'))),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to update name')),
          );
        }
      }
    }
  }

  Widget _buildUserInfo(String email, AppLocalizations l10n) {
    final String firstLetter = email.isNotEmpty ? email[0].toUpperCase() : 'U';
    
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: _profilePicturePath != null 
                    ? (_fullProfileImageUrl.startsWith('http')
                        ? NetworkImage(_fullProfileImageUrl) as ImageProvider
                        : FileImage(File(_profilePicturePath!)))
                    : null,
                child: _profilePicturePath == null 
                  ? Text(
                      firstLetter,
                      style: TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _showEditProfileOptions,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _displayNameInitialized ? _displayName : l10n.translate('user_label'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(email, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt(AppLocalizations l10n) {
    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[300],
            child: const Icon(
              Icons.person_outline,
              size: 50,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('not_logged_in'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              _loadProfile();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(l10n.translate('signin_register')),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    IconData icon,
    String title,
    String subtitle, {
    Color? color,
    bool isPro = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.darkBorder 
                : Colors.black.withOpacity(0.04),
          ),
          boxShadow: [
            if (Theme.of(context).brightness == Brightness.light)
              const BoxShadow(color: Colors.black12, blurRadius: 4)
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.primary)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                ],
              ),
            ),
            if (isPro)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "PRO",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
