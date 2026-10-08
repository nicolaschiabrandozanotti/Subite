import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/saved_journey.dart';
import '../services/place_search_service.dart';
import '../services/recent_places.dart';
import '../theme/app_theme.dart';
import 'confirm_address_point.dart';

class PlaceSearchSheet extends StatefulWidget {
  final List<Parada> places;
  final bool origin;
  final List<SavedJourney> journeys;
  final ValueChanged<SavedJourney>? onJourney;
  final VoidCallback onMap;
  const PlaceSearchSheet({
    super.key,
    required this.places,
    required this.origin,
    this.journeys = const [],
    this.onJourney,
    required this.onMap,
  });
  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
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
                            '${r.name} ${widget.origin ? r.origin.nombre : r.destination.nombre}',
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
                            if (context.mounted && point != null) {
                              await choosePoint(point);
                            }
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
