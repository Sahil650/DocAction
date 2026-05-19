import 'dart:convert';

class DocumentModel {
  final String id;
  final String name;
  final DateTime date;
  final List<String> imagePaths;
  final String? extractedText; 
  final String? pdfPath; // Path to finalized PDF version
  final int? pageCount;
  final bool isDeleted;
  final DateTime? deletedAt;
  final List<String>? thumbnailPaths;
  final bool isEncrypted;
  final String? folderId; // Association with a folder

  DocumentModel({
    required this.id,
    required this.name,
    required this.date,
    required this.imagePaths,
    this.extractedText,
    this.pdfPath,
    this.pageCount,
    this.isDeleted = false,
    this.deletedAt,
    this.thumbnailPaths,
    this.isEncrypted = false,
    this.folderId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'date': date.toIso8601String(),
      'imagePaths': imagePaths,
      'extractedText': extractedText,
      'pdfPath': pdfPath,
      'pageCount': pageCount,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'thumbnailPaths': thumbnailPaths,
      'isEncrypted': isEncrypted,
      'folderId': folderId,
    };
  }

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'],
      name: json['name'],
      date: DateTime.parse(json['date']),
      imagePaths: List<String>.from(json['imagePaths']),
      extractedText: json['extractedText'],
      pdfPath: json['pdfPath'],
      pageCount: json['pageCount'],
      isDeleted: json['isDeleted'] ?? false,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt']) : null,
      thumbnailPaths: json['thumbnailPaths'] != null ? List<String>.from(json['thumbnailPaths']) : null,
      isEncrypted: json['isEncrypted'] ?? false,
      folderId: json['folderId'],
    );
  }

  DocumentModel copyWith({
    String? id,
    String? name,
    DateTime? date,
    List<String>? imagePaths,
    String? extractedText,
    String? pdfPath,
    int? pageCount,
    bool? isDeleted,
    DateTime? deletedAt,
    List<String>? thumbnailPaths,
    bool? isEncrypted,
    Object? folderId = _undefined,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      imagePaths: imagePaths ?? this.imagePaths,
      extractedText: extractedText ?? this.extractedText,
      pdfPath: pdfPath ?? this.pdfPath,
      pageCount: pageCount ?? this.pageCount,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      thumbnailPaths: thumbnailPaths ?? this.thumbnailPaths,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      folderId: folderId == _undefined ? this.folderId : (folderId as String?),
    );
  }

  static const _undefined = Object();

  static String encode(List<DocumentModel> documents) => json.encode(
        documents
            .map<Map<String, dynamic>>((doc) => doc.toJson())
            .toList(),
      );

  static List<DocumentModel> decode(String documents) =>
      (json.decode(documents) as List<dynamic>)
          .map<DocumentModel>((item) => DocumentModel.fromJson(item))
          .toList();
}
