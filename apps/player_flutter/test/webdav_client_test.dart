import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_flutter/main.dart';

void main() {
  test('openlist lists files and resolves playback links', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/auth/login') {
        expect(jsonDecode(body)['otp_code'], '123456');
        request.response.write(jsonEncode({
          'code': 200,
          'data': {'token': 'token-1'},
        }));
      } else if (request.uri.path == '/api/fs/list') {
        expect(request.headers.value('authorization'), 'token-1');
        expect(jsonDecode(body)['path'], '/');
        request.response.write(jsonEncode({
          'code': 200,
          'data': {
            'content': [
              {'name': 'Shows', 'is_dir': true, 'size': 0},
              {'name': 'Movie.mp4', 'is_dir': false, 'size': 42, 'sign': 's 1'},
            ],
          },
        }));
      } else if (request.uri.path == '/api/fs/get') {
        expect(jsonDecode(body)['path'], '/Movie.mp4');
        request.response.write(jsonEncode({
          'code': 200,
          'data': {
            'url': 'https://cdn.example/Movie.mp4',
            'header': {'Referer': 'https://openlist.example/'},
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'code': 404}));
      }
      await request.response.close();
    });

    try {
      final source = MediaSourceConfig.openlist(
        id: 'openlist',
        name: 'OpenList',
        baseUrl: 'http://${server.address.host}:${server.port}',
        username: 'admin',
        password: 'secret',
        otpCode: '123456',
        directory: '/',
      );
      final client = OpenlistClient.fromSource(source);

      final entries = await client.list('/');

      expect(entries.map((entry) => entry.path), ['/Shows/', '/Movie.mp4']);
      expect(entries.last.url, contains('/d/Movie.mp4?sign=s+1'));
      final item = MediaItem.remote(source: source, entry: entries.last);
      expect(item.type, SourceType.openlist);
      expect(item.uri, '/Movie.mp4');

      final playback = await client.playback(item);
      expect(playback.uri, 'https://cdn.example/Movie.mp4');
      expect(playback.headers, {'Referer': 'https://openlist.example/'});
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

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
