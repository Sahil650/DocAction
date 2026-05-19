import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/edge_detector.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/ocr_service.dart';
import 'package:intl/intl.dart';
import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'ocr_result_screen.dart';

class MakeACopyEditScreen extends StatefulWidget {
  final String imagePath;
  final bool isSessionMode;

  const MakeACopyEditScreen({
    super.key,
    required this.imagePath,
    this.isSessionMode = false,
  });

  @override
  State<MakeACopyEditScreen> createState() => _MakeACopyEditScreenState();
}

class _MakeACopyEditScreenState extends State<MakeACopyEditScreen> {
  late String _currentPath;
  String _activeFilter = 'original';
  bool _isProcessing = false;
  final StorageService _storageService = StorageService();
  final OCRService _ocrService = OCRService();

  // Manual Adjustments
  double _brightness = 0.0;
  double _contrast = 1.1;

  // UI State
  String _currentTab = 'filters'; // 'filters' or 'tune'

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
  }

  Future<void> _applyManualAdjustments() async {
    setState(() => _isProcessing = true);
    try {
      final adjustedPath = await EdgeDetector.applyFilter(
        widget.imagePath, // Always start from original for manual tuning
        'adjust',
        params: {
          'brightness': _brightness,
          'contrast': _contrast,
        },
      );
      setState(() {
        _currentPath = adjustedPath;
        _activeFilter = 'custom';
      });
    } catch (e) {
       // handle error
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyFilter(String filter) async {
    if (_activeFilter == filter && filter != 'rotate') return;
    
    // If switching to a preset filter, reset manual adjustments
    if (filter != 'rotate' && filter != 'custom') {
      _brightness = 0.0;
      _contrast = 1.1;
    }

    setState(() => _isProcessing = true);
    try {
      if (filter == 'original') {
        setState(() {
          _currentPath = widget.imagePath;
          _activeFilter = filter;
        });
      } else {
        final filteredPath = await EdgeDetector.applyFilter(
          filter == 'rotate' ? _currentPath : widget.imagePath,
          filter,
        );
        setState(() {
          _currentPath = filteredPath;
          if (filter != 'rotate') _activeFilter = filter;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _performOCR() async {
    setState(() => _isProcessing = true);
    try {
      final result = await _ocrService.getRecognizedText(_currentPath);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OCRResultScreen(
              imagePaths: [_currentPath],
              extractedText: result.text,
              ocrData: {"0": result},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("OCR Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveDocument() async {
    if (widget.isSessionMode) {
      Navigator.pop(context, _currentPath);
      return;
    }

    final TextEditingController controller = TextEditingController(
      text: "Scan ${DateFormat('MMM dd, HH:mm').format(DateTime.now())}",
    );

    final String? title = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Save",
      pageBuilder: (context, anim1, anim2) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Save Document",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Document Title",
                    labelStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white),
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("CANCEL", style: TextStyle(color: Colors.white60)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (title != null && title.isNotEmpty) {
      setState(() => _isProcessing = true);
      try {
        await _storageService.saveDocumentNamed(
          name: title,
          imagePaths: [_currentPath],
        );
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving: $e")),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Light grey background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isSessionMode ? "PAGE PREVIEW" : "ENHANCE",
          style: GoogleFonts.inter(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 14,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saveDocument,
              child: Text(
                "DONE",
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.black.withOpacity(0.05), height: 1),
        ),
      ),
      body: Column(
        children: [
          // Expanded Image View (No bulky margins, sleek background)
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF1F5F9), // Very subtle grey background to make document pop
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Hero(
                          tag: widget.imagePath,
                          child: Image.file(
                            File(_currentPath),
                            key: ValueKey(_currentPath),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_isProcessing)
                    Container(
                      color: Colors.white.withOpacity(0.8),
                      child: const Center(
                        child: CircularProgressIndicator(color: Color(0xFF1E293B)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Tab Content Area (Filters or Tune)
          Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_currentTab == 'tune') _buildTunePanel(),
                if (_currentTab == 'filters') _buildFiltersPanel(),
                
                // Bottom Navigation Bar
                _buildBottomNavBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(LucideIcons.sparkles, "Filters", _currentTab == 'filters', () => setState(() => _currentTab = 'filters')),
          _navItem(LucideIcons.sliders, "Tune", _currentTab == 'tune', () => setState(() => _currentTab = 'tune')),
          _navItem(LucideIcons.rotateCw, "Rotate", false, () => _applyFilter('rotate')),
          _navItem(LucideIcons.fileText, "OCR", false, _performOCR),
          _navItem(LucideIcons.camera, "Retake", false, () {
             if (widget.isSessionMode) {
               Navigator.pop(context, "RETAKE");
             } else {
               Navigator.pop(context); // Go back to crop
             }
          }),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon, 
            color: isActive ? AppColors.primary : const Color(0xFF64748B), 
            size: 24,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isActive ? AppColors.primary : const Color(0xFF64748B),
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return Container(
      height: 120,
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _filterOption("Original", 'original', LucideIcons.image),
          _filterOption("Magic", 'magic', LucideIcons.sparkles),
          _filterOption("Gray", 'gray', LucideIcons.filter),
          _filterOption("B&W", 'bw', LucideIcons.scan),
        ],
      ),
    );
  }

  Widget _filterOption(String label, String filter, IconData icon) {
    final bool isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => _applyFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary : const Color(0xFFE2E8F0),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primary : const Color(0xFF94A3B8),
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTunePanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Column(
        children: [
          _adjustmentSlider(
            label: "Brightness",
            value: _brightness,
            min: -50.0,
            max: 50.0,
            onChanged: (val) {
              setState(() => _brightness = val);
            },
            onChangeEnd: (_) => _applyManualAdjustments(),
          ),
          const SizedBox(height: 12),
          _adjustmentSlider(
            label: "Contrast",
            value: _contrast,
            min: 0.5,
            max: 2.0,
            onChanged: (val) {
              setState(() => _contrast = val);
            },
            onChangeEnd: (_) => _applyManualAdjustments(),
          ),
        ],
      ),
    );
  }

  Widget _adjustmentSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }
}
