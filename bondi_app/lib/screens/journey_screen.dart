import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/saved_journey.dart';
import '../controllers/journey_controller.dart';
import '../widgets/journey_map.dart';
import '../widgets/journey_alerts_sheet.dart';
import '../widgets/journey_preferences_sheet.dart';
import '../widgets/journey_results_panel.dart';
import '../widgets/place_search_sheet.dart';
import '../widgets/save_place_dialog.dart';
import '../widgets/saved_journey_editor.dart';
import '../theme/app_theme.dart';
import '../services/trip_alert_service.dart';
import '../services/arrival_alert.dart';
import '../services/journey_planner.dart';
import 'expenses_screen.dart';
import 'support_sheet.dart';

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
  late final _journey = JourneyController(onMessage: _message);
  List<Parada> _saved = [];
  List<SavedJourney> _journeys = [];
  Position? _lastPosition;
  String? _picking;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alerts.addListener(_alertChanged);
    _arrivalAlert.addListener(_arrivalChanged);
    _journey.addListener(_journeyChanged);
    _load();
    _journey.load();
    _detectLightMode();
  }

  void _journeyChanged() {
    if (!mounted) return;
    if (_journey.offline && !_wasOffline) {
      _alerts.stopWatching();
      _arrivalAlert.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _journey.offline) _fitJourney();
      });
    }
    _wasOffline = _journey.offline;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _journey.setForeground(state == AppLifecycleState.resumed);
  }

  Future<void> _detectLightMode() async {
    try {
      final light = await const MethodChannel('bondi/device')
          .invokeMethod<bool>('lightMode');
      if (mounted) _journey.setLightMode(light ?? false);
    } on MissingPluginException {
      /* Desktop uses the standard display. */
    } on PlatformException {
      /* Keep the standard display if detection fails. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _journey.dispose();
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
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _journeys = journeys;
    });
  }

  Future<void> _selectLine(Linea line, [Ruta? route]) async {
    _arrivalAlert.cancel();
    if (await _journey.selectLine(line, route) &&
        mounted &&
        !_journey.planned) {
      _fitJourney();
    }
  }

  Future<void> _openOffline() async {
    await _journey.openOffline();
    if (mounted) _fitJourney();
  }

  Future<void> _chooseTrip(DirectJourney trip) async {
    _arrivalAlert.cancel();
    if (await _journey.chooseTrip(trip) && mounted) _fitJourney();
  }

  Future<void> _findJourneys() async {
    _arrivalAlert.cancel();
    final result = await _journey.findJourneys();
    if (!mounted || result == JourneySearchResult.cancelled) return;
    if (result == JourneySearchResult.noRoutes) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('No encontramos un viaje directo'),
          content: Text(
            _journey.planningFailed == 0
                ? 'No encontramos un recorrido directo con paradas a menos de 800 m de cada punto. Probá ajustar el inicio o el destino.'
                : 'No encontramos un recorrido directo entre los datos disponibles. ${_journey.planningFailed} recorridos no pudieron consultarse. Probá nuevamente.',
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
    _fitJourney();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
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
        setState(() => _lastPosition = position);
        _map.move(LatLng(position.latitude, position.longitude), 15);
        return;
      }
      setState(() {
        _lastPosition = position;
      });
      _journey.setEndpoints(
        origin: Parada(
          codigo: 'gps',
          nombre: 'Mi ubicación actual',
          lat: position.latitude,
          lon: position.longitude,
        ),
      );
      _map.move(_journey.origin, 15);
      await _findJourneys();
    } catch (_) {
      _message('No pudimos obtener tu ubicación. Probá elegirla en el mapa.');
    }
  }

  void _pickMapPoint(LatLng point) {
    if (_picking == null) return;
    if (_picking == 'origin') {
      _journey.setEndpoints(
        origin: Parada(
          codigo: 'map',
          nombre: 'Origen en el mapa',
          lat: point.latitude,
          lon: point.longitude,
        ),
      );
    } else {
      _setDestination(
        Parada(
          codigo: 'map',
          nombre: 'Destino en el mapa',
          lat: point.latitude,
          lon: point.longitude,
        ),
      );
    }
    setState(() => _picking = null);
    _findJourneys();
  }

  void _pick(String target) {
    setState(() => _picking = target);
    _message(
      target == 'origin'
          ? 'Tocá el mapa para elegir el origen'
          : 'Tocá el mapa para elegir el destino',
    );
  }

  void _setDestination(Parada point) {
    _alerts.stopWatching();
    _arrivalAlert.cancel();
    _journey.setEndpoints(destination: point);
  }

  Future<void> _search({bool origin = false}) async {
    final point = await showModalBottomSheet<Parada>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => PlaceSearchSheet(
        places: [..._saved, ..._journey.trace?.paradas ?? []],
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
      _journey.setEndpoints(origin: point);
    } else {
      _setDestination(point);
      _map.move(point.position, 15);
      await _findJourneys();
    }
    if (origin) await _findJourneys();
  }

  Future<void> _useJourney(SavedJourney route, {required bool origin}) async {
    _alerts.stopWatching();
    _arrivalAlert.cancel();
    _journey.setEndpoints(origin: route.origin, destination: route.destination);
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
      builder: (_) => SavedJourneyEditor(
        existing: existing,
        origin: !_journey.hasOrigin
            ? null
            : Parada(
                codigo: 'origin',
                nombre: _journey.originName,
                lat: _journey.origin.latitude,
                lon: _journey.origin.longitude,
              ),
        destination: _journey.destination,
        places: [..._saved, ..._journey.trace?.paradas ?? []],
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
    setState(() => _lastPosition = _alerts.lastPosition);
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

  Future<void> _openAlerts() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => JourneyAlertsSheet(
      journey: _journey,
      alerts: _alerts,
      arrivalAlert: _arrivalAlert,
      onMessage: _message,
    ),
  );

  Future<void> _save() async {
    if (_journey.destination == null) {
      _message('Elegí un destino para guardarlo.');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const SavePlaceDialog(),
    );
    if (!mounted || name == null) return;
    final place = Parada(
      codigo: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      nombre: name,
      lat: _journey.destination!.lat,
      lon: _journey.destination!.lon,
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

  void _showBuses() {
    final buses = _journey.visibleBuses;
    if (buses.isEmpty) return;
    _journey.trackVehicle(null);
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          _journey.origin,
          if (_journey.pickup != null) _journey.pickup!.position,
          ...buses.map((b) => b.position),
        ]),
        padding: const EdgeInsets.fromLTRB(45, 210, 45, 270),
      ),
    );
  }

  Future<void> _parameters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => JourneyPreferencesSheet(
      journey: _journey,
      onEditEndpoint: (origin) => _search(origin: origin),
      onFindJourneys: _findJourneys,
      onPickLine: () async {
        await _linePicker();
        if (mounted) await _parameters();
      },
      onSaveDestination: _save,
      onChooseTrip: _chooseTrip,
    ),
  );

  Future<void> _linePicker() async {
    if (_journey.destination != null && _journey.hasOrigin) {
      if (_journey.planning) {
        _message('Esperá que termine la búsqueda de líneas compatibles.');
        return;
      }
      if (_journey.tripOptions.isEmpty) {
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
            ..._journey.tripOptions.map(
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
                children: _journey.lines
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

  void _fitJourney() {
    final points = [
      ..._journey.routePoints,
      if (_journey.pickup != null) ...[
        _journey.origin,
        _journey.pickup!.position,
      ],
      if (_journey.inTrip &&
          _journey.dropoff != null &&
          _journey.destination != null) ...[
        _journey.dropoff!.position,
        _journey.destination!.position,
      ],
      ..._journey.visibleBuses.map((bus) => bus.position),
    ];
    if (points.length < 2) return;
    // A zero-area route produces an infinite camera zoom in flutter_map.
    // This can happen with a saved trip whose stops share coordinates.
    if (points.every(
      (point) =>
          point.latitude == points.first.latitude &&
          point.longitude == points.first.longitude,
    )) {
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(45, 210, 45, 240),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            JourneyMap(
              journey: _journey,
              controller: _map,
              savedPlaces: _saved,
              onPointPicked: _pickMapPoint,
              onDestinationSelected: (point) {
                _setDestination(point);
                _findJourneys();
              },
              onMessage: _message,
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
                        itemCount:
                            (_journeys.isEmpty ? 1 : _journeys.length) +
                            (_journey.preparedTrip != null && !_journey.offline
                                ? 1
                                : 0),
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final savedCount = _journeys.isEmpty
                              ? 1
                              : _journeys.length;
                          final isOfflineShortcut =
                              _journey.preparedTrip != null &&
                              !_journey.offline &&
                              i == savedCount;
                          return SizedBox(
                            width: (bounds.maxWidth - 8) / 2,
                            child: OutlinedButton.icon(
                              onPressed: isOfflineShortcut
                                  ? _openOffline
                                  : _journeys.isEmpty
                                  ? _manageJourneys
                                  : () => _useJourney(
                                      _journeys[i],
                                      origin: false,
                                    ),
                              icon: Icon(
                                isOfflineShortcut
                                    ? Icons.offline_pin_outlined
                                    : _journeys.isEmpty
                                    ? Icons.add
                                    : Icons.bookmark_outline,
                                size: 16,
                              ),
                              label: Text(
                                isOfflineShortcut
                                    ? 'Abrir viaje sin datos'
                                    : _journeys.isEmpty
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
                          );
                        },
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
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'support',
                    backgroundColor: Colors.white,
                    foregroundColor: blue,
                    tooltip: 'Bancá Subite',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => const SupportSheet(),
                    ),
                    child: const Icon(Icons.favorite_outline),
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
            if (_journey.planned || _journey.line != null || _journey.offline)
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
                          '© OpenStreetMap contributors',
                          style: TextStyle(fontSize: 9, color: Colors.blueGrey),
                        ),
                      ),
                      GestureDetector(
                        key: const ValueKey('journey-sheet-handle'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_sheet.isAttached) {
                            _sheet.animateTo(
                              _sheet.size < .5 ? .7 : .3,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        onVerticalDragUpdate: (details) {
                          if (_sheet.isAttached) {
                            _sheet.jumpTo(
                              (_sheet.size -
                                      details.delta.dy /
                                          MediaQuery.sizeOf(context).height)
                                  .clamp(.2, .7),
                            );
                          }
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
                      JourneyResultsPanel(
                        journey: _journey,
                        position: _lastPosition,
                        onFocusPoint: (point, zoom) => _map.move(point, zoom),
                        onChooseTrip: _chooseTrip,
                        onShowBuses: _showBuses,
                        onPreferences: _parameters,
                        onSaveDestination: _save,
                        onOpenOffline: _openOffline,
                        onReconnect: () => _journey.reconnect(),
                      ),
                      if (!_journey.inTrip) ...[
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
                              _journey.pickup?.nombre ?? 'Explorá las paradas',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _journey.line == null
                                  ? 'Elegí una línea para ver su recorrido'
                                  : 'Línea ${_journey.line!.nombre} · ${_journey.trace?.paradas.length ?? 0} paradas',
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
                        if (_journey.offline) ...[
                          Text(
                            _journey.preparedTrip?.positionsAt == null ||
                                    _journey.preparedTrip!.buses.isEmpty
                                ? 'Este viaje no tiene ubicaciones de colectivos guardadas.'
                                : 'Estimación con datos de hace ${DateTime.now().difference(_journey.preparedTrip!.positionsAt!).inMinutes.clamp(0, 99999)} min · no son en vivo.',
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin conexión. Podés ver tu recorrido y las paradas guardadas. El mapa de Córdoba está guardado. Las posiciones se estiman según el tiempo transcurrido.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _journey.reconnect(),
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
                            if (_journey.tracked != null)
                              TextButton(
                                onPressed: () => _journey.trackVehicle(null),
                                child: const Text('Ver todos'),
                              ),
                            IconButton(
                              tooltip: 'Actualizar colectivos',
                              onPressed: _journey.refresh,
                              icon: const Icon(
                                Icons.refresh,
                                size: 19,
                                color: blue,
                              ),
                            ),
                          ],
                        ),
                        if (_journey.loading)
                          const LinearProgressIndicator()
                        else if (_journey.visibleBuses.isEmpty)
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
                        ..._journey.visibleBuses.map(
                          (b) => Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: _journey.line?.color ?? blue,
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
                                _journey.tracked?.coche == b.coche
                                    ? Icons.check_circle
                                    : Icons.chevron_right,
                                color: blue,
                              ),
                              onTap: () {
                                _journey.trackVehicle(b.coche);
                                _map.move(b.position, 15);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_journey.planned)
                          const Text(
                            'Estás explorando una línea. Elegí inicio y destino para buscar tu viaje.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey,
                              height: 1.5,
                            ),
                          ),
                        if (_journey.destination != null)
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
              _nav(
                Icons.map_outlined,
                'Mapa',
                () => _map.move(_journey.origin, 14),
              ),
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

  Future<void> _swapEndpoints() async {
    final destination = _journey.destination;
    if (destination == null || !_journey.hasOrigin) {
      return;
    }
    await _alerts.stopWatching();
    if (!mounted) return;
    _journey.swapEndpoints();
    setState(() => _picking = null);
    await _findJourneys();
  }

  Widget _searchBar({required bool origin}) {
    final selected = origin ? _journey.hasOrigin : _journey.destination != null;
    final text = origin
        ? (selected ? _journey.originName : '¿Desde dónde salís?')
        : (_journey.destination?.nombre ?? '¿A dónde querés ir?');
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
            tooltip: origin ? 'Usar mi ubicación' : 'Invertir inicio y destino',
            onPressed: origin
                ? _locate
                : (_journey.destination != null && _journey.hasOrigin
                      ? _swapEndpoints
                      : null),
            icon: Icon(
              origin ? Icons.gps_fixed : Icons.swap_vert,
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
