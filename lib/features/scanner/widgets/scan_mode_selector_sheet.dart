import 'package:flutter/material.dart';
import '../models/scanner_mode.dart';
import '../screens/universal_scanner_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';

class ScanModeSelectorSheet extends StatelessWidget {
  const ScanModeSelectorSheet({super.key});

  static Future<void> show(BuildContext context, {VoidCallback? onRefresh}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const ScanModeSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.translate('scan_prompt'),
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xff1A1C1E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('scan_sub'),
              style: GoogleFonts.inter(
                color: Colors.grey[500],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 0.85,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildModeItem(
                  context,
                  ScannerMode.document,
                  const Color(0xff4CAF50),
                ),
                _buildModeItem(
                  context,
                  ScannerMode.qrCode,
                  const Color(0xff00BCD4),
                ),
                _buildModeItem(
                  context,
                  ScannerMode.signature,
                  const Color(0xff9C27B0),
                ),
                _buildModeItem(
                  context,
                  ScannerMode.photo,
                  const Color(0xff607D8B),
                ),
                _buildModeItem(
                  context,
                  ScannerMode.ocr,
                  const Color(0xffFF9800),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildModeItem(BuildContext context, ScannerMode mode, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // Close sheet
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => UniversalScannerScreen(initialMode: mode)),
        );
      },
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.1), width: 1.5),
            ),
            child: Icon(mode.icon, color: color, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            mode.label(context),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xff1A1C1E),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
