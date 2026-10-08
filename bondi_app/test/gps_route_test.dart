import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/predictive_engine.dart';

void main() {
  test(
    'Offline prediction never moves an unrelated GPS point onto the route',
    () {
      final trace = Traza(
        lineaId: '1',
        rutaId: '1',
        colorHex: '',
        puntos: [const LatLng(-31.4, -64.18), const LatLng(-31.42, -64.18)],
        paradas: [],
      );
      final bus = Coche(
        coche: 1,
        linea: '87',
        sentido: 'I',
        lat: -31.5,
        lon: -64.3,
        curso: 0,
        demora: '',
        rampa: false,
      );
      final now = DateTime(2026, 10, 7, 17);
      for (final age in [5, 120, 900]) {
        expect(
          PredictiveEngine.calculatePredictiveBuses(
            lastKnownBuses: [bus],
            snapshotTime: now.subtract(Duration(seconds: age)),
            traza: trace,
            now: now,
          ),
          isEmpty,
        );
      }
      expect(bus.lat, -31.5);
    },
  );
}
