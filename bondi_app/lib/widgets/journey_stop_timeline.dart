import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/journey_planner.dart';
import '../theme/app_theme.dart';

class JourneyStopTimeline extends StatelessWidget {
  final List<Parada> stops;
  final Traza? trace;
  final Position? position;
  const JourneyStopTimeline({
    super.key,
    required this.stops,
    required this.trace,
    this.position,
  });
  @override
  Widget build(BuildContext context) {
    final stops = this.stops;
    final fix = position;
    final validFix =
        fix != null &&
        fix.accuracy <= 50 &&
        DateTime.now().difference(fix.timestamp).inSeconds <= 30;
    final progress = validFix && trace != null
        ? JourneyPlanner.progress(
            LatLng(fix.latitude, fix.longitude),
            trace!.puntos,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            progress == null
                ? 'Activá el aviso de bajada para seguir tu avance.'
                : 'Tu avance según tu ubicación',
            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
        ),
        for (var i = 0; i < stops.length; i++)
          Builder(
            builder: (context) {
              final stop = stops[i];
              final stopProgress = JourneyPlanner.progress(
                stop.position,
                trace!.puntos,
              );
              final passed =
                  progress != null &&
                  stopProgress != null &&
                  progress > stopProgress + 60;
              final here =
                  validFix &&
                  const Distance()(
                        LatLng(fix.latitude, fix.longitude),
                        stop.position,
                      ) <=
                      60;
              final color = here
                  ? blue
                  : passed
                  ? Colors.blueGrey
                  : blue;
              final label = here
                  ? 'Estás acá'
                  : passed
                  ? 'Ya pasaste'
                  : i == 0
                  ? 'Subís acá'
                  : i == stops.length - 1
                  ? 'Bajás acá'
                  : null;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    height: 64,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        if (i < stops.length - 1)
                          Positioned(
                            top: 22,
                            bottom: 0,
                            child: Container(
                              width: 2,
                              color: passed ? Colors.blueGrey.shade200 : pale,
                            ),
                          ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: here || passed ? color : Colors.white,
                            border: Border.all(color: color, width: 2),
                          ),
                          child: Icon(
                            here
                                ? Icons.my_location
                                : passed
                                ? Icons.check
                                : Icons.circle,
                            size: here || passed ? 14 : 7,
                            color: here || passed ? Colors.white : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.nombre,
                            style: TextStyle(
                              color: passed ? Colors.blueGrey : ink,
                              fontWeight:
                                  here || i == 0 || i == stops.length - 1
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          if (label != null)
                            Text(
                              label,
                              style: TextStyle(color: color, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
