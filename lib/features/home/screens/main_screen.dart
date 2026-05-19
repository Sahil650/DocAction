import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'documents_list_screen.dart';
import '../../tools/screens/tools_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../scanner/screens/universal_scanner_screen.dart';
import '../widgets/sidebar_drawer.dart';
import 'settings_screen.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../shared/widgets/selection_bar.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/security_service.dart';
import 'package:flutter/services.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import '../../../shared/widgets/responsive_layout.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<DocumentsListScreenState> _listKey =
      GlobalKey<DocumentsListScreenState>();

  bool _isSelectionMode = false;
  int _selectedCount = 0;

  bool _isAuthenticated = false;
  bool _isAuthLoading = true;
  final SecurityService _security = SecurityService();
  final SettingsService _settings = SettingsService();

  final List<Widget?> _pages = List.filled(4, null);

  @override
  void initState() {
    super.initState();
    _checkAppLock();
  }

  Future<void> _checkAppLock() async {
    if (!_settings.appLock) {
      setState(() {
        _isAuthenticated = true;
        _isAuthLoading = false;
      });
      return;
    }

    final success = await _security.authenticate();
    if (success) {
      setState(() {
        _isAuthenticated = true;
        _isAuthLoading = false;
      });
    } else {
      // If failed, we might want to exit or show a "Retry" button
      setState(() => _isAuthLoading = false);
    }
  }

  Future<void> _onTabTapped(int index) async {
    if (index == 1) {
      // Center button triggers Scanner
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UniversalScannerScreen()),
      );
      // Auto-refresh after returning from scanner
      _listKey.currentState?.loadDocuments();
      return;
    }
    if (index == 0) {
      _listKey.currentState?.loadDocuments();
    }
    setState(() {
      _currentIndex = index;
    });
  }

  Widget _buildLazyPage(int index) {
    if (_pages[index] == null) {
      switch (index) {
        case 0:
          _pages[0] = DocumentsListScreen(
            key: _listKey,
            scaffoldKey: _scaffoldKey,
            onSelectionChanged: (isSelecting, count) {
              setState(() {
                _isSelectionMode = isSelecting;
                _selectedCount = count;
              });
            },
          );
          break;
        case 1:
          _pages[1] = const SizedBox.shrink();
          break;
        case 2:
          _pages[2] = ToolsScreen(
            onRefresh: () => _listKey.currentState?.loadDocuments()
          );
          break;
        case 3:
          _pages[3] = ProfileScreen(onNavigate: _onTabTapped);
          break;
      }
    }
    return _pages[index]!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_isAuthenticated) {
      return _buildLockScreen(l10n);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = ResponsiveLayout.isDesktop(context);
        final bool isTablet = ResponsiveLayout.isTablet(context);
        final bool isMobile = ResponsiveLayout.isMobile(context);

        return Scaffold(
          key: isMobile ? _scaffoldKey : null,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          drawer: isMobile ? SidebarDrawer(onNavigate: _onTabTapped) : null,
          body: Row(
            children: [
              if (!isMobile)
                _buildSideNavigation(context, isDesktop, isTablet, l10n),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      children: [
                        _buildResponsiveAppBar(context, isMobile, l10n),
                        Expanded(
                          child: Stack(
                            children: [
                              IndexedStack(
                                index: _currentIndex,
                                children: List.generate(4, (index) {
                                  // Lazy load logic: if visited, build it. Otherwise shrink.
                                  if (index == _currentIndex || _pages[index] != null) {
                                    return _buildLazyPage(index);
                                  }
                                  return const SizedBox.shrink();
                                }),
                              ),
                              if (_isSelectionMode)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: SelectionBar(
                                    selectedCount: _selectedCount,
                                    onClear: () =>
                                        _listKey.currentState?.clearSelection(),
                                    onDelete: () =>
                                        _listKey.currentState?.deleteSelected(),
                                    onShare: () =>
                                        _listKey.currentState?.shareSelected(),
                                    onMove: () => _listKey.currentState
                                        ?.showMoveSelected(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isMobile && !_isSelectionMode
              ? BottomNavBar(currentIndex: _currentIndex, onTap: _onTabTapped)
              : null,
          floatingActionButton:
              (isMobile && !_isSelectionMode && _currentIndex == 0)
              ? _buildFab(context, l10n)
              : null,
        );
      },
    );
  }

  Widget _buildSideNavigation(
    BuildContext context,
    bool isDesktop,
    bool isTablet,
    AppLocalizations l10n,
  ) {
    return NavigationRail(
      extended: isDesktop,
      selectedIndex: _currentIndex == 1
          ? 0
          : (_currentIndex > 1 ? _currentIndex - 1 : _currentIndex),
      onDestinationSelected: (index) {
        if (index == 0) {
          _onTabTapped(0);
        } else if (index == 1)
          _onTabTapped(2);
        else if (index == 2)
          _onTabTapped(3);
      },
      labelType: isDesktop
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      selectedIconTheme: IconThemeData(
        color: Theme.of(context).colorScheme.primary,
      ),
      unselectedIconTheme: IconThemeData(color: Colors.grey[400]),
      selectedLabelTextStyle: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: FloatingActionButton(
          onPressed: () => _onTabTapped(1),
          backgroundColor: Theme.of(context).colorScheme.primary,
          elevation: 2,
          child: const Icon(Icons.camera_alt, color: Colors.white),
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.description_outlined),
          selectedIcon: const Icon(Icons.description),
          label: Text(l10n.translate('documents')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.grid_view_outlined),
          selectedIcon: const Icon(Icons.grid_view_rounded),
          label: Text(l10n.translate('tools')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: Text(l10n.translate('profile')),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildResponsiveAppBar(
    BuildContext context,
    bool isMobile,
    AppLocalizations l10n,
  ) {
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      elevation: 0,
      centerTitle: isMobile,
      leading: _isSelectionMode
          ? IconButton(
              onPressed: () => _listKey.currentState?.clearSelection(),
              icon: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : (isMobile
                ? IconButton(
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: Icon(
                      Icons.menu,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : null),
      title: Text(
        _isSelectionMode
            ? "$_selectedCount ${l10n.translate('selected')}"
            : _currentIndex == 0
            ? l10n.translate('my_scanner')
            : _currentIndex == 2
            ? l10n.translate('tools_hub')
            : l10n.translate('my_profile'),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
      ),
      actions: [
        if (_isSelectionMode)
          IconButton(
            onPressed: () => _listKey.currentState?.toggleSelectAll(),
            icon: Icon(
              Icons.select_all,
              color: Theme.of(context).colorScheme.primary,
            ),
            tooltip: "Select All",
          ),
        if (!_isSelectionMode)
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: Icon(
              Icons.settings,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildFab(BuildContext context, AppLocalizations l10n) {
    return FloatingActionButton.extended(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UniversalScannerScreen()),
        );
        _listKey.currentState?.loadDocuments();
      },
      backgroundColor: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.camera_alt, color: Colors.white),
      label: Text(
        l10n.translate('scan_doc'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLockScreen(AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_person_outlined,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.translate('scanner_locked'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('auth_required'),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 40),
            if (_isAuthLoading)
              const CircularProgressIndicator(color: Colors.white)
            else
              ElevatedButton.icon(
                onPressed: _checkAppLock,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.fingerprint),
                label: Text(l10n.translate('unlock_biometrics')),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: Text(
                l10n.translate('exit_app'),
                style: const TextStyle(color: Colors.white60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
