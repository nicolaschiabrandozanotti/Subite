import 'dart:async';

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

class _OfflineMapLayerState extends State<OfflineMapLayer>
    with WidgetsBindingObserver {
  Future<RasterMap> _map = RasterMap.load();
  Timer? _wifiCheck;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    _wifiCheck = Timer.periodic(const Duration(seconds: 30), (_) => _sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    if (!mounted ||
        _checking ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _checking = true;
    try {
      // Finish reading the saved map before deciding whether it needs downloading.
      var hadMap = false;
      try {
        await _map;
        hadMap = true;
      } catch (_) {}
      if (!mounted) return;
      final package = MapPackage.instance;
      final revision = package.revision;
      final success = await package.updateOnWifi(
        hasWifi: () async =>
            await const MethodChannel('bondi/device')
                .invokeMethod<bool>('wifi') ==
            true,
      );
      if (success && (!hadMap || package.revision != revision) && mounted) {
        RasterMap.invalidate();
        setState(() => _map = RasterMap.load());
      }
    } catch (_) {
      // A saved map stays usable when the connection check fails.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _wifiCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RasterMap>(
    future: _map,
    builder: (context, snapshot) => ListenableBuilder(
      listenable: MapPackage.instance,
      builder: (context, _) {
        final package = MapPackage.instance;
        if (snapshot.hasData) {
          final map = snapshot.data!;
          return TileLayer(
            tileProvider: map,
            tileBounds: map.bounds,
            minNativeZoom: map.minZoom,
            maxNativeZoom: map.maxZoom,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 240,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Preparando mapa de Córdoba',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (package.downloading) ...[
                        LinearProgressIndicator(
                          value: package.total == null
                              ? null
                              : package.received / package.total!,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Descargando: ${(package.received / 1000000).toStringAsFixed(1)} / ${package.total == null ? "…" : (package.total! / 1000000).toStringAsFixed(1)} MB',
                        ),
                      ] else
                        Text(
                          package.error == null
                              ? 'Se descarga automáticamente al conectarte a Wi-Fi (43 MB).'
                              : 'La descarga se interrumpió. Se reintentará con Wi-Fi.',
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
