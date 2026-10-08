import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/place_search_service.dart';
import '../theme/app_theme.dart';

class ConfirmAddressPoint extends StatefulWidget {
  final PlaceSuggestion suggestion;
  const ConfirmAddressPoint({super.key, required this.suggestion});
  @override
  State<ConfirmAddressPoint> createState() => ConfirmAddressPointState();
}

class ConfirmAddressPointState extends State<ConfirmAddressPoint> {
  LatLng? selected;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  widget.suggestion.point.nombre,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Altura sin verificar. El mapa muestra una zona de referencia; tocá el lugar exacto para marcarlo.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: widget.suggestion.point.position,
                initialZoom: 16,
                onTap: (_, point) => setState(() => selected = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bondicba.app',
                ),
                if (selected != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: selected!,
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_pin,
                          color: blue,
                          size: 44,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Text('© OpenStreetMap', style: TextStyle(fontSize: 10)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),

                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(
                          context,
                          Parada(
                            codigo:
                                'manual_${DateTime.now().millisecondsSinceEpoch}',
                            nombre: widget.suggestion.point.nombre,
                            lat: selected!.latitude,
                            lon: selected!.longitude,
                          ),
                        ),
                  child: const Text('Usar este punto'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
