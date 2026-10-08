import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'api_service.dart';

/// Parses the provider's Córdoba wall-clock arrival time, not vehicle delay.
int? arrivalSeconds(String value, DateTime cordobaNow) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$')
      .firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match[1]!),
      minute = int.parse(match[2]!),
      second = int.parse(match[3] ?? '0');
  if (hour > 23 || minute > 59 || second > 59) return null;
  var delta =
      hour * 3600 +
      minute * 60 +
      second -
      (cordobaNow.hour * 3600 + cordobaNow.minute * 60 + cordobaNow.second);
  if (cordobaNow.hour == 23 && hour == 0) delta += 86400;
  return delta >= 0 && delta <= 4800 ? delta : null;
}

int? stopArrivalSeconds(Map<String, dynamic> item, DateTime now) {
  // The adjusted stop arrival has seconds. Vehicle delay and distance are not ETA.
  return arrivalSeconds('${item['horaTeoricaAjustada'] ?? ''}', now) ??
      arrivalSeconds('${item['hora_salida'] ?? ''}', now);
}

class ArrivalAlert extends ChangeNotifier {
  static const channel = MethodChannel('bondi/notifications');
  Timer? _timer;
  int _generation = 0;
  bool active = false, _disposed = false;
  bool _polling = false;
  int minutes = 10;
  String status = 'Elegí un viaje y la línea para activar el aviso.';
  String? firedMessage;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    active = false;
    firedMessage = null;
    status = 'Aviso de llegada desactivado.';
    _changed();
  }

  Future<void> start({
    required String stop,
    required String stopName,
    required String route,
    required String line,
    required int threshold,
    int? vehicle,
  }) async {
    cancel();
    final version = _generation;
    minutes = threshold;
    bool notifications = false;
    try {
      if (Platform.isAndroid)
        notifications =
            await channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {}
    if (_disposed || version != _generation) return;
    active = true;
    status = notifications
        ? 'Consultando próximas llegadas…'
        : 'Mantené la app abierta para recibir el aviso.';
    _changed();
    Future<void> poll() async {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (_polling || !active || version != _generation) return;
      _polling = true;
      try {
        final data = await ApiService.fetchArrivals(stop);
        if (_disposed || version != _generation || !active) return;
        final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
        int? nearest, bus;
        for (final item in data) {
          final id = int.tryParse('${item['coche']}');
          if (id == null ||
              id <= 0 ||
              (vehicle != null && id != vehicle) ||
              '${item['ruta']}' != route ||
              '${item['linea']}' != line)
            continue;
          final seconds = stopArrivalSeconds(item, now);
          if (seconds != null && (nearest == null || seconds < nearest)) {
            nearest = seconds;
            bus = id;
          }
        }
        status = nearest == null
            ? 'Todavía no hay un horario disponible. Te avisamos cuando se actualice.'
            : 'Interno $bus · llegada estimada en ${(nearest / 60).ceil()} min';
        if (nearest != null && nearest <= minutes * 60) {
          active = false;
          _timer?.cancel();
          firedMessage =
              'Interno $bus: llegada estimada en ${(nearest / 60).ceil()} min a $stopName.';
          final notificationBody = firedMessage;
          _changed();
          if (notifications && Platform.isAndroid) {
            await channel.invokeMethod('show', {
              'title': 'Subite · Se acerca tu colectivo',
              'body': notificationBody,
            });
          } else {
            await SystemSound.play(SystemSoundType.alert);
            await HapticFeedback.vibrate();
          }
        }
      } catch (_) {
        if (!_disposed && version == _generation && active)
          status = 'No pudimos actualizar el horario. Volvemos a intentar…';
      } finally {
        _polling = false;
        _changed();
      }
    }

    await poll();
    if (!_disposed && version == _generation && active)
      _timer = Timer.periodic(const Duration(seconds: 20), (_) => poll());
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }
}
