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
  final Map<(int, int), List<int>> _cells = {};
  static const _cellSize = .01;
  OfflineBasemap(this.features, this.dataDate) {
    for (var i = 0; i < features.length; i++) {
      final bounds = features[i].bounds;
      for (
        var y = (bounds.south / _cellSize).floor();
        y <= (bounds.north / _cellSize).floor();
        y++
      ) {
        for (
          var x = (bounds.west / _cellSize).floor();
          x <= (bounds.east / _cellSize).floor();
          x++
        ) {
          (_cells[(y, x)] ??= []).add(i);
        }
      }
    }
  }

  Iterable<MapFeature> visibleFeatures(LatLngBounds bounds) sync* {
    final candidates = <int>{};
    // Iterate populated cells so zooming out cannot enumerate an unbounded grid.
    final south = (bounds.south / _cellSize).floor();
    final north = (bounds.north / _cellSize).floor();
    final west = (bounds.west / _cellSize).floor();
    final east = (bounds.east / _cellSize).floor();
    for (final entry in _cells.entries) {
      final (y, x) = entry.key;
      if (y >= south && y <= north && x >= west && x <= east) {
        candidates.addAll(entry.value);
      }
    }
    final ordered = candidates.toList()..sort();
    for (final index in ordered) {
      final feature = features[index];
      if (feature.bounds.isOverlapping(bounds)) yield feature;
    }
  }

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
