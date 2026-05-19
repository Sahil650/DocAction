import 'package:flutter/material.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

class SortDropdown extends StatelessWidget {
  final String selectedValue;
  final ValueChanged<String?> onChanged;

  const SortDropdown({
    super.key,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurfaceLight 
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark 
              ? AppColors.darkBorder 
              : Colors.grey[200]!, 
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sort_rounded, 
            size: 18, 
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Text(
            l10n.translate('sort_by'),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded, 
                size: 20, 
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
              ),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white 
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              items: [
                _buildMenuItem(l10n.translate('sort_modified'), "Modified"),
                _buildMenuItem(l10n.translate('sort_name'), "Name"),
                _buildMenuItem(l10n.translate('sort_date'), "Date"),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _buildMenuItem(String label, String value) {
    return DropdownMenuItem(
      value: value,
      child: Text(label),
    );
  }
}
