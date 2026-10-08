import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/map_package.dart';
import '../services/raster_map.dart';

class OfflineMapLayer extends StatefulWidget {
  const OfflineMapLayer({super.key});
  @override
  State<OfflineMapLayer> createState() => _OfflineMapLayerState();
}

class _OfflineMapLayerState extends State<OfflineMapLayer> {
  Future<RasterMap> _map = RasterMap.load();
  String? _message;
  Future<void> _download() async {
    try {
      final wifi = await const MethodChannel('bondi/device')
          .invokeMethod<bool>('wifi');
      if (wifi != true) {
        if (mounted) {
          setState(() => _message = 'Conectate a Wi-Fi para descargar el mapa');
        }
        return;
      }
      if (await MapPackage.instance.download() && mounted) {
        RasterMap.invalidate();
        setState(() {
          _map = RasterMap.load();
          _message = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'No se pudo comprobar la conexion Wi-Fi');
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RasterMap>(
    future: _map,
    builder: (context, snapshot) => ListenableBuilder(
      listenable: MapPackage.instance,
      builder: (context, _) {
        final package = MapPackage.instance;
        final ready = snapshot.hasData;
        final control = package.downloading
            ? SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: package.total == null
                          ? null
                          : package.received / package.total!,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Descargando mapa: ${(package.received / 1000000).toStringAsFixed(1)} / ${package.total == null ? "…" : (package.total! / 1000000).toStringAsFixed(1)} MB',
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!ready)
                    const Text(
                      'Mapa de Cordoba sin conexion',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (!ready)
                    const Text('Descargalo una vez con Wi-Fi (43 MB)'),
                  if (package.error != null || _message != null)
                    SizedBox(
                      width: 240,
                      child: Text(
                        _message ?? package.error!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _download,
                    icon: const Icon(Icons.download),
                    label: Text(
                      ready ? 'Actualizar mapa' : 'Descargar mapa de Cordoba',
                    ),
                  ),
                ],
              );
        return Stack(
          children: [
            if (ready)
              TileLayer(
                tileProvider: snapshot.data!,
                tileBounds: snapshot.data!.bounds,
                minNativeZoom: snapshot.data!.minZoom,
                maxNativeZoom: snapshot.data!.maxZoom,
              ),
            Align(
              alignment: ready ? Alignment.topLeft : Alignment.center,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, ready ? 190 : 12, 12, 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: control,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
