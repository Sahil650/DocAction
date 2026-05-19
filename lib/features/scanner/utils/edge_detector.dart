import 'package:flutter/services.dart';

class EdgeDetector {
  static const _channel = MethodChannel('edge_detection');

  static Future<List<Offset>?> detectCorners(String imagePath) async {
    try {
      final result = await _channel.invokeMethod('detectCorners', {
        "path": imagePath,
      });

      if (result == null) return null;

      final list = result as List<dynamic>;
      List<Offset> points = [];
      for (int i = 0; i < list.length; i += 2) {
        points.add(Offset(list[i].toDouble(), list[i + 1].toDouble()));
      }
      return points;
    } catch (e) {
      return null;
    }
  }

  static Future<String> warpPerspective(
    String imagePath,
    List<Offset> points,
  ) async {
    final pointsList = points.expand((p) => [p.dx, p.dy]).toList();

    final result = await _channel.invokeMethod('warpPerspective', {
      "path": imagePath,
      "points": pointsList,
    });

    return result as String;
  }

  static Future<String> applyFilter(
    String imagePath,
    String filter, {
    Map<String, dynamic>? params,
  }) async {
    final Map<String, dynamic> args = {
      "path": imagePath,
      "filter": filter,
    };
    if (params != null) {
      args.addAll(params);
    }
    final result = await _channel.invokeMethod('applyFilter', args);
    return result as String;
  }
}
