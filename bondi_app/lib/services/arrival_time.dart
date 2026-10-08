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
