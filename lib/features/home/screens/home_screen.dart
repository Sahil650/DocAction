import 'package:flutter/material.dart';
import '../widgets/view_toggle.dart';
import '../widgets/sort_dropdown.dart';
import '../widgets/sidebar_drawer.dart';
import 'document_detail_screen.dart';
import 'settings_screen.dart';
import '../widgets/document_card.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../scanner/widgets/scan_mode_selector_sheet.dart';
import '../../../data/models/document_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/services/storage_service.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../pdf/screens/pdf_password_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storageService = StorageService();
  final _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<DocumentModel> _documents = [];
  List<DocumentModel> _filteredDocs = [];
  bool _isLoading = true;
  bool _isGridView = true;
  int _currentIndex = 0;
  String _sortBy = "Modified";
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _updateFilteredDocs();
    });
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    final docs = await _storageService.loadDocuments();
    if (mounted) {
      setState(() {
        _documents = docs;
        _updateFilteredDocs();
        _isLoading = false;
      });
    }
  }

  void _updateFilteredDocs() {
    final query = _searchQuery.toLowerCase();
    List<DocumentModel> filtered = _documents.where((doc) {
      if (query.isEmpty) return true;
      return doc.name.toLowerCase().contains(query);
    }).toList();

    if (_sortBy == "Name") {
      filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_sortBy == "Date") {
      filtered.sort((a, b) => b.date.compareTo(a.date));
    } else {
      filtered.sort((a, b) => b.id.compareTo(a.id));
    }
    _filteredDocs = filtered;
  }

  Future<void> _deleteDocument(String id) async {
    await _storageService.deleteDocument(id);
    _loadDocuments();
  }

  Future<void> _showNewFolderDialog() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          l10n.translate('new_folder'),
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.translate('folder_name'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final folder = FolderModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  createdAt: DateTime.now(),
                );
                await _storageService.saveFolder(folder);
                if (mounted) {
                  Navigator.pop(context);
                  _loadDocuments(); // Refresh to show folders if needed (folders are loaded separately in some views)
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l10n.translate('create')),
          ),
        ],
      ),
    );
  }

  Future<void> _importFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'docx'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        final file = File(result.files.single.path!);
        final ext = p.extension(file.path).toLowerCase();
        
        final pdfService = PdfService();
        String? finalPdfPath;
        List<String> imagePaths = [];
        int pageCount = 1;

        if (ext == '.pdf') {
          finalPdfPath = file.path;
          final bytes = await file.readAsBytes();
          pageCount = pdfService.getPdfPageCount(bytes);
        } else if (ext == '.docx') {
          final pdfBytes = await pdfService.convertWordToPdf(file);
          final directory = await getApplicationDocumentsDirectory();
          final fileName = "${p.basenameWithoutExtension(file.path)}_${DateTime.now().millisecondsSinceEpoch}.pdf";
          final pdfFile = File("${directory.path}/$fileName");
          await pdfFile.writeAsBytes(pdfBytes);
          finalPdfPath = pdfFile.path;
          pageCount = pdfService.getPdfPageCount(pdfBytes);
        } else {
          imagePaths = [file.path];
          pageCount = 1;
        }

        await _storageService.saveDocumentNamed(
          name: p.basenameWithoutExtension(file.path),
          imagePaths: imagePaths,
          pdfPath: finalPdfPath,
          pageCount: pageCount,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('import_success')),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadDocuments();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${l10n.translate('import_failed')}: $e"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildDocumentItem(DocumentModel doc) {
    return DocumentCard(
      key: ValueKey(doc.id),
      document: doc,
      onDelete: () => _deleteDocument(doc.id),
      onProtect: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PdfPasswordScreen(initialDocument: doc)),
        );
      },
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => DocumentDetailScreen(document: doc)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final l10n = AppLocalizations.of(context);
    final isWide = MediaQuery.of(context).size.width > 900;

    final mainContent = CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      l10n.translate('my_documents'),
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showNewFolderDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.plus, size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.translate('new_folder'),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurfaceLight : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.black.withOpacity(0.04)),
                  boxShadow: [
                    if (Theme.of(context).brightness == Brightness.light)
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
                  decoration: InputDecoration(
                    hintText: l10n.translate('search_hint'),
                    hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    prefixIcon: Icon(LucideIcons.search, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.primary, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ViewToggle(isGrid: _isGridView, onChanged: (val) => setState(() => _isGridView = val)),
                  SortDropdown(selectedValue: _sortBy, onChanged: (val) {
                    setState(() {
                      _sortBy = val!;
                      _updateFilteredDocs();
                    });
                  }),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (_isLoading)
          SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: isWide ? 300 : 400,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate((context, index) => const DocumentCardSkeleton(), childCount: 6),
          )
        else if (_filteredDocs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.fileSearch, size: 64, color: Colors.grey[200]),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isEmpty ? l10n.translate('no_docs_msg') : l10n.translate('no_match_msg'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final autoGrid = constraints.crossAxisExtent >= 600;
                final useGrid = autoGrid || _isGridView;

                if (useGrid) {
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: isWide ? 300 : 400,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) => _buildDocumentItem(_filteredDocs[index]), childCount: _filteredDocs.length),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(padding: const EdgeInsets.only(bottom: 16), child: _buildDocumentItem(_filteredDocs[index])),
                    childCount: _filteredDocs.length,
                  ),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: isWide ? null : const SidebarDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: isWide ? null : IconButton(onPressed: () => _scaffoldKey.currentState?.openDrawer(), icon: Icon(LucideIcons.menu, color: Theme.of(context).colorScheme.primary)),
        title: Text(l10n.translate('my_scanner'), style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(onPressed: _importFile, icon: Icon(LucideIcons.filePlus, color: Theme.of(context).colorScheme.primary), tooltip: l10n.translate('import_pdf')),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())), icon: Icon(LucideIcons.settings, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
                if (index == 1) ScanModeSelectorSheet.show(context).then((_) { if (mounted) _loadDocuments(); });
              },
              backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.white,
              indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(icon: const Icon(LucideIcons.home), selectedIcon: const Icon(LucideIcons.home, color: AppColors.accent), label: Text(l10n.translate('nav_home'))),
                NavigationRailDestination(icon: const Icon(LucideIcons.scan), selectedIcon: const Icon(LucideIcons.scan, color: AppColors.accent), label: Text(l10n.translate('nav_scan'))),
                NavigationRailDestination(icon: const Icon(LucideIcons.settings), selectedIcon: const Icon(LucideIcons.settings, color: AppColors.accent), label: Text(l10n.translate('nav_settings'))),
              ],
            ),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: mainContent)),
        ],
      ),
      bottomNavigationBar: isWide ? null : BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) async {
          setState(() => _currentIndex = index);
          if (index == 1) {
            await ScanModeSelectorSheet.show(context);
            if (mounted) _loadDocuments();
          }
        },
      ),
      floatingActionButton: isWide ? null : FloatingActionButton(
        onPressed: () async {
          await ScanModeSelectorSheet.show(context);
          _loadDocuments();
        },
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.accent : AppColors.primary,
        child: const Icon(LucideIcons.camera, color: Colors.white),
      ),
    );
  }
}
