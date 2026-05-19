import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doc_scanner_app/core/theme/app_colors.dart';
import '../models/scanner_mode.dart';
import 'scanner_mode_selector.dart';

class ScannerBottomArea extends StatelessWidget {
  final ScannerMode currentMode;
  final List<String> currentSessionList;
  final Map<String, String> sessionThumbnails;
  final VoidCallback onCapture;
  final VoidCallback onGalleryImport;
  final VoidCallback onOpenSession;
  final VoidCallback onDrawSignature;
  final VoidCallback onImportSignature;
  final Function(ScannerMode) onModeChanged;

  final bool isAutoMode;
  final VoidCallback onToggleAutoMode;

  const ScannerBottomArea({
    super.key,
    required this.currentMode,
    required this.currentSessionList,
    this.sessionThumbnails = const {},
    required this.onCapture,
    required this.onGalleryImport,
    required this.onOpenSession,
    required this.onDrawSignature,
    required this.onImportSignature,
    required this.onModeChanged,
    this.isAutoMode = true,
    required this.onToggleAutoMode,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(bottom: bottomPadding + 10, top: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            stops: const [0.0, 0.7, 1.0],
            colors: [
              Colors.black,
              Colors.black.withOpacity(0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MultiOptionModeSelector(
              currentMode: currentMode,
              onModeChanged: onModeChanged,
            ),
            const SizedBox(height: 12),
            if (currentMode == ScannerMode.document)
              GestureDetector(
                onTap: onToggleAutoMode,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAutoMode ? AppColors.primary : Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isAutoMode ? Colors.transparent : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAutoMode ? Icons.auto_awesome_rounded : Icons.touch_app_rounded,
                        color: isAutoMode ? Colors.white : Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isAutoMode ? "AUTO" : "MANUAL",
                        style: GoogleFonts.inter(
                          color: isAutoMode ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. IMPORT / DIGITAL DRAW (LEFT)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: currentMode == ScannerMode.signature
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildActionIcon(
                                  icon: Icons.draw_rounded,
                                  onTap: onDrawSignature,
                                  label: "DRAW",
                                  size: 42,
                                ),
                                const SizedBox(width: 8),
                                _buildActionIcon(
                                  icon: Icons.image_rounded,
                                  onTap: onImportSignature,
                                  label: "IMAGE",
                                  size: 42,
                                ),
                              ],
                            )
                          : _buildActionIcon(
                              icon: Icons.photo_library_rounded,
                              onTap: onGalleryImport,
                              label: "IMPORT",
                            ),
                    ),
                  ),

                  // 2. MAIN CAPTURE TRIGGER
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _CaptureButton(onTap: onCapture),
                  ),

                  // 3. SESSION PREVIEW (RIGHT)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildSessionThumbnail(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionThumbnail() {
    final hasItems = currentSessionList.isNotEmpty;
    final itemCount = currentSessionList.length;

    return GestureDetector(
      onTap: hasItems ? onOpenSession : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Photo Stack Effect (Multiple layers for depth)
              if (itemCount > 1)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                  ),
                ),
              if (itemCount > 2)
                Positioned(
                  top: 3,
                  left: 3,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                  ),
                ),
              
              // Main Thumbnail
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: hasItems ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ] : null,
                  border: Border.all(
                    color: hasItems ? AppColors.primary.withOpacity(0.8) : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.5),
                  child: hasItems
                      ? Image.file(
                          File(sessionThumbnails[currentSessionList.last] ?? currentSessionList.last),
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          cacheWidth: 150,
                        )
                      : Container(
                          color: Colors.white.withOpacity(0.05),
                          child: const Icon(
                            Icons.collections_rounded,
                            color: Colors.white38,
                            size: 22,
                          ),
                        ),
                ),
              ),
              
              // Professional Notification Badge
              if (hasItems)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2), // "Cut-out" look
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    child: Center(
                      child: Text(
                        "$itemCount",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required VoidCallback onTap,
    required String label,
    double size = 48,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12, width: 1.2),
            ),
            child: Center(
              child: Icon(
                icon,
                color: Colors.white,
                size: size * 0.45,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CaptureButton({required this.onTap});

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Premium Outer Ring
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
            ),
            // Middle translucent layer
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
