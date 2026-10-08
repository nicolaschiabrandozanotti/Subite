import 'package:flutter/material.dart';

import '../controllers/journey_controller.dart';
import '../services/journey_planner.dart';
import '../theme/app_theme.dart';

class JourneyPreferencesSheet extends StatelessWidget {
  final JourneyController journey;
  final void Function(bool) onEditEndpoint;
  final VoidCallback onFindJourneys, onSaveDestination;
  final Future<void> Function() onPickLine;
  final void Function(DirectJourney) onChooseTrip;
  const JourneyPreferencesSheet({
    super.key,
    required this.journey,
    required this.onEditEndpoint,
    required this.onFindJourneys,
    required this.onPickLine,
    required this.onSaveDestination,
    required this.onChooseTrip,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: journey,
    builder: (context, _) {
      final hasOrigin = journey.hasOrigin;
      final nearest = journey.currentJourney()?.boarding;
      final pickup = journey.pickupPreference == PickupPreference.nearest
          ? nearest
          : journey.pickup;
      final candidate = journey.currentJourney(boardingCode: pickup?.codigo);
      final ready =
          hasOrigin &&
          journey.destination != null &&
          journey.line != null &&
          pickup != null &&
          candidate != null &&
          !journey.loading;
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
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
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
                        'Inicio · ${hasOrigin ? journey.originName : 'Sin elegir'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Destino · ${journey.destination?.nombre ?? 'Sin elegir'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!hasOrigin || journey.destination == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onEditEndpoint(!hasOrigin);
                      },
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: Text(
                        !hasOrigin ? 'Elegir inicio' : 'Elegir destino',
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: !hasOrigin || journey.destination == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          onFindJourneys();
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
                    journey.line == null
                        ? 'Elegí una línea'
                        : 'Línea ${journey.line!.nombre}',
                  ),
                  subtitle: Text(
                    journey.route?.nombre ?? 'Sin recorrido seleccionado',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(context);
                    await onPickLine();
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
                      selected:
                          journey.pickupPreference == PickupPreference.nearest,
                      onSelected: (_) {
                        journey.setPickupPreference(PickupPreference.nearest);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Elegir parada'),
                      selected:
                          journey.pickupPreference == PickupPreference.stop,
                      onSelected: (_) {
                        journey.setPickupPreference(PickupPreference.stop);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (journey.pickupPreference == PickupPreference.nearest)
                  Text(
                    !hasOrigin
                        ? 'Elegí el inicio para encontrar una parada cercana.'
                        : nearest == null
                        ? 'No hay paradas disponibles para este recorrido.'
                        : nearest.nombre,
                    style: const TextStyle(fontSize: 13, color: ink),
                  ),
                if (journey.pickupPreference == PickupPreference.stop)
                  DropdownButtonFormField<String>(
                    initialValue: journey.pickup?.codigo,
                    isExpanded: true,
                    hint: const Text('Paradas de la línea seleccionada'),
                    items: (journey.trace?.paradas ?? [])
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
                      journey.setPickup(
                        journey.trace!.paradas.firstWhere(
                          (p) => p.codigo == code,
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 18),
                Text(
                  candidate == null
                      ? 'Este recorrido no tiene un viaje directo válido con estas preferencias. Buscá otras líneas.'
                      : 'Bajás en ${candidate.alighting.nombre}. A pie aprox.: ${candidate.walkStart.round()} m al subir y ${candidate.walkEnd.round()} m al llegar. Llegadas de bondis aún sin confirmar.',
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
                            Navigator.pop(context);
                            onChooseTrip(candidate);
                          },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Elegir este viaje'),
                  ),
                ),
                if (journey.destination != null)
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onSaveDestination();
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
  );
}
