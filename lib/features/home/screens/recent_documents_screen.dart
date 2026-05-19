import 'package:doc_scanner_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/storage_service.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'document_detail_screen.dart';

class RecentDocumentsScreen extends StatefulWidget {
  const RecentDocumentsScreen({super.key});

  @override
  State<RecentDocumentsScreen> createState() => _RecentDocumentsScreenState();
}

class _RecentDocumentsScreenState extends State<RecentDocumentsScreen> {
  final StorageService _storageService = StorageService();
  List<DocumentModel> _recentDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentDocs();
  }

  Future<void> _loadRecentDocs() async {
    setState(() => _isLoading = true);
    final docs = await _storageService.loadDocuments();
    // We can limit this to the 10 most recent or from the last week
    // For now, let's just show the top 15 most recent documents
    setState(() {
      _recentDocs = docs.take(15).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent Scans'),
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _recentDocs.isEmpty
                ? _buildEmptyState()
                : _buildList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No recent scans found',
            style: TextStyle(color: Colors.grey[600], fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _recentDocs.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final doc = _recentDocs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DocumentDetailScreen(document: doc),
                ),
              );
            },
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.description_outlined, color: Colors.white),
            ),
            title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(DateFormat('MMM d, h:mm a').format(doc.date)),
          ),
        );
      },
    );
  }
}
