import 'package:flutter_test/flutter_test.dart';
import 'package:bondi_app/services/arrival_time.dart';

void main() {
  test(
    'Stop ETA uses adjusted seconds and ignores conflicting arriving label',
    () {
      final now = DateTime(2026, 10, 7, 17, 0, 30);
      expect(
        stopArrivalSeconds({
          'horaTeoricaAjustada': '17:15:30',
          'hora_salida': '17:15',
          'proximo': 'Llegando',
          'dist_parada': 250,
        }, now),
        900,
      );
      expect(stopArrivalSeconds({'hora_salida': '17:07'}, now), 390);
      expect(
        stopArrivalSeconds({'proximo': 'Llegando', 'dist_parada': 10}, now),
        isNull,
      );
    },
  );
  test('Arrival times reject delay labels and expired times', () {
    final now = DateTime(2026, 10, 7, 10, 0);
    expect(arrivalSeconds('10:05', now), 300);
    expect(arrivalSeconds('09:59', now), isNull);
    expect(arrivalSeconds('A tiempo', now), isNull);
    expect(arrivalSeconds('25:00', now), isNull);
    expect(arrivalSeconds('12:00', now), isNull);
  });
  test('Midnight arrivals retain a positive near-future interval', () {
    expect(arrivalSeconds('00:04', DateTime(2026, 10, 7, 23, 59)), 300);
  });
}
