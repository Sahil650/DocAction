import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scanner_mode.dart';
import 'package:google_fonts/google_fonts.dart';

class MultiOptionModeSelector extends StatefulWidget {
  final ScannerMode currentMode;
  final ValueChanged<ScannerMode> onModeChanged;

  const MultiOptionModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  State<MultiOptionModeSelector> createState() =>
      _MultiOptionModeSelectorState();
}

class _MultiOptionModeSelectorState extends State<MultiOptionModeSelector> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.28,
      initialPage: widget.currentMode.index,
    );
  }

  @override
  void didUpdateWidget(MultiOptionModeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentMode != oldWidget.currentMode) {
      if (_pageController.hasClients &&
          _pageController.page?.round() != widget.currentMode.index) {
        _pageController.animateToPage(
          widget.currentMode.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          HapticFeedback.selectionClick();
          widget.onModeChanged(ScannerMode.values[index]);
        },
        itemCount: ScannerMode.values.length,
        itemBuilder: (context, index) {
          final mode = ScannerMode.values[index];
          final isSelected = mode == widget.currentMode;

          return GestureDetector(
            onTap: () {
              if (isSelected) return;
              HapticFeedback.mediumImpact();
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutExpo,
              );
              // Notification comes via onPageChanged
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mode.label(context).toUpperCase(),
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white : Colors.white38,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: isSelected ? 12 : 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
