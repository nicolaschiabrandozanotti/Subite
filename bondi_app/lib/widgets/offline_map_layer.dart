import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/raster_map.dart';

class OfflineMapLayer extends StatefulWidget {
  const OfflineMapLayer({super.key});
  @override
  State<OfflineMapLayer> createState() => _OfflineMapLayerState();
}

class _OfflineMapLayerState extends State<OfflineMapLayer> {
  final _map = RasterMap.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<RasterMap>(
    future: _map,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Center(
          child: Text(
            snapshot.hasError
                ? 'No se pudo abrir el mapa local'
                : 'Abriendo mapa local…',
          ),
        );
      }
      final map = snapshot.data!;
      return TileLayer(
        tileProvider: map,
        tileBounds: map.bounds,
        minNativeZoom: map.minZoom,
        maxNativeZoom: map.maxZoom,
      );
    },
  );
}
