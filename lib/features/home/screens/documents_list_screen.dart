import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/view_toggle.dart';
import '../widgets/sort_dropdown.dart';
import '../widgets/document_card.dart';
import '../widgets/document_list_tile.dart';
import '../screens/document_detail_screen.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/pdf_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/models/folder_model.dart';
import '../widgets/folder_card.dart';
import '../widgets/folder_list_tile.dart';
import 'package:doc_scanner_app/shared/utils/app_localizations.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';

class DocumentsListScreen extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool isPickerMode;
  final Function(bool isSelecting, int count) onSelectionChanged;

  const DocumentsListScreen({
    super.key,
    required this.scaffoldKey,
    required this.onSelectionChanged,
    this.isPickerMode = false,
  });

  @override
  State<DocumentsListScreen> createState() => DocumentsListScreenState();
}

class DocumentsListScreenState extends State<DocumentsListScreen> {
  final _storageService = StorageService();
  final _pdfService = PdfService();
  final _searchController = TextEditingController();

  List<DocumentModel> _documents = [];
  List<FolderModel> _folders = [];
  List<DocumentModel> _filteredDocuments = [];
  List<FolderModel> _filteredFolders = [];
  String? _currentFolderId; // Null means root
  final List<String> _navigationHistory = []; // For breadcrumbs

  bool _isLoading = true;
  bool _isGridView = true;
  String _sortBy = "Date";
  String _searchQuery = "";

  // Selection Logic
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    loadDocuments();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
          _updateFilteredLists();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadDocuments() async {
    setState(() => _isLoading = true);
    final docs = await _storageService.loadDocuments();
    final folders = await _storageService.loadFolders(
      parentId: _currentFolderId,
    );
    setState(() {
      _documents = docs;
      _folders = folders;
      _updateFilteredLists();
      _isLoading = false;
    });
  }

  void _navigateToFolder(String folderId) {
    setState(() {
      _navigationHistory.add(_currentFolderId ?? 'root');
      _currentFolderId = folderId;
    });
    loadDocuments();
  }

  void _navigateBack() {
    if (_navigationHistory.isNotEmpty) {
      setState(() {
        final last = _navigationHistory.removeLast();
        _currentFolderId = last == 'root' ? null : last;
      });
      loadDocuments();
    }
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.translate('new_folder'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.translate('folder_name'),
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.translate('cancel').toUpperCase(),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n.translate('create').toUpperCase()),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      final folder = FolderModel(
        id: const Uuid().v4(),
        name: newName,
        createdAt: DateTime.now(),
        parentId: _currentFolderId,
      );
      await _storageService.saveFolder(folder);
      loadDocuments();
    }
  }

  Future<void> _deleteFolder(String folderId) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('delete_folder')),
        content: Text(l10n.translate('delete_folder_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.translate('delete_forever'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storageService.deleteFolder(folderId);
      loadDocuments();
    }
  }

  void toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _isSelectionMode = _selectedIds.isNotEmpty;
    });
    widget.onSelectionChanged(_isSelectionMode, _selectedIds.length);
  }

  void clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
    widget.onSelectionChanged(false, 0);
  }

  void toggleSelectAll() {
    final visibleDocs = _filteredDocuments;
    setState(() {
      // Check if all visible docs are already selected
      bool allSelected = true;
      if (visibleDocs.isEmpty) {
        allSelected = false;
      } else {
        for (var doc in visibleDocs) {
          if (!_selectedIds.contains(doc.id)) {
            allSelected = false;
            break;
          }
        }
      }

      if (allSelected && visibleDocs.isNotEmpty) {
        // Deselect only visible ones
        for (var doc in visibleDocs) {
          _selectedIds.remove(doc.id);
        }
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _isSelectionMode = true;
        for (var doc in visibleDocs) {
          _selectedIds.add(doc.id);
        }
      }
    });
    widget.onSelectionChanged(_isSelectionMode, _selectedIds.length);
  }

  Future<void> deleteSelected() async {
    for (var id in _selectedIds) {
      await _storageService.deleteDocument(id);
    }
    clearSelection();
    loadDocuments();
  }

  Future<void> shareSelected() async {
    final docsToShare = _documents
        .where((d) => _selectedIds.contains(d.id))
        .toList();
    if (docsToShare.isEmpty) return;

    List<XFile> files = [];
    for (var doc in docsToShare) {
      if (doc.pdfPath != null && File(doc.pdfPath!).existsSync()) {
        files.add(XFile(doc.pdfPath!));
      } else {
        for (var path in doc.imagePaths) {
          files.add(XFile(path));
        }
      }
    }

    if (files.isNotEmpty) {
      await Share.shareXFiles(
        files,
        text: 'Sharing ${docsToShare.length} documents',
      );
    }
  }

  Future<void> _deleteDocument(String id) async {
    await _storageService.deleteDocument(id);
    loadDocuments();
  }

  Future<void> _renameDocument(DocumentModel doc) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: doc.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('rename_doc')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.translate('enter_new_name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.translate('save')),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != doc.name) {
      await _storageService.renameDocument(doc.id, newName);
      loadDocuments();
    }
  }

  void _updateFilteredLists() {
    _filteredFolders = _folders.where((folder) {
      return folder.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    List<DocumentModel> filtered = _documents.where((doc) {
      final matchesSearch = doc.name.toLowerCase().contains(_searchQuery.toLowerCase());
      
      // If searching, search globally across all folders
      if (_searchQuery.isNotEmpty) return matchesSearch;
      
      // Otherwise, only show items in the current folder
      return doc.folderId == _currentFolderId && matchesSearch;
    }).toList();

    if (_sortBy == "Name") {
      filtered.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } else if (_sortBy == "Date") {
      filtered.sort((a, b) => b.date.compareTo(a.date));
    } else {
      filtered.sort((a, b) => b.id.compareTo(a.id));
    }

    _filteredDocuments = filtered;
  }

  Future<void> _exportDocument(DocumentModel doc) async {
    try {
      String? filePath = doc.pdfPath;
      final quality = SettingsService().pdfQuality;

      // If it's a scan (has images), we re-generate the PDF using current quality setting
      // to ensure the export respects the user's preference.
      if (doc.imagePaths.isNotEmpty) {
        final bytes = await _pdfService.compileImagesToPdf(
          doc.imagePaths,
          quality: quality,
        );
        final tempDir = await getTemporaryDirectory();
        final sanitizedName = StorageService.sanitizeFilename(doc.name);
        final tempFile = File('${tempDir.path}/$sanitizedName.pdf');
        await tempFile.writeAsBytes(bytes);
        filePath = tempFile.path;
      } else if (filePath == null || !File(filePath).existsSync()) {
        final l10n = AppLocalizations.of(context);
        _showSnackBar(l10n.translate('no_content_export'));
        return;
      }

      // Instead of just sharing, we use FilePicker to let the user save to a specific location
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF to device',
        fileName: '${StorageService.sanitizeFilename(doc.name)}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: await File(filePath).readAsBytes(),
      );

      if (result != null) {
        final l10n = AppLocalizations.of(context);
        _showSnackBar(l10n.translate('saved_to').replaceFirst('{0}', result));
      }
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      _showSnackBar(
        l10n.translate('export_failed').replaceFirst('{0}', e.toString()),
      );
    }
  }

  Future<void> _showFolderPicker(List<String> docIds) async {
    final allFolders = await _storageService.loadAllFolders();

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('move_to_folder')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFolders.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(l10n.translate('root_documents')),
                  onTap: () {
                    _moveDocumentsToFolder(docIds, null);
                    Navigator.pop(context);
                  },
                );
              }
              final folder = allFolders[index - 1];
              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xff3B82F6)),
                title: Text(folder.name),
                onTap: () {
                  _moveDocumentsToFolder(docIds, folder.id);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
        ],
      ),
    );
  }

  Future<void> _moveDocumentsToFolder(
    List<String> docIds,
    String? folderId,
  ) async {
    try {
      await _storageService.moveDocumentsToFolder(docIds, folderId);
      final l10n = AppLocalizations.of(context);
      final itemLabel = docIds.length == 1
          ? l10n.translate('item_label')
          : l10n.translate('items_label');
      _showSnackBar(
        l10n
            .translate('moved_items')
            .replaceFirst('{0}', docIds.length.toString())
            .replaceFirst('{1}', itemLabel),
      );
      clearSelection();
      loadDocuments();
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      _showSnackBar(
        l10n.translate('move_failed').replaceFirst('{0}', e.toString()),
      );
    }
  }

  void showMoveSelected() {
    _showFolderPicker(_selectedIds.toList());
  }

  Widget _buildDocumentItem(DocumentModel doc, bool useGrid) {
    final isSelected = _selectedIds.contains(doc.id);

    if (useGrid) {
      return DocumentCard(
        document: doc,
        isSelectionMode: _isSelectionMode,
        isSelected: isSelected,
        onDelete: () => _deleteDocument(doc.id),
        onRename: () => _renameDocument(doc),
        onExport: () => _exportDocument(doc),
        onMove: () => _showFolderPicker([doc.id]),
        onTap: () {
          if (widget.isPickerMode) {
            Navigator.pop(context, doc);
            return;
          }
          if (_isSelectionMode) {
            toggleSelection(doc.id);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DocumentDetailScreen(document: doc),
              ),
            );
          }
        },
        onLongPress: widget.isPickerMode ? () {} : () => toggleSelection(doc.id),
      );
    } else {
      return DocumentListTile(
        document: doc,
        isSelectionMode: _isSelectionMode,
        isSelected: isSelected,
        onDelete: () => _deleteDocument(doc.id),
        onRename: () => _renameDocument(doc),
        onExport: () => _exportDocument(doc),
        onMove: () => _showFolderPicker([doc.id]),
        onTap: () {
          if (widget.isPickerMode) {
            Navigator.pop(context, doc);
            return;
          }
          if (_isSelectionMode) {
            toggleSelection(doc.id);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DocumentDetailScreen(document: doc),
              ),
            );
          }
        },
        onLongPress: widget.isPickerMode ? () {} : () => toggleSelection(doc.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayDocs = _filteredDocuments;
    final displayFolders = _filteredFolders;

    return SafeArea(
      top: false,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: RefreshIndicator(
          onRefresh: loadDocuments,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _buildHeader(l10n),
                    const SizedBox(height: 12),
                    _buildSearchBar(l10n),
                    const SizedBox(height: 12),
                    if (_currentFolderId != null) _buildBreadcrumbs(l10n),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [_buildFolderActions(l10n)],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        SortDropdown(
                          selectedValue: _sortBy,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _sortBy = val;
                                _updateFilteredLists();
                              });
                            }
                          },
                        ),
                        const Spacer(),
                        ViewToggle(
                          isGrid: _isGridView,
                          onChanged: (val) => setState(() => _isGridView = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (_isLoading)
                _buildLoadingSkeletons()
              else if (displayFolders.isEmpty && displayDocs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(l10n),
                )
              else ...[
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final crossExtent = constraints.crossAxisExtent;
                    final useGrid = (crossExtent >= 600) || _isGridView;

                    // Dynamic extent based on screen width
                    double maxExtent = 180;
                    if (crossExtent > 1200) {
                      maxExtent = 280;
                    } else if (crossExtent > 900)
                      maxExtent = 240;
                    else if (crossExtent > 600)
                      maxExtent = 200;

                    return SliverMainAxisGroup(
                      slivers: [
                        if (displayFolders.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.only(bottom: 20),
                            sliver: useGrid
                                ? SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: maxExtent,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 16,
                                          childAspectRatio: 0.78,
                                        ),
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final folder = displayFolders[index];
                                      final isSelected = _selectedIds.contains(
                                        folder.id,
                                      );
                                      final count = _documents
                                          .where((d) => d.folderId == folder.id)
                                          .length;
                                      return FolderCard(
                                        folder: folder,
                                        documentCount: count,
                                        isSelectionMode: _isSelectionMode,
                                        isSelected: isSelected,
                                        onTap: () {
                                          if (_isSelectionMode) {
                                            toggleSelection(folder.id);
                                          } else {
                                            _navigateToFolder(folder.id);
                                          }
                                        },
                                        onLongPress: () =>
                                            toggleSelection(folder.id),
                                        onDelete: () =>
                                            _deleteFolder(folder.id),
                                        onRename: () {},
                                      );
                                    }, childCount: displayFolders.length),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final folder = displayFolders[index];
                                      final isSelected = _selectedIds.contains(
                                        folder.id,
                                      );
                                      final count = _documents
                                          .where((d) => d.folderId == folder.id)
                                          .length;
                                      return FolderListTile(
                                        folder: folder,
                                        documentCount: count,
                                        isSelectionMode: _isSelectionMode,
                                        isSelected: isSelected,
                                        onTap: () {
                                          if (_isSelectionMode) {
                                            toggleSelection(folder.id);
                                          } else {
                                            _navigateToFolder(folder.id);
                                          }
                                        },
                                        onLongPress: () =>
                                            toggleSelection(folder.id),
                                        onDelete: () =>
                                            _deleteFolder(folder.id),
                                        onRename: () {},
                                      );
                                    }, childCount: displayFolders.length),
                                  ),
                          ),
                        if (displayDocs.isNotEmpty)
                          useGrid
                              ? SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: maxExtent,
                                        mainAxisSpacing: 16,
                                        crossAxisSpacing: 16,
                                        mainAxisExtent: maxExtent * 1.25,
                                      ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) => _buildDocumentItem(
                                      displayDocs[index],
                                      true,
                                    ),
                                    childCount: displayDocs.length,
                                  ),
                                )
                              : SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) => _buildDocumentItem(
                                      displayDocs[index],
                                      false,
                                    ),
                                    childCount: displayDocs.length,
                                  ),
                                ),
                      ],
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentFolderId == null
                  ? l10n.translate('my_documents')
                  : l10n.translate('folder_content'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : AppColors.primary,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurfaceLight
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkBorder
              : Colors.black.withOpacity(0.04),
        ),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : AppColors.primary,
        ),
        decoration: InputDecoration(
          hintText: l10n.translate('search_docs'),
          hintStyle: GoogleFonts.plusJakartaSans(
            color: Colors.grey[400],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            LucideIcons.search,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkTextSecondary
                : AppColors.primary,
            size: 18,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _navigateBack,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.chevronLeft,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.translate('back_to_library'),
                style: GoogleFonts.plusJakartaSans(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderActions(AppLocalizations l10n) {
    return GestureDetector(
      onTap: _createFolder,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.plus, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.translate('new_folder'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.folderSearch,
            size: 64,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBorder
                : Colors.grey[200],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('no_docs_msg'),
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey[500],
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeletons() {
    return SliverFillRemaining(
      child: Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isSuccess = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess
            ? Theme.of(context).colorScheme.primary
            : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
