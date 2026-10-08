import '../models/models.dart';

class RouteCatalogResult {
  final List<(Linea, Ruta, Traza)> routes;
  final int unavailable;
  RouteCatalogResult(this.routes, this.unavailable);
}

/// Bounded concurrency and a deadline; failed routes do not strand the UI.
Future<RouteCatalogResult> loadRouteCatalog(
  List<Linea> lines,
  Future<Traza?> Function(Linea, Ruta) fetch, {
  required bool Function() keepGoing,
  required void Function(int, int) onProgress,
  Duration budget = const Duration(seconds: 45),
}) async {
  final jobs = [
    for (final line in lines)
      for (final route in line.rutas) (line, route),
  ];
  final result = <(Linea, Ruta, Traza)>[];
  final deadline = DateTime.now().add(budget);
  int next = 0, complete = 0;
  Future<void> worker() async {
    while (keepGoing() &&
        next < jobs.length &&
        DateTime.now().isBefore(deadline)) {
      final job = jobs[next++];
      Traza? trace;
      try {
        final remaining = deadline.difference(DateTime.now());
        final timeout = remaining < const Duration(seconds: 7)
            ? remaining
            : const Duration(seconds: 7);
        trace = await fetch(job.$1, job.$2).timeout(timeout);
      } catch (_) {}
      if (!keepGoing()) return;
      if (trace != null) result.add((job.$1, job.$2, trace));
      onProgress(++complete, jobs.length);
    }
  }

  await Future.wait([worker(), worker(), worker()]);
  return RouteCatalogResult(result, jobs.length - result.length);
}
