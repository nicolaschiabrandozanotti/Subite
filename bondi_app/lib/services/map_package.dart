import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void validateMapIndex(Map<String, dynamic> manifest, int length) {
  if (manifest['version'] != 1 ||
      manifest['minZoom'] != 10 ||
      manifest['maxZoom'] != 16 ||
      manifest['tileSize'] != 256) {
    throw const FormatException('Formato de mapa incompatible');
  }
  final bounds = manifest['bounds'] as List;
  if (bounds.length != 4 ||
      bounds.any((v) => v is! num || !v.isFinite) ||
      bounds[0] >= bounds[2] ||
      bounds[1] >= bounds[3]) {
    throw const FormatException('Limites de mapa invalidos');
  }
  var end = 0;
  final tiles = manifest['tiles'] as Map<String, dynamic>;
  if (tiles.isEmpty || tiles.length > 20000) {
    throw const FormatException('Indice de mapa invalido');
  }
  for (final entry in tiles.entries) {
    if (!RegExp(r'^\d+/\d+/\d+$').hasMatch(entry.key)) {
      throw const FormatException('Coordenada de mapa invalida');
    }
    final range = entry.value as List;
    if (range.length != 2 ||
        range[0] != end ||
        range[1] is! int ||
        range[1] < 8) {
      throw const FormatException('Indice de mapa incompleto');
    }
    end += range[1] as int;
    if (end > length) throw const FormatException('Mapa truncado');
  }
  if (end != length) throw const FormatException('Tamano de mapa incorrecto');
}

/// Only a complete, verified generation becomes active. Downloads never touch
/// the current package; the small pointer is replaced after both files exist.
class MapPackage extends ChangeNotifier {
  MapPackage({
    Future<Directory> Function()? directory,
    http.Client? client,
    Uri? source,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _client = client ?? http.Client(),
       _source =
           source ??
           Uri.parse(
             'https://raw.githubusercontent.com/nicolaschiabrandozanotti/Subite/feat/support-subite/bondi_app/assets/maps/',
           );
  static final instance = MapPackage();
  final Future<Directory> Function() _directory;
  final http.Client _client;
  final Uri _source;
  bool downloading = false;
  int received = 0;
  int? total;
  String? error;
  Future<Directory> _root() async {
    final root = Directory('${(await _directory()).path}/maps');
    await root.create(recursive: true);
    return root;
  }

  Future<(File, File)?> currentFiles() async {
    final root = await _root();
    final pointer = File('${root.path}/active.json');
    if (!await pointer.exists()) return null;
    final hash = jsonDecode(await pointer.readAsString())['sha256'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Referencia de mapa invalida');
    }
    return (File('${root.path}/$hash.json'), File('${root.path}/$hash.tiles'));
  }

  Future<bool> download() async {
    if (downloading) return false;
    downloading = true;
    error = null;
    received = 0;
    total = null;
    notifyListeners();
    File? partial;
    IOSink? sink;
    try {
      final response = await _client
          .get(_source.resolve('cordoba.tiles.json'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
        throw const FormatException('No se pudo obtener el indice');
      }
      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final hash = manifest['sha256'] as String;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException('Checksum de mapa invalido');
      }
      final entries = (manifest['tiles'] as Map<String, dynamic>).values;
      final last = entries.last as List;
      total = (last[0] as int) + (last[1] as int);
      if (total! > 100000000) {
        throw const FormatException('Mapa demasiado grande');
      }
      validateMapIndex(manifest, total!);
      final root = await _root();
      final current = await currentFiles();
      if (current != null &&
          current.$2.path == '${root.path}/$hash.tiles' &&
          await current.$2.exists()) {
        return true;
      }
      partial = File('${root.path}/download.part');
      sink = partial.openWrite();
      final stream = await _client
          .send(http.Request('GET', _source.resolve('cordoba.tiles')))
          .timeout(const Duration(seconds: 30));
      if (stream.statusCode != 200) {
        throw const HttpException('No se pudo descargar el mapa');
      }
      var lastUpdate = DateTime.now();
      await for (final chunk in stream.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > total!) throw const FormatException('Tamano inesperado');
        sink.add(chunk);
        if (DateTime.now().difference(lastUpdate).inMilliseconds > 150) {
          lastUpdate = DateTime.now();
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != total) throw const FormatException('Descarga incompleta');
      final path = partial.path;
      final actual = await Isolate.run(
        () async => (await sha256.bind(File(path).openRead()).first).toString(),
      );
      if (actual != hash) {
        throw const FormatException('El mapa descargado esta danado');
      }
      await partial.rename('${root.path}/$hash.tiles');
      partial = null;
      await File('${root.path}/$hash.json')
          .writeAsString(response.body, flush: true);
      final pointer = File('${root.path}/active.next');
      await pointer.writeAsString(jsonEncode({'sha256': hash}), flush: true);
      await pointer.rename('${root.path}/active.json');
      return true;
    } catch (_) {
      error = 'No se pudo descargar el mapa. Conectate a Wi-Fi y reintenta.';
      return false;
    } finally {
      await sink?.close();
      if (partial != null && await partial.exists()) await partial.delete();
      downloading = false;
      notifyListeners();
    }
  }
}
