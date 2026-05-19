import 'package:flutter/material.dart';

class TextSegment {
  final String text;
  final bool isBold;
  final bool isItalic;
  final double fontSize;

  TextSegment({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.fontSize = 12.0,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isBold': isBold,
    'isItalic': isItalic,
    'fontSize': fontSize,
  };
}

class RichTextController extends TextEditingController {
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final List<TextSpan> spans = [];
    final String text = value.text;
    
    // Pattern to match all our tags: b, i, u, color, size, left, center, right, justify
    final RegExp tagRegex = RegExp(
      r'<(b|i|u|color=#[0-9a-fA-F]{6}|size=\d+|left|center|right|justify)>|</(b|i|u|color|size|left|center|right|justify)>',
      dotAll: true,
    );
    
    int lastIndex = 0;
    
    // State for styling
    bool isB = false;
    bool isI = false;
    bool isU = false;
    Color? currentColor;
    double currentFontSize = style?.fontSize ?? 14.0;

    void addText(String content) {
      if (content.isEmpty) return;
      
      TextStyle combinedStyle = style ?? const TextStyle();
      if (isB) combinedStyle = combinedStyle.copyWith(fontWeight: FontWeight.bold);
      if (isI) combinedStyle = combinedStyle.copyWith(fontStyle: FontStyle.italic);
      if (isU) combinedStyle = combinedStyle.copyWith(decoration: TextDecoration.underline);
      if (currentColor != null) combinedStyle = combinedStyle.copyWith(color: currentColor);
      combinedStyle = combinedStyle.copyWith(fontSize: currentFontSize);
      
      spans.add(TextSpan(text: content, style: combinedStyle));
    }

    final matches = tagRegex.allMatches(text);
    for (final match in matches) {
      // Add preceding text
      addText(text.substring(lastIndex, match.start));

      // HIDE tags completely (Industry Standard "Zero-Width" approach)
      final tagText = text.substring(match.start, match.end);
      spans.add(TextSpan(
        text: tagText,
        style: const TextStyle(
          color: Colors.transparent,
          fontSize: 0.1, 
          height: 0,
          letterSpacing: -1.0,
        ),
      ));

      // Update state
      if (tagText.startsWith('<color=')) {
        try {
          final hex = tagText.split('=')[1].replaceAll('>', '');
          currentColor = Color(int.parse(hex.replaceFirst('#', '0xff')));
        } catch (e) { currentColor = null; }
      } else if (tagText.startsWith('<size=')) {
        currentFontSize = double.tryParse(tagText.split('=')[1].replaceAll('>', '')) ?? (style?.fontSize ?? 14.0);
      } else if (tagText == '<b>') isB = true;
      else if (tagText == '<i>') isI = true;
      else if (tagText == '<u>') isU = true;
      else if (tagText == '</b>') isB = false;
      else if (tagText == '</i>') isI = false;
      else if (tagText == '</u>') isU = false;
      else if (tagText == '</color>') currentColor = null;
      else if (tagText == '</size>') currentFontSize = style?.fontSize ?? 14.0;
      
      lastIndex = match.end;
    }

    addText(text.substring(lastIndex));
    
    return TextSpan(children: spans, style: style);
  }
}
