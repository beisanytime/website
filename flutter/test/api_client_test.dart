import 'dart:convert';

import 'package:beisanytime/models/user_profile.dart';
import 'package:beisanytime/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientFor(
  Future<http.Response> Function(http.Request request) handler,
) =>
    ApiClient(client: MockClient(handler));

void main() {
  test('sorts the library newest first', () async {
    final api = clientFor((http.Request request) async {
      expect(request.url.path, '/api/all-shiurim');
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'id': 'old', 'title': 'Old', 'date': '2025-01-01'},
          <String, dynamic>{'id': 'new', 'title': 'New', 'date': '2026-05-01'},
          <String, dynamic>{'id': 'mid', 'title': 'Mid', 'date': '2026-02-01'},
        ]),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final shiurim = await api.getAllShiurim();
    expect(shiurim.map((dynamic s) => s.id), <String>['new', 'mid', 'old']);
  });

  test('serves the cached library on a second call', () async {
    var calls = 0;
    final api = clientFor((http.Request request) async {
      calls++;
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'id': '1', 'title': 'Parsha'},
        ]),
        200,
      );
    });

    await api.getAllShiurim();
    await api.getAllShiurim();
    expect(calls, 1);

    api.invalidateCache();
    await api.getAllShiurim();
    expect(calls, 2);
  });

  test('treats a 2xx with an unexpected shape as a read failure', () async {
    final api = clientFor(
      (http.Request request) async => http.Response('"just a string"', 200),
    );

    await expectLater(
      api.getPosts(),
      throwsA(isA<ApiException>()),
    );
  });

  test('surfaces the worker error text on a 401', () async {
    final api = clientFor(
      (http.Request request) async =>
          http.Response(jsonEncode(<String, String>{'error': 'Bad password'}), 401),
    );

    expect(
      () => api.getUploadLogs(
        credentials: const AdminCredentials(
          email: 'a@b.c',
          name: 'A',
          password: 'nope',
        ),
      ),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.isUnauthorized, 'isUnauthorized', true)
            .having((ApiException e) => e.message, 'message', 'Bad password'),
      ),
    );
  });

  test('explains a bare 401 instead of showing a status code', () async {
    final api = clientFor(
      (http.Request request) async => http.Response('', 401),
    );

    await expectLater(
      api.getLikes('x'),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.message,
          'message',
          contains('upload password'),
        ),
      ),
    );
  });

  test('reports a server error with its code', () async {
    final api = clientFor(
      (http.Request request) async => http.Response('', 500),
    );

    await expectLater(
      api.getPosts(),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.message, 'message', 'Server error: 500'),
      ),
    );
  });

  test('sends admin headers on every admin request', () async {
    final seen = <http.Request>[];
    final api = clientFor((http.Request request) async {
      seen.add(request);
      if (request.url.path.endsWith('prepare-upload')) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'r2Key': 'key',
            'uploadId': 'uid',
            'thumbnailUrl': 'https://example.test/thumb',
          }),
          200,
        );
      }
      if (request.url.path.endsWith('upload-part')) {
        return http.Response(
          jsonEncode(<String, dynamic>{'partNumber': 1, 'etag': 'e1'}),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    const credentials = AdminCredentials(
      email: 'admin@example.com',
      name: 'Admin',
      password: 'secret',
    );

    final ticket = await api.prepareUpload(
      title: 'Parsha',
      rabbi: 'Rabbi Hartman',
      date: '2026-10-14',
      fileName: 'a.mov',
      credentials: credentials,
    );
    expect(ticket.r2Key, 'key');
    expect(ticket.thumbnailUrl, 'https://example.test/thumb');

    final etag = await api.uploadPart(
      r2Key: ticket.r2Key,
      uploadId: ticket.uploadId,
      partNumber: 1,
      data: <int>[1, 2, 3],
      credentials: credentials,
    );
    expect(etag, 'e1');

    for (final request in seen) {
      expect(request.headers['X-Upload-Password'], 'secret');
      expect(request.headers['X-User-Name'], 'Admin');
    }
  });

  test('escapes plus signs in query values', () async {
    Uri? seen;
    final api = clientFor((http.Request request) async {
      seen = request.url;
      return http.Response(
        jsonEncode(<String, dynamic>{'partNumber': 1, 'etag': 'e'}),
        200,
      );
    });

    await api.uploadPart(
      r2Key: 'a+b.mov',
      uploadId: 'uid',
      partNumber: 1,
      data: <int>[1],
      credentials: const AdminCredentials(
        email: 'a@b.c',
        name: 'A',
        password: 'p',
      ),
    );

    // URLSearchParams on the worker reads a literal "+" as a space, so the
    // value has to arrive percent-encoded.
    expect(seen!.query, contains('%2B'));
    expect(seen!.query, isNot(contains('a+b')));
  });

  test('parses comments and milliseconds timestamps', () async {
    final api = clientFor(
      (http.Request request) async => http.Response(
        jsonEncode(<String, dynamic>{
          'comments': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c1',
              'text': 'Yasher koach',
              'email': 'a@b.c',
              'displayName': 'Someone',
              'createdAt': 1770000000000,
            },
          ],
        }),
        200,
      ),
    );

    final comments = await api.getComments('2026-10-14-film.mov');
    expect(comments, hasLength(1));
    expect(comments.first.authorLabel, 'Someone');
    expect(comments.first.formattedDate, isNotEmpty);
  });

  test('tolerates a comment with no display name', () async {
    final api = clientFor(
      (http.Request request) async => http.Response(
        jsonEncode(<String, dynamic>{
          'comments': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c1',
              'text': 'hi',
              'email': 'a@b.c',
              'createdAt': 0,
            },
          ],
        }),
        200,
      ),
    );

    final comments = await api.getComments('x');
    expect(comments.first.authorLabel, 'a@b.c');
  });

  test('view counting never throws', () async {
    final api = clientFor(
      (http.Request request) async => http.Response('boom', 500),
    );
    // A failed view increment must not interrupt playback.
    await api.incrementViews('x');
  });
}
