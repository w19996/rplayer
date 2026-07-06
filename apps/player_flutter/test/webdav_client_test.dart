import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_flutter/main.dart';

void main() {
  test('webdav file transfer streams progress', () async {
    final payload = List<int>.generate(256 * 1024, (index) => index % 251);
    var stored = <int>[];
    final dir = await Directory.systemTemp.createTemp('rplayer-webdav-test-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      if (request.method == 'PUT') {
        stored = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'GET') {
        request.response.contentLength = stored.length;
        request.response.add(stored);
      } else {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });

    try {
      final client = WebdavClient.fromSource(MediaSourceConfig.webdav(
        id: 'sync',
        name: 'sync',
        baseUrl: 'http://${server.address.host}:${server.port}/',
        username: '',
        password: '',
        directory: '/',
      ));
      final source = File('${dir.path}/source.sqlite');
      final target = File('${dir.path}/target.sqlite');
      await source.writeAsBytes(payload);

      final uploadProgress = <int>[];
      await client.putFile('/Player/metadata.sqlite', source,
          onProgress: (done, total) {
        expect(total, payload.length);
        uploadProgress.add(done);
      });
      expect(stored, payload);
      expect(uploadProgress.last, payload.length);

      final downloadProgress = <int>[];
      await client.getFile('/Player/metadata.sqlite', target,
          onProgress: (done, total) {
        expect(total, payload.length);
        downloadProgress.add(done);
      });
      expect(await target.readAsBytes(), payload);
      expect(downloadProgress.last, payload.length);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
