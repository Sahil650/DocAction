import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/models/photo_size_model.dart';
import '../../../shared/utils/app_localizations.dart';
import 'id_photo_session_screen.dart';

class IdPhotoSizeScreen extends StatefulWidget {
  const IdPhotoSizeScreen({super.key});

  @override
  State<IdPhotoSizeScreen> createState() => _IdPhotoSizeScreenState();
}

class _IdPhotoSizeScreenState extends State<IdPhotoSizeScreen> {
  late List<PhotoSizeModel> _sizes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    _sizes = [
      PhotoSizeModel(name: l10n.translate('photo_size_passport'), width: 35, height: 45, unit: "mm"),
      PhotoSizeModel(name: l10n.translate('photo_size_visa_us'), width: 2, height: 2, unit: "in"),
      PhotoSizeModel(name: l10n.translate('photo_size_id_card'), width: 30, height: 40, unit: "mm"),
      PhotoSizeModel(name: l10n.translate('photo_size_pan_card'), width: 25, height: 35, unit: "mm"),
      PhotoSizeModel(name: l10n.translate('photo_size_driving_license'), width: 30, height: 30, unit: "mm"),
    ];
  }

  Future<void> _handleCapture(PhotoSizeModel size) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (image != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IdPhotoSessionScreen(
            size: size,
            initialImagePath: image.path,
          ),
        ),
      );
    }
  }

  void _showAddCustomDialog() {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final widthController = TextEditingController();
    final heightController = TextEditingController();
    String selectedUnit = "mm";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.translate("add_custom_size"), style: const TextStyle(color: AppColors.primary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(nameController, l10n.translate("label_hint")),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildField(widthController, l10n.translate("width_label"), isNumber: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildField(heightController, l10n.translate("height_label"), isNumber: true)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _unitBtn("mm", selectedUnit, (u) => setDialogState(() => selectedUnit = u)),
                    const SizedBox(width: 10),
                    _unitBtn("in", selectedUnit, (u) => setDialogState(() => selectedUnit = u)),
                  ],
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.translate("cancel_btn")),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty && 
                    widthController.text.isNotEmpty && 
                    heightController.text.isNotEmpty) {
                  setState(() {
                    _sizes.add(PhotoSizeModel(
                      name: nameController.text,
                      width: double.parse(widthController.text),
                      height: double.parse(heightController.text),
                      unit: selectedUnit,
                    ));
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(l10n.translate("add_btn")),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String hint, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _unitBtn(String unit, String current, Function(String) onSelect) {
    bool isSelected = unit == current;
    return ChoiceChip(
      label: Text(unit),
      selected: isSelected,
      onSelected: (_) => onSelect(unit),
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xffF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xffF3F4F6),
        elevation: 0,
        title: Text(l10n.translate("select_id_photo_size"), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;
          final int crossAxisCount = width > 900 ? 4 : (width > 600 ? 3 : 2);
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: 180,
                    ),
                    itemCount: _sizes.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _sizes.length) {
                        return _buildAddCard(l10n);
                      }
                      final size = _sizes[index];
                      return _buildSizeCard(size);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSizeCard(PhotoSizeModel size) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _handleCapture(size),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50 * (size.aspectForPreview > 1.2 ? 1.2 : size.aspectForPreview),
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    border: Border.all(color: AppColors.primary, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(child: Icon(Icons.person, color: AppColors.primary, size: 24)),
                ),
                const SizedBox(height: 16),
                Text(
                  size.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  size.sizeString,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddCard(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _showAddCustomDialog,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 40),
              const SizedBox(height: 8),
              Text(
                l10n.translate("custom_size_card"),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
