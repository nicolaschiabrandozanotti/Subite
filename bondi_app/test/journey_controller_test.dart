import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bondi_app/widgets/journey_preferences_sheet.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bondi_app/controllers/journey_controller.dart';
import 'package:bondi_app/models/models.dart';
import 'package:bondi_app/services/journey_planner.dart';
import 'package:bondi_app/services/offline_trip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final route = Ruta(id: 'r', sentido: 'I', nombre: 'Ida', longitud: '');
  Linea line(String id) => Linea(
    id: id,
    nombre: id,
    grupo: '',
    colorHex: '',
    clienteId: 1,
    clienteNombre: '',
    rutas: [route],
  );
  final a = Parada(codigo: 'a', nombre: 'Casa', lat: -31.42, lon: -64.18);
  final b = Parada(codigo: 'b', nombre: 'Destino', lat: -31.40, lon: -64.18);
  Traza trace(String id) => Traza(
    lineaId: id,
    rutaId: route.id,
    colorHex: '',
    puntos: [a.position, b.position],
    paradas: [a, b],
  );
  DirectJourney trip(String id) =>
      DirectJourney(line(id), route, trace(id), a, b, 0, 0);
  List<Map<String, dynamic>> positions(String id, String stop) => [
    {
      'coche': 562,
      'cliente': 1,
      'linea': id,
      'ruta': route.id,
      'a': [stop == 'a' ? a.lat : b.lat, a.lon, a.lat, a.lon],
    },
  ];

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Offline references cannot cross companies sharing line and route IDs',
    () async {
      final at = DateTime.now();
      await OfflineTrip(
        line('1'),
        route,
        trace('1'),
        a,
        b,
        a,
        b,
        at,
        positionsAt: at,
        buses: [
          Coche(
            coche: 562,
            linea: '1',
            sentido: 'I',
            lat: a.lat,
            lon: a.lon,
            curso: 0,
            demora: '',
            rampa: false,
          ),
        ],
      ).save();
      final otherCompany = Linea(
        id: '1',
        nombre: '1',
        grupo: '',
        colorHex: '',
        clienteId: 2,
        clienteNombre: '',
        rutas: [route],
      );
      final controller = JourneyController(
        fetchLines: () async => [otherCompany],
        fetchTrace: (_, _, {bool refreshCached = true}) async => trace('1'),
        fetchArrivals: (_) async => throw StateError('Disconnected'),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.setEndpoints(origin: a, destination: b);
      await controller.chooseTrip(
        DirectJourney(otherCompany, route, trace('1'), a, b, 0, 0),
      );
      expect(controller.offline, isTrue);
      expect(controller.buses, isEmpty);
      expect(controller.preparedTrip!.line.clienteId, 2);
      expect(controller.preparedTrip!.buses, isEmpty);
    },
  );

  test(
    'Late route selection cannot replace the current line or loading state',
    () async {
      final first = Completer<Traza?>(), second = Completer<Traza?>();
      final controller = JourneyController(
        fetchTrace: (line, route, {bool refreshCached = true}) =>
            line.id == '1' ? first.future : second.future,
        fetchArrivals: (_) async => [],
      );
      addTearDown(controller.dispose);
      final oldSelection = controller.selectLine(line('1'));
      final newSelection = controller.selectLine(line('2'));
      second.complete(trace('2'));
      expect(await newSelection, isTrue);
      first.complete(trace('1'));
      expect(await oldSelection, isFalse);
      expect(controller.line!.id, '2');
      expect(controller.trace!.lineaId, '2');
      expect(controller.loading, isFalse);
    },
  );

  test(
    'Changing endpoints cancels an in-flight search and discards its results',
    () async {
      final pending = Completer<Traza?>();
      final controller = JourneyController(
        fetchLines: () async => [line('1')],
        fetchTrace: (_, _, {bool refreshCached = true}) => pending.future,
        fetchArrivals: (_) async => [],
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.setEndpoints(origin: a, destination: b);
      final oldSearch = controller.findJourneys();
      expect(controller.planning, isTrue);
      controller.setEndpoints(origin: b, destination: a);
      pending.complete(trace('1'));
      expect(await oldSearch, JourneySearchResult.cancelled);
      expect(controller.planning, isFalse);
      expect(controller.tripOptions, isEmpty);
      expect(controller.origin, b.position);
      expect(controller.destination!.position, a.position);
    },
  );

  test('Empty arrivals preserve the last snapshot and failure opens the matching offline trip', () async {
    var response = positions('1', 'a');
    var failed = false;
    var now = DateTime.utc(2026, 10, 8, 15);
    final controller = JourneyController(
      fetchTrace: (line, _, {bool refreshCached = true}) async =>
          trace(line.id),
      fetchArrivals: (stop) async {
        if (failed) throw StateError('Disconnected');
        return stop == 'a' ? response : [];
      },
      now: () => now,
    );
    addTearDown(controller.dispose);
    controller.setEndpoints(origin: a, destination: b);
    expect(await controller.chooseTrip(trip('1')), isTrue);
    expect(controller.preparedTrip!.buses.single.coche, 562);
    final originalTimestamp = controller.preparedTrip!.positionsAt;
    now = now.add(const Duration(minutes: 1));
    response = [];
    await controller.refresh();
    expect(controller.buses, isEmpty);
    expect(controller.preparedTrip!.buses.single.coche, 562);
    expect(controller.preparedTrip!.positionsAt, originalTimestamp);
    failed = true;
    await controller.refresh();
    expect(controller.offline, isTrue);
    expect(controller.inTrip, isTrue);
    expect(controller.buses.single.isPredictive, isTrue);
    expect(controller.buses.single.lat, greaterThan(a.lat));
    expect((await OfflineTrip.load())!.positionsAt, originalTimestamp);
  });

  test('A changed destination never inherits buses from the previous saved journey', () async {
    var failed = false;
    final controller = JourneyController(
      fetchTrace: (line, _, {bool refreshCached = true}) async =>
          trace(line.id),
      fetchArrivals: (stop) async {
        if (failed) throw StateError('Disconnected');
        return positions('1', stop);
      },
    );
    addTearDown(controller.dispose);
    controller.setEndpoints(origin: a, destination: b);
    await controller.chooseTrip(trip('1'));
    expect(controller.preparedTrip!.buses, isNotEmpty);
    controller.setEndpoints(
      destination: Parada(
        codigo: 'c',
        nombre: 'Otro destino',
        lat: b.lat,
        lon: b.lon + .001,
      ),
    );
    failed = true;
    await controller.chooseTrip(trip('1'));
    expect(controller.offline, isTrue);
    expect(controller.preparedTrip!.destination.codigo, 'c');
    expect(controller.buses, isEmpty);
    expect(controller.preparedTrip!.buses, isEmpty);
  });

  test(
    'Offline tracking advances from the stored timestamp without network',
    () async {
      var now = DateTime.utc(2026, 10, 8, 15);
      final snapshot = OfflineTrip(
        line('1'),
        route,
        trace('1'),
        a,
        b,
        a,
        b,
        now,
        positionsAt: now,
        buses: [
          Coche(
            coche: 562,
            linea: '1',
            sentido: 'I',
            lat: a.lat,
            lon: a.lon,
            curso: 0,
            demora: '',
            rampa: false,
          ),
        ],
      );
      await snapshot.save();
      var requests = 0;
      final controller = JourneyController(
        fetchLines: () async => [],
        fetchArrivals: (_) async {
          requests++;
          return [];
        },
        now: () => now,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.openOffline();
      controller.trackVehicle(562);
      final initial = controller.tracked!.lat;
      now = now.add(const Duration(seconds: 30));
      await controller.refresh();
      expect(controller.tracked!.lat, greaterThan(initial));
      expect(controller.arrivalVehicle, 562);
      expect(controller.routePoints, [a.position, b.position]);
      expect(requests, 0);
      controller.trackVehicle(null);
      expect(controller.tracked, isNull);
    },
  );

  testWidgets(
    'Polling pauses in background, resumes, and stops after disposal',
    (tester) async {
      var calls = 0;
      final controller = JourneyController(
        fetchTrace: (line, _, {bool refreshCached = true}) async =>
            trace(line.id),
        fetchArrivals: (_) async {
          calls++;
          return [];
        },
      );
      controller.setEndpoints(origin: a, destination: b);
      await controller.chooseTrip(trip('1'));
      controller.setForeground(false);
      final before = calls;
      await tester.pump(const Duration(minutes: 2));
      expect(calls, before);
      controller.setForeground(true);
      await tester.pump();
      expect(calls, greaterThan(before));
      final resumed = calls;
      await tester.pump(const Duration(seconds: 20));
      expect(calls, greaterThan(resumed));
      controller.dispose();
      final disposed = calls;
      await tester.pump(const Duration(minutes: 2));
      expect(calls, disposed);
    },
  );

  test(
    'Disposal rejects a late request without notifying or scheduling more work',
    () async {
      final pending = Completer<Traza?>();
      final controller = JourneyController(
        fetchTrace: (_, _, {bool refreshCached = true}) => pending.future,
        fetchArrivals: (_) async => [],
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final selected = controller.selectLine(line('1'));
      controller.dispose();
      final before = notifications;
      pending.complete(trace('1'));
      expect(await selected, isFalse);
      expect(notifications, before);
    },
  );

  test('Reconnect preserves stops and resumes live arrivals', () async {
    var failed = false;
    final c = JourneyController(
      fetchTrace: (l, _, {bool refreshCached = true}) async => trace(l.id),
      fetchArrivals: (stop) async {
        if (failed) throw StateError('Disconnected');
        return positions('1', stop);
      },
    );
    addTearDown(c.dispose);
    c.setEndpoints(origin: a, destination: b);
    await c.chooseTrip(trip('1'));
    await c.openOffline();
    failed = true;
    await c.reconnect();
    expect(c.offline, isFalse);
    expect(c.arrivalError, isNotNull);
    expect(c.pickup, a);
    expect(c.dropoff, b);
    failed = false;
    await c.refresh();
    expect(c.offline, isFalse);
    expect(c.inTrip, isTrue);
    expect(c.pickup, a);
    expect(c.dropoff, b);
    expect(c.buses.single.isPredictive, isFalse);
  });
  test('Other companies cannot contribute to the route ETA', () async {
    final c = JourneyController(
      fetchLines: () async => [line('1')],
      fetchTrace: (l, _, {bool refreshCached = true}) async => trace(l.id),
      fetchArrivals: (_) async => [
        {'linea': '1', 'ruta': 'r', 'cliente': 999, 'hora_salida': '12:10'},
      ],
      now: () => DateTime.utc(2026, 10, 8, 15),
    );
    addTearDown(c.dispose);
    await c.load();
    c.setEndpoints(origin: a, destination: b);
    await c.findJourneys();
    expect(c.reachableArrival(trip('1')), isNull);
    expect(c.buses, isEmpty);
  });
  test(
    'Line loading stays pending when endpoints change before response',
    () async {
      final pending = Completer<List<Linea>>();
      final c = JourneyController(fetchLines: () => pending.future);
      addTearDown(c.dispose);
      final load = c.load();
      c.setEndpoints(origin: a, destination: b);
      expect(c.loadingLines, isTrue);
      pending.complete([line('1')]);
      await load;
      expect(c.loadingLines, isFalse);
      expect(c.lines.single.id, '1');
    },
  );
  testWidgets(
    'Preferences distinguish pending lines from an unavailable route',
    (tester) async {
      final pending = Completer<List<Linea>>();
      final c = JourneyController(fetchLines: () => pending.future);
      final load = c.load();
      c.setEndpoints(origin: a, destination: b);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JourneyPreferencesSheet(
              journey: c,
              onEditEndpoint: (_) {},
              onFindJourneys: () {},
              onSaveDestination: () {},
              onPickLine: () async {},
              onChooseTrip: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Cargando líneas y recorrido…'), findsOneWidget);
      expect(find.textContaining('Este recorrido no tiene'), findsNothing);
      pending.complete([]);
      await load;
      await tester.pump();
      expect(find.text('Cargando líneas y recorrido…'), findsNothing);
      expect(find.textContaining('Este recorrido no tiene'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
