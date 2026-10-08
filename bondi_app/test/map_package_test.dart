import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bondi_app/services/map_package.dart';

void main() {
  late Directory root;
  final original = [137, 80, 78, 71, 13, 10, 26, 10];
  var bytes = original;
  var corrupt = false;
  Map<String, dynamic> manifest() => {
    'version': 1,
    'minZoom': 10,
    'maxZoom': 16,
    'tileSize': 256,
    'bounds': [-31.55, -64.35, -31.25, -64.05],
    'sha256': sha256.convert(bytes).toString(),
    'tiles': {
      '10/328/605': [0, bytes.length],
    },
  };
  setUp(() async {
    root = await Directory.systemTemp.createTemp('subite-map-test-');
    bytes = original;
    corrupt = false;
  });
  tearDown(() async => root.delete(recursive: true));
  MapPackage package() => MapPackage(
    directory: () async => root,
    source: Uri.parse('https://example.test/maps/'),
    client: MockClient(
      (request) async => request.url.path.endsWith('.json')
          ? http.Response(jsonEncode(manifest()), 200)
          : http.Response.bytes(corrupt ? [0, ...bytes.skip(1)] : bytes, 200),
    ),
  );

  test(
    'Verified download survives reopening without a network request',
    () async {
      final store = package();
      expect(await store.currentFiles(), isNull);
      expect(await store.download(), isTrue);
      final files = (await store.currentFiles())!;
      expect(await files.$2.readAsBytes(), original);
      final offline = MapPackage(
        directory: () async => root,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      expect((await offline.currentFiles())!.$2.path, files.$2.path);
      expect(await offline.download(), isFalse);
      expect(await files.$2.readAsBytes(), original);
      store.dispose();
      offline.dispose();
    },
  );
  test(
    'Corrupt update retains the previous package and removes partial file',
    () async {
      final store = package();
      expect(await store.download(), isTrue);
      final previous = (await store.currentFiles())!.$2;
      bytes = [1, 2, 3, 4, 5, 6, 7, 8, 9];
      corrupt = true;
      expect(await store.download(), isFalse);
      expect((await store.currentFiles())!.$2.path, previous.path);
      expect(await previous.readAsBytes(), original);
      expect(await File('${root.path}/maps/download.part').exists(), isFalse);
      store.dispose();
    },
  );
  test('Malformed index is rejected before it becomes active', () async {
    final store = MapPackage(
      directory: () async => root,
      client: MockClient((_) async {
        final m = manifest();
        m['tiles'] = {
          '10/0/0': [5, 8],
        };
        return http.Response(jsonEncode(m), 200);
      }),
    );
    expect(await store.download(), isFalse);
    expect(await store.currentFiles(), isNull);
    store.dispose();
  });
  test('A complete update switches both files together', () async {
    final store = package();
    expect(await store.download(), isTrue);
    final old = (await store.currentFiles())!.$2;
    bytes = [1, 2, 3, 4, 5, 6, 7, 8, 9];
    expect(await store.download(), isTrue);
    final current = (await store.currentFiles())!;
    expect(current.$2.path, isNot(old.path));
    expect(await current.$2.readAsBytes(), bytes);
    expect(
      jsonDecode(await current.$1.readAsString())['sha256'],
      sha256.convert(bytes).toString(),
    );
    expect(await old.readAsBytes(), original);
    store.dispose();
  });
  test(
    'Automatic sync waits for Wi-Fi and downloads when it becomes available',
    () async {
      final store = package();
      expect(await store.updateOnWifi(hasWifi: () async => false), isFalse);
      expect(await store.currentFiles(), isNull);
      expect(store.downloading, isFalse);
      expect(await store.updateOnWifi(hasWifi: () async => true), isTrue);
      expect(await (await store.currentFiles())!.$2.readAsBytes(), original);
      expect(store.revision, 1);
      store.dispose();
    },
  );
  test('Automatic checks are throttled and unchanged maps are not downloaded again', () async {
    final store = package();
    expect(await store.download(), isTrue);
    expect(await store.updateOnWifi(hasWifi: () async => true), isTrue);
    expect(store.received, 0);
    expect(store.revision, 1);
    expect(await store.updateOnWifi(hasWifi: () async => true), isFalse);
    store.dispose();
  });
  test(
    'Failed automatic update preserves the map and is not retried in a loop',
    () async {
      final store = package();
      expect(await store.download(), isTrue);
      final old = (await store.currentFiles())!.$2;
      bytes = [1, 2, 3, 4, 5, 6, 7, 8, 9];
      corrupt = true;
      expect(await store.updateOnWifi(hasWifi: () async => true), isFalse);
      expect((await store.currentFiles())!.$2.path, old.path);
      expect(await store.updateOnWifi(hasWifi: () async => true), isFalse);
      expect(await old.readAsBytes(), original);
      store.dispose();
    },
  );
}
