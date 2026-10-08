import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/offline_trip.dart';
import 'package:bondi_app/services/predictive_engine.dart';

void main() {
  final route = Ruta(id: 'r', sentido: 'I', nombre: 'Ida', longitud: '');
  final line = Linea(
    id: 'l',
    nombre: '70',
    grupo: '',
    colorHex: '',
    clienteId: 1,
    clienteNombre: '',
    rutas: [route],
  );
  final a = Parada(codigo: 'a', nombre: 'Casa', lat: -31.42, lon: -64.18);
  final b = Parada(codigo: 'b', nombre: 'UTN', lat: -31.40, lon: -64.18);
  final trace = Traza(
    lineaId: 'l',
    rutaId: 'r',
    colorHex: '#009ee2',
    puntos: [a.position, b.position],
    paradas: [a, b],
  );
  test(
    'Prepared trip restores route geometry and both travel endpoints',
    () async {
      SharedPreferences.setMockInitialValues({});
      final saved = OfflineTrip(line, route, trace, a, b, a, b, DateTime(2026));
      expect(await saved.save(), isTrue);
      final restored = await OfflineTrip.load();
      expect(restored?.origin.nombre, 'Casa');
      expect(restored?.alighting.codigo, 'b');
      expect(restored?.trace.puntos.last, b.position);
      expect(restored?.trace.paradas.length, 2);
    },
  );
  test('Corrupt download is ignored', () async {
    SharedPreferences.setMockInitialValues({'offline_trip_v1': 'broken'});
    expect(await OfflineTrip.load(), isNull);
  });
  test('Official arrival positions and receipt age survive restart and advance to route end', () async {
    SharedPreferences.setMockInitialValues({});
    final at = DateTime(2026, 10, 7, 17);
    final bus = Coche(
      coche: 562,
      linea: '70',
      sentido: 'I',
      lat: a.lat,
      lon: a.lon,
      curso: 0,
      demora: '',
      rampa: false,
    );
    final saved = OfflineTrip(
      line,
      route,
      trace,
      a,
      b,
      a,
      b,
      at.add(const Duration(minutes: 3)),
      buses: [bus],
      positionsAt: at,
    );
    expect(await saved.save(), isTrue);
    final loaded = (await OfflineTrip.load())!;
    expect(loaded.buses.single.coche, 562);
    expect(loaded.positionsAt, at);
    final estimate = PredictiveEngine.calculatePredictiveBuses(
      lastKnownBuses: loaded.buses,
      snapshotTime: loaded.positionsAt!,
      traza: loaded.trace,
      now: at.add(const Duration(minutes: 2)),
    ).single;
    expect(estimate.isPredictive, isTrue);
    expect(estimate.lat, isNot(a.lat));
    final expired = PredictiveEngine.calculatePredictiveBuses(
      lastKnownBuses: loaded.buses,
      snapshotTime: loaded.positionsAt!,
      traza: loaded.trace,
      now: at.add(const Duration(minutes: 11)),
    ).single;
    expect(expired.lat, b.lat);
    expect(expired.isPredictive, isTrue);
    expect(loaded.buses.single.lat, a.lat);
  });
  test('Old snapshots advance to route end and never mutate originals', () {
    final bus = Coche(
      coche: 1,
      linea: '70',
      sentido: 'I',
      lat: a.lat,
      lon: a.lon,
      curso: 0,
      demora: '',
      rampa: false,
    );
    final timestamp = DateTime(2026);
    final old = PredictiveEngine.calculatePredictiveBuses(
      lastKnownBuses: [bus],
      snapshotTime: timestamp,
      traza: trace,
      now: timestamp.add(const Duration(minutes: 11)),
    ).single;
    expect(old.position, b.position);
    expect(old.isPredictive, isTrue);
    expect(old.demora, contains('11 min'));
    final fresh = PredictiveEngine.calculatePredictiveBuses(
      lastKnownBuses: [bus],
      snapshotTime: timestamp,
      traza: trace,
      now: timestamp.add(const Duration(seconds: 5)),
    ).single;
    expect(fresh.isPredictive, isTrue);
    expect(bus.isPredictive, isFalse);
  });
  test('Prediction advances from a fractional segment and keeps moving past ten minutes', () {
    final at = DateTime(2026);
    final longTrace = Traza(
      lineaId: 'l',
      rutaId: 'r',
      colorHex: '',
      puntos: [const LatLng(-31.5, -64.18), const LatLng(-31.3, -64.18)],
      paradas: [],
    );
    final bus = Coche(
      coche: 1,
      linea: '70',
      sentido: 'I',
      lat: -31.45,
      lon: -64.18,
      curso: 0,
      demora: '',
      rampa: false,
    );
    Coche estimate(int seconds) => PredictiveEngine.calculatePredictiveBuses(
      lastKnownBuses: [bus],
      snapshotTime: at,
      traza: longTrace,
      now: at.add(Duration(seconds: seconds)),
    ).single;
    expect(estimate(0).lat, closeTo(bus.lat, .00001));
    expect(estimate(-60).lat, closeTo(bus.lat, .00001));
    final early = estimate(30), later = estimate(660);
    expect(early.lat, greaterThan(bus.lat));
    expect(later.lat, greaterThan(early.lat));
    expect(later.lat, lessThan(longTrace.puntos.last.latitude));
    expect(
      const Distance().as(LengthUnit.Meter, bus.position, early.position),
      closeTo(150, 2),
    );
    expect(bus.lat, -31.45);
    expect(estimate(99999).position, longTrace.puntos.last);
  });
}
