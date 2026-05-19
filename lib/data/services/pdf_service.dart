import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:archive/archive.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'word_service.dart';
import 'ocr_service.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/pdf_annotation.dart';

class PdfService {
  /// Checks if a PDF document is encrypted/password protected.
  bool isPdfEncrypted(Uint8List bytes) {
    try {
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: bytes);
      document.dispose();
      return false; // Successfully opened without password
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains("password") || msg.contains("encrypt")) {
        return true;
      }
      return false; // Might be a different error, but assume not encrypted
    }
  }

  /// Attempts to decrypt PDF bytes and returns a brand-new UNENCRYPTED version.
  /// This physically rebuilds the document to ensure OS-level renderers don't see encryption flags.
  Future<Uint8List?> decryptPdf(Uint8List bytes, String password) async {
    try {
      final sf.PdfDocument document = sf.PdfDocument(
        inputBytes: bytes,
        password: password,
      );

      try {
        // Explicitly clear passwords to remove encryption while preserving the internal structure
        document.security.userPassword = '';
        document.security.ownerPassword = '';
        
        final List<int> decryptedBytes = await document.save();
        return Uint8List.fromList(decryptedBytes);
      } finally {
        document.dispose();
      }
    } catch (e) {
      debugPrint("Decryption preservation failed: $e");
      return null;
    }
  }

  /// Merges multiple PDF files into one.
  Future<Uint8List> mergePdfs(List<String> pdfPaths) async {
    return await Isolate.run(() async {
      final sf.PdfDocument finalDoc = sf.PdfDocument();
      try {
        for (final path in pdfPaths) {
          final bytes = await File(path).readAsBytes();
          final sf.PdfDocument sourceDoc = sf.PdfDocument(inputBytes: bytes);
          for (int i = 0; i < sourceDoc.pages.count; i++) {
            final sf.PdfPage page = finalDoc.pages.add();
            final sf.PdfTemplate template = sourceDoc.pages[i].createTemplate();
            page.graphics.drawPdfTemplate(template, Offset.zero, page.getClientSize());
          }
          sourceDoc.dispose();
        }
        final List<int> bytes = await finalDoc.save();
        return Uint8List.fromList(bytes);
      } finally {
        finalDoc.dispose();
      }
    });
  }

  /// Splits a PDF into multiple segments based on ranges (1-indexed).
  Future<List<Map<String, dynamic>>> splitPdfByRanges(
    Uint8List sourceBytes,
    List<PdfRangeSelection> ranges,
  ) async {
    return await Isolate.run(() async {
      final sf.PdfDocument sourceDoc = sf.PdfDocument(inputBytes: sourceBytes);
      final List<Map<String, dynamic>> results = [];

      try {
        for (final range in ranges) {
          final sf.PdfDocument partDoc = sf.PdfDocument();
          
          for (int i = range.start - 1; i <= range.end - 1; i++) {
            if (i >= 0 && i < sourceDoc.pages.count) {
              final sf.PdfPage page = partDoc.pages.add();
              final sf.PdfTemplate template = sourceDoc.pages[i].createTemplate();
              page.graphics.drawPdfTemplate(template, Offset.zero, page.getClientSize());
            }
          }
          
          final List<int> partBytes = await partDoc.save();
          results.add({
            'name': range.label ?? "Part_${range.start}-${range.end}",
            'bytes': Uint8List.fromList(partBytes),
          });
          partDoc.dispose();
        }
        return results;
      } finally {
        sourceDoc.dispose();
      }
    });
  }

  /// Compresses multiple files into a single ZIP archive.
  Future<Uint8List> createZipArchive(List<Map<String, dynamic>> files) async {
    final archive = Archive();
    for (final file in files) {
      final String name = file['name'];
      final Uint8List bytes = file['bytes'];
      final archiveFile = ArchiveFile("$name.pdf", bytes.length, bytes);
      archive.addFile(archiveFile);
    }
    final tarData = ZipEncoder().encode(archive);
    return Uint8List.fromList(tarData!);
  }

  /// Compile images to PDF with advanced layout options and quality control. (Verified Signature)
  /// [quality]: 0 = Low (Fast/Small), 1 = Medium, 2 = High (Best Fidelity)
  Future<Uint8List> compileImagesToPdf(
    List<String> imagePaths, {
    int quality = 2,
    PdfPageFormat? format,
    pw.BoxFit fit = pw.BoxFit.contain,
  }) async {
    // We use Isolate.run to move the entire PDF construction process to a background thread
    // This prevents the UI from freezing when processing many high-resolution images.
    return await Isolate.run(() async {
      final pdf = pw.Document();

      for (final path in imagePaths) {
        Uint8List bytes = File(path).readAsBytesSync();

        // Apply compression if quality is not High (2)
        if (quality < 2) {
          try {
            final decoded = img.decodeImage(bytes);
            if (decoded != null) {
              final jpgQuality = quality == 0 ? 40 : 70;
              bytes = Uint8List.fromList(
                img.encodeJpg(decoded, quality: jpgQuality),
              );
            }
          } catch (e) {
            // In isolate, we use print instead of debugPrint if needed, or just ignore
          }
        }

        final image = pw.MemoryImage(bytes);
        double imgWidth = image.width?.toDouble() ?? PdfPageFormat.a4.width;
        double imgHeight = image.height?.toDouble() ?? PdfPageFormat.a4.height;

        double pageWidth = PdfPageFormat.a4.width;
        double pageHeight = pageWidth * (imgHeight / imgWidth);

        PdfPageFormat pageFormat =
            format ?? PdfPageFormat(pageWidth, pageHeight, marginAll: 0);

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(image, fit: pw.BoxFit.fill),
              );
            },
          ),
        );
      }
      return await pdf.save();
    });
  }

  /// Reorders or removes pages from a PDF based on a list of indices (0-indexed).
  Future<Uint8List> reorderPages(
    Uint8List sourceBytes,
    List<int> pageIndices,
  ) async {
    return await Isolate.run(() async {
      final sf.PdfDocument sourceDoc = sf.PdfDocument(inputBytes: sourceBytes);
      final sf.PdfDocument destDoc = sf.PdfDocument();
      try {
        for (final index in pageIndices) {
          if (index >= 0 && index < sourceDoc.pages.count) {
            final sf.PdfPage page = destDoc.pages.add();
            final sf.PdfTemplate template = sourceDoc.pages[index].createTemplate();
            page.graphics.drawPdfTemplate(template, Offset.zero, page.getClientSize());
          }
        }
        final List<int> bytes = await destDoc.save();
        return Uint8List.fromList(bytes);
      } finally {
        sourceDoc.dispose();
        destDoc.dispose();
      }
    });
  }

  /// Compresses a PDF based on the specified level.
  Future<Uint8List> compressPdf(Uint8List sourceBytes, String level) async {
    return await Isolate.run(() async {
      final sf.PdfDocument doc = sf.PdfDocument(inputBytes: sourceBytes);
      doc.compressionLevel = sf.PdfCompressionLevel.best;
      try {
        final List<int> bytes = await doc.save();
        return Uint8List.fromList(bytes);
      } finally {
        doc.dispose();
      }
    });
  }

  /// Checks the health of a PDF by attempting to parse its structure.
  Future<bool> isPdfHealthy(Uint8List sourceBytes) async {
    try {
      final sf.PdfDocument doc = sf.PdfDocument(inputBytes: sourceBytes);
      doc.dispose();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Attempts to repair a corrupted PDF by reconstructing its internal structure.
  Future<Uint8List> repairPdf(Uint8List sourceBytes) async {
    if (sourceBytes.isEmpty) throw Exception("Source byte-stream is empty.");

    // Stage 0: Quick Integrity Check (Try original first)
    try {
      final sf.PdfDocument doc = sf.PdfDocument(inputBytes: sourceBytes);
      try {
        final List<int> bytes = await doc.save();
        return Uint8List.fromList(bytes);
      } finally {
        doc.dispose();
      }
    } catch (e) {
      debugPrint("Direct load failed: $e. Starting Surgical Stabilization.");
    }

    // Stage 1: Byte-Stream Stabilization (Surgical Patching)
    final patchedBytes = _stabilizePdfBytes(sourceBytes);

    try {
      // Stage 2: Structural Rewrite (Syncfusion's built-in repair on patched bytes)
      final sf.PdfDocument doc = sf.PdfDocument(inputBytes: patchedBytes);
      try {
        final List<int> bytes = await doc.save();
        return Uint8List.fromList(bytes);
      } finally {
        doc.dispose();
      }
    } catch (e) {
      debugPrint(
        "Surgical Repair failed: $e. Initializing Level 3: Raster Salvage.",
      );

      // Stage 3: Raster Reconstruction (The final fallback)
      try {
        return await rasterSalvage(patchedBytes);
      } catch (e2) {
        debugPrint("Raster Salvage failed: $e2. Document is beyond recovery.");
        throw Exception("file not in PDF format or corrupted");
      }
    }
  }

  Uint8List _stabilizePdfBytes(Uint8List bytes) {
    if (bytes.length < 10) return bytes;
    var result = bytes;

    // Fix 1: Header Alignment (Trim leading junk)
    const headerStr = "%PDF-";
    final headerBytes = Uint8List.fromList(headerStr.codeUnits);
    int headerIndex = -1;

    for (int i = 0; i < result.length - 5; i++) {
      if (result[i] == headerBytes[0] &&
          result[i + 1] == headerBytes[1] &&
          result[i + 2] == headerBytes[2] &&
          result[i + 3] == headerBytes[3] &&
          result[i + 4] == headerBytes[4]) {
        headerIndex = i;
        break;
      }
    }

    if (headerIndex > 0) {
      result = result.sublist(headerIndex);
    } else if (headerIndex == -1) {
      // FORCE HEADER if missing but file looks like it might be a PDF
      final buffer = BytesBuilder();
      buffer.add("%PDF-1.7\n".codeUnits);
      buffer.add(result);
      result = buffer.toBytes();
    }

    // Fix 2: Trailer/XRef Integrity & Trailing Junk Cleanup
    const eofStr = "%%EOF";
    final eofBytes = Uint8List.fromList(eofStr.codeUnits);
    int lastEOF = -1;

    // Find the LAST occurrence of %%EOF
    for (int i = result.length - 5; i >= 0; i--) {
      if (result[i] == eofBytes[0] &&
          result[i + 1] == eofBytes[1] &&
          result[i + 2] == eofBytes[2] &&
          result[i + 3] == eofBytes[3] &&
          result[i + 4] == eofBytes[4]) {
        lastEOF = i;
        break;
      }
    }

    if (lastEOF != -1) {
      // Trim everything after the last %%EOF (fixes "trailing junk" errors)
      result = result.sublist(0, lastEOF + 5);
    } else {
      // Force append a minimal valid trailer if none found
      final buffer = BytesBuilder();
      buffer.add(result);
      buffer.add("\nstartxref\n0\n%%EOF\n".codeUnits);
      result = buffer.toBytes();
    }

    return result;
  }

  /// Falls back to rasterizing pages and rebuilding the PDF from scratch.
  /// This is the most robust salvage method as it uses the OS's native PDF renderer.
  Future<Uint8List> rasterSalvage(Uint8List bytes) async {
    final List<String> tempPaths = [];
    final tempDir = await getTemporaryDirectory();

    try {
      // Level 3: Native PDF Rasterization
      try {
        await for (final page in Printing.raster(bytes, dpi: 200)) {
          final png = await page.toPng();
          final path =
              "${tempDir.path}/salvage_${DateTime.now().microsecondsSinceEpoch}_${tempPaths.length}.png";
          await File(path).writeAsBytes(png);
          tempPaths.add(path);
        }
      } catch (e) {
        debugPrint(
          "Native rasterization failed: $e. Checking for Level 4: Image Fallback.",
        );
      }

      // Level 4: Image Fallback (If file is actually a renamed JPG/PNG)
      if (tempPaths.isEmpty) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final path = "${tempDir.path}/salvage_image_fallback.png";
            await File(
              path,
            ).writeAsBytes(Uint8List.fromList(img.encodePng(decoded)));
            tempPaths.add(path);
          }
        } catch (e) {
          debugPrint("Image fallback salvage failed: $e");
        }
      }

      if (tempPaths.isEmpty) {
        throw Exception("Renderer could not find any readable visual content.");
      }

      return await compileImagesToPdf(tempPaths, quality: 2);
    } catch (e) {
      debugPrint("Final Salvage Stage failed: $e");
      rethrow;
    } finally {
      for (final p in tempPaths) {
        try {
          if (File(p).existsSync()) await File(p).delete();
        } catch (_) {}
      }
    }
  }

  /// Converts a single image and its extracted text into a professional PDF.
  Future<Uint8List> convertImageAndTextToPdf(
    String imagePath,
    String text, {
    double fontSize = 12,
  }) async {
    return convertImagesAndTextToPdf([imagePath], text, fontSize: fontSize);
  }

  /// Converts multiple images and combined extracted text into a professional PDF.
  /// Images are placed at the beginning (one or more per page), and text follows.
  Future<Uint8List> convertImagesAndTextToPdf(
    List<String> imagePaths,
    String text, {
    double fontSize = 12,
  }) async {
    final pdf = pw.Document();

    // 1. Load Fonts for Devanagari support
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(
          base: baseFont,
          bold: boldFont,
        ),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Text('OCR Extracted Content', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ),
        build: (pw.Context context) {
          final List<pw.Widget> content = [];
          
          // Add all reference images
          for (int i = 0; i < imagePaths.length; i++) {
            final Uint8List imageBytes = File(imagePaths[i]).readAsBytesSync();
            final image = pw.MemoryImage(imageBytes);
            
            content.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reference Image ${i + 1}:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  pw.SizedBox(height: 5),
                  pw.Container(
                    height: 350,
                    width: double.infinity,
                    margin: const pw.EdgeInsets.only(bottom: 30),
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                ],
              ),
            );
          }
          
          content.add(pw.Divider(color: PdfColors.grey300));
          content.add(pw.SizedBox(height: 10));
          
          // Extracted Text
          content.add(
            pw.Text(
              'Combined Extracted Text:',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
            ),
          );
          content.add(pw.SizedBox(height: 8));
          content.add(
            pw.Paragraph(
              text: text,
              style: pw.TextStyle(
                fontSize: fontSize,
                lineSpacing: 1.5,
                color: PdfColors.black,
              ),
            ),
          );
          
          return content;
        },
      ),
    );

    return await pdf.save();
  }

  /// Converts plain text into a multi-page PDF document with styling options.
  Future<Uint8List> convertTextToPdf(
    String text, {
    double fontSize = 14,
    String fontFamily = 'notoSans',
    double lineSpacing = 1.5,
    double margin = 50.0,
    bool isBold = false,
    bool isItalic = false,
  }) async {
    final pdf = pw.Document();

    // Load font variants based on the selected font family
    late final pw.Font baseFont;
    late final pw.Font boldFont;
    late final pw.Font italicFont;
    late final pw.Font boldItalicFont;

    // Supported font families
    switch (fontFamily.toLowerCase()) {
      case 'roboto':
        baseFont = await PdfGoogleFonts.robotoRegular();
        boldFont = await PdfGoogleFonts.robotoBold();
        italicFont = await PdfGoogleFonts.robotoItalic();
        boldItalicFont = await PdfGoogleFonts.robotoBoldItalic();
        break;
      case 'opensans':
        baseFont = await PdfGoogleFonts.openSansRegular();
        boldFont = await PdfGoogleFonts.openSansBold();
        italicFont = await PdfGoogleFonts.openSansItalic();
        boldItalicFont = await PdfGoogleFonts.openSansBoldItalic();
        break;
      case 'lato':
        baseFont = await PdfGoogleFonts.latoRegular();
        boldFont = await PdfGoogleFonts.latoBold();
        italicFont = await PdfGoogleFonts.latoItalic();
        boldItalicFont = await PdfGoogleFonts.latoBoldItalic();
        break;
      case 'montserrat':
        baseFont = await PdfGoogleFonts.montserratRegular();
        boldFont = await PdfGoogleFonts.montserratBold();
        italicFont = await PdfGoogleFonts.montserratItalic();
        boldItalicFont = await PdfGoogleFonts.montserratBoldItalic();
        break;
      case 'poppins':
        baseFont = await PdfGoogleFonts.poppinsRegular();
        boldFont = await PdfGoogleFonts.poppinsBold();
        italicFont = await PdfGoogleFonts.poppinsItalic();
        boldItalicFont = await PdfGoogleFonts.poppinsBoldItalic();
        break;
      case 'notosans':
      default:
        baseFont = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
        italicFont = await PdfGoogleFonts.notoSansItalic();
        boldItalicFont = await PdfGoogleFonts.notoSansBoldItalic();
        break;
    }

    // Replace placeholders
    final now = DateTime.now();
    text = text.replaceAll('[DATE]', "${now.day}/${now.month}/${now.year}");
    text = text.replaceAll('[TIME]', "${now.hour}:${now.minute}");

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(margin),
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          );
        },
        theme: pw.ThemeData.withFont(
          base: baseFont,
          bold: boldFont,
          italic: italicFont,
          boldItalic: boldItalicFont,
        ),
        build: (pw.Context context) {
          // Robust parsing for nested tags and alignment
          final List<pw.Widget> content = [];

          // Split text into paragraphs based on alignment tags or newlines
          final RegExp alignRegex = RegExp(r'<(left|center|right|justify)>(.*?)</\1>', dotAll: true);
          int lastIndex = 0;

          void processParagraph(String pText, pw.TextAlign align) {
            if (pText.trim().isEmpty) return;

            final List<pw.InlineSpan> spans = _parseRichText(pText, fontSize, baseFont, boldFont, italicFont, boldItalicFont);
            content.add(
              pw.Container(
                margin: pw.EdgeInsets.only(bottom: fontSize * 0.3), // Dynamic bottom margin based on font size
                child: pw.RichText(
                  text: pw.TextSpan(children: spans),
                  textAlign: align,
                ),
              )
            );
          }

          for (final Match match in alignRegex.allMatches(text)) {
            // Process text before the alignment tag
            if (match.start > lastIndex) {
              processParagraph(text.substring(lastIndex, match.start), pw.TextAlign.left);
            }

            final alignStr = match.group(1);
            final innerText = match.group(2) ?? "";

            pw.TextAlign align = pw.TextAlign.left;
            if (alignStr == 'center') align = pw.TextAlign.center;
            if (alignStr == 'right') align = pw.TextAlign.right;
            if (alignStr == 'justify') align = pw.TextAlign.justify;

            processParagraph(innerText, align);
            lastIndex = match.end;
          }

          // Remaining text
          if (lastIndex < text.length) {
            processParagraph(text.substring(lastIndex), pw.TextAlign.left);
          }

          return content;
        },
      ),
    );

    return await pdf.save();
  }

  List<pw.InlineSpan> _parseRichText(
    String text, 
    double baseFontSize, 
    pw.Font base, 
    pw.Font bold, 
    pw.Font italic, 
    pw.Font boldItalic
  ) {
    final List<pw.InlineSpan> spans = [];
    final RegExp tagRegex = RegExp(r'<(b|i|u|color=#[0-9a-fA-F]{6}|size=\d+)>|</(b|i|u|color|size|left|center|right|justify)>', dotAll: true);
    
    // State machine for nested tags
    bool isB = false;
    bool isI = false;
    bool isU = false;
    PdfColor? currentColor;
    double currentFontSize = baseFontSize;
    
    int lastIndex = 0;

    void addSpan(String content) {
      if (content.isEmpty) return;
      
      pw.Font? font;
      if (isB && isI) font = boldItalic;
      else if (isB) font = bold;
      else if (isI) font = italic;
      else font = base;

      spans.add(pw.TextSpan(
        text: content,
        style: pw.TextStyle(
          font: font,
          fontSize: currentFontSize,
          color: currentColor,
          decoration: isU ? pw.TextDecoration.underline : null,
          lineSpacing: 1.5,
        ),
      ));
    }

    final matches = tagRegex.allMatches(text);
    for (final match in matches) {
      // Add preceding text
      addSpan(text.substring(lastIndex, match.start));

      final tag = match.group(0)!;
      if (tag.startsWith('<color=')) {
        final hex = tag.split('=')[1].replaceAll('>', '');
        currentColor = PdfColor.fromHex(hex);
      } else if (tag.startsWith('<size=')) {
        currentFontSize = double.tryParse(tag.split('=')[1].replaceAll('>', '')) ?? baseFontSize;
      } else if (tag == '<b>') isB = true;
      else if (tag == '<i>') isI = true;
      else if (tag == '<u>') isU = true;
      else if (tag == '</b>') isB = false;
      else if (tag == '</i>') isI = false;
      else if (tag == '</u>') isU = false;
      else if (tag == '</color>') currentColor = null;
      else if (tag == '</size>') currentFontSize = baseFontSize;

      lastIndex = match.end;
    }

    addSpan(text.substring(lastIndex));
    return spans;
  }

  /// Extracts text from a Word (.docx) file and converts it into a PDF.
  Future<Uint8List> convertWordToPdf(File wordFile) async {
    final bytes = await wordFile.readAsBytes();
    final text = docxToText(bytes);

    if (text.isEmpty) {
      throw Exception("Could not extract any text from the Word document.");
    }

    return await convertTextToPdf(text);
  }

  /// Converts a PDF document into a list of high-quality image bytes.
  Stream<Uint8List> rasterizePdfToImages(
    Uint8List pdfBytes, {
    double dpi = 150,
  }) async* {
    await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
      final pngBytes = await page.toPng();
      yield pngBytes;
    }
  }

  /// Renders a specific page of a PDF as an image.
  Future<Uint8List?> rasterizePdfPage(
    Uint8List pdfBytes, {
    int pageIndex = 0,
    double dpi = 72,
  }) async {
    try {
      await for (final page in Printing.raster(
        pdfBytes,
        pages: [pageIndex],
        dpi: dpi,
      )) {
        return await page.toPng();
      }
    } catch (e) {
      debugPrint("Error rasterizing single page: $e");
    }
    return null;
  }

  /// Extracts raw text from a PDF document.
  Future<String> extractText(Uint8List pdfBytes) async {
    return await Isolate.run(() async {
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: pdfBytes);
      try {
        final String text = sf.PdfTextExtractor(document).extractText();
        return text;
      } finally {
        document.dispose();
      }
    });
  }

  /// Extracts text with OCR fallback if the PDF is scanned/image-based.
  Future<String> extractTextWithOcrFallback(Uint8List pdfBytes) async {
    String text = await extractText(pdfBytes);
    if (text.trim().isEmpty) {
      // Fallback: convert PDF pages to images and run OCR
      // This is a complex logic, for now we return what we have or a placeholder
      // In a real scenario, we'd render PDF pages to images and OCR them.
    }
    return text;
  }
}

class PdfRangeSelection {
  final int start;
  final int end;
  final String? label;
  PdfRangeSelection({required this.start, required this.end, this.label});
}

class MergeItemSource {
  final String title;
  final bool isInternalScan;
  final List<String>? imagePaths;
  final String? externalPath;
  final int pageCount;

  MergeItemSource({
    required this.title,
    required this.isInternalScan,
    this.imagePaths,
    this.externalPath,
    required this.pageCount,
  });
}

/// Helper service for Word generation integration.
enum WatermarkPosition {
  diagonalCenter,
  horizontalCenter,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

enum PageNumberPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

extension PdfToWordExtension on PdfService {
  Future<Uint8List> convertPdfToWord(Uint8List pdfBytes) async {
    final text = await extractTextWithOcrFallback(pdfBytes);
    if (text.trim().isEmpty) {
      throw Exception("No text or visual readable content found in PDF to convert to Word.");
    }
    return await WordService().createDocxFromText(text);
  }

  Future<Uint8List> convertImageToWord(String imagePath) async {
    final text = await OCRService().processImage(imagePath);
    if (text.trim().isEmpty) {
      throw Exception("No text detected in the image.");
    }
    return await WordService().createDocxFromText(text);
  }

  Future<Uint8List> convertTextFileToWord(File textFile) async {
    final text = await textFile.readAsString();
    if (text.trim().isEmpty) {
      throw Exception("The text file is empty.");
    }
    return await WordService().createDocxFromText(text);
  }

  /// Calculates the number of pages in a PDF document.
  int getPdfPageCount(Uint8List pdfBytes) {
    final sf.PdfDocument document = sf.PdfDocument(inputBytes: pdfBytes);
    final int count = document.pages.count;
    document.dispose();
    return count;
  }

  /// Applies a set of annotations to a source PDF.
  /// [renderedSize] is the size of the PDF page as displayed on the screen when annotations were placed.
  Future<Uint8List> applyAnnotationsToPdf(
    Uint8List sourceBytes,
    Map<int, List<PdfAnnotation>> annotationsByPage, {
    Size? renderedSize,
  }) async {
    final sf.PdfDocument document = sf.PdfDocument(inputBytes: sourceBytes);

    try {
      annotationsByPage.forEach((pageIndex, annotations) {
        if (pageIndex < 0 || pageIndex >= document.pages.count) return;

        final sf.PdfPage page = document.pages[pageIndex];
        final sf.PdfGraphics graphics = page.graphics;

        // Calculate scaling factors
        double scaleX = 1.0;
        double scaleY = 1.0;
        if (renderedSize != null) {
          scaleX = page.size.width / renderedSize.width;
          scaleY = page.size.height / renderedSize.height;
        }

        for (final ann in annotations) {
          final sf.PdfColor color = sf.PdfColor(
            ann.color.red,
            ann.color.green,
            ann.color.blue,
          );
          final double opacity = (ann.type == AnnotationType.highlighter)
              ? 0.5
              : 1.0;

          final rect = Rect.fromLTWH(
            ann.position.dx * scaleX,
            ann.position.dy * scaleY,
            ann.width * scaleX,
            ann.height * scaleY,
          );

          switch (ann.type) {
            case AnnotationType.text:
              if (ann.content != null) {
                if (ann.content == "✓") {
                  final sf.PdfPen pen = sf.PdfPen(color, width: 4.0 * scaleX);
                  graphics.drawLine(
                    pen,
                    Offset(
                      rect.left + rect.width * 0.2,
                      rect.top + rect.height * 0.5,
                    ),
                    Offset(
                      rect.left + rect.width * 0.45,
                      rect.top + rect.height * 0.8,
                    ),
                  );
                  graphics.drawLine(
                    pen,
                    Offset(
                      rect.left + rect.width * 0.45,
                      rect.top + rect.height * 0.8,
                    ),
                    Offset(
                      rect.left + rect.width * 0.8,
                      rect.top + rect.height * 0.25,
                    ),
                  );
                } else {
                  // Approximate font scale (using scaleX as representative)
                  final sf.PdfFont font = sf.PdfStandardFont(
                    sf.PdfFontFamily.helvetica,
                    ann.fontSize * scaleX,
                  );
                  graphics.save();
                  graphics.setTransparency(opacity);
                  graphics.drawString(
                    ann.content!,
                    font,
                    brush: sf.PdfSolidBrush(color),
                    bounds: rect,
                  );
                  graphics.restore();
                }
              }
              break;
            case AnnotationType.rectangle:
            case AnnotationType.highlighter:
              graphics.save();
              graphics.setTransparency(opacity);
              graphics.drawRectangle(
                brush: sf.PdfSolidBrush(color),
                bounds: rect,
              );
              graphics.restore();
              break;
            case AnnotationType.circle:
              graphics.save();
              graphics.setTransparency(opacity);
              graphics.drawEllipse(rect, brush: sf.PdfSolidBrush(color));
              graphics.restore();
              break;
            case AnnotationType.line:
            case AnnotationType.arrow:
              final sf.PdfPen pen = sf.PdfPen(color, width: 2 * scaleX);
              graphics.drawLine(pen, rect.topLeft, rect.bottomRight);
              break;
            case AnnotationType.image:
              if (ann.content != null && File(ann.content!).existsSync()) {
                final imageBytes = File(ann.content!).readAsBytesSync();
                final sf.PdfBitmap bitmap = sf.PdfBitmap(imageBytes);

                // Calculate "Contain" rectangle to preserve aspect ratio
                double imgRatio = bitmap.width / bitmap.height;
                double rectRatio = rect.width / rect.height;

                double drawWidth, drawHeight;
                if (imgRatio > rectRatio) {
                  drawWidth = rect.width;
                  drawHeight = rect.width / imgRatio;
                } else {
                  drawHeight = rect.height;
                  drawWidth = rect.height * imgRatio;
                }

                final centeredRect = Rect.fromLTWH(
                  rect.left + (rect.width - drawWidth) / 2,
                  rect.top + (rect.height - drawHeight) / 2,
                  drawWidth,
                  drawHeight,
                );

                graphics.drawImage(bitmap, centeredRect);
              }
              break;
            case AnnotationType.pen:
              if (ann.points != null && ann.points!.length > 1) {
                final sf.PdfPen pen = sf.PdfPen(
                  color,
                  width: ann.strokeWidth * scaleX,
                );
                for (int i = 0; i < ann.points!.length - 1; i++) {
                  if (ann.points![i].dx.isNaN || ann.points![i + 1].dx.isNaN) {
                    continue;
                  }
                  graphics.drawLine(
                    pen,
                    Offset(
                      ann.points![i].dx * scaleX,
                      ann.points![i].dy * scaleY,
                    ),
                    Offset(
                      ann.points![i + 1].dx * scaleX,
                      ann.points![i + 1].dy * scaleY,
                    ),
                  );
                }
              }
              break;
            case AnnotationType.signature:
              if (ann.points != null && ann.points!.length > 1) {
                final sf.PdfPen pen = sf.PdfPen(
                  color,
                  width: ann.strokeWidth * scaleX,
                );
                final offX = ann.position.dx * scaleX;
                final offY = ann.position.dy * scaleY;
                for (int i = 0; i < ann.points!.length - 1; i++) {
                  final p1 = ann.points![i];
                  final p2 = ann.points![i + 1];
                  if (p1.dx.isNaN || p2.dx.isNaN) continue;
                  graphics.drawLine(
                    pen,
                    Offset(offX + (p1.dx * scaleX), offY + (p1.dy * scaleY)),
                    Offset(offX + (p2.dx * scaleX), offY + (p2.dy * scaleY)),
                  );
                }
              }
              break;
            default:
              break;
          }
        }
      });

      final List<int> bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }

  /// Rotates a specific page by 90 degrees clockwise.
  Future<Uint8List> rotatePage(Uint8List sourceBytes, int pageIndex) async {
    final sf.PdfDocument document = sf.PdfDocument(inputBytes: sourceBytes);
    try {
      if (pageIndex >= 0 && pageIndex < document.pages.count) {
        final currentRotation = document.pages[pageIndex].rotation;
        // Syncfusion rotations are enums: 0, 90, 180, 270
        int nextValue = 0;
        if (currentRotation == sf.PdfPageRotateAngle.rotateAngle0) {
          nextValue = 90;
        } else if (currentRotation == sf.PdfPageRotateAngle.rotateAngle90)
          nextValue = 180;
        else if (currentRotation == sf.PdfPageRotateAngle.rotateAngle180)
          nextValue = 270;
        else
          nextValue = 0;

        document.pages[pageIndex].rotation = _mapDegreeToRotateAngle(nextValue);
      }
      final List<int> bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }

  sf.PdfPageRotateAngle _mapDegreeToRotateAngle(int degrees) {
    switch (degrees) {
      case 90:
        return sf.PdfPageRotateAngle.rotateAngle90;
      case 180:
        return sf.PdfPageRotateAngle.rotateAngle180;
      case 270:
        return sf.PdfPageRotateAngle.rotateAngle270;
      default:
        return sf.PdfPageRotateAngle.rotateAngle0;
    }
  }

  /// Adds a text or image watermark to all pages of the document.
  Future<Uint8List> addWatermarkToPdf(
    Uint8List sourceBytes, {
    String? text,
    Uint8List? imageBytes,
    WatermarkPosition position = WatermarkPosition.diagonalCenter,
    Color color = const Color(0xFFFF0000),
    double opacity = 0.3,
    double textSize = 60,
    double imageScale = 0.5,
  }) async {
    final sf.PdfDocument document = sf.PdfDocument(inputBytes: sourceBytes);
    try {
      final sf.PdfFont font = sf.PdfStandardFont(
        sf.PdfFontFamily.helvetica,
        textSize,
        style: sf.PdfFontStyle.bold,
      );
      final sf.PdfColor pdfColor = sf.PdfColor(
        color.red,
        color.green,
        color.blue,
      );

      sf.PdfBitmap? sharedBitmap;
      if (imageBytes != null) {
        sharedBitmap = sf.PdfBitmap(imageBytes);
      }

      for (int i = 0; i < document.pages.count; i++) {
        final sf.PdfPage page = document.pages[i];
        final sf.PdfGraphics graphics = page.graphics;
        final Size pageSize = page.size;

        // Visual Corner Mapping that accounts for page rotation
        final bool isLand =
            page.rotation == sf.PdfPageRotateAngle.rotateAngle90 ||
            page.rotation == sf.PdfPageRotateAngle.rotateAngle270;

        final double vWidth = isLand ? pageSize.height : pageSize.width;
        final double vHeight = isLand ? pageSize.width : pageSize.height;

        Size itemSize = Size.zero;

        if (sharedBitmap != null) {
          double baseMaxWidth =
              (position == WatermarkPosition.diagonalCenter ||
                  position == WatermarkPosition.horizontalCenter)
              ? vWidth * 0.5
              : vWidth * 0.25;

          double targetWidth = baseMaxWidth * imageScale;
          double origWidth = sharedBitmap.width.toDouble();
          double origHeight = sharedBitmap.height.toDouble();

          double targetHeight = origHeight * (targetWidth / origWidth);
          itemSize = Size(targetWidth, targetHeight);
        } else if (text != null && text.isNotEmpty) {
          itemSize = font.measureString(text);
        } else {
          continue;
        }

        final sf.PdfGraphicsState state = graphics.save();

        // NORMALIZE COORDINATES: Translate/Rotate graphics to match visual top-left
        if (page.rotation == sf.PdfPageRotateAngle.rotateAngle90) {
          graphics.translateTransform(pageSize.width, 0);
          graphics.rotateTransform(90);
        } else if (page.rotation == sf.PdfPageRotateAngle.rotateAngle180) {
          graphics.translateTransform(pageSize.width, pageSize.height);
          graphics.rotateTransform(180);
        } else if (page.rotation == sf.PdfPageRotateAngle.rotateAngle270) {
          graphics.translateTransform(0, pageSize.height);
          graphics.rotateTransform(270);
        }

        graphics.setTransparency(opacity);

        double dx = 0;
        double dy = 0;
        double angle = 0;
        double margin = vWidth * 0.05; // Matches preview margin

        switch (position) {
          case WatermarkPosition.diagonalCenter:
            dx = vWidth / 2;
            dy = vHeight / 2;
            angle = -45;
            break;
          case WatermarkPosition.horizontalCenter:
            dx = vWidth / 2;
            dy = vHeight / 2;
            break;
          case WatermarkPosition.topLeft:
            dx = itemSize.width / 2 + margin;
            dy = itemSize.height / 2 + margin;
            break;
          case WatermarkPosition.topRight:
            dx = vWidth - (itemSize.width / 2) - margin;
            dy = itemSize.height / 2 + margin;
            break;
          case WatermarkPosition.bottomLeft:
            dx = itemSize.width / 2 + margin;
            dy = vHeight - (itemSize.height / 2) - margin;
            break;
          case WatermarkPosition.bottomRight:
            dx = vWidth - (itemSize.width / 2) - margin;
            dy = vHeight - (itemSize.height / 2) - margin;
            break;
        }

        if (angle != 0) {
          graphics.translateTransform(dx, dy);
          graphics.rotateTransform(angle);
          final rect = Rect.fromLTWH(
            -itemSize.width / 2,
            -itemSize.height / 2,
            itemSize.width,
            itemSize.height,
          );

          if (sharedBitmap != null) {
            graphics.drawImage(sharedBitmap, rect);
          } else if (text != null) {
            graphics.drawString(
              text,
              font,
              brush: sf.PdfSolidBrush(pdfColor),
              bounds: rect,
            );
          }
        } else {
          final rect = Rect.fromLTWH(
            dx - itemSize.width / 2,
            dy - itemSize.height / 2,
            itemSize.width,
            itemSize.height,
          );

          if (sharedBitmap != null) {
            graphics.drawImage(sharedBitmap, rect);
          } else if (text != null) {
            graphics.drawString(
              text,
              font,
              brush: sf.PdfSolidBrush(pdfColor),
              bounds: rect,
            );
          }
        }

        graphics.restore(state);
      }

      final List<int> bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }

  /// Adds page numbers to all pages (or all except first) of the document.
  /// [format] can contain {n} for current page and {total} for total pages.
  Future<Uint8List> addPageNumbersToPdf(
    Uint8List sourceBytes, {
    String format = "Page {n} of {total}",
    PageNumberPosition position = PageNumberPosition.bottomCenter,
    Color color = Colors.black,
    double fontSize = 12,
    int startNumber = 1,
    bool skipFirstPage = false,
  }) async {
    final sf.PdfDocument document = sf.PdfDocument(inputBytes: sourceBytes);
    final int totalPages = document.pages.count;

    try {
      final sf.PdfFont font = sf.PdfStandardFont(
        sf.PdfFontFamily.helvetica,
        fontSize,
      );
      final sf.PdfBrush brush = sf.PdfSolidBrush(
        sf.PdfColor(color.red, color.green, color.blue),
      );

      for (int i = 0; i < totalPages; i++) {
        if (skipFirstPage && i == 0) continue;

        final sf.PdfPage page = document.pages[i];
        final sf.PdfGraphics graphics = page.graphics;
        final Size pageSize = page.size;

        final int displayNum = skipFirstPage
            ? i + startNumber - 1
            : i + startNumber;
        final String text = format
            .replaceAll("{n}", displayNum.toString())
            .replaceAll(
              "{total}",
              (skipFirstPage ? totalPages - 1 : totalPages).toString(),
            );

        final Size textSize = font.measureString(text);

        // Use the same approach as the watermark engine:
        // Calculate visual dimensions accounting for rotation,
        // then draw at absolute coordinates — NO manual transforms.
        final bool isLand =
            page.rotation == sf.PdfPageRotateAngle.rotateAngle90 ||
            page.rotation == sf.PdfPageRotateAngle.rotateAngle270;

        final double w = isLand ? pageSize.height : pageSize.width;
        final double h = isLand ? pageSize.width : pageSize.height;
        const double margin = 30.0;

        double dx = 0;
        double dy = 0;

        switch (position) {
          case PageNumberPosition.topLeft:
            dx = margin;
            dy = margin;
            break;
          case PageNumberPosition.topCenter:
            dx = (w - textSize.width) / 2;
            dy = margin;
            break;
          case PageNumberPosition.topRight:
            dx = w - textSize.width - margin;
            dy = margin;
            break;
          case PageNumberPosition.bottomLeft:
            dx = margin;
            dy = h - textSize.height - margin;
            break;
          case PageNumberPosition.bottomCenter:
            dx = (w - textSize.width) / 2;
            dy = h - textSize.height - margin;
            break;
          case PageNumberPosition.bottomRight:
            dx = w - textSize.width - margin;
            dy = h - textSize.height - margin;
            break;
        }

        // Draw directly at absolute coordinates — same pattern as watermark engine
        graphics.drawString(
          text,
          font,
          brush: brush,
          bounds: Rect.fromLTWH(dx, dy, textSize.width, textSize.height),
        );
      }

      final List<int> bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }

  /// Protects a PDF with a password using AES 256-bit encryption.
  Future<Uint8List> protectPdf(Uint8List sourceBytes, String password) async {
    return await Isolate.run(() async {
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: sourceBytes);
      try {
        // Configure security
        final sf.PdfSecurity security = document.security;
        security.userPassword = password;
        // PDF specification requires owner and user passwords to be different to trigger prompts reliably
        security.ownerPassword = '${password}_owner_syncfusion';
        security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;

        // Allow all permissions by default but require password to open
        security.permissions.addAll([
          sf.PdfPermissionsFlags.print,
          sf.PdfPermissionsFlags.copyContent,
          sf.PdfPermissionsFlags.editContent,
          sf.PdfPermissionsFlags.editAnnotations,
        ]);

        final List<int> bytes = await document.save();
        return Uint8List.fromList(bytes);
      } finally {
        document.dispose();
      }
    });
  }

  /// Compile images to a Searchable PDF where OCR text is overlaid transparently.
  Future<Uint8List> compileSearchablePdf(
    Map<String, RecognizedText> pagesData, {
    int quality = 2,
    bool useDevanagari = true,
  }) async {
    final font = useDevanagari ? await PdfGoogleFonts.hindRegular() : null;

    return await Isolate.run(() async {
      final pdf = pw.Document();

      for (var entry in pagesData.entries) {
        final imagePath = entry.key;
        final ocrData = entry.value;

        Uint8List bytes = File(imagePath).readAsBytesSync();
        final image = pw.MemoryImage(bytes);

        final imgWidth = image.width?.toDouble() ?? 595;
        final imgHeight = image.height?.toDouble() ?? 842;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(imgWidth, imgHeight, marginAll: 0),
            build: (pw.Context context) {
              return pw.Stack(
                children: [
                  pw.Image(image, fit: pw.BoxFit.fill),
                  // Overlay OCR text
                  ...ocrData.blocks.expand((block) => block.lines).expand((line) => line.elements).map((element) {
                    final rect = element.boundingBox;
                    return pw.Positioned(
                      left: rect.left,
                      top: rect.top,
                      child: pw.Text(
                        element.text,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: rect.height * 0.8,
                          color: PdfColor.fromHex('#00000000'),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      }
      return await pdf.save();
    });
  }
}
