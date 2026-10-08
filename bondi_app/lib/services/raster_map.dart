import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// PNG tiles generated on the desktop; no street geometry is drawn on the phone.
class RasterMap extends TileProvider {
  RasterMap._(
    this._bytes,
    this._index,
    this.bounds,
    this.minZoom,
    this.maxZoom,
  );
  final Uint8List _bytes;
  final Map<String, dynamic> _index;
  final LatLngBounds bounds;
  final int minZoom, maxZoom;
  final Map<String, MemoryImage> _images = {};
  static Future<RasterMap>? _loaded;
  static Future<RasterMap> load() => _loaded ??= _load();
  static Future<RasterMap> _load() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/maps/cordoba.tiles.json'),
    ) as Map<String, dynamic>;
    if (manifest['version'] != 1) {
      throw const FormatException('Unsupported raster map');
    }
    final data = await rootBundle.load('assets/maps/cordoba.tiles');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final bounds = manifest['bounds'] as List;
    final index = manifest['tiles'] as Map<String, dynamic>;
    for (final entry in index.values) {
      final range = entry as List;
      final offset = range[0] as int, length = range[1] as int;
      if (offset < 0 || length < 8 || offset + length > bytes.length) {
        throw const FormatException('Invalid raster tile range');
      }
    }
    return RasterMap._(
      bytes,
      index,
      LatLngBounds(
        LatLng((bounds[0] as num).toDouble(), (bounds[1] as num).toDouble()),
        LatLng((bounds[2] as num).toDouble(), (bounds[3] as num).toDouble()),
      ),
      manifest['minZoom'] as int,
      manifest['maxZoom'] as int,
    );
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}/${coordinates.x}/${coordinates.y}';
    return _images.putIfAbsent(key, () {
      final range = _index[key] as List?;
      if (range == null) throw StateError('Map tile outside package: $key');
      return MemoryImage(
        Uint8List.sublistView(
          _bytes,
          range[0] as int,
          (range[0] as int) + (range[1] as int),
        ),
      );
    });
  }
}
