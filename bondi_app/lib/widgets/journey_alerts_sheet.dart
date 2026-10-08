import 'package:flutter/material.dart';

import '../controllers/journey_controller.dart';
import '../models/models.dart';
import '../services/trip_alert_service.dart';
import '../services/arrival_alert.dart';
import '../theme/app_theme.dart';

class JourneyAlertsSheet extends StatefulWidget {
  final JourneyController journey;
  final TripAlertService alerts;
  final ArrivalAlert arrivalAlert;
  final void Function(String) onMessage;
  const JourneyAlertsSheet({
    super.key,
    required this.journey,
    required this.alerts,
    required this.arrivalAlert,
    required this.onMessage,
  });
  @override
  State<JourneyAlertsSheet> createState() => _JourneyAlertsSheetState();
}

class _JourneyAlertsSheetState extends State<JourneyAlertsSheet> {
  late Parada? _selected = widget.journey.destination;
  late double _radius = widget.alerts.radius;
  bool _busy = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.journey,
      widget.alerts,
      widget.arrivalAlert,
    ]),
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
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.notifications_active_outlined, color: blue),
                title: Text('Preparáte para bajar'),
                subtitle: Text(
                  'Te avisamos cuando estés cerca del lugar que elijas.',
                ),
              ),
              if (widget.alerts.active)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: pale,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Aviso activo · ${widget.alerts.target!.nombre}\n${widget.alerts.distance == null ? 'Esperando una ubicación precisa…' : 'Distancia aproximada: ${widget.alerts.distance!.round()} m'}',
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              if (widget.alerts.fired)
                const Text(
                  'Ya emitimos el aviso. Podés activar uno nuevo.',
                  style: TextStyle(color: blue),
                ),
              const SizedBox(height: 12),
              if (!widget.alerts.active) ...[
                if (widget.journey.destination == null &&
                    (widget.journey.trace?.paradas.isEmpty ?? true))
                  const Text(
                    'Elegí un destino o una línea con paradas para configurar el aviso.',
                  ),
                if (widget.journey.destination != null ||
                    (widget.journey.trace?.paradas.isNotEmpty ?? false))
                  DropdownButtonFormField<int>(
                    initialValue: widget.journey.destination == null
                        ? null
                        : -1,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Punto de bajada',
                    ),
                    items: [
                      if (widget.journey.destination != null)
                        DropdownMenuItem(
                          value: -1,
                          child: Text(
                            'Destino: ${widget.journey.destination!.nombre}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ...(widget.journey.trace?.paradas ?? [])
                          .asMap()
                          .entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                e.value.nombre,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: _busy
                        ? null
                        : (index) {
                            setState(
                              () => _selected = index == -1
                                  ? widget.journey.destination
                                  : index == null
                                  ? null
                                  : widget.journey.trace!.paradas[index],
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
                          selected: _radius == meters,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _radius = meters),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (widget.alerts.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    widget.alerts.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : widget.alerts.active
                      ? () => widget.alerts.stopWatching()
                      : _selected == null
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await widget.alerts.start(_selected!, _radius);
                          if (ctx.mounted) setState(() => _busy = false);
                        },
                  icon: Icon(
                    widget.alerts.active
                        ? Icons.stop_circle_outlined
                        : Icons.notifications_active_outlined,
                  ),
                  label: Text(
                    _busy
                        ? 'Activando…'
                        : widget.alerts.active
                        ? 'Cancelar aviso'
                        : 'Ya estoy arriba · Activar aviso',
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await widget.alerts.testSound();
                        if (ctx.mounted) {
                          widget.onMessage('Aviso de prueba solicitado.');
                        }
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
              if (widget.alerts.active && !widget.alerts.systemNotifications)
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
                subtitle: Text(widget.arrivalAlert.status),
              ),
              Wrap(
                spacing: 8,
                children: [5, 10]
                    .map(
                      (minutes) => ChoiceChip(
                        label: Text('$minutes min'),
                        selected: widget.arrivalAlert.minutes == minutes,
                        onSelected: widget.arrivalAlert.active
                            ? null
                            : (_) => setState(
                                () => widget.arrivalAlert.minutes = minutes,
                              ),
                      ),
                    )
                    .toList(),
              ),
              TextButton.icon(
                icon: Icon(
                  widget.arrivalAlert.active
                      ? Icons.cancel_outlined
                      : Icons.notifications_active_outlined,
                ),
                label: Text(
                  widget.arrivalAlert.active
                      ? 'Cancelar aviso de llegada'
                      : 'Activar aviso de llegada',
                ),
                onPressed: widget.arrivalAlert.active
                    ? widget.arrivalAlert.cancel
                    : !widget.journey.inTrip ||
                          widget.journey.offline ||
                          widget.journey.pickup == null ||
                          widget.journey.route == null ||
                          widget.journey.line == null
                    ? null
                    : () => widget.arrivalAlert.start(
                        stop: widget.journey.pickup!.codigo,
                        stopName: widget.journey.pickup!.nombre,
                        route: widget.journey.route!.id,
                        line: widget.journey.line!.id,
                        threshold: widget.arrivalAlert.minutes,
                        vehicle:
                            widget.journey.arrivalVehicle ??
                            widget.journey.tracked?.coche,
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
  );
}
