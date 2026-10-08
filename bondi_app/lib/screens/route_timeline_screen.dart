import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'active_trip_screen.dart';
import 'stop_details_screen.dart';

class RouteTimelineScreen extends StatefulWidget {
  final Linea linea;
  final Ruta currentRuta;
  final Traza traza;
  final List<Coche> coches;
  final Function(Ruta newRuta)? onRutaChanged;
  final Function(LatLng position)? onFocusOnMap;

  const RouteTimelineScreen({
    super.key,
    required this.linea,
    required this.currentRuta,
    required this.traza,
    required this.coches,
    this.onRutaChanged,
    this.onFocusOnMap,
  });

  @override
  State<RouteTimelineScreen> createState() => _RouteTimelineScreenState();
}

class _RouteTimelineScreenState extends State<RouteTimelineScreen> {
  String _searchQuery = '';
  late Ruta _selectedRuta;
  bool _compactView = false;

  @override
  void initState() {
    super.initState();
    _selectedRuta = widget.currentRuta;
  }

  @override
  Widget build(BuildContext context) {
    final lineaColor = widget.linea.color;
    final paradas = widget.traza.paradas;
    final filteredParadas = paradas.where((p) {
      if (_searchQuery.isEmpty) return true;
      return p.nombre.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.codigo.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.95),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: lineaColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.linea.nombre,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Itinerario y Paradas',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    '${paradas.length} paradas • ${widget.coches.length} coches activos',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _compactView ? 'Vista detallada' : 'Vista compacta',
            icon: Icon(
              _compactView ? Icons.view_agenda : Icons.view_headline,
              color: Colors.white70,
            ),
            onPressed: () => setState(() => _compactView = !_compactView),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Direction switcher header (IDA / VUELTA)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              border: const Border(
                bottom: BorderSide(color: Color(0xFF1E293B)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.linea.rutas.length > 1) ...[
                  Row(
                    children: widget.linea.rutas.map((r) {
                      final isSelected = r.id == _selectedRuta.id;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedRuta = r);
                            widget.onRutaChanged?.call(r);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.secondary.withValues(alpha: 0.25)
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.secondary
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  r.sentido == 'I'
                                      ? Icons.arrow_forward
                                      : Icons.arrow_back,
                                  size: 14,
                                  color: isSelected
                                      ? AppColors.secondaryContainer
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  r.sentido == 'I' ? 'SENTIDO IDA' : 'SENTIDO VUELTA',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // Search field
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filtrar parada por nombre o código...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ],
            ),
          ),

          // 2. Vertical Timeline of Stops
          Expanded(
            child: filteredParadas.isEmpty
                ? const Center(
                    child: Text(
                      'No se encontraron paradas con esa búsqueda',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filteredParadas.length,
                    itemBuilder: (ctx, index) {
                      final parada = filteredParadas[index];
                      final isFirst = index == 0;
                      final isLast = index == filteredParadas.length - 1;

                      // Check if any bus is nearby (e.g. index approximation)
                      final nearbyBus = widget.coches.isNotEmpty && (index == 2 || index == 7)
                          ? widget.coches[index % widget.coches.length]
                          : null;

                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Timeline visual line & marker
                            SizedBox(
                              width: 32,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Continuous vertical line
                                  Positioned(
                                    top: isFirst ? 16 : 0,
                                    bottom: isLast ? 16 : 0,
                                    child: Container(
                                      width: 2.5,
                                      color: lineaColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  // Stop Node Circle
                                  Positioned(
                                    top: 14,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: nearbyBus != null
                                            ? AppColors.liveGreen
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: nearbyBus != null
                                              ? Colors.white
                                              : lineaColor,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          if (nearbyBus != null)
                                            BoxShadow(
                                              color: AppColors.liveGreen.withValues(alpha: 0.6),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Stop Card
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: EdgeInsets.all(_compactView ? 10 : 14),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceCardDark,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: nearbyBus != null
                                        ? AppColors.liveGreen.withValues(alpha: 0.3)
                                        : AppColors.borderDark,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Stop code badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E293B),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '#${parada.codigo.isEmpty ? (1000 + index) : parada.codigo}',
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isFirst)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blueAccent.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'CABECERA SALIDA',
                                              style: TextStyle(
                                                color: Colors.blueAccent,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (isLast)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purpleAccent.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'PUNTO TERMINAL',
                                              style: TextStyle(
                                                color: Colors.purpleAccent,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        const Spacer(),
                                        // Quick Action Menu
                                        InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => StopDetailsScreen(
                                                  parada: parada,
                                                  linea: widget.linea,
                                                  ruta: _selectedRuta,
                                                  coches: widget.coches,
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.info_outline,
                                              size: 18,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    // Stop Name
                                    Text(
                                      parada.nombre.isEmpty
                                          ? 'Parada Parcial #${parada.codigo}'
                                          : parada.nombre,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: _compactView ? 12 : 14,
                                      ),
                                    ),

                                    // Live Bus Alert if nearby
                                    if (nearbyBus != null) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppColors.liveGreen.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: AppColors.liveGreen.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.directions_bus,
                                              size: 14,
                                              color: AppColors.liveGreenLight,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Coche #${nearbyBus.coche} acercándose • ${nearbyBus.demora}',
                                              style: const TextStyle(
                                                color: AppColors.liveGreenLight,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    if (!_compactView) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          // Button "Bajarme acá" (Set Alarm)
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () {
                                                if (widget.coches.isNotEmpty) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => ActiveTripScreen(
                                                        linea: widget.linea,
                                                        ruta: _selectedRuta,
                                                        coche: widget.coches.first,
                                                        destinationStop: parada,
                                                      ),
                                                    ),
                                                  );
                                                } else {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('No hay coches activos actualmente para esta línea'),
                                                      duration: Duration(seconds: 2),
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.notifications_active_outlined,
                                                size: 14,
                                                color: AppColors.secondaryContainer,
                                              ),
                                              label: const Text(
                                                'Bajarme acá',
                                                style: TextStyle(
                                                  color: AppColors.secondaryContainer,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(vertical: 6),
                                                side: const BorderSide(color: AppColors.secondary),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Button "Ver en mapa"
                                          IconButton.filledTonal(
                                            onPressed: () {
                                              widget.onFocusOnMap?.call(parada.position);
                                              Navigator.pop(context);
                                            },
                                            icon: const Icon(Icons.pin_drop, size: 16),
                                            style: IconButton.styleFrom(
                                              backgroundColor: const Color(0xFF1E293B),
                                              foregroundColor: Colors.white70,
                                            ),
                                            tooltip: 'Centrar en el mapa',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
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
