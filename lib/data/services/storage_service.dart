import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../models/scan_result_model.dart';
import 'image_optimization_service.dart';
import 'pdf_service.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static String sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static const String _fileName = 'documents.json';
  static const String _foldersFileName = 'folders.json';
  final _optimizationService = ImageOptimizationService();
  final _pdfService = PdfService();

  // In-memory cache for better performance
  List<DocumentModel>? _documentsCache;
  List<FolderModel>? _foldersCache;

  void clearCache() {
    _documentsCache = null;
    _foldersCache = null;
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File(p.join(path, _fileName));
  }

  Future<File> get _foldersFile async {
    final path = await _localPath;
    return File(p.join(path, _foldersFileName));
  }

  Future<List<DocumentModel>> loadDocuments({
    bool forceRefresh = false,
    bool includeDeleted = false,
  }) async {
    try {
      if (_documentsCache != null && !forceRefresh) {
        if (includeDeleted) return List.from(_documentsCache!);
        return _documentsCache!.where((doc) => !doc.isDeleted).toList();
      }

      final file = await _localFile;
      if (!await file.exists()) {
        _documentsCache = [];
        return [];
      }
      final contents = await file.readAsString();
      
      // Moving heavy JSON decoding to background isolate
      final allDocs = await Isolate.run(() => DocumentModel.decode(contents));
      _documentsCache = allDocs;
      
      if (includeDeleted) return List.from(allDocs);
      return allDocs.where((doc) => !doc.isDeleted).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<DocumentModel>> loadDeletedDocuments() async {
    final allDocs = await loadDocuments(includeDeleted: true);
    return allDocs.where((doc) => doc.isDeleted).toList();
  }

  Future<List<DocumentModel>> loadDocumentsInFolder(String? folderId) async {
    final allDocs = await loadDocuments();
    return allDocs.where((doc) => doc.folderId == folderId).toList();
  }

  // --- Folder Management ---

  Future<List<FolderModel>> loadAllFolders() async {
    try {
      final file = await _foldersFile;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      return await Isolate.run(() => FolderModel.decode(contents));
    } catch (e) {
      return [];
    }
  }

  Future<List<FolderModel>> loadFolders({
    String? parentId,
    bool forceRefresh = false,
  }) async {
    try {
      if (_foldersCache != null && !forceRefresh) {
        return _foldersCache!.where((f) => f.parentId == parentId).toList();
      }

      final file = await _foldersFile;
      if (!await file.exists()) {
        _foldersCache = [];
        return [];
      }
      final contents = await file.readAsString();
      final allFolders = await Isolate.run(() => FolderModel.decode(contents));
      _foldersCache = allFolders;
      
      return allFolders.where((f) => f.parentId == parentId).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveFolder(FolderModel folder) async {
    final file = await _foldersFile;
    List<FolderModel> folders = [];
    if (await file.exists()) {
      folders = FolderModel.decode(await file.readAsString());
    }

    // Check if update or new
    final idx = folders.indexWhere((f) => f.id == folder.id);
    if (idx != -1) {
      folders[idx] = folder;
    } else {
      folders.insert(0, folder);
    }

    final jsonString = await Isolate.run(() => FolderModel.encode(folders));
    _foldersCache = folders; // Update cache
    await file.writeAsString(jsonString);
  }

  Future<void> deleteFolder(String folderId) async {
    // 1. Remove folder
    final file = await _foldersFile;
    if (await file.exists()) {
      final folders = FolderModel.decode(await file.readAsString());
      folders.removeWhere((f) => f.id == folderId);
      final jsonString = await Isolate.run(() => FolderModel.encode(folders));
      _foldersCache = folders; // Update cache
      await file.writeAsString(jsonString);
    }

    // 2. Unset folderId for all documents in this folder (move to root)
    final docs = await loadDocuments(includeDeleted: true);
    bool changed = false;
    for (int i = 0; i < docs.length; i++) {
      if (docs[i].folderId == folderId) {
        docs[i] = docs[i].copyWith(folderId: null);
        changed = true;
      }
    }

    if (changed) {
      final docFile = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(docs));
      _documentsCache = docs; // Update cache
      await docFile.writeAsString(jsonString);
    }
  }

  Future<void> moveDocumentsToFolder(
    List<String> docIds,
    String? folderId,
  ) async {
    final docs = await loadDocuments(includeDeleted: true);
    bool changed = false;
    for (var id in docIds) {
      final idx = docs.indexWhere((d) => d.id == id);
      if (idx != -1) {
        docs[idx] = docs[idx].copyWith(folderId: folderId);
        changed = true;
      }
    }
    if (changed) {
      final file = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(docs));
      _documentsCache = docs; // Update cache
      await file.writeAsString(jsonString);
    }
  }

  Future<void> saveDocument(
    DocumentModel document, {
    String? name,
    List<String>? imagePaths,
    String? pdfPath,
    int? pageCount,
  }) async {
    final documents = await loadDocuments(includeDeleted: true);

    DocumentModel finalDoc = document;

    // Optimization Phase
    List<String> optimizedImages = imagePaths ?? document.imagePaths;
    List<String> thumbPaths = [];

    bool isEncrypted = document.isEncrypted;

    // Optimize images if provided
    if (optimizedImages.isNotEmpty) {
      // Parallelize image optimization to avoid sequential bottleneck
      final results = await Future.wait(
        optimizedImages.map((path) => _optimizationService.processImage(path)),
      );
      
      optimizedImages = results.map((r) => r['optimized']!).toList();
      thumbPaths = results.map((r) => r['thumbnail']!).toList();
    } else if (pdfPath != null || document.pdfPath != null) {
      // Generate PDF thumbnail
      final path = pdfPath ?? document.pdfPath!;
      final thumb = await _optimizationService.generatePdfThumbnail(path);
      if (thumb != null) thumbPaths.add(thumb);

      // Check encryption status
      try {
        final bytes = await File(path).readAsBytes();
        isEncrypted = _pdfService.isPdfEncrypted(bytes);
      } catch (_) {}
    }

    if (name != null) {
      finalDoc = DocumentModel(
        id: document.id,
        name: name,
        date: DateTime.now(),
        imagePaths: optimizedImages,
        pdfPath: pdfPath,
        pageCount: pageCount,
        thumbnailPaths: thumbPaths,
        isEncrypted: isEncrypted,
      );
    } else {
      finalDoc = document.copyWith(
        imagePaths: optimizedImages,
        thumbnailPaths: thumbPaths,
        isEncrypted: isEncrypted,
      );
    }

    documents.insert(0, finalDoc);
    _documentsCache = documents; // Update cache
    final file = await _localFile;
    
    // Move heavy JSON encoding to background isolate
    final jsonString = await Isolate.run(() => DocumentModel.encode(documents));
    await file.writeAsString(jsonString);
  }

  /// Convenience wrapper for saving documents with named parameters.
  Future<void> saveDocumentNamed({
    required String name,
    required List<String> imagePaths,
    String? pdfPath,
    int? pageCount,
    String? extractedText,
  }) async {
    final doc = DocumentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      date: DateTime.now(),
      imagePaths: imagePaths,
      pdfPath: pdfPath,
      pageCount: pageCount,
      extractedText: extractedText,
    );
    return saveDocument(doc);
  }

  Future<void> softDeleteDocument(String id) async {
    final documents = await loadDocuments(includeDeleted: true);
    final index = documents.indexWhere((doc) => doc.id == id);
    if (index != -1) {
      documents[index] = documents[index].copyWith(
        isDeleted: true,
        deletedAt: DateTime.now(),
      );
      final file = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(documents));
      _documentsCache = documents; // Update cache
      await file.writeAsString(jsonString);
    }
  }

  /// Automatically deletes documents that have been in the recycle bin for more than 30 days.
  Future<void> runRecycleBinCleanup() async {
    final documents = await loadDocuments(includeDeleted: true);
    final now = DateTime.now();
    final List<DocumentModel> keptDocuments = [];
    bool changed = false;

    for (var doc in documents) {
      if (doc.isDeleted && doc.deletedAt != null) {
        final difference = now.difference(doc.deletedAt!).inDays;
        if (difference >= 30) {
          // Permanently delete files
          await _deletePhysicalFiles(doc);
          changed = true;
          continue; // Skip adding to keptDocuments
        }
      }
      keptDocuments.add(doc);
    }

    if (changed) {
      final file = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(keptDocuments));
      _documentsCache = keptDocuments; // Update cache
      await file.writeAsString(jsonString);
    }
  }

  Future<void> _deletePhysicalFiles(DocumentModel doc) async {
    try {
      for (var path in doc.imagePaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      if (doc.pdfPath != null) {
        final file = File(doc.pdfPath!);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      print("Error deleting physical files during cleanup: $e");
    }
  }

  Future<void> renameDocument(String id, String newName) async {
    final documents = await loadDocuments(includeDeleted: true);
    final index = documents.indexWhere((doc) => doc.id == id);
    if (index != -1) {
      documents[index] = documents[index].copyWith(name: newName);
      final file = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(documents));
      _documentsCache = documents; // Update cache
      await file.writeAsString(jsonString);
    }
  }

  Future<void> restoreDocument(String id) async {
    final documents = await loadDocuments(includeDeleted: true);
    final index = documents.indexWhere((doc) => doc.id == id);
    if (index != -1) {
      documents[index] = documents[index].copyWith(isDeleted: false);
      final file = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(documents));
      _documentsCache = documents; // Update cache
      await file.writeAsString(jsonString);
    }
  }

  Future<void> permanentlyDeleteDocument(String id) async {
    final documents = await loadDocuments(includeDeleted: true);
    final docToDelete = documents.firstWhere((doc) => doc.id == id);

    // Physical file deletion
    if (docToDelete.pdfPath != null) {
      final pdfFile = File(docToDelete.pdfPath!);
      if (await pdfFile.exists()) await pdfFile.delete();
    }
    for (var path in docToDelete.imagePaths) {
      final imgFile = File(path);
      if (await imgFile.exists()) await imgFile.delete();
    }

    documents.removeWhere((doc) => doc.id == id);
    final file = await _localFile;
    final jsonString = await Isolate.run(() => DocumentModel.encode(documents));
    _documentsCache = documents; // Update cache
    await file.writeAsString(jsonString);
  }

  /// Bulk optimizes all existing documents that haven't been processed yet.
  Future<void> optimizeAllExistingDocuments() async {
    final documents = await loadDocuments(includeDeleted: true);
    bool changed = false;

    for (int i = 0; i < documents.length; i++) {
      final doc = documents[i];
      // Only optimize if missing thumbnails or has unoptimized images
      bool needsOpt =
          (doc.thumbnailPaths == null || doc.thumbnailPaths!.isEmpty);
      if (!needsOpt) {
        for (final path in doc.imagePaths) {
          if (path.contains('cache') ||
              path.contains('scaled_') ||
              !path.contains('opt_')) {
            needsOpt = true;
            break;
          }
        }
      }

      if (needsOpt || doc.pdfPath != null) {
        List<String> optImages = [];
        List<String> thumbPaths = [];
        bool isEncrypted = doc.isEncrypted;

        if (doc.imagePaths.isNotEmpty) {
          final results = await Future.wait(
            doc.imagePaths.map((path) => _optimizationService.processImage(path)),
          );
          optImages = results.map((r) => r['optimized']!).toList();
          thumbPaths = results.map((r) => r['thumbnail']!).toList();
        } else if (doc.pdfPath != null) {
          if (doc.thumbnailPaths == null || doc.thumbnailPaths!.isEmpty) {
            final thumb = await _optimizationService.generatePdfThumbnail(
              doc.pdfPath!,
            );
            if (thumb != null) thumbPaths.add(thumb);
          }

          // Force check encryption if not set or just as a sanity check during optimization
          try {
            final bytes = await File(doc.pdfPath!).readAsBytes();
            isEncrypted = _pdfService.isPdfEncrypted(bytes);
          } catch (_) {}
        }

        documents[i] = doc.copyWith(
          imagePaths: optImages.isNotEmpty ? optImages : doc.imagePaths,
          thumbnailPaths: thumbPaths.isNotEmpty ? thumbPaths : doc.thumbnailPaths,
          isEncrypted: isEncrypted,
        );
        changed = true;
      }
    }

    if (changed) {
      final file = await _localFile;
      final jsonString = await Isolate.run(() => DocumentModel.encode(documents));
      _documentsCache = documents; // Update cache
      await file.writeAsString(jsonString);
    }
  }

  Future<void> clearRecycleBin() async {
    final deletedDocs = await loadDeletedDocuments();
    for (var doc in deletedDocs) {
      await permanentlyDeleteDocument(doc.id);
    }
  }

  Future<void> deleteDocument(String id) async {
    // By default, we now do a soft delete
    await softDeleteDocument(id);
  }

  Future<int> getTotalStorageUsed() async {
    int totalBytes = 0;
    final documents = await loadDocuments();
    for (var doc in documents) {
      if (doc.pdfPath != null) {
        final pdfFile = File(doc.pdfPath!);
        if (await pdfFile.exists()) {
          totalBytes += await pdfFile.length();
        }
      }
      for (var imgPath in doc.imagePaths) {
        final imgFile = File(imgPath);
        if (await imgFile.exists()) {
          totalBytes += await imgFile.length();
        }
      }
    }
    return totalBytes;
  }

  // --- Scan History Management ---

  static const String _scanHistoryFileName = 'scan_history.json';

  Future<File> get _scanHistoryFile async {
    final path = await _localPath;
    return File(p.join(path, _scanHistoryFileName));
  }

  Future<List<ScanResultModel>> loadScanHistory() async {
    try {
      final file = await _scanHistoryFile;
      if (!await file.exists()) {
        return [];
      }
      final contents = await file.readAsString();
      return ScanResultModel.decode(contents);
    } catch (e) {
      return [];
    }
  }

  Future<void> saveScanResult(ScanResultModel result) async {
    final history = await loadScanHistory();
    // Prevent duplicate entries for the same data if it's very recent
    if (history.isNotEmpty &&
        history.first.data == result.data &&
        result.timestamp.difference(history.first.timestamp).inSeconds < 5) {
      return;
    }
    history.insert(0, result);
    final file = await _scanHistoryFile;
    final jsonString = await Isolate.run(() => ScanResultModel.encode(history));
    await file.writeAsString(jsonString);
  }

  Future<void> deleteScanHistory(String id) async {
    final history = await loadScanHistory();
    history.removeWhere((res) => res.id == id);
    final file = await _scanHistoryFile;
    await file.writeAsString(ScanResultModel.encode(history));
  }

  Future<String> savePdf(Uint8List bytes, String fileName) async {
    final path = await _localPath;
    final pdfDir = Directory(p.join(path, 'pdfs'));
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    
    final sanitizedFileName = sanitizeFilename(fileName);
    final finalFileName = sanitizedFileName.endsWith('.pdf') ? sanitizedFileName : '$sanitizedFileName.pdf';
    final fullPath = p.join(pdfDir.path, finalFileName);
    final file = File(fullPath);
    await file.writeAsBytes(bytes);
    return fullPath;
  }
}
