import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapFeature {
  final String kind, name;
  final List<LatLng> points;
  final LatLngBounds bounds;
  MapFeature(this.kind, this.name, this.points)
    : bounds = LatLngBounds.fromPoints(points);
}

class OfflineBasemap {
  final List<MapFeature> features;
  final String dataDate;
  OfflineBasemap(this.features, this.dataDate);

  static Future<OfflineBasemap>? _loaded;
  static Future<OfflineBasemap> load() => _loaded ??= _load();

  static Future<OfflineBasemap> _load() async {
    final bytes = await rootBundle.load('assets/maps/cordoba.json.gz');
    return compute(
      decode,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  static OfflineBasemap decode(Uint8List bytes) {
    final data =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('Unsupported map');
    final features = (data['features'] as List).map((row) {
      final points = (row[2] as List)
          .map(
            (p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          )
          .toList();
      return MapFeature(row[0] as String, row[1] as String, points);
    }).toList();
    return OfflineBasemap(features, data['dataDate'] as String);
  }
}
