import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bondi_app/services/trip_alert_service.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);
  const target = LatLng(-31.44, -64.19);
  test('Two fresh accurate nearby positions trigger once', () {
    final alert = ProximityAlert(target, 300);
    expect(alert.update(target, 20, now, now), isFalse);
    expect(
      alert.update(
        target,
        20,
        now.add(const Duration(seconds: 5)),
        now.add(const Duration(seconds: 5)),
      ),
      isTrue,
    );
    expect(
      alert.update(
        target,
        20,
        now.add(const Duration(seconds: 10)),
        now.add(const Duration(seconds: 10)),
      ),
      isFalse,
    );
  });
  test('Stale, duplicate and inaccurate positions cannot trigger', () {
    final alert = ProximityAlert(target, 300);
    expect(
      alert.update(target, 20, now.subtract(const Duration(seconds: 30)), now),
      isFalse,
    );
    expect(alert.update(target, 200, now, now), isFalse);
    expect(alert.update(target, 20, now, now), isFalse);
    expect(alert.update(target, 20, now, now), isFalse);
    expect(alert.fired, isFalse);
  });
  test('An outside reading clears the proximity confirmation', () {
    final alert = ProximityAlert(target, 300);
    expect(alert.update(target, 20, now, now), isFalse);
    expect(
      alert.update(
        const LatLng(-31.4, -64.19),
        20,
        now.add(const Duration(seconds: 5)),
        now.add(const Duration(seconds: 5)),
      ),
      isFalse,
    );
    expect(
      alert.update(
        target,
        20,
        now.add(const Duration(seconds: 10)),
        now.add(const Duration(seconds: 10)),
      ),
      isFalse,
    );
  });
}
