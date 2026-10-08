import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map_package.dart';

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
  static void invalidate() => _loaded = null;
  static Future<RasterMap> load({Directory? directory}) =>
      _loaded ??= _load(directory);
  static Future<RasterMap> _load(Directory? directory) async {
    final files = directory == null
        ? await MapPackage.instance.currentFiles()
        : (
            File('${directory.path}/cordoba.tiles.json'),
            File('${directory.path}/cordoba.tiles'),
          );
    if (files == null) throw StateError('Mapa pendiente de descarga');
    final manifest =
        jsonDecode(await files.$1.readAsString()) as Map<String, dynamic>;
    final bytes = await files.$2.readAsBytes();
    validateMapIndex(manifest, bytes.length);
    final bounds = manifest['bounds'] as List;
    final index = manifest['tiles'] as Map<String, dynamic>;
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
