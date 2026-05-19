import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SignatureService {
  static const String _sigFile = 'signatures_lib.json';

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File(p.join(path, _sigFile));
  }

  Future<List<String>> getSavedSignatures() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      final List<dynamic> list = json.decode(contents);
      // Verify files still exist
      final List<String> existing = [];
      for (var path in list) {
        if (await File(path).exists()) {
          existing.add(path);
        }
      }
      return existing;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveSignature(String path) async {
    final list = await getSavedSignatures();
    if (!list.contains(path)) {
      list.insert(0, path);
      final file = await _localFile;
      await file.writeAsString(json.encode(list));
    }
  }

  Future<void> deleteSignature(String path) async {
    final list = await getSavedSignatures();
    list.remove(path);
    final file = await _localFile;
    await file.writeAsString(json.encode(list));
    
    // Optionally delete the physical file if it's in our temp/app dir
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
