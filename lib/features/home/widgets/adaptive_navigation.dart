import 'package:flutter/material.dart';

import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import 'sidebar_drawer.dart';

class AdaptiveNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabTapped;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final PreferredSizeWidget? appBar;

  const AdaptiveNavigation({
    super.key,
    required this.currentIndex,
    required this.onTabTapped,
    required this.body,
    this.floatingActionButton,
    this.drawer,
    this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveBuilder(
      builder: (context, deviceType, orientation) {
        if (deviceType == DeviceType.desktop) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: [
                SizedBox(
                  width: 300.w,
                  child: SidebarDrawer(
                    onNavigate: onTabTapped,
                    isPermanent: true,
                  ),
                ),
                VerticalDivider(
                  width: 1.w,
                  thickness: 1.w,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(child: body),
              ],
            ),
          );
        }

        if (deviceType == DeviceType.tablet) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: [
                NavigationRail(
                  extended: orientation == Orientation.landscape,
                  selectedIndex: currentIndex,
                  onDestinationSelected: onTabTapped,
                  labelType: orientation == Orientation.portrait
                      ? NavigationRailLabelType.all
                      : NavigationRailLabelType.none,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  indicatorColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  selectedIconTheme: IconThemeData(
                    color: Theme.of(context).colorScheme.primary,
                    size: 28.sp,
                  ),
                  unselectedIconTheme: IconThemeData(
                    color: Colors.grey,
                    size: 24.sp,
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      selectedIcon: Icon(Icons.grid_view_rounded),
                      label: Text('Documents'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.camera_alt_rounded),
                      selectedIcon: Icon(Icons.camera_alt_rounded),
                      label: Text('Scanner'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.widgets_rounded),
                      selectedIcon: Icon(Icons.widgets_rounded),
                      label: Text('Tools'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: Text('Profile'),
                    ),
                  ],
                ),
                VerticalDivider(
                  width: 1.w,
                  thickness: 1.w,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(child: body),
              ],
            ),
            floatingActionButton: floatingActionButton,
          );
        }

        // Mobile Layout
        return Scaffold(
          appBar: appBar,
          drawer: drawer ?? SidebarDrawer(onNavigate: onTabTapped),
          body: body,
          bottomNavigationBar: BottomNavBar(
            currentIndex: currentIndex,
            onTap: onTabTapped,
          ),
          floatingActionButton: floatingActionButton,
        );
      },
    );
  }
}

// Simple wrapper to avoid circular dependency if we moved BottomNavBar here
class _BottomNavBarWrapper extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const _BottomNavBarWrapper({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // This is just a conceptual placeholder, we'll use the real BottomNavBar in MainScreen
    return const SizedBox.shrink();
  }
}
