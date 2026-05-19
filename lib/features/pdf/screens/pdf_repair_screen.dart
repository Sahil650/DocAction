import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/pdf_service.dart';
import 'pdf_viewer_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/document_selection_sheet.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../core/theme/app_colors.dart';


class RepairLog {
  final String message;
  final LogType type;
  final DateTime timestamp;

  RepairLog(this.message, this.type) : timestamp = DateTime.now();
}

enum LogType { info, warning, success, error, diagnostic }

class PdfRepairScreen extends StatefulWidget {
  const PdfRepairScreen({super.key});

  @override
  State<PdfRepairScreen> createState() => _PdfRepairScreenState();
}

class _PdfRepairScreenState extends State<PdfRepairScreen>
    with SingleTickerProviderStateMixin {
  // Removed hardcoded primaryGreen to use theme's primary color
  static const Color accentAmber = Color(0xffF59E0B);

  final _pdfService = PdfService();
  final _storageService = StorageService();
  AppLocalizations get l10n => AppLocalizations.of(context);

  File? _sourceFile;
  Uint8List? _sourceBytes;
  Uint8List? _repairedBytes;
  String? _selectedFileName;

  bool _isProcessing = false;
  final List<RepairLog> _logs = [];
  bool _isSuccess = false;
  bool _isHealthy = true;
  double _repairProgress = 0.0;
  String _currentStage = "Idle";

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _addLog(String msg, {LogType type = LogType.info}) {
    if (!mounted) return;
    setState(() => _logs.insert(0, RepairLog(msg, type)));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final sizeInKb = bytes.length / 1024;

      _logs.clear();
      _addLog(
        l10n
            .translate('selected_label')
            .replaceAll('{0}', result.files.single.name),
        type: LogType.info,
      );
      _addLog(
        l10n.translate('path_label').replaceAll('{0}', file.path),
        type: LogType.diagnostic,
      );
      _addLog(
        l10n
            .translate('size_label_kb')
            .replaceAll('{0}', sizeInKb.toStringAsFixed(2)),
        type: LogType.diagnostic,
      );

      if (bytes.isEmpty) {
        _addLog(l10n.translate('empty_file_error'), type: LogType.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.translate('empty_file_snack'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
        return;
      }

      final healthy = await _pdfService.isPdfHealthy(bytes);
      setState(() {
        _sourceFile = file;
        _selectedFileName = result.files.single.name;
        _sourceBytes = bytes;
        _isHealthy = healthy;
        _isSuccess = false;
        _repairedBytes = null;
        _repairProgress = 0.0;
        _currentStage = "idle";
      });
      if (!healthy) {
        _addLog(l10n.translate('healthcheck_error_log'), type: LogType.error);
      }
    }
  }

  Future<void> _pickFromLibrary() async {
    final doc = await showModalBottomSheet<DocumentModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentSelectionSheet(
        title: l10n.translate('from_library'),
        onlyPdfs: true,
      ),
    );

    if (doc != null) {
      final path = doc.pdfPath;
      if (path == null) {
        _addLog(l10n.translate('no_pdf_version_error'), type: LogType.error);
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        _addLog(
          l10n.translate('file_not_found_error').replaceAll('{0}', path),
          type: LogType.error,
        );
        return;
      }

      final bytes = await file.readAsBytes();
      final sizeInKb = bytes.length / 1024;

      _logs.clear();
      _addLog(
        l10n.translate('selected_label').replaceAll('{0}', doc.name),
        type: LogType.info,
      );
      _addLog(
        l10n.translate('path_label').replaceAll('{0}', path),
        type: LogType.diagnostic,
      );
      _addLog(
        l10n
            .translate('size_label_kb')
            .replaceAll('{0}', sizeInKb.toStringAsFixed(2)),
        type: LogType.diagnostic,
      );

      if (bytes.isEmpty) {
        _addLog(
          l10n.translate('library_file_empty_error'),
          type: LogType.error,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.translate('library_file_empty_snack'),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
        return;
      }

      final healthy = await _pdfService.isPdfHealthy(bytes);
      setState(() {
        _sourceFile = file;
        _selectedFileName = doc.name;
        _sourceBytes = bytes;
        _isHealthy = healthy;
        _repairedBytes = null;
        _isSuccess = false;
        _repairProgress = 0.0;
        _currentStage = "idle";
      });
      _addLog(
        "${l10n.translate('imported_label')}: ${doc.name}",
        type: healthy ? LogType.success : LogType.warning,
      );
      if (!healthy) {
        _addLog(l10n.translate('healthcheck_error'), type: LogType.error);
      }
    }
  }

  Future<void> _handleRepair() async {
    if (_sourceBytes == null || _sourceBytes!.isEmpty) {
      _addLog(l10n.translate('empty_file_error'), type: LogType.error);
      return;
    }

    setState(() {
      _isProcessing = true;
      _repairProgress = 0.1;
      _currentStage = "initializing_analysis";
    });

    _logs.clear();
    _addLog(l10n.translate('starting_repair_engine'), type: LogType.diagnostic);

    try {
      await Future.delayed(const Duration(milliseconds: 600));
      setState(() {
        _repairProgress = 0.3;
        _currentStage = "stabilizing_bytes";
      });
      _addLog(l10n.translate('byte_stream_norm'));

      await Future.delayed(const Duration(milliseconds: 800));
      setState(() {
        _repairProgress = 0.6;
        _currentStage = "reconstructing_structure";
      });
      _addLog(l10n.translate('structural_repair'), type: LogType.warning);

      final Uint8List result = await _pdfService.repairPdf(_sourceBytes!);

      setState(() {
        _repairedBytes = result;
        _isSuccess = true;
        _repairProgress = 1.0;
        _currentStage = "ready";
      });
      _addLog(l10n.translate('repair_success_log'), type: LogType.success);
    } catch (e) {
      _addLog(
        l10n.translate('fatal_recovery_error').replaceAll('{0}', e.toString()),
        type: LogType.error,
      );
      _addLog(l10n.translate('structure_too_far_gone'), type: LogType.info);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n
                  .translate('repair_failed_snack')
                  .replaceAll('{0}', e.toString()),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleSave() async {
    if (_repairedBytes == null) return;

    setState(() => _isProcessing = true);
    try {
      final name =
          "${l10n.translate('repaired_doc_prefix')}_${DateTime.now().millisecondsSinceEpoch}";
      final appDir = await getApplicationDocumentsDirectory();
      final internalPath = "${appDir.path}/final_pdfs/$name.pdf";
      final internalFile = File(internalPath);
      if (!await internalFile.parent.exists()) {
        await internalFile.parent.create(recursive: true);
      }
      await internalFile.writeAsBytes(_repairedBytes!);

      await _storageService.saveDocument(
        DocumentModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          date: DateTime.now(),
          imagePaths: [],
          pdfPath: internalPath,
        ),
      );

      if (Platform.isAndroid && await Permission.storage.request().isGranted) {
        final downDir = Directory(
          "/storage/emulated/0/Download/DocumentScanner/Repaired",
        );
        if (!await downDir.exists()) await downDir.create(recursive: true);
        await File("${downDir.path}/$name.pdf").writeAsBytes(_repairedBytes!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.translate('save_success_snack'),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xff10B981),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(_repairedBytes),
              title: l10n.translate('repaired_document'),
            ),
          ),
        );
      }
    } catch (e) {
      _addLog(
        l10n.translate('save_failed_log').replaceAll('{0}', e.toString()),
        type: LogType.error,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.translate('repair_pdf'),
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.chevronLeft, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      body: ResponsiveLayout(
        maxWidth: 600,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('repair_hint'),
                style: GoogleFonts.inter(
                  color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[600],
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              if (_sourceFile == null)
                _buildUploadHub()
              else ...[
                _buildFileStatusCard(),
                const SizedBox(height: 24),
                _buildDiagnosticsPanel(),
                const SizedBox(height: 32),
                if (!_isSuccess) _buildActionBtn() else _buildFinalActions(),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadHub() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppColors.darkSurface 
                : Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              if (Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: accentAmber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.shieldAlert,
                  size: 48,
                  color: accentAmber,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.translate('drop_corrupted_pdf'),
                style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.translate('repair_sub_hint'),
                style: GoogleFonts.inter(
                  color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        _premiumBtn(
          l10n.translate('select_file_label'),
          LucideIcons.uploadCloud,
          const Color(0xff3B82F6),
          _pickFile,
        ),
        const SizedBox(height: 16),
        _premiumBtn(
          l10n.translate('from_library').toUpperCase(),
          LucideIcons.layoutGrid,
          Theme.of(context).colorScheme.primary,
          _pickFromLibrary,
        ),
      ],
    );
  }

  Widget _premiumBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _buildFileStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkSurface 
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_isHealthy ? Colors.green : accentAmber)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isHealthy ? LucideIcons.check : LucideIcons.alertTriangle,
              color: _isHealthy ? Colors.green : accentAmber,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedFileName ?? "",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (_isHealthy ? Colors.green : Colors.red)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isHealthy
                            ? l10n.translate('healthy_status')
                            : l10n.translate('corrupted_status'),
                        style: GoogleFonts.inter(
                          color: _isHealthy ? Colors.green : Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isHealthy
                          ? l10n.translate('verified_integrity')
                          : l10n.translate('structural_instability'),
                      style: GoogleFonts.inter(
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _sourceFile = null),
            icon: Icon(LucideIcons.x, size: 20, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.translate('salvage_logs'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                   color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : Colors.grey[500],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.translate(_currentStage),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          height: 260,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : const Color(0xff0F172A),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.terminal,
                        color: Colors.white.withValues(alpha: 0.1),
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.translate('engine_standby'),
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.zero,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    Color color = Colors.white;
                    IconData icon = LucideIcons.circle;

                    switch (log.type) {
                      case LogType.warning:
                        color = const Color(0xffF59E0B);
                        icon = LucideIcons.alertCircle;
                        break;
                      case LogType.error:
                        color = const Color(0xffEF4444);
                        icon = LucideIcons.xCircle;
                        break;
                      case LogType.success:
                        color = const Color(0xff10B981);
                        icon = LucideIcons.checkCircle2;
                        break;
                      case LogType.diagnostic:
                        color = const Color(0xff3B82F6);
                        icon = LucideIcons.cpu;
                        break;
                      default:
                        color = Colors.white.withValues(alpha: 0.7);
                        icon = LucideIcons.chevronRight;
                        break;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(icon, color: color, size: 12),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              log.message,
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontFamily: "monospace",
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _repairProgress,
              backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : const Color(0xffE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionBtn() {
    return _premiumBtn(
      _isProcessing
          ? l10n.translate('salvaging_doc')
          : l10n.translate('repair_doc_label'),
      _isProcessing ? LucideIcons.refreshCw : LucideIcons.zap,
      _isProcessing ? Colors.grey[400]! : Theme.of(context).colorScheme.primary,
      _isProcessing ? () {} : _handleRepair,
    );
  }

  Widget _buildFinalActions() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : const Color(0xffF0FDF4),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : const Color(0xffBBF7D0), width: 2),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.green.withValues(alpha: 0.2) : const Color(0xffBBF7D0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.checkCircle2,
                  color: Color(0xff15803D),
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.translate('repair_successful'),
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('repair_success_hint'),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: const Color(0xff15803D),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _premiumBtn(
          l10n.translate('save_repair_label').toUpperCase(),
          LucideIcons.save,
          Theme.of(context).colorScheme.primary,
          _handleSave,
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() {
            _sourceFile = null;
            _repairedBytes = null;
            _isSuccess = false;
            _logs.clear();
          }),
          icon: const Icon(LucideIcons.refreshCw, size: 16, color: Colors.grey),
          label: Text(
            l10n.translate('repair_another'),
            style: GoogleFonts.inter(
              color: Colors.grey[600],
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
