import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/saved_journey.dart';
import '../services/api_service.dart';
import '../services/place_search_service.dart';
import '../widgets/bus_marker.dart';
import '../services/trip_alert_service.dart';
import '../services/arrival_alert.dart';
import '../services/journey_planner.dart';
import '../services/route_catalog.dart';
import '../services/offline_trip.dart';
import '../services/recent_places.dart';
import '../services/arrival_positions.dart';
import '../services/route_position.dart';
import '../services/predictive_engine.dart';
import 'expenses_screen.dart';

const blue = Color(0xFF006CA8);
const ink = Color(0xFF182D46);
const pale = Color(0xFFEAF2FF);

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen>
    with WidgetsBindingObserver {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  final _alerts = TripAlertService();
  final _arrivalAlert = ArrivalAlert();
  List<Linea> _lines = [];
  Linea? _line;
  Ruta? _route;
  Traza? _trace;
  List<Coche> _buses = [];
  DateTime? _positionsAt;
  Coche? _tracked;
  int? _arrivalVehicle;
  List<Parada> _saved = [];
  List<SavedJourney> _journeys = [];
  Parada? _destination;
  Parada? _pickup;
  Parada? _dropoff;
  LatLng _origin = const LatLng(-31.4167, -64.1833);
  String _originName = 'Elegí tu punto de partida';
  String? _picking;
  String _preference = 'nearest';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alerts.addListener(_alertChanged);
    _arrivalAlert.addListener(_arrivalChanged);
    _load();
    _detectLightMode();
  }

  bool _lightMode = false;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _line != null && !_planning) {
      _resumeUpdates();
    }
  }

  Future<void> _resumeUpdates() async {
    if (_planned && _inTrip && !_offline)
      await _refreshArrivals(_planningToken);
    else if (_planned && !_inTrip && !_offline) {
      await _refreshComparison(_planningToken);
      return;
    }
    if (mounted) await _refresh();
  }

  Future<void> _detectLightMode() async {
    try {
      final light = await const MethodChannel('bondi/device')
          .invokeMethod<bool>('lightMode');
      if (mounted) setState(() => _lightMode = light ?? false);
    } on MissingPluginException {
      /* Desktop uses the standard display. */
    } on PlatformException {
      /* Keep the standard display if detection fails. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _alerts.dispose();
    _arrivalAlert.dispose();
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    List<Parada> saved = [];
    try {
      saved = (jsonDecode(
        prefs.getString('saved_places_native') ?? '[]',
      ) as List).map((p) => Parada.fromJson(p)).toList();
    } catch (_) {}
    final journeys = await SavedJourney.load();
    final prepared = await OfflineTrip.load();
    if (!mounted) return;
    setState(() => _preparedTrip = prepared);
    final lines = await ApiService.fetchLineas();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _journeys = journeys;
      _lines = lines;
      _loading = false;
    });
  }

  Future<void> _selectLine(Linea line, [Ruta? route]) async {
    _arrivalAlert.cancel();
    if (line.rutas.isEmpty) return;
    final token = ++_request;
    _timer?.cancel();
    setState(() {
      _offline = false;
      _line = line;
      _route = route ?? line.rutas.first;
      _trace = null;
      _buses = [];
      _positionsAt = null;
      _tracked = null;
      _arrivalVehicle = null;
      _pickup = null;
      _inTrip = false;
      _loading = true;
    });
    final trace = await ApiService.fetchTraza(
      line.id,
      _route!.id,
      line.clienteId,
    );
    if (!mounted || token != _request) return;
    setState(() {
      _trace = trace;
      _loading = false;
    });
    await _refresh();
    if (!mounted || token != _request) return;
    if (!_planned) _fitJourney();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  bool _exploringBuses = false;
  Future<void> _refresh() async {
    if (!_foreground) return;
    if (_planned && !_inTrip && !_offline) return;
    if (_line == null || _route == null) return;
    if (_offline && _preparedTrip != null) {
      final trip = _preparedTrip!;
      setState(
        () => _buses = trip.positionsAt == null
            ? []
            : PredictiveEngine.calculatePredictiveBuses(
                lastKnownBuses: trip.buses,
                snapshotTime: trip.positionsAt!,
                traza: trip.trace,
              ),
      );
      return;
    }
    if (_planned && _inTrip && !_offline && _pickup != null) {
      setState(() {
        _buses = arrivalPositions(_arrivals, _pickup!, _line!, _route!);
        if (_tracked != null) {
          final matches = _buses.where((b) => b.coche == _tracked!.coche);
          if (matches.isNotEmpty) _tracked = matches.first;
        }
      });
      return;
    }
    if (!_offline && !_planned && _trace != null) {
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
            mounted &&
            _foreground &&
            token == _request) {
          final stop = selected[next++];
          try {
            final arrivals = await ApiService.fetchArrivals(stop.codigo);
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
        if (mounted && token == _request)
          setState(() {
            _buses = buses.values.toList();
            _positionsAt = DateTime.now();
          });
      } finally {
        _exploringBuses = false;
      }
      return;
    }
    final token = _request;
    final result = await ApiService.fetchCoches(
      rutaId: _route!.id,
      clienteId: _line!.clienteId,
      lineaNombre: _line!.nombre,
      traza: _trace,
      offline: _offline,
    );
    if (!mounted || token != _request) return;
    setState(() {
      _buses = (result['coches'] as List<Coche>?) ?? [];
    });
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _prepareOffline({bool quiet = false}) async {
    if (!_inTrip ||
        _line == null ||
        _route == null ||
        _trace == null ||
        _pickup == null ||
        _dropoff == null ||
        _destination == null) {
      if (!quiet) _message('Elegí un viaje A → B antes de prepararlo.');
      return;
    }
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
      DateTime.now(),
      buses: List<Coche>.from(_buses),
      positionsAt: _positionsAt,
    );
    final saved = await trip.save();
    if (!mounted) return;
    if (saved) setState(() => _preparedTrip = trip);
    if (!quiet)
      _message(
        saved
            ? 'Viaje guardado con ${trip.buses.length} colectivos. Sin conexión sus ubicaciones serán aproximadas; el mapa de calles no se descarga.'
            : 'No se pudo guardar el viaje.',
      );
  }

  Future<void> _openOffline() async {
    final trip = _preparedTrip;
    if (trip == null) return;
    ++_planningToken;
    ++_request;
    _alerts.stopWatching();
    _arrivalAlert.cancel();
    _timer?.cancel();
    setState(() {
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
      _buses = [];
      _tracked = null;
      _arrivalVehicle = null;
    });
    await _refresh();
    if (!mounted || !_offline) return;
    _fitJourney();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _locate({bool changeOrigin = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('Activá la ubicación o elegí el origen en el mapa.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('Podés elegir tu origen en el mapa.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      if (!changeOrigin) {
        _map.move(LatLng(position.latitude, position.longitude), 15);
        return;
      }
      setState(() {
        _origin = LatLng(position.latitude, position.longitude);
        _originName = 'Mi ubicación actual';
      });
      _map.move(_origin, 15);
      await _findJourneys();
    } catch (_) {
      _message('No pudimos obtener tu ubicación. Probá elegirla en el mapa.');
    }
  }

  void _pick(String target) {
    setState(() => _picking = target);
    _message(
      target == 'origin'
          ? 'Tocá el mapa para elegir el origen'
          : 'Tocá el mapa para elegir el destino',
    );
  }

  Future<void> _search({bool origin = false}) async {
    final point = await showModalBottomSheet<Parada>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PlaceSearch(
        places: [..._saved, ..._trace?.paradas ?? []],
        origin: origin,
        journeys: _journeys,
        onJourney: (journey) {
          Navigator.pop(ctx);
          _useJourney(journey, origin: origin);
        },
        onMap: () {
          Navigator.pop(ctx);
          _pick(origin ? 'origin' : 'destination');
        },
      ),
    );
    if (!mounted || point == null) return;
    if (origin) {
      setState(() {
        _origin = point.position;
        _originName = point.nombre;
      });
    } else {
      setState(() {
        _alerts.stopWatching();
        _arrivalAlert.cancel();
        _destination = point;
        _inTrip = false;
      });
      _map.move(point.position, 15);
      await _findJourneys();
    }
    if (origin) await _findJourneys();
  }

  Future<void> _useJourney(SavedJourney route, {required bool origin}) async {
    setState(() {
      _origin = route.origin.position;
      _originName = route.origin.nombre;
      _alerts.stopWatching();
      _arrivalAlert.cancel();
      _destination = route.destination;
      _pickup = null;
      _inTrip = false;
    });
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          route.origin.position,
          route.destination.position,
        ]),
        padding: const EdgeInsets.all(80),
      ),
    );
    final change = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(route.name),
        content: Text(
          '${route.origin.nombre} → ${route.destination.nombre}\n\n¿Querés cambiar ${origin ? 'el destino' : 'el inicio'} solo para este viaje?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(origin ? 'Cambiar destino' : 'Cambiar inicio'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Usar tal cual'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (change == true) {
      await _search(origin: !origin);
    } else if (change == false) {
      await _findJourneys();
    }
  }

  Future<void> _editJourney([SavedJourney? existing]) async {
    final result = await showModalBottomSheet<SavedJourney>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _JourneyEditor(
        existing: existing,
        origin: _originName == 'Elegí tu punto de partida'
            ? null
            : Parada(
                codigo: 'origin',
                nombre: _originName,
                lat: _origin.latitude,
                lon: _origin.longitude,
              ),
        destination: _destination,
        places: [..._saved, ..._trace?.paradas ?? []],
      ),
    );
    if (!mounted || result == null) return;
    final next = [..._journeys.where((r) => r.id != result.id), result];
    if (await SavedJourney.save(next)) {
      if (mounted) setState(() => _journeys = next);
    } else {
      _message('No pudimos guardar el viaje.');
    }
  }

  Future<void> _manageJourneys() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .65,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tus viajes guardados',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Guardá un inicio y un destino con el nombre que quieras.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await _editJourney();
                      if (ctx.mounted) update(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Crear viaje'),
                  ),
                  Expanded(
                    child: _journeys.isEmpty
                        ? const Center(
                            child: Text('Todavía no guardaste viajes.'),
                          )
                        : ListView(
                            children: _journeys
                                .map(
                                  (r) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(r.name),
                                    subtitle: Text(
                                      '${r.origin.nombre} → ${r.destination.nombre}',
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _useJourney(r, origin: false);
                                    },
                                    trailing: IconButton(
                                      tooltip: 'Editar viaje guardado',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () async {
                                        await _editJourney(r);
                                        if (ctx.mounted) update(() {});
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _alertAnnounced = false;
  void _alertChanged() {
    if (!mounted) return;
    if (_alerts.active) _alertAnnounced = false;
    if (_alerts.fired && !_alertAnnounced) {
      _alertAnnounced = true;
      _message(
        'Preparáte para bajar: estás cerca de ${_alerts.target?.nombre}.',
      );
    }
  }

  void _arrivalChanged() {
    if (!mounted) return;
    setState(() {});
    final message = _arrivalAlert.firedMessage;
    if (message != null) {
      _arrivalAlert.firedMessage = null;
      _message(message);
    }
  }

  Future<void> _openAlerts() async {
    var selected = _destination;
    var radius = _alerts.radius;
    bool busy = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AnimatedBuilder(
          animation: Listenable.merge([_alerts, _arrivalAlert]),
          builder: (ctx, _) => SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Viajá con un aviso',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.notifications_active_outlined,
                        color: blue,
                      ),
                      title: Text('Preparáte para bajar'),
                      subtitle: Text(
                        'Te avisamos cuando estés cerca del lugar que elijas.',
                      ),
                    ),
                    if (_alerts.active)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: pale,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Aviso activo · ${_alerts.target!.nombre}\n${_alerts.distance == null ? 'Esperando una ubicación precisa…' : 'Distancia aproximada: ${_alerts.distance!.round()} m'}',
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    if (_alerts.fired)
                      const Text(
                        'Ya emitimos el aviso. Podés activar uno nuevo.',
                        style: TextStyle(color: blue),
                      ),
                    const SizedBox(height: 12),
                    if (!_alerts.active) ...[
                      if (_destination == null &&
                          (_trace?.paradas.isEmpty ?? true))
                        const Text(
                          'Elegí un destino o una línea con paradas para configurar el aviso.',
                        ),
                      if (_destination != null ||
                          (_trace?.paradas.isNotEmpty ?? false))
                        DropdownButtonFormField<int>(
                          initialValue: _destination == null ? null : -1,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Punto de bajada',
                          ),
                          items: [
                            if (_destination != null)
                              DropdownMenuItem(
                                value: -1,
                                child: Text(
                                  'Destino: ${_destination!.nombre}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ...(_trace?.paradas ?? []).asMap().entries.map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value.nombre,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: busy
                              ? null
                              : (index) {
                                  update(
                                    () => selected = index == -1
                                        ? _destination
                                        : index == null
                                        ? null
                                        : _trace!.paradas[index],
                                  );
                                },
                        ),
                      const SizedBox(height: 16),
                      const Text('Avisarme cuando esté a menos de:'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [150.0, 300.0, 500.0]
                            .map(
                              (meters) => ChoiceChip(
                                label: Text('${meters.round()} m'),
                                selected: radius == meters,
                                onSelected: busy
                                    ? null
                                    : (_) => update(() => radius = meters),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (_alerts.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _alerts.error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy
                            ? null
                            : _alerts.active
                            ? () => _alerts.stopWatching()
                            : selected == null
                            ? null
                            : () async {
                                update(() => busy = true);
                                await _alerts.start(selected!, radius);
                                if (ctx.mounted) update(() => busy = false);
                              },
                        icon: Icon(
                          _alerts.active
                              ? Icons.stop_circle_outlined
                              : Icons.notifications_active_outlined,
                        ),
                        label: Text(
                          busy
                              ? 'Activando…'
                              : _alerts.active
                              ? 'Cancelar aviso'
                              : 'Ya estoy arriba · Activar aviso',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              await _alerts.testSound();
                              if (ctx.mounted)
                                _message('Aviso de prueba solicitado.');
                            },
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Probar sonido y aviso'),
                    ),
                    const Text(
                      'En Android se muestra una notificación mientras seguimos tu ubicación. El aviso puede interrumpirse si el sistema cierra la app. En Windows, el aviso y sonido se muestran dentro de la app. No reemplaza prestar atención a las paradas.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                        height: 1.5,
                      ),
                    ),
                    if (_alerts.active && !_alerts.systemNotifications)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Las notificaciones del sistema no están habilitadas: mantené la app abierta para ver el aviso.',
                          style: TextStyle(fontSize: 11, color: blue),
                        ),
                      ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule, color: blue),
                      title: const Text('Antes de que llegue el bondi'),
                      subtitle: Text(_arrivalAlert.status),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [5, 10]
                          .map(
                            (minutes) => ChoiceChip(
                              label: Text('$minutes min'),
                              selected: _arrivalAlert.minutes == minutes,
                              onSelected: _arrivalAlert.active
                                  ? null
                                  : (_) => update(
                                      () => _arrivalAlert.minutes = minutes,
                                    ),
                            ),
                          )
                          .toList(),
                    ),
                    TextButton.icon(
                      icon: Icon(
                        _arrivalAlert.active
                            ? Icons.cancel_outlined
                            : Icons.notifications_active_outlined,
                      ),
                      label: Text(
                        _arrivalAlert.active
                            ? 'Cancelar aviso de llegada'
                            : 'Activar aviso de llegada',
                      ),
                      onPressed: _arrivalAlert.active
                          ? _arrivalAlert.cancel
                          : !_inTrip ||
                                _offline ||
                                _pickup == null ||
                                _route == null ||
                                _line == null
                          ? null
                          : () => _arrivalAlert.start(
                              stop: _pickup!.codigo,
                              stopName: _pickup!.nombre,
                              route: _route!.id,
                              line: _line!.id,
                              threshold: _arrivalAlert.minutes,
                              vehicle: _arrivalVehicle ?? _tracked?.coche,
                            ),
                    ),
                    const Text(
                      'Elegí un viaje y una línea para activar el aviso. Mantené la app abierta y con conexión para recibirlo.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_destination == null) {
      _message('Elegí un destino para guardarlo.');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (!mounted || name == null) return;
    final place = Parada(
      codigo: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      nombre: name,
      lat: _destination!.lat,
      lon: _destination!.lon,
    );
    final next = [..._saved, place];
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setString(
      'saved_places_native',
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );
    if (!mounted) return;
    if (success) {
      setState(() => _saved = next);
      _message('Lugar guardado');
    } else {
      _message('No se pudo guardar el lugar.');
    }
  }

  Parada? _nearestStop() {
    return _currentJourney()?.boarding;
  }

  DirectJourney? _currentJourney({String? boardingCode}) {
    if (_trace == null ||
        _line == null ||
        _route == null ||
        _destination == null ||
        _originName == 'Elegí tu punto de partida')
      return null;
    return JourneyPlanner.find(
      _line!,
      _route!,
      _trace!,
      _origin,
      _destination!.position,
      boardingCode: boardingCode,
    );
  }

  Future<void> _findJourneys() async {
    _arrivalAlert.cancel();
    if (_offline ||
        _destination == null ||
        _originName == 'Elegí tu punto de partida' ||
        _lines.isEmpty)
      return;
    final origin = _origin, destination = _destination!.position;
    final token = ++_planningToken;
    ++_request;
    _timer?.cancel();
    setState(() {
      _planning = true;
      _planned = true;
      _inTrip = false;
      _tripOptions = [];
      _arrivalVehicle = null;
      _buses = [];
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
      (line, route) => ApiService.fetchTraza(
        line.id,
        route.id,
        line.clienteId,
        refreshCached: false,
      ),
      keepGoing: () => mounted && token == _planningToken,
      // The screen shows a loading state; per-route counters are not displayed.
      onProgress: (_, _) {},
    );
    final available = catalog.routes;
    _planningFailed = catalog.unavailable;
    for (final item in available) {
      if (!mounted || token != _planningToken) return;
      final journey = JourneyPlanner.find(
        item.$1,
        item.$2,
        item.$3,
        origin,
        destination,
      );
      if (journey != null) candidates.add(journey);
    }
    if (!mounted || token != _planningToken) return;
    candidates.sort((a, b) => a.walkStart.compareTo(b.walkStart));
    final compatible = candidates;
    _arrivalsByStop.clear();
    _arrivalStopErrors.clear();
    setState(() {
      _planning = false;
      _tripOptions = compatible;
      _pickup = null;
      _loading = false;
    });
    if (compatible.isEmpty) {
      setState(() => _planned = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('No encontramos un viaje directo'),
          content: Text(
            _planningFailed == 0
                ? 'No encontramos un recorrido directo con paradas a menos de 800 m de cada punto. Probá ajustar el inicio o el destino.'
                : 'No encontramos un recorrido directo entre los datos disponibles. $_planningFailed recorridos no pudieron consultarse. Probá nuevamente.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return;
    }
    if (_sheet.isAttached) {
      _sheet.animateTo(
        .48,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    await _refreshComparison(token);
    if (!mounted || token != _planningToken) return;
    await _chooseTrip(_tripOptions.first);
    if (!mounted || token != _planningToken) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_inTrip) {
        await _refreshArrivals(token);
        if (mounted && token == _planningToken) await _refresh();
      } else {
        _refreshComparison(token);
      }
    });
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
          mounted &&
          _foreground &&
          token == _planningToken &&
          !_inTrip) {
        final code = codes[next++];
        try {
          final arrivals = await ApiService.fetchArrivals(code);
          if (!mounted || token != _planningToken || _inTrip) return;
          updated[code] = arrivals;
        } catch (_) {
          if (!mounted || token != _planningToken) return;
          failed.add(code);
        }
      }
    }

    try {
      await Future.wait([worker(), worker(), worker()]);
      if (!mounted || token != _planningToken || _inTrip) return;
      setState(() {
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

  int? _reachableArrival(DirectJourney trip) {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    int? best;
    for (final a
        in _arrivalsByStop[trip.boarding.codigo] ?? <Map<String, dynamic>>[]) {
      if ('${a['ruta']}' != trip.route.id || '${a['linea']}' != trip.line.id)
        continue;
      final seconds = stopArrivalSeconds(a, now);
      // Walking is a rough estimate; leave a minute of margin rather than
      // recommending a vehicle that would arrive before the user can walk there.
      if (seconds != null &&
          seconds >= trip.walkStart / 1.2 + 60 &&
          (best == null || seconds < best))
        best = seconds;
    }
    return best;
  }

  int? _eta(Map<String, dynamic> arrival) => stopArrivalSeconds(
    arrival,
    DateTime.now().toUtc().subtract(const Duration(hours: 3)),
  );

  String _arrivalLabel(Map<String, dynamic> arrival) {
    final seconds = _eta(arrival);
    if (seconds == null) return 'Horario sin confirmar';
    if (seconds < 60) return 'Llegando';
    return 'En ${(seconds / 60).ceil()} min';
  }

  List<Map<String, dynamic>> _sortedArrivals(
    Iterable<Map<String, dynamic>> arrivals,
  ) =>
      arrivals.toList()
        ..sort((a, b) => (_eta(a) ?? 99999).compareTo(_eta(b) ?? 99999));

  void _sortTripOptions() {
    _tripOptions.sort((a, b) {
      final first = _reachableArrival(a), second = _reachableArrival(b);
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
      final arrivals = await ApiService.fetchArrivals(stop.codigo);
      if (!mounted ||
          token != _planningToken ||
          version != _arrivalRequest ||
          _pickup?.codigo != stop.codigo)
        return;
      setState(() {
        _arrivals = arrivals;
        _arrivalsByStop[stop.codigo] = arrivals;
        _arrivalStopErrors.remove(stop.codigo);
        _arrivalError = null;
        if (_line != null && _route != null) {
          _buses = arrivalPositions(arrivals, stop, _line!, _route!);
          _positionsAt = DateTime.now();
        }
      });
      // Preserve the latest usable snapshot while there is connection. Empty
      // responses must not erase the only positions available without data.
      if (_buses.isNotEmpty) await _prepareOffline(quiet: true);
    } catch (_) {
      if (!mounted ||
          token != _planningToken ||
          version != _arrivalRequest ||
          _pickup?.codigo != stop.codigo)
        return;
      final saved = _preparedTrip;
      if (saved != null &&
          saved.buses.isNotEmpty &&
          saved.line.id == _line?.id &&
          saved.route.id == _route?.id &&
          saved.boarding.codigo == _pickup?.codigo &&
          saved.alighting.codigo == _dropoff?.codigo &&
          saved.origin.position == _origin &&
          saved.destination.position == _destination?.position) {
        await _openOffline();
        _message(
          'No pudimos conectar. Mostramos ubicaciones aproximadas guardadas.',
        );
        return;
      }
      setState(() {
        _arrivals = [];
        _buses = [];
        _arrivalStopErrors.add(stop.codigo);
        _arrivalError = 'No pudimos actualizar las llegadas. Volvé a intentar.';
      });
    }
  }

  Future<void> _chooseTrip(DirectJourney trip) async {
    final token = _planningToken;
    await _selectLine(trip.line, trip.route);
    if (!mounted || token != _planningToken) return;
    setState(() {
      _pickup = trip.boarding;
      _dropoff = trip.alighting;
      _inTrip = true;
    });
    await _refreshArrivals(token);
    await _refresh();
    if (!mounted || token != _planningToken) return;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          _origin,
          trip.boarding.position,
          trip.alighting.position,
          _destination!.position,
        ]),
        padding: const EdgeInsets.fromLTRB(45, 210, 45, 240),
      ),
    );
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _lightMode ? 30 : 20), (_) async {
      await _refreshArrivals(token);
      if (mounted && token == _planningToken) await _refresh();
    });
  }

  Traza? _stopsTrace;
  Parada? _stopsPickup, _stopsDropoff;
  List<Parada> _cachedStops = [];
  List<Parada> _tripStops() {
    final trace = _trace;
    if (trace == null) return [];
    if (!_inTrip || _pickup == null || _dropoff == null) return trace.paradas;
    if (identical(trace, _stopsTrace) &&
        identical(_pickup, _stopsPickup) &&
        identical(_dropoff, _stopsDropoff))
      return _cachedStops;
    final start = JourneyPlanner.progress(_pickup!.position, trace.puntos);
    final end = JourneyPlanner.progress(_dropoff!.position, trace.puntos);
    if (start == null || end == null) return [];
    final ordered = <(Parada, double)>[];
    for (final p in trace.paradas) {
      final position = JourneyPlanner.progress(p.position, trace.puntos);
      if (position != null && position >= start && position <= end)
        ordered.add((p, position));
    }
    ordered.sort((a, b) => a.$2.compareTo(b.$2));
    _stopsTrace = trace;
    _stopsPickup = _pickup;
    _stopsDropoff = _dropoff;
    return _cachedStops = ordered.map((p) => p.$1).toList();
  }

  Widget _selectedTripPanel() {
    final arrivals = _sortedArrivals(
      _arrivals.where(
        (a) => '${a['ruta']}' == _route?.id && '${a['linea']}' == _line?.id,
      ),
    );
    final buses = _visibleBuses();
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _line?.color ?? blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Línea ${_line?.nombre ?? ""}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Actualizar llegadas',
                onPressed: () async {
                  await _refreshArrivals(_planningToken);
                  if (mounted) await _refresh();
                },
                icon: const Icon(Icons.refresh, color: blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Subís en ${_pickup?.nombre ?? "la parada"}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Bajás en ${_dropoff?.nombre ?? "tu destino"}',
            style: const TextStyle(fontSize: 14, color: ink),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                if (buses.isNotEmpty) {
                  _showBuses();
                } else if (_pickup != null) {
                  _map.move(_pickup!.position, 16);
                }
              },
              icon: Icon(
                buses.isNotEmpty
                    ? Icons.directions_bus
                    : Icons.signpost_outlined,
              ),
              label: Text(
                buses.isNotEmpty
                    ? 'Ver colectivos y parada'
                    : 'Ver parada de subida',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _offline ? 'Últimas ubicaciones guardadas' : 'Próximos colectivos',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (_offline)
            Text(
              'Ubicaciones guardadas hace ${DateTime.now().difference(_preparedTrip?.positionsAt ?? DateTime.now()).inMinutes.clamp(0, 99999)} min · no son en vivo.',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          if (!_offline && arrivals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _arrivalError ?? 'Todavía no hay llegadas para esta línea.',
                style: const TextStyle(color: Colors.blueGrey),
              ),
            ),
          if (_offline && buses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Este viaje no tiene ubicaciones de colectivos guardadas.',
              ),
            ),
          if (!_offline)
            ...arrivals.map((arrival) {
              final id = int.tryParse('${arrival['coche']}');
              final matches = buses.where((b) => b.coche == id);
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.directions_bus,
                    color: _line?.color ?? blue,
                  ),
                  title: Text(
                    _arrivalLabel(arrival),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: blue,
                    ),
                  ),
                  subtitle: Text(
                    'Interno ${arrival['coche']}${arrival['dist_parada'] != null ? " · ${arrival['dist_parada']} m a la parada" : ""}${matches.isEmpty ? " · ubicación pendiente" : ""}',
                  ),
                  trailing: Icon(
                    _arrivalVehicle == id
                        ? Icons.check_circle
                        : Icons.chevron_right,
                    color: blue,
                  ),
                  onTap: id == null
                      ? null
                      : () {
                          setState(() {
                            _arrivalVehicle = id;
                            _tracked = matches.isEmpty ? null : matches.first;
                          });
                          if (_tracked != null)
                            _map.move(_tracked!.position, 15);
                        },
                ),
              );
            }),
          if (_offline)
            ...buses.map(
              (bus) => Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.directions_bus,
                    color: _line?.color ?? blue,
                  ),
                  title: Text('Interno ${bus.coche}'),
                  subtitle: Text(bus.demora),
                  onTap: () {
                    setState(() {
                      _tracked = bus;
                      _arrivalVehicle = bus.coche;
                    });
                    _map.move(bus.position, 15);
                  },
                ),
              ),
            ),
          if (_arrivalVehicle != null)
            TextButton(
              onPressed: () => setState(() {
                _arrivalVehicle = null;
                _tracked = null;
              }),
              child: const Text('Mostrar todos los colectivos'),
            ),
          if (!_offline && _tripOptions.length > 1)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Otras líneas que te llevan'),
              children: [_journeyResults(comparisonOnly: true)],
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Paradas hasta tu bajada'),
            subtitle: Text('${_tripStops().length} paradas en este tramo'),
            children: [
              for (final stop in _tripStops())
                ListTile(dense: true, title: Text(stop.nombre)),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Opciones del viaje'),
            children: [
              if (!_offline)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _prepareOffline,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Preparar viaje sin datos'),
                  ),
                ),
              if (_preparedTrip != null && !_offline)
                TextButton(
                  onPressed: _openOffline,
                  child: const Text('Abrir viaje sin datos'),
                ),
              if (_offline)
                TextButton(
                  onPressed: () => _selectLine(_line!, _route),
                  child: const Text('Volver a conectar'),
                ),
              TextButton.icon(
                onPressed: _parameters,
                icon: const Icon(Icons.tune),
                label: const Text('Cambiar preferencias'),
              ),
              TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('Guardar destino'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _journeyResults({bool comparisonOnly = false}) {
    if (_inTrip && !comparisonOnly) return _selectedTripPanel();
    if (!_planned || _offline) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_planning) ...[
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Buscando cómo llegar…'),
          ),
          TextButton(
            onPressed: () {
              ++_planningToken;
              setState(() {
                _planning = false;
                _planned = false;
                _loading = false;
              });
            },
            child: const Text('Cancelar búsqueda'),
          ),
        ],
        if (!_planning && _tripOptions.isNotEmpty) ...[
          if (!comparisonOnly) ...[
            Text(
              _inTrip && _pickup != null
                  ? 'Subís en ${_pickup!.nombre}'
                  : 'Compará líneas y paradas',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              _inTrip
                  ? 'Tomá la línea ${_line?.nombre ?? ""} hacia ${_dropoff?.nombre ?? "tu destino"}.'
                  : 'Buscando la mejor llegada para tu caminata…',
            ),
            if (_inTrip) ...[
              if (_arrivalVehicle != null &&
                  !_visibleBuses().any((b) => b.coche == _arrivalVehicle))
                Text(
                  'Interno $_arrivalVehicle seleccionado. Esperando una nueva ubicación…',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              if (_visibleBuses().isNotEmpty)
                TextButton.icon(
                  onPressed: _showBuses,
                  icon: const Icon(Icons.directions_bus),
                  label: Text(
                    'Ver ${_visibleBuses().length} colectivos en el mapa',
                  ),
                ),
              Text(
                'Parada de subida: señal azul. Caminata aproximada: línea punteada.',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              if (_visibleBuses().isEmpty)
                Text(
                  _buses.isNotEmpty
                      ? 'Todavía no podemos mostrar dónde está el colectivo.'
                      : (_arrivalError ??
                            'Ubicación del colectivo no disponible. Podés ver las llegadas abajo.'),
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
            ],
            if (_planningFailed > 0)
              Text(
                'Algunas líneas no están disponibles. Podés volver a buscar.',
              ),
            const SizedBox(height: 12),
            const Text(
              'COMPARÁ LÍNEAS Y PARADAS',
              style: TextStyle(color: blue, fontWeight: FontWeight.w700),
            ),
          ],
          SizedBox(
            height: 280,
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                scrollDirection: Axis.horizontal,
                children: _tripOptions.map((trip) {
                  final arrivals =
                      (_arrivalsByStop[trip.boarding.codigo] ??
                              <Map<String, dynamic>>[])
                          .where(
                            (a) =>
                                a['ruta']?.toString() == trip.route.id &&
                                a['linea']?.toString() == trip.line.id,
                          )
                          .toList();
                  arrivals.sort(
                    (a, b) => (_eta(a) ?? 99999).compareTo(_eta(b) ?? 99999),
                  );
                  return Container(
                    width: constraints.maxWidth >= 1000
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth >= 650
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth * .9),
                    margin: const EdgeInsets.only(right: 12, top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pale,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SingleChildScrollView(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.directions_bus,
                          color: trip.line.color,
                        ),
                        title: Text(
                          'Línea ${trip.line.nombre}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.route.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Subís: ${trip.boarding.nombre}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Caminata: ${trip.walkStart.round()} m · aprox. ${(trip.walkStart / 72).ceil()} min',
                              ),
                              Text('Bajás: ${trip.alighting.nombre}'),
                              const SizedBox(height: 8),
                              Text(
                                _arrivalStopErrors.contains(
                                      trip.boarding.codigo,
                                    )
                                    ? 'Llegadas sin confirmar'
                                    : !_arrivalsByStop.containsKey(
                                        trip.boarding.codigo,
                                      )
                                    ? 'Consultando llegadas…'
                                    : (arrivals.isEmpty
                                          ? 'Todavía no hay próximas llegadas disponibles'
                                          : arrivals
                                                .map(
                                                  (a) =>
                                                      '${_arrivalLabel(a)} · interno ${a['coche']}${a['dist_parada'] != null ? " · ${a['dist_parada']} m" : ""}',
                                                )
                                                .join('\n')),
                                style: const TextStyle(
                                  color: blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text(
                                'Llegadas estimadas',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Icon(
                          _inTrip && _route?.id == trip.route.id
                              ? Icons.check_circle
                              : Icons.chevron_right,
                          color: blue,
                        ),
                        onTap: () => _chooseTrip(trip),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (_inTrip &&
              !comparisonOnly &&
              _trace != null &&
              _dropoff != null) ...[
            const Text(
              'ELEGÍ EL COLECTIVO',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ..._sortedArrivals(
              _arrivals.where(
                (a) =>
                    '${a['ruta']}' == _route?.id &&
                    '${a['linea']}' == _line?.id,
              ),
            ).map((arrival) {
              final id = int.tryParse('${arrival['coche']}');
              return ListTile(
                leading: Icon(
                  Icons.directions_bus,
                  color: _line?.color ?? blue,
                ),
                title: Text(
                  '${_arrivalLabel(arrival)} · interno ${arrival['coche']}',
                ),
                subtitle: Text(
                  '${arrival['dist_parada'] ?? "?"} m a la parada · horario estimado',
                ),
                trailing: _arrivalVehicle == id
                    ? const Icon(Icons.check_circle, color: blue)
                    : null,
                onTap: id == null
                    ? null
                    : () {
                        final matches = _buses
                            .where((b) => b.coche == id)
                            .toList();
                        setState(() {
                          _arrivalVehicle = id;
                          _tracked = matches.isEmpty ? null : matches.first;
                        });
                        if (_tracked != null)
                          _map.move(_tracked!.position, 15);
                        else
                          _message(
                            'Colectivo $id seleccionado. Su ubicación todavía no está disponible.',
                          );
                      },
              );
            }),
            const Text(
              'PARADAS HASTA TU BAJADA',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ..._tripStops().map(
              (p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('• ' + p.nombre),
              ),
            ),
          ],
        ],
      ],
    );
  }

  List<Coche>? _displaySource;
  Traza? _displayTrace;
  List<Coche> _displayBuses = [];
  List<Coche> _visibleBuses() {
    // Route GPS and stop arrivals are separate provider feeds. Show the route
    // positions without claiming that every vehicle will pick the user up.
    final trace = _trace;
    if (trace == null) return [];
    if (identical(_buses, _displaySource) && identical(trace, _displayTrace))
      return _displayBuses;
    final displayed = <Coche>[];
    for (final bus in _buses) {
      if (bus.lat == 0 || bus.lon == 0) continue;
      final point = routePosition(bus.position, trace.puntos);
      // Validated stop-arrival positions can be slightly outside the geometry.
      // Keep small offsets visible without moving them far across the map.
      if (point == null) {
        if (JourneyPlanner.progress(bus.position, trace.puntos) != null)
          displayed.add(bus);
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

  void _showBuses() {
    final buses = _visibleBuses();
    if (buses.isEmpty) return;
    setState(() {
      _tracked = null;
      _arrivalVehicle = null;
    });
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          _origin,
          if (_pickup != null) _pickup!.position,
          ...buses.map((b) => b.position),
        ]),
        padding: const EdgeInsets.fromLTRB(45, 210, 45, 270),
      ),
    );
  }

  Future<void> _parameters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final hasOrigin = _originName != 'Elegí tu punto de partida';
          final nearest = _nearestStop();
          final pickup = _preference == 'nearest' ? nearest : _pickup;
          final journey = _currentJourney(boardingCode: pickup?.codigo);
          final ready =
              hasOrigin &&
              _destination != null &&
              _line != null &&
              pickup != null &&
              journey != null &&
              !_loading;
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Opciones del recorrido',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pale,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inicio · ${hasOrigin ? _originName : 'Sin elegir'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Destino · ${_destination?.nombre ?? 'Sin elegir'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (!hasOrigin || _destination == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _search(origin: !hasOrigin);
                          },
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: Text(
                            !hasOrigin ? 'Elegir inicio' : 'Elegir destino',
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: !hasOrigin || _destination == null
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _findJourneys();
                            },
                      icon: const Icon(Icons.alt_route),
                      label: const Text('Buscar líneas que me llevan'),
                    ),
                    const Text(
                      '1. LÍNEA Y SENTIDO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: blue,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.directions_bus, color: blue),
                      title: Text(
                        _line == null
                            ? 'Elegí una línea'
                            : 'Línea ${_line!.nombre}',
                      ),
                      subtitle: Text(
                        _route?.nombre ?? 'Sin recorrido seleccionado',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _linePicker();
                        if (mounted) _parameters();
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '2. PARADA DE SUBIDA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: blue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Más cercana al inicio'),
                          selected: _preference == 'nearest',
                          onSelected: (_) {
                            setState(() {
                              _preference = 'nearest';
                              _pickup = null;
                              _inTrip = false;
                            });
                            update(() {});
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Elegir parada'),
                          selected: _preference == 'stop',
                          onSelected: (_) {
                            setState(() => _preference = 'stop');
                            update(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_preference == 'nearest')
                      Text(
                        !hasOrigin
                            ? 'Elegí el inicio para encontrar una parada cercana.'
                            : nearest == null
                            ? 'No hay paradas disponibles para este recorrido.'
                            : nearest.nombre,
                        style: const TextStyle(fontSize: 13, color: ink),
                      ),
                    if (_preference == 'stop')
                      DropdownButtonFormField<String>(
                        initialValue: _pickup?.codigo,
                        isExpanded: true,
                        hint: const Text('Paradas de la línea seleccionada'),
                        items: (_trace?.paradas ?? [])
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.codigo,
                                child: Text(
                                  p.nombre,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (code) {
                          if (code == null) return;
                          setState(
                            () => _pickup = _trace!.paradas.firstWhere(
                              (p) => p.codigo == code,
                            ),
                          );
                          update(() {});
                        },
                      ),
                    const SizedBox(height: 18),
                    Text(
                      journey == null
                          ? 'Este recorrido no tiene un viaje directo válido con estas preferencias. Buscá otras líneas.'
                          : 'Bajás en ${journey.alighting.nombre}. A pie aprox.: ${journey.walkStart.round()} m al subir y ${journey.walkEnd.round()} m al llegar. Llegadas de bondis aún sin confirmar.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: !ready
                            ? null
                            : () {
                                setState(() {
                                  _pickup = pickup;
                                  _dropoff = journey!.alighting;
                                  _inTrip = true;
                                });
                                Navigator.pop(ctx);
                                _map.move(pickup.position, 15);
                              },
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Elegir este viaje'),
                      ),
                    ),
                    if (_destination != null)
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _save();
                          },
                          icon: const Icon(Icons.bookmark_outline),
                          label: const Text('Guardar destino'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _linePicker() async {
    if (_destination != null && _originName != 'Elegí tu punto de partida') {
      if (_planning) {
        _message('Esperá que termine la búsqueda de líneas compatibles.');
        return;
      }
      if (_tripOptions.isEmpty) {
        await _findJourneys();
        return;
      }
      final selected = await showModalBottomSheet<DirectJourney>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Líneas para tu viaje A → B')),
            ..._tripOptions.map(
              (trip) => ListTile(
                leading: Icon(Icons.directions_bus, color: trip.line.color),
                title: Text('Línea ${trip.line.nombre} · ${trip.route.nombre}'),
                subtitle: Text(
                  '${trip.boarding.nombre} → ${trip.alighting.nombre}',
                ),
                onTap: () => Navigator.pop(ctx, trip),
              ),
            ),
          ],
        ),
      );
      if (selected != null && mounted) await _chooseTrip(selected);
      return;
    }
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .65,
        child: Column(
          children: [
            const Text(
              'Elegí línea y sentido',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView(
                children: _lines
                    .expand(
                      (line) => line.rutas.map(
                        (route) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: pale,
                            child: Text(
                              line.nombre,
                              style: const TextStyle(color: blue, fontSize: 12),
                            ),
                          ),
                          title: Text(route.nombre),
                          subtitle: Text(
                            'Línea ${line.nombre} · ${route.sentido}',
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _selectLine(line, route);
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Object? _polylineKey;
  List<Polyline> _cachedPolylines = [];
  List<Polyline> _mapPolylines() {
    final key = (
      _trace,
      _pickup,
      _dropoff,
      _origin,
      _destination,
      _line,
      _inTrip,
      _planned,
    );
    if (key == _polylineKey) return _cachedPolylines;
    final routes = <(List<LatLng>, Color)>[];
    if (_inTrip && _trace != null && _pickup != null && _dropoff != null) {
      routes.add((
        JourneyPlanner.segment(_trace!, _pickup!, _dropoff!),
        _line?.color ?? blue,
      ));
    } else if (!_planned && _trace != null) {
      routes.add((_trace!.puntos, _line?.color ?? blue));
    }
    _polylineKey = key;
    return _cachedPolylines = [
      for (final route in routes) ...[
        Polyline(points: route.$1, strokeWidth: 7, color: Colors.white),
        Polyline(points: route.$1, strokeWidth: 4, color: route.$2),
      ],
      if (_pickup != null)
        Polyline(
          points: [_origin, _pickup!.position],
          strokeWidth: 3,
          color: blue,
          pattern: StrokePattern.dashed(segments: [6, 5]),
        ),
      if (_inTrip && _dropoff != null && _destination != null)
        Polyline(
          points: [_dropoff!.position, _destination!.position],
          strokeWidth: 3,
          color: const Color(0xFF00A281),
          pattern: StrokePattern.dashed(segments: [6, 5]),
        ),
    ];
  }

  void _fitJourney() {
    final points = [
      ..._mapPolylines().expand((line) => line.points),
      ..._visibleBuses().map((bus) => bus.position),
    ];
    if (points.length < 2) return;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(45, 210, 45, 240),
      ),
    );
  }

  Widget _stopPin(String label, Color color) => Tooltip(
    message: label,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x22003366), blurRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.signpost_rounded, color: color, size: 23),
    ),
  );

  Widget _pin(LatLng point, String label, Color color) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: Colors.white, width: 3),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [BoxShadow(color: Color(0x22003366), blurRadius: 10)],
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        height: 1,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _origin,
                initialZoom: 14,
                onTap: (_, point) {
                  if (_picking == null) return;
                  final target = _picking;
                  setState(() {
                    if (target == 'origin') {
                      _origin = point;
                      _originName = 'Origen en el mapa';
                    } else {
                      _alerts.stopWatching();
                      _arrivalAlert.cancel();
                      _destination = Parada(
                        codigo: 'map',
                        nombre: 'Destino en el mapa',
                        lat: point.latitude,
                        lon: point.longitude,
                      );
                      _inTrip = false;
                    }
                    _picking = null;
                  });
                  _findJourneys();
                },
              ),
              children: [
                if (!_offline)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.bondicba.app',
                  ),
                PolylineLayer(polylines: _mapPolylines()),
                MarkerLayer(
                  markers: [
                    if (_originName != 'Elegí tu punto de partida')
                      Marker(
                        point: _origin,
                        width: 38,
                        height: 38,
                        child: _pin(_origin, 'A', blue),
                      ),
                    if (_destination != null)
                      Marker(
                        point: _destination!.position,
                        width: 38,
                        height: 38,
                        child: _pin(
                          _destination!.position,
                          'B',
                          const Color(0xFF00A281),
                        ),
                      ),
                    ..._saved.map(
                      (p) => Marker(
                        point: p.position,
                        width: 32,
                        height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: p.nombre,
                          icon: const Icon(Icons.bookmark, color: blue),
                          onPressed: () {
                            setState(() {
                              _alerts.stopWatching();
                              _arrivalAlert.cancel();
                              _destination = p;
                              _inTrip = false;
                            });
                            _findJourneys();
                          },
                        ),
                      ),
                    ),
                    if (_pickup != null)
                      Marker(
                        point: _pickup!.position,
                        width: 40,
                        height: 40,
                        child: _stopPin('Subida · ${_pickup!.nombre}', blue),
                      ),
                    if (_inTrip && _dropoff != null)
                      Marker(
                        point: _dropoff!.position,
                        width: 40,
                        height: 40,
                        child: _stopPin(
                          'Bajada · ${_dropoff!.nombre}',
                          const Color(0xFF00A281),
                        ),
                      ),
                    ..._tripStops()
                        .where(
                          (p) =>
                              p.codigo != _pickup?.codigo &&
                              p.codigo != _dropoff?.codigo,
                        )
                        .take(_lightMode ? 0 : 80)
                        .map(
                          (p) => Marker(
                            point: p.position,
                            width: 18,
                            height: 18,
                            child: GestureDetector(
                              onTap: () {
                                _message('Parada: ${p.nombre}');
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: _line?.color ?? blue,
                                    width: 2,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ..._visibleBuses()
                        .where(
                          (b) =>
                              _arrivalVehicle == null ||
                              b.coche == _arrivalVehicle,
                        )
                        .map(
                          (b) => Marker(
                            point: b.position,
                            width: 65,
                            height: 68,
                            alignment: const Alignment(0, .38),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _tracked = b;
                                  _arrivalVehicle = b.coche;
                                });
                                _message(
                                  'Línea ${b.linea} · interno ${b.coche} · ubicación aproximada sobre el recorrido${b.isPredictive ? " · sin conexión" : ""}.',
                                );
                              },
                              child: BusMarker(
                                line: b.linea,
                                color: _line?.color ?? blue,
                                selected: _tracked?.coche == b.coche,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 15,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  _searchBar(origin: true),
                  const SizedBox(height: 8),
                  _searchBar(origin: false),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: LayoutBuilder(
                      builder: (ctx, bounds) => ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _journeys.isEmpty ? 1 : _journeys.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => SizedBox(
                          width: (bounds.maxWidth - 8) / 2,
                          child: OutlinedButton.icon(
                            onPressed: _journeys.isEmpty
                                ? _manageJourneys
                                : () =>
                                      _useJourney(_journeys[i], origin: false),
                            icon: Icon(
                              _journeys.isEmpty
                                  ? Icons.add
                                  : Icons.bookmark_outline,
                              size: 16,
                            ),
                            label: Text(
                              _journeys.isEmpty
                                  ? 'Crear viaje'
                                  : _journeys[i].name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              top: 190,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'gps',
                    backgroundColor: Colors.white,
                    foregroundColor: blue,
                    onPressed: () => _locate(changeOrigin: false),
                    tooltip: 'Mi ubicación',
                    child: const Icon(Icons.gps_fixed),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'route',
                    backgroundColor: Colors.white,
                    foregroundColor: blue,
                    onPressed: _fitJourney,
                    tooltip: 'Ver recorrido',
                    child: const Icon(Icons.layers_outlined),
                  ),
                ],
              ),
            ),
            if (_picking != null)
              Positioned(
                top: 205,
                left: 20,
                right: 20,
                child: Material(
                  color: blue,
                  borderRadius: BorderRadius.circular(15),
                  child: ListTile(
                    title: Text(
                      'Tocá el mapa: ${_picking == 'origin' ? 'origen' : 'destino'}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: IconButton(
                      onPressed: () => setState(() => _picking = null),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
            if (_planned || _line != null || _offline || _preparedTrip != null)
              DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: .30,
                minChildSize: .20,
                maxChildSize: .70,
                builder: (context, controller) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x18003366),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                    children: [
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '© OpenStreetMap',
                          style: TextStyle(fontSize: 9, color: Colors.blueGrey),
                        ),
                      ),
                      GestureDetector(
                        key: const ValueKey('journey-sheet-handle'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_sheet.isAttached)
                            _sheet.animateTo(
                              _sheet.size < .5 ? .7 : .3,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                        },
                        onVerticalDragUpdate: (details) {
                          if (_sheet.isAttached)
                            _sheet.jumpTo(
                              (_sheet.size -
                                      details.delta.dy /
                                          MediaQuery.sizeOf(context).height)
                                  .clamp(.2, .7),
                            );
                        },
                        child: SizedBox(
                          height: 28,
                          child: Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD5DEEB),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (!_inTrip && _preparedTrip != null && !_offline)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openOffline,
                              icon: const Icon(Icons.offline_pin_outlined),
                              label: const Text('Abrir viaje sin datos'),
                            ),
                          ),
                        ),
                      _journeyResults(),
                      if (!_inTrip) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: pale,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.signpost_outlined,
                              color: blue,
                            ),
                            title: Text(
                              _inTrip
                                  ? 'Subís: ${_pickup?.nombre ?? ""}'
                                  : _pickup?.nombre ?? 'Explorá las paradas',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _inTrip && _dropoff != null
                                  ? 'Bajás: ${_dropoff!.nombre}'
                                  : _line == null
                                  ? 'Elegí una línea para ver su recorrido'
                                  : 'Línea ${_line!.nombre} · ${_trace?.paradas.length ?? 0} paradas',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              tooltip: 'Guardar destino',
                              onPressed: _save,
                              icon: const Icon(
                                Icons.bookmark_outline,
                                color: blue,
                              ),
                            ),
                          ),
                        ),
                        if (_offline) ...[
                          Text(
                            _preparedTrip?.positionsAt == null ||
                                    _preparedTrip!.buses.isEmpty
                                ? 'Este viaje no tiene ubicaciones de colectivos guardadas.'
                                : 'Ubicaciones guardadas hace ${DateTime.now().difference(_preparedTrip!.positionsAt!).inMinutes.clamp(0, 99999)} min · no son en vivo.',
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin conexión. Podés ver tu recorrido y las paradas guardadas. El mapa de calles no está disponible y las ubicaciones pueden estar desactualizadas.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _selectLine(_line!, _route),
                            child: const Text('Volver a conectar'),
                          ),
                        ],
                        const SizedBox(height: 17),
                        Row(
                          children: [
                            const Text(
                              'COLECTIVOS DEL RECORRIDO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .7,
                              ),
                            ),
                            const Spacer(),
                            if (_tracked != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  _tracked = null;
                                  _arrivalVehicle = null;
                                }),
                                child: const Text('Ver todos'),
                              ),
                            IconButton(
                              tooltip: 'Actualizar colectivos',
                              onPressed: _refresh,
                              icon: const Icon(
                                Icons.refresh,
                                size: 19,
                                color: blue,
                              ),
                            ),
                          ],
                        ),
                        if (_loading)
                          const LinearProgressIndicator()
                        else if (_visibleBuses().isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Todavía no hay ubicaciones disponibles para estos colectivos.',
                              style: TextStyle(
                                color: Colors.blueGrey,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ..._visibleBuses().map(
                          (b) => Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: _line?.color ?? blue,
                                child: Text(
                                  b.linea,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                'Interno ${b.coche}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                b.isPredictive
                                    ? b.demora
                                    : 'Ubicación aproximada sobre el recorrido',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Icon(
                                _tracked?.coche == b.coche
                                    ? Icons.check_circle
                                    : Icons.chevron_right,
                                color: blue,
                              ),
                              onTap: () {
                                setState(() {
                                  _tracked = b;
                                  _arrivalVehicle = b.coche;
                                });
                                _map.move(b.position, 15);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_planned)
                          const Text(
                            'Estás explorando una línea. Elegí inicio y destino para buscar tu viaje.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey,
                              height: 1.5,
                            ),
                          ),
                        if (_destination != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 15),
                            child: FilledButton.icon(
                              onPressed: _parameters,
                              icon: const Icon(Icons.tune),
                              label: const Text('Configurar mi viaje'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 65,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: pale)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _nav(Icons.map_outlined, 'Mapa', () => _map.move(_origin, 14)),
              _nav(Icons.directions_bus_outlined, 'Líneas', _linePicker),
              _nav(Icons.bookmark_outline, 'Guardados', _manageJourneys),
              _nav(Icons.notifications_none, 'Alertas', _openAlerts),
              _nav(
                Icons.wallet_outlined,
                'Gastos',
                () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * .7,
                    child: const ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: ExpensesScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar({required bool origin}) {
    final selected = origin
        ? _originName != 'Elegí tu punto de partida'
        : _destination != null;
    final text = origin
        ? (selected ? _originName : '¿Desde dónde salís?')
        : (_destination?.nombre ?? '¿A dónde querés ir?');
    return Material(
      elevation: 4,
      shadowColor: const Color(0x22003366),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            origin ? Icons.trip_origin : Icons.location_on_outlined,
            color: blue,
            size: 21,
          ),
          Expanded(
            child: InkWell(
              onTap: () => _search(origin: origin),
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      origin ? 'INICIO' : 'DESTINO',
                      style: const TextStyle(
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: blue,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? ink : Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: origin ? 'Usar mi ubicación' : 'Preferencias del viaje',
            onPressed: origin ? _locate : _findJourneys,
            icon: Icon(
              origin ? Icons.gps_fixed : Icons.tune,
              color: blue,
              size: 21,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _nav(IconData icon, String title, VoidCallback action) => Semantics(
    button: true,
    child: InkWell(
      onTap: action,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: blue, size: 22),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 10, color: ink)),
          ],
        ),
      ),
    ),
  );
}

class _PlaceSearch extends StatefulWidget {
  final List<Parada> places;
  final bool origin;
  final List<SavedJourney> journeys;
  final ValueChanged<SavedJourney>? onJourney;
  final VoidCallback onMap;
  const _PlaceSearch({
    required this.places,
    required this.origin,
    this.journeys = const [],
    this.onJourney,
    required this.onMap,
  });
  @override
  State<_PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<_PlaceSearch> {
  List<RecentPlace> recent = [];
  @override
  void initState() {
    super.initState();
    RecentPlaces.load(widget.origin).then((value) {
      if (mounted) setState(() => recent = value);
    });
  }

  Future<void> choosePoint(Parada point) async {
    try {
      await RecentPlaces.remember(point, widget.origin);
    } catch (_) {
      // Selecting a place still works if local storage is unavailable.
    }
    if (mounted) Navigator.pop(context, point);
  }

  String query = '';
  List<PlaceSuggestion> remote = [];
  bool searching = false;
  String? error;
  Timer? debounce;
  int generation = 0;
  @override
  void dispose() {
    debounce?.cancel();
    generation++;
    super.dispose();
  }

  void changed(String text) {
    debounce?.cancel();
    final version = ++generation;
    setState(() {
      query = text;
      remote = [];
      error = null;
      searching = text.trim().length >= 3;
    });
    if (!searching) return;
    debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await PlaceSearchService.search(text);
        if (!mounted || version != generation) return;
        setState(() {
          remote = results;
          searching = false;
        });
      } catch (_) {
        if (!mounted || version != generation) return;
        setState(() {
          searching = false;
          error = 'No pudimos consultar lugares. Tus guardados y paradas siguen disponibles.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.places
        .where((p) => PlaceSearchService.matches(p.nombre, query))
        .map(
          (p) => PlaceSuggestion(
            p,
            p.codigo.startsWith('saved_')
                ? 'Lugar guardado'
                : 'Parada del recorrido',
          ),
        )
        .toList();
    final seen = <String>{};
    final results =
        [
              ...recent
                  .where(
                    (p) => PlaceSearchService.matches(p.point.nombre, query),
                  )
                  .map(
                    (p) => PlaceSuggestion(
                      p.point,
                      'Búsqueda reciente · ${p.uses == 1 ? 'usado una vez' : 'usado ${p.uses} veces'}',
                    ),
                  ),
              ...PlaceSearchService.localSuggestions(query),
              ...local,
              ...remote,
            ]
            .where(
              (p) =>
                  seen.add('${p.point.nombre}|${p.point.lat}|${p.point.lon}'),
            )
            .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .58,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.origin ? '¿Desde dónde salís?' : '¿A dónde querés ir?',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Lugar, universidad o dirección',
                ),
                onChanged: changed,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Elegir un punto en el mapa'),
              ),
              if (widget.journeys.isNotEmpty)
                SizedBox(
                  height: 45,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: widget.journeys
                        .where(
                          (r) => PlaceSearchService.matches(
                            r.name +
                                ' ' +
                                (widget.origin
                                    ? r.origin.nombre
                                    : r.destination.nombre),
                            query,
                          ),
                        )
                        .map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(r.name),
                              onPressed: () => widget.onJourney?.call(r),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (searching) const LinearProgressIndicator(minHeight: 2),
              if (recent.isNotEmpty && query.trim().isEmpty)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Últimas búsquedas',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await RecentPlaces.clear(widget.origin);
                        if (mounted) setState(() => recent = []);
                      },
                      child: const Text('Borrar recientes'),
                    ),
                  ],
                ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          searching
                              ? 'Buscando en Córdoba…'
                              : query.trim().length < 3
                              ? 'Probá con UTN, arquitectura o una calle.'
                              : 'No encontramos coincidencias. Probá otro nombre o elegí en el mapa.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (ctx, i) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.place_outlined,
                            color: blue,
                          ),
                          title: Text(
                            results[i].point.nombre,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            results[i].requiresMap
                                ? '${results[i].address}\nAltura sin verificar · marcá el punto en el mapa'
                                : results[i].address,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () async {
                            final suggestion = results[i];
                            if (!suggestion.requiresMap) {
                              await choosePoint(suggestion.point);
                              return;
                            }
                            final point = await showModalBottomSheet<Parada>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) =>
                                  ConfirmAddressPoint(suggestion: suggestion),
                            );
                            if (context.mounted && point != null)
                              await choosePoint(point);
                          },
                        ),
                      ),
              ),
              const Text(
                'Buscá una dirección o un lugar de Córdoba.',
                style: TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Guardá tu lugar'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(hintText: 'Casa, Trabajo, Facultad…'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}

class _JourneyEditor extends StatefulWidget {
  final SavedJourney? existing;
  final Parada? origin, destination;
  final List<Parada> places;
  const _JourneyEditor({
    this.existing,
    this.origin,
    this.destination,
    required this.places,
  });
  @override
  State<_JourneyEditor> createState() => _JourneyEditorState();
}

class _JourneyEditorState extends State<_JourneyEditor> {
  late final TextEditingController name;
  Parada? origin, destination;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.existing?.name ?? '');
    origin = widget.existing?.origin ?? widget.origin;
    destination = widget.existing?.destination ?? widget.destination;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> choose(bool start) async {
    final point = await showModalBottomSheet<Parada>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PlaceSearch(
        places: widget.places,
        origin: start,
        onMap: () {
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Para usar un punto del mapa, elegilo en la pantalla principal antes de crear el viaje.',
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || point == null) return;
    setState(() {
      if (start) {
        origin = point;
      } else {
        destination = point;
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'Crear viaje guardado'
                  : 'Editar viaje guardado',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Casa → Facultad',
              ),
              maxLength: 50,
              onChanged: (_) => setState(() {}),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inicio'),
              subtitle: Text(origin?.nombre ?? 'Elegí un lugar'),
              trailing: const Icon(Icons.search),
              onTap: () => choose(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Destino'),
              subtitle: Text(destination?.nombre ?? 'Elegí un lugar'),
              trailing: const Icon(Icons.search),
              onTap: () => choose(false),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    name.text.trim().isEmpty ||
                        origin == null ||
                        destination == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        SavedJourney(
                          id:
                              widget.existing?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: name.text.trim(),
                          origin: origin!,
                          destination: destination!,
                        ),
                      ),
                child: const Text('Guardar viaje'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ConfirmAddressPoint extends StatefulWidget {
  final PlaceSuggestion suggestion;
  const ConfirmAddressPoint({required this.suggestion});
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
