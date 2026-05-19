import 'package:flutter/material.dart';

enum DeviceType { mobile, tablet, desktop }

class ResponsiveLayout extends StatelessWidget {
  final Widget? child;
  final Widget? mobile;
  final Widget? tablet;
  final Widget? desktop;
  final double maxWidth;
  final EdgeInsets padding;
  final Alignment alignment;

  const ResponsiveLayout({
    super.key,
    this.child,
    this.mobile,
    this.tablet,
    this.desktop,
    this.maxWidth = 1200,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
  });

  // Breakpoints
  static const double kMobileBreakpoint = 600;
  static const double kTabletBreakpoint = 1024;
  static const double kDesktopBreakpoint = 1440;

  static DeviceType deviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= kTabletBreakpoint) return DeviceType.desktop;
    if (width >= kMobileBreakpoint) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  static bool isMobile(BuildContext context) => deviceType(context) == DeviceType.mobile;
  static bool isTablet(BuildContext context) => deviceType(context) == DeviceType.tablet;
  static bool isDesktop(BuildContext context) => deviceType(context) == DeviceType.desktop;
  static bool isWide(BuildContext context) => MediaQuery.of(context).size.width >= kMobileBreakpoint;
  
  static bool isPortrait(BuildContext context) => MediaQuery.of(context).orientation == Orientation.portrait;
  static bool isLandscape(BuildContext context) => MediaQuery.of(context).orientation == Orientation.landscape;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final type = deviceType(context);
        Widget? activeWidget;

        if (type == DeviceType.desktop) {
          activeWidget = desktop ?? tablet ?? mobile ?? child;
        } else if (type == DeviceType.tablet) {
          activeWidget = tablet ?? mobile ?? child;
        } else {
          activeWidget = mobile ?? child;
        }

        return Align(
          alignment: alignment,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: padding,
            child: activeWidget,
          ),
        );
      },
    );
  }
}

/// A builder that provides both device type and orientation for granular control
class AdaptiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, DeviceType deviceType, Orientation orientation) builder;

  const AdaptiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return builder(
      context,
      ResponsiveLayout.deviceType(context),
      MediaQuery.of(context).orientation,
    );
  }
}

