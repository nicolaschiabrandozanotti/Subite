import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/arrival_time.dart';
import '../services/arrival_positions.dart';
import '../services/journey_planner.dart';
import '../services/offline_trip.dart';
import '../services/predictive_engine.dart';
import '../services/route_catalog.dart';
import '../services/route_position.dart';

typedef TraceLoader = Future<Traza?> Function(
  Linea line,
  Ruta route, {
  bool refreshCached,
});

enum JourneySearchResult { ready, noRoutes, cancelled }

enum PickupPreference { nearest, stop }

class JourneyController extends ChangeNotifier {
  JourneyController({
    Future<List<Linea>> Function()? fetchLines,
    TraceLoader? fetchTrace,
    Future<List<Map<String, dynamic>>> Function(String)? fetchArrivals,
    DateTime Function()? now,
    this._onMessage,
  }) : _fetchLines = fetchLines ?? ApiService.fetchLineas,
       _fetchTrace =
           fetchTrace ??
           ((line, route, {bool refreshCached = true}) => ApiService.fetchTraza(
             line.id,
             route.id,
             line.clienteId,
             refreshCached: refreshCached,
           )),
       _fetchArrivals = fetchArrivals ?? ApiService.fetchArrivals,
       _now = now ?? DateTime.now;

  final Future<List<Linea>> Function() _fetchLines;
  final TraceLoader _fetchTrace;
  final Future<List<Map<String, dynamic>>> Function(String) _fetchArrivals;
  final DateTime Function() _now;
  final void Function(String)? _onMessage;
  bool _disposed = false,
      _foreground = true,
      _lightMode = false,
      _polling = false;
  bool get _active => !_disposed;

  bool _loadingLines = true;
  bool get loadingLines => _loadingLines;
  List<Linea> _lines = [];
  Linea? _line;
  Ruta? _route;
  Traza? _trace;
  List<Coche> _buses = [];
  DateTime? _positionsAt;
  Coche? _tracked;
  int? _arrivalVehicle;
  Parada? _destination;
  Parada? _pickup;
  Parada? _dropoff;
  PickupPreference _pickupPreference = PickupPreference.nearest;
  LatLng _origin = const LatLng(-31.4167, -64.1833);
  String _originName = 'Elegí tu punto de partida';
  bool _loading = true;

  bool _inTrip = false;
  int _planningToken = 0;
  bool _planning = false, _planned = false;
  int _planningFailed = 0;
  List<DirectJourney> _tripOptions = [];
  List<Map<String, dynamic>> _arrivals = [];
  String? _arrivalError;
  final Map<String, List<Map<String, dynamic>>> _arrivalsByStop = {};
  final Set<String> _arrivalStopErrors = {};
  bool _comparisonBusy = false;
  bool _offline = false;
  OfflineTrip? _preparedTrip;
  Timer? _timer;
  int _request = 0;

  List<Linea> get lines => List.unmodifiable(_lines);
  Linea? get line => _line;
  Ruta? get route => _route;
  Traza? get trace => _trace;
  List<Coche> get buses => List.unmodifiable(_buses);
  Coche? get tracked => _tracked;
  int? get arrivalVehicle => _arrivalVehicle;
  Parada? get destination => _destination;
  Parada? get pickup => _pickup;
  Parada? get dropoff => _dropoff;
  LatLng get origin => _origin;
  String get originName => _originName;
  bool get loading => _loading;
  bool get inTrip => _inTrip;
  bool get planning => _planning;
  bool get planned => _planned;
  int get planningFailed => _planningFailed;
  List<DirectJourney> get tripOptions => List.unmodifiable(_tripOptions);
  List<Map<String, dynamic>> get arrivals => List.unmodifiable(_arrivals);
  String? get arrivalError => _arrivalError;
  bool get offline => _offline;
  OfflineTrip? get preparedTrip => _preparedTrip;
  bool get hasOrigin => _originName != 'Elegí tu punto de partida';
  bool get lightMode => _lightMode;
  PickupPreference get pickupPreference => _pickupPreference;
  Map<String, List<Map<String, dynamic>>> get arrivalsByStop =>
      Map.unmodifiable(_arrivalsByStop);
  Set<String> get arrivalStopErrors => Set.unmodifiable(_arrivalStopErrors);

  void _update(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  void _message(String text) => _onMessage?.call(text);

  Future<void> load() async {
    final prepared = await OfflineTrip.load();
    if (_disposed) return;
    _update(() => _preparedTrip = prepared);
    final lines = await _fetchLines();
    _update(() {
      _loadingLines = false;
      _lines = lines;
      _loading = false;
    });
  }

  void setEndpoints({Parada? origin, Parada? destination}) {
    _automaticOffline = true;
    cancelPlanning();
    _update(() {
      if (origin != null) {
        _origin = origin.position;
        _originName = origin.nombre;
      }
      if (destination != null) _destination = destination;
      _offline = false;
      _inTrip = false;
      _pickup = null;
      _dropoff = null;
      _tracked = null;
      _arrivalVehicle = null;
      _tripOptions = [];
      _arrivals = [];
      _arrivalsByStop.clear();
      _arrivalStopErrors.clear();
    });
  }

  void swapEndpoints() {
    final destination = _destination;
    if (destination == null || !hasOrigin) return;
    setEndpoints(
      origin: destination,
      destination: Parada(
        codigo: 'origin',
        nombre: _originName,
        lat: _origin.latitude,
        lon: _origin.longitude,
      ),
    );
  }

  void setPickup(Parada? stop) {
    _update(() {
      _pickup = stop;
      _pickupPreference = stop == null
          ? PickupPreference.nearest
          : PickupPreference.stop;
      _inTrip = false;
    });
  }

  void setPickupPreference(PickupPreference preference) {
    _update(() {
      _pickupPreference = preference;
      if (preference == PickupPreference.nearest) {
        _pickup = null;
        _inTrip = false;
      }
    });
  }

  void _setBusPositions(List<Coche> buses) {
    _buses = buses;
    final matches = buses.where((bus) => bus.coche == _arrivalVehicle);
    _tracked = matches.isEmpty ? null : matches.first;
  }

  void trackVehicle(int? id) {
    final matches = visibleBuses.where((bus) => bus.coche == id);
    _update(() {
      _arrivalVehicle = id;
      _tracked = matches.isEmpty ? null : matches.first;
    });
  }

  void cancelPlanning() {
    ++_planningToken;
    ++_request;
    ++_arrivalRequest;
    _timer?.cancel();
    _update(() {
      _planning = false;
      _planned = false;
      _loading = false;
    });
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    _timer?.cancel();
    if (foreground && !_planning && _line != null) {
      unawaited(refresh());
      _scheduleUpdates();
    }
  }

  void setLightMode(bool light) {
    _lightMode = light;
    if (_line != null) _scheduleUpdates();
  }

  Future<void> refresh() async {
    if (!_foreground || _disposed || _planning) return;
    final token = _planningToken;
    if (_planned && !_offline) {
      if (!_inTrip) {
        await _refreshComparison(token);
        return;
      }
      await _refreshArrivals(token);
    } else if (_inTrip && !_offline) {
      await _refreshArrivals(token);
    }
    if (_active && token == _planningToken) await _refresh();
  }

  void _scheduleUpdates() {
    _timer?.cancel();
    if (!_foreground || _disposed) return;
    final interval = _inTrip && !_offline && !_lightMode ? 20 : 30;
    _timer = Timer.periodic(Duration(seconds: interval), (_) async {
      if (_polling) return;
      _polling = true;
      try {
        await refresh();
      } finally {
        _polling = false;
      }
    });
  }

  int? arrivalSeconds(Map<String, dynamic> arrival) => stopArrivalSeconds(
    arrival,
    _now().toUtc().subtract(const Duration(hours: 3)),
  );

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    ++_planningToken;
    ++_arrivalRequest;
    _timer?.cancel();
    super.dispose();
  }

  bool _automaticOffline = true;

  Future<void> reconnect() async {
    if (!_offline || !_inTrip) return;
    ++_request;
    ++_arrivalRequest;
    _automaticOffline = false;
    _update(() {
      _offline = false;
      _setBusPositions([]);
    });
    await refresh();
    if (_active) _scheduleUpdates();
  }

  Future<bool> selectLine(Linea line, [Ruta? route]) async {
    if (line.rutas.isEmpty) return false;
    final token = ++_request;
    ++_arrivalRequest;
    _timer?.cancel();
    _update(() {
      _offline = false;
      _line = line;
      _route = route ?? line.rutas.first;
      _trace = null;
      _setBusPositions([]);
      _positionsAt = null;
      _tracked = null;
      _arrivalVehicle = null;
      _pickup = null;
      _dropoff = null;
      _inTrip = false;
      _loading = true;
    });
    final trace = await _fetchTrace(line, _route!);
    if (!_active || token != _request) return false;
    _update(() {
      _trace = trace;
      _loading = false;
    });
    await _refresh();
    if (!_active || token != _request) return false;
    _scheduleUpdates();
    return true;
  }

  bool _exploringBuses = false;
  Future<void> _refresh() async {
    if (!_foreground) return;
    if (_planned && !_inTrip && !_offline) return;
    if (_line == null || _route == null) return;
    if (_offline && _preparedTrip != null) {
      final trip = _preparedTrip!;
      _update(() {
        _setBusPositions(
          trip.positionsAt == null
              ? []
              : PredictiveEngine.calculatePredictiveBuses(
                  lastKnownBuses: trip.buses,
                  snapshotTime: trip.positionsAt!,
                  traza: trip.trace,
                  now: _now(),
                ),
        );
      });
      return;
    }
    if (_inTrip && !_offline && _pickup != null) {
      _update(() {
        _setBusPositions(
          arrivalPositions(_arrivals, _pickup!, _line!, _route!),
        );
      });
      return;
    }
    if (!_offline && !_planned && !_inTrip && _trace != null) {
      if (_exploringBuses) return;
      _exploringBuses = true;
      final token = _request;
      final line = _line!, route = _route!;
      final stops = _trace!.paradas;
      final selected = <Parada>[];
      for (var i = 0; i < 6 && stops.isNotEmpty; i++) {
        final stop = stops[((stops.length - 1) * i / 5).round()];
        if (!selected.any((s) => s.codigo == stop.codigo)) selected.add(stop);
      }
      final buses = <int, Coche>{};
      var next = 0;
      Future<void> worker() async {
        while (next < selected.length &&
            _active &&
            _foreground &&
            token == _request) {
          final stop = selected[next++];
          try {
            final arrivals = await _fetchArrivals(stop.codigo);
            for (final bus in arrivalPositions(arrivals, stop, line, route)) {
              buses.putIfAbsent(bus.coche, () => bus);
            }
          } catch (_) {
            /* Other stops may still have current positions. */
          }
        }
      }

      try {
        await Future.wait([worker(), worker(), worker()]);
        if (_active && token == _request) {
          _update(() {
            _setBusPositions(buses.values.toList());
            _positionsAt = _now();
          });
        }
      } finally {
        _exploringBuses = false;
      }
      return;
    }
  }

  bool _matchesPreparedTrip(OfflineTrip saved) =>
      saved.line.clienteId == _line?.clienteId &&
      saved.line.id == _line?.id &&
      saved.route.id == _route?.id &&
      saved.route.sentido == _route?.sentido &&
      saved.boarding.codigo == _pickup?.codigo &&
      saved.alighting.codigo == _dropoff?.codigo &&
      saved.origin.position == _origin &&
      saved.destination.position == _destination?.position;

  Future<bool> prepareOffline({bool quiet = false}) async {
    final version = _request;
    if (!_inTrip ||
        _line == null ||
        _route == null ||
        _trace == null ||
        _pickup == null ||
        _dropoff == null ||
        _destination == null) {
      if (!quiet) _message('Elegí un viaje A → B antes de prepararlo.');
      return false;
    }
    final previous = _preparedTrip;
    final sameTrip = previous != null && _matchesPreparedTrip(previous);
    final keepPositions = _buses.isEmpty && sameTrip;
    final trip = OfflineTrip(
      _line!,
      _route!,
      _trace!,
      Parada(
        codigo: 'origin',
        nombre: _originName,
        lat: _origin.latitude,
        lon: _origin.longitude,
      ),
      _destination!,
      _pickup!,
      _dropoff!,
      _now(),
      buses: List<Coche>.from(keepPositions ? previous.buses : _buses),
      positionsAt: keepPositions ? previous.positionsAt : _positionsAt,
    );
    final saved = await trip.save();
    if (!_active || version != _request) return saved;
    if (saved) _update(() => _preparedTrip = trip);
    if (!quiet) {
      _message(
        saved
            ? 'Viaje guardado con ${trip.buses.length} colectivos. Sin conexión sus ubicaciones serán aproximadas; el mapa local de Córdoba está disponible.'
            : 'No se pudo guardar el viaje.',
      );
    }
    return saved;
  }

  Future<void> openOffline() async {
    final trip = _preparedTrip;
    if (trip == null) return;
    _automaticOffline = true;
    ++_planningToken;
    ++_request;
    _timer?.cancel();
    _update(() {
      _offline = true;
      _loading = false;
      _inTrip = true;
      _line = trip.line;
      _route = trip.route;
      _trace = trip.trace;
      _origin = trip.origin.position;
      _originName = trip.origin.nombre;
      _destination = trip.destination;
      _pickup = trip.boarding;
      _dropoff = trip.alighting;
      _setBusPositions([]);
      _tracked = null;
      _arrivalVehicle = null;
    });
    await _refresh();
    if (!_active || !_offline) return;
    _scheduleUpdates();
  }

  DirectJourney? currentJourney({String? boardingCode}) {
    if (_trace == null ||
        _line == null ||
        _route == null ||
        _destination == null ||
        !hasOrigin) {
      return null;
    }
    return JourneyPlanner.find(
      _line!,
      _route!,
      _trace!,
      _origin,
      _destination!.position,
      boardingCode: boardingCode,
    );
  }

  Future<JourneySearchResult> findJourneys() async {
    if (_offline || _destination == null || !hasOrigin || _lines.isEmpty) {
      return JourneySearchResult.cancelled;
    }
    final origin = _origin, destination = _destination!.position;
    final token = ++_planningToken;
    ++_request;
    _timer?.cancel();
    _update(() {
      _planning = true;
      _planned = true;
      _inTrip = false;
      _tripOptions = [];
      _arrivalVehicle = null;
      _setBusPositions([]);
      _trace = null;
      _pickup = null;
      _dropoff = null;
      _arrivals = [];
      _arrivalError = null;
      _planningFailed = 0;
    });
    final candidates = <DirectJourney>[];
    final catalog = await loadRouteCatalog(
      _lines,
      (line, route) => _fetchTrace(line, route, refreshCached: false),
      keepGoing: () => _active && token == _planningToken,
    );
    final available = catalog.routes;
    if (!_active || token != _planningToken) {
      return JourneySearchResult.cancelled;
    }
    _planningFailed = catalog.unavailable;
    for (final item in available) {
      if (!_active || token != _planningToken) {
        return JourneySearchResult.cancelled;
      }
      final journey = JourneyPlanner.find(
        item.$1,
        item.$2,
        item.$3,
        origin,
        destination,
      );
      if (journey != null) candidates.add(journey);
    }
    if (!_active || token != _planningToken) {
      return JourneySearchResult.cancelled;
    }
    candidates.sort((a, b) => a.walkStart.compareTo(b.walkStart));
    final compatible = candidates;
    _arrivalsByStop.clear();
    _arrivalStopErrors.clear();
    _update(() {
      _planning = false;
      _tripOptions = compatible;
      _pickup = null;
      _loading = false;
    });
    if (compatible.isEmpty) {
      _update(() => _planned = false);
      return JourneySearchResult.noRoutes;
    }
    await _refreshComparison(token);
    if (!_active || token != _planningToken) {
      return JourneySearchResult.cancelled;
    }
    await chooseTrip(_tripOptions.first);
    if (!_active || token != _planningToken) {
      return JourneySearchResult.cancelled;
    }
    _scheduleUpdates();
    return JourneySearchResult.ready;
  }

  Future<void> _refreshComparison(int token) async {
    if (!_foreground) return;
    if (_comparisonBusy) return;
    _comparisonBusy = true;
    final codes = _tripOptions
        .map((trip) => trip.boarding.codigo)
        .toSet()
        .toList();
    var next = 0;
    final updated = <String, List<Map<String, dynamic>>>{};
    final failed = <String>{};
    Future<void> worker() async {
      while (next < codes.length &&
          _active &&
          _foreground &&
          token == _planningToken &&
          !_inTrip) {
        final code = codes[next++];
        try {
          final arrivals = await _fetchArrivals(code);
          if (!_active || token != _planningToken || _inTrip) return;
          updated[code] = arrivals;
        } catch (_) {
          if (!_active || token != _planningToken) return;
          failed.add(code);
        }
      }
    }

    try {
      await Future.wait([worker(), worker(), worker()]);
      if (!_active || token != _planningToken || _inTrip) return;
      _update(() {
        _arrivalsByStop.addAll(updated);
        _arrivalStopErrors.removeAll(updated.keys);
        for (final code in failed) {
          _arrivalsByStop.remove(code);
        }
        _arrivalStopErrors.addAll(failed);
        _sortTripOptions();
      });
    } finally {
      _comparisonBusy = false;
    }
  }

  int? reachableArrival(DirectJourney trip) {
    final now = _now().toUtc().subtract(const Duration(hours: 3));
    int? best;
    for (final a
        in _arrivalsByStop[trip.boarding.codigo] ?? <Map<String, dynamic>>[]) {
      if (!arrivalMatchesRoute(a, trip.line, trip.route)) {
        continue;
      }
      final seconds = stopArrivalSeconds(a, now);
      // Walking is a rough estimate; leave a minute of margin rather than
      // recommending a vehicle that would arrive before the user can walk there.
      if (seconds != null &&
          seconds >= trip.walkStart / 1.2 + 60 &&
          (best == null || seconds < best)) {
        best = seconds;
      }
    }
    return best;
  }

  void _sortTripOptions() {
    _tripOptions.sort((a, b) {
      final first = reachableArrival(a), second = reachableArrival(b);
      if (first == null && second != null) return 1;
      if (first != null && second == null) return -1;
      if (first != null && second != null) return first.compareTo(second);
      return a.walkStart.compareTo(b.walkStart);
    });
  }

  int _arrivalRequest = 0;
  Future<void> _refreshArrivals(int token) async {
    if (!_foreground) return;
    final stop = _pickup;
    if (stop == null || _offline) return;
    final version = ++_arrivalRequest;
    try {
      final arrivals = await _fetchArrivals(stop.codigo);
      if (!_active ||
          token != _planningToken ||
          version != _arrivalRequest ||
          _pickup?.codigo != stop.codigo) {
        return;
      }
      _update(() {
        _arrivals = arrivals;
        _arrivalsByStop[stop.codigo] = arrivals;
        _arrivalStopErrors.remove(stop.codigo);
        _arrivalError = null;
        if (_line != null && _route != null) {
          _setBusPositions(arrivalPositions(arrivals, stop, _line!, _route!));
          _positionsAt = _now();
        }
      });
      // Preserve the latest usable snapshot while there is connection. Empty
      // responses must not erase the only positions available without data.
      if (_buses.isNotEmpty) await prepareOffline(quiet: true);
    } catch (_) {
      if (!_active ||
          token != _planningToken ||
          version != _arrivalRequest ||
          _pickup?.codigo != stop.codigo) {
        return;
      }
      final saved = _preparedTrip;
      if (_automaticOffline && saved != null && _matchesPreparedTrip(saved)) {
        await openOffline();
        _message(
          'No pudimos conectar. Mostramos ubicaciones aproximadas guardadas.',
        );
        return;
      }
      _update(() {
        _arrivals = [];
        _setBusPositions([]);
        _arrivalStopErrors.add(stop.codigo);
        _arrivalError = 'No pudimos actualizar las llegadas. Volvé a intentar.';
      });
    }
  }

  Future<bool> chooseTrip(DirectJourney trip) async {
    final token = _planningToken;
    if (!await selectLine(trip.line, trip.route)) return false;
    if (!_active || token != _planningToken || _trace == null) return false;
    final version = _request;
    _update(() {
      _pickup = trip.boarding;
      _dropoff = trip.alighting;
      _inTrip = true;
    });
    await prepareOffline(quiet: true);
    if (!_active || token != _planningToken || version != _request) {
      return false;
    }
    await _refreshArrivals(token);
    if (!_active || token != _planningToken || version != _request) {
      return false;
    }
    await _refresh();
    if (!_active || token != _planningToken) return false;
    _scheduleUpdates();
    return true;
  }

  Traza? _stopsTrace;
  Object? _routePointsKey;
  List<LatLng> _routePoints = [];
  List<LatLng> get routePoints {
    final key = (_trace, _pickup, _dropoff, _inTrip, _planned);
    if (key == _routePointsKey) return _routePoints;
    _routePointsKey = key;
    final points =
        _inTrip && _trace != null && _pickup != null && _dropoff != null
        ? JourneyPlanner.segment(_trace!, _pickup!, _dropoff!)
        : !_planned && _trace != null
        ? _trace!.puntos
        : <LatLng>[];
    return _routePoints = List.unmodifiable(points);
  }

  Parada? _stopsPickup, _stopsDropoff;
  List<Parada> _cachedStops = [];
  List<Parada> get tripStops {
    final trace = _trace;
    if (trace == null) return [];
    if (!_inTrip || _pickup == null || _dropoff == null) return trace.paradas;
    if (identical(trace, _stopsTrace) &&
        identical(_pickup, _stopsPickup) &&
        identical(_dropoff, _stopsDropoff)) {
      return _cachedStops;
    }
    final start = JourneyPlanner.progress(_pickup!.position, trace.puntos);
    final end = JourneyPlanner.progress(_dropoff!.position, trace.puntos);
    if (start == null || end == null) return [];
    final ordered = <(Parada, double)>[];
    for (final p in trace.paradas) {
      final position = JourneyPlanner.progress(p.position, trace.puntos);
      if (position != null && position >= start && position <= end) {
        ordered.add((p, position));
      }
    }
    ordered.sort((a, b) => a.$2.compareTo(b.$2));
    _stopsTrace = trace;
    _stopsPickup = _pickup;
    _stopsDropoff = _dropoff;
    return _cachedStops = ordered.map((p) => p.$1).toList();
  }

  List<Coche>? _displaySource;
  Traza? _displayTrace;
  List<Coche> _displayBuses = [];
  List<Coche> get visibleBuses {
    // Route GPS and stop arrivals are separate provider feeds. Show the route
    // positions without claiming that every vehicle will pick the user up.
    final trace = _trace;
    if (trace == null) return [];
    if (identical(_buses, _displaySource) && identical(trace, _displayTrace)) {
      return _displayBuses;
    }
    final displayed = <Coche>[];
    for (final bus in _buses) {
      if (bus.lat == 0 || bus.lon == 0) continue;
      final point = routePosition(bus.position, trace.puntos);
      // Validated stop-arrival positions can be slightly outside the geometry.
      // Keep small offsets visible without moving them far across the map.
      if (point == null) {
        if (JourneyPlanner.progress(bus.position, trace.puntos) != null) {
          displayed.add(bus);
        }
        continue;
      }
      displayed.add(
        Coche.fromJson({
          ...bus.toJson(),
          'lat': point.latitude,
          'lon': point.longitude,
        }),
      );
    }
    _displaySource = _buses;
    _displayTrace = trace;
    return _displayBuses = displayed;
  }
}
