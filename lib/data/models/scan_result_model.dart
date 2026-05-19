import 'dart:convert';

class ScanResultModel {
  final String id;
  final String data;
  final String format; // e.g. 'QR_CODE', 'EAN_13'
  final String type;   // e.g. 'URL', 'TEXT', 'EMAIL'
  final DateTime timestamp;

  ScanResultModel({
    required this.id,
    required this.data,
    required this.format,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data': data,
      'format': format,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ScanResultModel.fromMap(Map<String, dynamic> map) {
    return ScanResultModel(
      id: map['id'] ?? '',
      data: map['data'] ?? '',
      format: map['format'] ?? 'QR_CODE',
      type: map['type'] ?? 'TEXT',
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  static String encode(List<ScanResultModel> results) {
    return json.encode(results.map((r) => r.toMap()).toList());
  }

  static List<ScanResultModel> decode(String data) {
    if (data.isEmpty) return [];
    final List<dynamic> decoded = json.decode(data);
    return decoded.map((item) => ScanResultModel.fromMap(item)).toList();
  }
}
