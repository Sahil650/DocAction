import 'package:flutter/material.dart';

enum AnnotationType {
  text,
  pen,
  rectangle,
  highlighter,
  image,
  hand,
  signature,
  circle,
  line,
  arrow,
  eraser,
}

class PdfAnnotation {
  final String id;
  final AnnotationType type;
  final Offset position;
  final Color color;
  final String? content;
  final double fontSize;
  final double width;
  final double height;
  final List<Offset>? points;
  final double strokeWidth;
  final double opacity;
  final bool isBold;
  final bool isItalic;
  final String fontFamily;

  const PdfAnnotation({
    required this.id,
    required this.type,
    required this.position,
    required this.color,
    this.content,
    this.fontSize = 16,
    this.width = 100,
    this.height = 40,
    this.points,
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
    this.isBold = false,
    this.isItalic = false,
    this.fontFamily = '',
  });

  PdfAnnotation copyWith({
    String? id,
    AnnotationType? type,
    Offset? position,
    Color? color,
    String? content,
    double? fontSize,
    double? width,
    double? height,
    List<Offset>? points,
    double? strokeWidth,
    double? opacity,
    bool? isBold,
    bool? isItalic,
    String? fontFamily,
  }) {
    return PdfAnnotation(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      color: color ?? this.color,
      content: content ?? this.content,
      fontSize: fontSize ?? this.fontSize,
      width: width ?? this.width,
      height: height ?? this.height,
      points: points ?? this.points,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
