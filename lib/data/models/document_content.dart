import 'package:flutter/material.dart';

enum DocumentNodeType {
  paragraph,
  heading1,
  heading2,
  heading3,
  bulletList,
  numberedList,
  image,
  table,
}

class DocumentBlock {
  final String id;
  final DocumentNodeType type;
  final String content; // For text-based nodes
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> styles;

  DocumentBlock({
    required this.id,
    required this.type,
    this.content = '',
    this.metadata = const {},
    this.styles = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString(),
    'content': content,
    'metadata': metadata,
    'styles': styles,
  };

  factory DocumentBlock.fromJson(Map<String, dynamic> json) {
    return DocumentBlock(
      id: json['id'],
      type: DocumentNodeType.values.firstWhere((e) => e.toString() == json['type']),
      content: json['content'],
      metadata: json['metadata'],
      styles: json['styles'],
    );
  }
}

class DocumentModel {
  final List<DocumentBlock> blocks;
  final Map<String, dynamic> globalSettings;

  DocumentModel({
    required this.blocks,
    this.globalSettings = const {
      'pageSize': 'A4',
      'margins': {'top': 25, 'bottom': 25, 'left': 25, 'right': 25},
      'fontFamily': 'Inter',
      'fontSize': 12.0,
      'lineHeight': 1.5,
    },
  });

  Map<String, dynamic> toJson() => {
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'globalSettings': globalSettings,
  };
}
