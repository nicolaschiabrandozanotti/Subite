import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'active_trip_screen.dart';
import 'stop_details_screen.dart';
import 'route_timeline_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();

  List<Linea> _lineas = [];
  Linea? _currentLinea;
  Ruta? _currentRuta;
  Traza? _traza;
  List<Coche> _coches = [];
  Coche? _selectedCoche;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isPredictive = false;
  LatLng? _userLocation;
  int _currentTabIndex = 0;

  Parada? _destinationStop;
  String? _destinationName;
  List<LatLng>? _walkingRoute;

  Timer? _pollingTimer;

  static const LatLng cordobaCenter = LatLng(-31.4167, -64.1833);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final lines = await ApiService.fetchLineas();

    if (mounted) {
      setState(() {
        _lineas = lines;
        if (lines.isNotEmpty) {
          _currentLinea = lines.firstWhere(
            (l) => l.nombre == '70',
            orElse: () => lines.first,
          );
          if (_currentLinea!.rutas.isNotEmpty) {
            _currentRuta = _currentLinea!.rutas.first;
          }
        }
        _isLoading = false;
      });

      if (_currentLinea != null && _currentRuta != null) {
        _loadRouteAndBuses();
      }
    }
  }

  Future<void> _loadRouteAndBuses() async {
    if (_currentLinea == null || _currentRuta == null) return;

    final traza = await ApiService.fetchTraza(
      _currentLinea!.id,
      _currentRuta!.id,
      _currentLinea!.clienteId,
    );

    if (mounted) {
      setState(() => _traza = traza);

      if (traza != null && traza.puntos.isNotEmpty) {
        _mapController.move(traza.puntos.first, 13);
      }

      _refreshBuses(silent: false);
      _startPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshBuses(silent: true);
    });
  }

  Future<void> _refreshBuses({bool silent = false}) async {
    if (_currentLinea == null || _currentRuta == null) return;

    if (!silent) setState(() => _isRefreshing = true);

    final res = await ApiService.fetchCoches(
      rutaId: _currentRuta!.id,
      clienteId: _currentLinea!.clienteId,
      lineaNombre: _currentLinea!.nombre,
      traza: _traza,
    );

    if (mounted) {
      setState(() {
        _coches = (res['coches'] as List<Coche>?) ?? [];
        _isPredictive = res['isPredictive'] == true;
        _isRefreshing = false;
      });
    }
  }

  void _toggleSentido() {
    if (_currentLinea == null || _currentLinea!.rutas.length < 2) return;
    final currIdx = _currentLinea!.rutas.indexOf(_currentRuta!);
    final nextRuta = _currentLinea!.rutas[(currIdx + 1) % _currentLinea!.rutas.length];

    setState(() {
      _currentRuta = nextRuta;
      _selectedCoche = null;
    });

    _loadRouteAndBuses();
  }

  Future<void> _locateUser() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = loc);
      _mapController.move(loc, 16);
    } catch (_) {}
  }

  void _openLineSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _LineSelectorSheet(
        lineas: _lineas,
        currentLinea: _currentLinea,
        onSelect: (linea, ruta) {
          Navigator.pop(ctx);
          setState(() {
            _currentLinea = linea;
            _currentRuta = ruta;
            _selectedCoche = null;
          });
          _loadRouteAndBuses();
        },
      ),
    );
  }

  void _openRouteTimeline() {
    if (_currentLinea == null || _currentRuta == null || _traza == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cargando datos del recorrido...'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteTimelineScreen(
          linea: _currentLinea!,
          currentRuta: _currentRuta!,
          traza: _traza!,
          coches: _coches,
          onRutaChanged: (newRuta) {
            setState(() {
              _currentRuta = newRuta;
              _selectedCoche = null;
            });
            _loadRouteAndBuses();
          },
          onFocusOnMap: (pos) {
            _mapController.move(pos, 16);
          },
        ),
      ),
    );
  }

  void _openActiveTrip() {
    if (_currentLinea == null || _currentRuta == null) return;
    if (_coches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay coches en circulación en este momento'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final bus = _selectedCoche ?? _coches.first;
    final nextStop = (_traza != null && _traza!.paradas.isNotEmpty) ? _traza!.paradas.first : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveTripScreen(
          linea: _currentLinea!,
          ruta: _currentRuta!,
          coche: bus,
          destinationStop: _destinationStop ?? nextStop,
        ),
      ),
    );
  }

  void _setDestinationStop(Parada stop, String name) {
    setState(() {
      _destinationStop = stop;
      _destinationName = name;
      if (_traza != null && _traza!.paradas.isNotEmpty) {
        final userPos = _userLocation ?? cordobaCenter;
        Parada closest = _traza!.paradas.first;
        double minDist = double.infinity;
        for (final p in _traza!.paradas) {
          final d = (p.lat - userPos.latitude) * (p.lat - userPos.latitude) +
                    (p.lon - userPos.longitude) * (p.lon - userPos.longitude);
          if (d < minDist) {
            minDist = d;
            closest = p;
          }
        }
        _walkingRoute = [userPos, closest.position];
      }
    });

    _mapController.move(stop.position, 15);
  }

  void _openTripPlanner() {
    if (_traza == null || _traza!.paradas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cargando paradas...')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '¿A dónde querés ir?',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'DESTINOS FRECUENTES',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.school, color: Colors.blueAccent, size: 20),
                ),
                title: const Text('Ciudad Universitaria (UNC)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Pabellón Argentina / Haya de la Torre', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_traza != null && _traza!.paradas.isNotEmpty) {
                    _setDestinationStop(_traza!.paradas.last, 'Ciudad Universitaria');
                  }
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_bag, color: Colors.amberAccent, size: 20),
                ),
                title: const Text('Patio Olmos / Centro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Av. Vélez Sarsfield y San Juan', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_traza != null && _traza!.paradas.isNotEmpty) {
                    final middle = _traza!.paradas[_traza!.paradas.length ~/ 2];
                    _setDestinationStop(middle, 'Patio Olmos');
                  }
                },
              ),
              const Divider(color: Color(0xFF1E293B)),
              const Text(
                'O ELEGÍ UNA PARADA DEL RECORRIDO',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: _traza!.paradas.length,
                  itemBuilder: (_, i) {
                    final p = _traza!.paradas[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.flag_outlined, color: Colors.amberAccent, size: 18),
                      title: Text(p.nombre, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      trailing: Text('#${p.codigo}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _setDestinationStop(p, p.nombre);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lineaColor = _currentLinea?.color ?? AppColors.secondary;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          // 1. FlutterMap Vector-like Layer
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: cordobaCenter,
              initialZoom: 13,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.bondicba.app',
                maxZoom: 20,
              ),

              // Route Polyline
              if (_traza != null && _traza!.puntos.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Main Route
                    Polyline(
                      points: _traza!.puntos,
                      strokeWidth: 7,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    Polyline(
                      points: _traza!.puntos,
                      strokeWidth: 5,
                      color: lineaColor,
                    ),
                    // Walking path to pickup stop
                    if (_walkingRoute != null)
                      Polyline(
                        points: _walkingRoute!,
                        strokeWidth: 4,
                        color: const Color(0xFF38BDF8),
                      ),
                  ],
                ),

              // Interactive Stops Markers
              if (_traza != null)
                MarkerLayer(
                  markers: _traza!.paradas.map((p) {
                    final isMeta = _destinationStop != null && 
                        (_destinationStop!.codigo == p.codigo || _destinationStop!.nombre == p.nombre);

                    return Marker(
                      point: p.position,
                      width: isMeta ? 32 : 22,
                      height: isMeta ? 32 : 22,
                      child: GestureDetector(
                        onTap: () {
                          if (_currentLinea != null && _currentRuta != null) {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: AppColors.surfaceDark,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              builder: (ctx) => Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Parada #${p.codigo}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      p.nombre,
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _setDestinationStop(p, p.nombre);
                                      },
                                      icon: const Icon(Icons.flag, color: Colors.black),
                                      label: const Text('🎯 Fijar como Parada Meta (Bajada)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amberAccent,
                                        minimumSize: const Size(double.infinity, 45),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => StopDetailsScreen(
                                              parada: p,
                                              linea: _currentLinea!,
                                              ruta: _currentRuta!,
                                              coches: _coches,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.info_outline, color: Colors.white70),
                                      label: const Text('Ver Próximos Arribos', style: TextStyle(color: Colors.white)),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isMeta ? Colors.amberAccent : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isMeta ? Colors.black : lineaColor,
                              width: isMeta ? 2.5 : 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isMeta ? Colors.amberAccent.withValues(alpha: 0.8) : Colors.black38,
                                blurRadius: isMeta ? 10 : 4,
                                spreadRadius: isMeta ? 2 : 0,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: isMeta
                              ? const Text('🎯', style: TextStyle(fontSize: 14))
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // Bus Markers
              MarkerLayer(
                markers: _coches.map((c) {
                  final isSelected = _selectedCoche?.coche == c.coche;
                  return Marker(
                    point: c.position,
                    width: 90,
                    height: 50,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedCoche = c);
                        _mapController.move(c.position, 16);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: lineaColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? Colors.amberAccent : Colors.white,
                                width: isSelected ? 2.5 : 1.5,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 6),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🚌 ', style: TextStyle(fontSize: 10)),
                                Text(
                                  '${c.coche}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (c.rampa) ...[
                                  const SizedBox(width: 2),
                                  const Text('♿', style: TextStyle(fontSize: 9)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: c.isPredictive
                                  ? const Color(0xFFD97706)
                                  : AppColors.liveGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              c.demora,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // 2. Top Search & Quick Chips (Stitch inspired)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Main Top Bar Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF1E293B)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Line Badge Trigger
                        InkWell(
                          onTap: _openLineSelector,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: lineaColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _currentLinea?.nombre ?? '...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Línea ${_currentLinea?.nombre ?? ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white70),
                                      ],
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        _currentRuta?.nombre ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),

                        // Direction Switch
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Text(
                              _currentRuta?.sentido == 'I' ? 'IDA' : 'VTA',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          onPressed: _toggleSentido,
                        ),

                        // Live status chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: _isPredictive
                                ? const Color(0xFFD97706).withValues(alpha: 0.2)
                                : AppColors.liveGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isPredictive
                                  ? const Color(0xFFD97706).withValues(alpha: 0.4)
                                  : AppColors.liveGreen.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isPredictive ? Icons.bolt : Icons.fiber_manual_record,
                                size: 10,
                                color: _isPredictive ? Colors.amberAccent : AppColors.liveGreenLight,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isPredictive ? 'EST' : '${_coches.length}',
                                style: TextStyle(
                                  color: _isPredictive ? Colors.amberAccent : AppColors.liveGreenLight,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          icon: _isRefreshing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                                )
                              : const Icon(Icons.refresh, color: Colors.white70, size: 20),
                          onPressed: () => _refreshBuses(silent: false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Quick Destination Chips (Stitch inspired)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _openTripPlanner,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF38BDF8)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.navigation, size: 13, color: Colors.amberAccent),
                                const SizedBox(width: 4),
                                Text(
                                  _destinationName != null ? 'Meta: $_destinationName' : '¿A dónde vas?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _openRouteTimeline,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.secondary),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.format_list_bulleted, size: 13, color: AppColors.secondaryContainer),
                                SizedBox(width: 4),
                                Text(
                                  'Ver Recorrido',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: const Row(
                            children: [
                              Text('🏠 ', style: TextStyle(fontSize: 12)),
                              Text('Casa', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: const Row(
                            children: [
                              Text('🎓 ', style: TextStyle(fontSize: 12)),
                              Text('Ciudad Universitaria', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating GPS & Layer Buttons
          Positioned(
            right: 16,
            bottom: 230,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'center',
                  backgroundColor: AppColors.surfaceDark,
                  onPressed: () {
                    if (_traza != null && _traza!.puntos.isNotEmpty) {
                      _mapController.move(_traza!.puntos.first, 13);
                    }
                  },
                  child: const Icon(Icons.layers_outlined, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'gps',
                  backgroundColor: AppColors.surfaceDark,
                  onPressed: _locateUser,
                  child: const Icon(Icons.my_location, color: Color(0xFF38BDF8)),
                ),
              ],
            ),
          ),

          // 4. Bottom Active Stop / Bus Cards Pod (Stitch inspired)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 60),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black87, blurRadius: 16),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_coches.length} colectivos en recorrido',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        _isPredictive ? 'Ubicación aproximada' : 'Última ubicación disponible',
                        style: TextStyle(
                          color: _isPredictive ? Colors.amberAccent : AppColors.liveGreenLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 80,
                    child: _coches.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay coches reportando en este sentido ahora.',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _coches.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (ctx, i) {
                              final c = _coches[i];
                              final isSel = _selectedCoche?.coche == c.coche;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _selectedCoche = c);
                                  _mapController.move(c.position, 16);
                                },
                                child: Container(
                                  width: 170,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? const Color(0xFF1E293B)
                                        : AppColors.surfaceCardDark,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSel ? const Color(0xFF38BDF8) : AppColors.borderDark,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: lineaColor,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${c.coche}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              c.demora,
                                              style: TextStyle(
                                                color: c.isPredictive ? Colors.amberAccent : AppColors.liveGreenLight,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              c.rampa ? '♿ Con rampa' : 'Piso normal',
                                              style: const TextStyle(color: Colors.white38, fontSize: 9),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // 5. Bottom Navigation Bar (Stitch inspired)
      bottomNavigationBar: Container(
        height: 60,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark.withValues(alpha: 0.95),
          border: const Border(top: BorderSide(color: Color(0xFF1E293B))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.map, 'Mapa'),
            _buildNavItem(1, Icons.format_list_bulleted, 'Paradas', onTap: _openRouteTimeline),
            _buildNavItem(2, Icons.alt_route, 'Líneas', onTap: _openLineSelector),
            _buildNavItem(3, Icons.navigation, 'En Viaje', onTap: _openActiveTrip),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, {VoidCallback? onTap}) {
    final isSelected = _currentTabIndex == index;
    return InkWell(
      onTap: onTap ?? () => setState(() => _currentTabIndex = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 22,
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

// Line Selector Sheet
class _LineSelectorSheet extends StatefulWidget {
  final List<Linea> lineas;
  final Linea? currentLinea;
  final Function(Linea, Ruta) onSelect;

  const _LineSelectorSheet({
    required this.lineas,
    required this.currentLinea,
    required this.onSelect,
  });

  @override
  State<_LineSelectorSheet> createState() => _LineSelectorSheetState();
}

class _LineSelectorSheetState extends State<_LineSelectorSheet> {
  String _search = '';
  String _selectedCorredor = 'ALL';

  Widget _buildCorredorChip(String id, String label) {
    final isSel = _selectedCorredor == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedCorredor = id),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.lineas.where((l) {
      final matchesSearch = l.nombre.toLowerCase().contains(_search.toLowerCase()) ||
          l.rutas.any((r) => r.nombre.toLowerCase().contains(_search.toLowerCase()));
      final matchesCorredor = _selectedCorredor == 'ALL' ||
          (_selectedCorredor == 'CONIFERAL' && (l.clienteNombre.toUpperCase().contains('CONIFERAL') || l.nombre.startsWith('1') || l.nombre.startsWith('6') || l.nombre == 'B60')) ||
          (_selectedCorredor == 'TAMSE' && (l.clienteNombre.toUpperCase().contains('TAMSE') || ['600','601','AEROBUS','A','B','C'].contains(l.nombre) || l.nombre.startsWith('2') || l.nombre.startsWith('3') || l.nombre.startsWith('5'))) ||
          (_selectedCorredor == 'SOLBUS' && (l.clienteNombre.toUpperCase().contains('SOL') || l.nombre.startsWith('7'))) ||
          (_selectedCorredor == 'SIBUS' && (l.clienteNombre.toUpperCase().contains('SI') || l.nombre.startsWith('8') || l.nombre == 'B80'));
      return matchesSearch && matchesCorredor;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Líneas de Córdoba',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar línea (70, 20, Aerobus...)',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCorredorChip('ALL', 'Todas'),
                _buildCorredorChip('CONIFERAL', '🟧 Coniferal (1 y 6)'),
                _buildCorredorChip('TAMSE', '🟦 TAMSE (2, 3, 5)'),
                _buildCorredorChip('SOLBUS', '🟥 Sol Bus (7)'),
                _buildCorredorChip('SIBUS', '🟪 Si Bus (8)'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final linea = filtered[i];
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: ExpansionTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: linea.color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        linea.nombre,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    title: Text(
                      'Línea ${linea.nombre}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${linea.clienteNombre} • ${linea.rutas.length} recorridos',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    children: linea.rutas.map((ruta) {
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ruta.sentido == 'I'
                                ? AppColors.liveGreen.withValues(alpha: 0.2)
                                : Colors.blueAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ruta.sentido == 'I' ? 'IDA' : 'VUELTA',
                            style: TextStyle(
                              color: ruta.sentido == 'I' ? AppColors.liveGreenLight : Colors.blueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          ruta.nombre,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white38),
                        onTap: () => widget.onSelect(linea, ruta),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
