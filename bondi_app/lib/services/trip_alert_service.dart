import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';

class ProximityAlert {
  final LatLng target;
  final double radius;
  int _nearSamples = 0;
  DateTime? _previous;
  bool fired = false;
  ProximityAlert(this.target, this.radius);
  bool update(
    LatLng position,
    double accuracy,
    DateTime timestamp,
    DateTime now,
  ) {
    if (fired ||
        accuracy < 0 ||
        accuracy > 100 ||
        now.difference(timestamp).inSeconds > 15 ||
        timestamp.isAfter(now.add(const Duration(seconds: 2))))
      return false;
    if (_previous != null && !timestamp.isAfter(_previous!)) return false;
    _previous = timestamp;
    final distance = const Distance()(position, target);
    _nearSamples = distance + accuracy <= radius ? _nearSamples + 1 : 0;
    if (_nearSamples < 2) return false;
    fired = true;
    return true;
  }
}

class TripAlertService extends ChangeNotifier {
  static const _notifications = MethodChannel('bondi/notifications');
  StreamSubscription<Position>? _subscription;
  ProximityAlert? _detector;
  Parada? target;
  double radius = 300;
  double? distance;
  bool active = false;
  bool fired = false;
  bool systemNotifications = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _notificationPermission() async {
    if (!Platform.isAndroid) return false;
    return await _notifications.invokeMethod<bool>('requestPermission') ??
        false;
  }

  Future<void> start(Parada stop, double meters) async {
    await stopWatching();
    final version = ++_generation;
    error = null;
    fired = false;
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw Exception('Activá la ubicación del celular para usar el aviso.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw Exception('Hace falta permiso de ubicación para avisarte.');
      systemNotifications = await _notificationPermission();
      if (_disposed || version != _generation) return;
      target = stop;
      radius = meters;
      distance = null;
      _detector = ProximityAlert(stop.position, meters);
      final LocationSettings settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: const Duration(seconds: 5),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'Subite · Aviso de bajada activo',
                notificationText: 'Siguiendo tu ubicación hasta el punto elegido. Podés cancelar en Alertas.',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            );
      active = true;
      _changed();
      _subscription = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
            (position) async {
              if (_disposed || version != _generation || !active) return;
              distance = const Distance()(
                LatLng(position.latitude, position.longitude),
                stop.position,
              );
              if (_detector!.update(
                LatLng(position.latitude, position.longitude),
                position.accuracy,
                position.timestamp,
                DateTime.now(),
              )) {
                active = false;
                fired = true;
                await _subscription?.cancel();
                if (_disposed || version != _generation) return;
                _subscription = null;
                _changed();
                await _deliver(
                  'Estás cerca de ${stop.nombre}. Revisá si ya tenés que bajar.',
                );
              } else {
                _changed();
              }
            },
            onError: (_) {
              if (version == _generation) {
                error = 'No podemos obtener tu ubicación. Activala y volvé a encender el aviso.';
                stopWatching();
              }
            },
          );
    } catch (e) {
      if (_disposed || version != _generation) return;
      active = false;
      error = e.toString().replaceFirst('Exception: ', '');
      _changed();
    }
  }

  Future<void> _deliver(String body) async {
    try {
      if (systemNotifications && Platform.isAndroid) {
        await _notifications.invokeMethod('show', {
          'title': 'Subite · Preparáte para bajar',
          'body': body,
        });
      } else {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.vibrate();
      }
    } catch (_) {
      error = 'No pudimos emitir el sonido. Revisá el aviso en la app.';
      _changed();
    }
  }

  Future<void> testSound() async {
    try {
      systemNotifications = await _notificationPermission();
      await _deliver(
        'Este es un aviso de prueba. No corresponde a una llegada real.',
      );
      _changed();
    } catch (_) {
      error = 'No pudimos emitir la notificación de prueba.';
      _changed();
    }
  }

  Future<void> stopWatching() async {
    _generation++;
    active = false;
    distance = null;
    await _subscription?.cancel();
    _subscription = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }
}
