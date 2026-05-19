import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../../data/services/storage_service.dart';
import '../../../data/models/document_model.dart' as model;
import '../../../data/models/document_content.dart';
import '../../../data/services/document_layout_service.dart';
import 'pdf_viewer_screen.dart';
import '../../../shared/utils/app_localizations.dart';
import '../../../shared/widgets/responsive_layout.dart';

class TextToPdfScreen extends StatefulWidget {
  const TextToPdfScreen({super.key});

  @override
  State<TextToPdfScreen> createState() => _TextToPdfScreenState();
}

class _TextToPdfScreenState extends State<TextToPdfScreen> {
  final _storageService = StorageService();
  bool _isProcessing = false;
  AppLocalizations get l10n => AppLocalizations.of(context);

  late QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _convertToPdf() async {
    final nameController = TextEditingController(
      text: "Document_${DateTime.now().millisecondsSinceEpoch}",
    );

    final String? customName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('save_pdf_doc_title')),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.translate('cancel_label'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(l10n.translate('generate_save_btn')),
          ),
        ],
      ),
    );

    if (customName == null) return;

    setState(() => _isProcessing = true);
    try {
      final List<DocumentBlock> blocks = [];
      final delta = _controller.document.toDelta();
      
      for (final operation in delta.operations) {
        if (operation.data is String) {
          final text = operation.data as String;
          if (text.trim().isNotEmpty) {
            blocks.add(DocumentBlock(
              id: Uuid().v4(),
              type: DocumentNodeType.paragraph,
              content: text,
            ));
          }
        }
      }

      final docModel = DocumentModel(blocks: blocks);
      final pdf = await DocumentLayoutService.generatePdf(docModel);
      final pdfBytes = await pdf.save();

      final appDir = await getApplicationDocumentsDirectory();
      final file = File("${appDir.path}/${customName.replaceAll(" ", "_")}.pdf");
      await file.writeAsBytes(pdfBytes);

      final doc = model.DocumentModel(
        id: Uuid().v4(),
        name: customName,
        date: DateTime.now(),
        imagePaths: [],
        pdfPath: file.path,
        extractedText: blocks.isNotEmpty ? blocks.first.content : '',
      );

      await _storageService.saveDocument(doc);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(pdfBytes),
              title: customName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _previewDocument() async {
    if (_controller.document.isEmpty()) return;

    setState(() => _isProcessing = true);
    try {
      final List<DocumentBlock> blocks = [];
      final delta = _controller.document.toDelta();
      
      for (final operation in delta.operations) {
        if (operation.data is String) {
          final text = operation.data as String;
          if (text.trim().isNotEmpty) {
            blocks.add(DocumentBlock(
              id: Uuid().v4(),
              type: DocumentNodeType.paragraph,
              content: text,
            ));
          }
        }
      }

      final docModel = DocumentModel(blocks: blocks);
      final pdf = await DocumentLayoutService.generatePdf(docModel);
      final pdfBytes = await pdf.save();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfData: Future.value(pdfBytes),
              title: "Preview",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Preview Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF1F5F9),
      appBar: AppBar(
        title: const Text('Document Composer'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isProcessing ? null : _previewDocument,
            icon: const Icon(LucideIcons.eye),
            tooltip: 'Preview PDF',
          ),
          IconButton(onPressed: () => _controller.undo(), icon: const Icon(LucideIcons.undo2)),
          IconButton(onPressed: () => _controller.redo(), icon: const Icon(LucideIcons.redo2)),
        ],
      ),
      body: ResponsiveLayout(
        mobile: _buildResponsiveBody(isMobile: true),
        tablet: _buildResponsiveBody(isMobile: false),
        desktop: _buildResponsiveBody(isMobile: false),
      ),
    );
  }

  Widget _buildResponsiveBody({required bool isMobile}) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: QuillSimpleToolbar(
            controller: _controller,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 40,
              vertical: isMobile ? 12 : 30,
            ),
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isMobile ? double.infinity : 850,
                  minHeight: isMobile ? 0 : 1100,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(isMobile ? 0 : 4),
                  boxShadow: isMobile ? [] : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(isMobile ? 20 : 60),
                child: QuillEditor.basic(
                  controller: _controller,
                ),
              ),
            ),
          ),
        ),
        _buildBottomActions(isMobile: isMobile),
      ],
    );
  }

  Widget _buildBottomActions({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 40,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: SafeArea(
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 400),
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _convertToPdf,
              icon: _isProcessing 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.fileText),
              label: Text(
                _isProcessing ? 'Processing...' : 'Export to Professional PDF',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
