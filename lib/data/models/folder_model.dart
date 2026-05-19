import 'dart:convert';

class FolderModel {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? parentId;
  final String color; // For visual excellence - folder colors

  FolderModel({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
    this.color = "0xff1A10A8", // Default deep blue
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'parentId': parentId,
      'color': color,
    };
  }

  factory FolderModel.fromJson(Map<String, dynamic> json) {
    return FolderModel(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      parentId: json['parentId'],
      color: json['color'] ?? "0xff1A10A8",
    );
  }

  FolderModel copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? parentId,
    String? color,
  }) {
    return FolderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
      color: color ?? this.color,
    );
  }

  static String encode(List<FolderModel> folders) => json.encode(
        folders.map<Map<String, dynamic>>((f) => f.toJson()).toList(),
      );

  static List<FolderModel> decode(String folders) =>
      (json.decode(folders) as List<dynamic>)
          .map<FolderModel>((item) => FolderModel.fromJson(item))
          .toList();
}
