import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/post.dart';
import '../models/shiur.dart';
import '../models/user_profile.dart';

/// A failure carrying a message already suitable for display.
///
/// The worker answers failures with `{"error": "..."}`, and the native app
/// surfaced that text so a 401 read as "Not authorized — check your upload
/// password" rather than a bare status code.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Ticket returned by `/api/admin/prepare-upload` for a chunked R2 upload.
class UploadTicket {
  const UploadTicket({
    required this.r2Key,
    required this.uploadId,
    this.thumbnailUrl,
  });

  final String r2Key;
  final String uploadId;

  /// Where the generated thumbnail should be PUT (video uploads only).
  final String? thumbnailUrl;
}

class UploadPart {
  const UploadPart({required this.partNumber, required this.etag});

  final int partNumber;
  final String etag;
}

/// Talks to the same three workers the Swift app used.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  List<Shiur> _shiurCache = const <Shiur>[];

  void dispose() => _client.close();

  void invalidateCache() => _shiurCache = const <Shiur>[];

  // MARK: - Request plumbing

  /// Percent-encodes a query value the way the worker's `URLSearchParams`
  /// expects.
  ///
  /// `URLSearchParams` reads a literal `+` as a space, so plus signs must arrive
  /// escaped — which is why the native client post-processed its encoded query.
  static String encodeQueryComponent(String value) =>
      Uri.encodeComponent(value);

  Uri _url(
    String base, {
    String path = '',
    Map<String, String> query = const <String, String>{},
  }) {
    final uri = Uri.parse('$base$path');
    if (query.isEmpty) {
      return uri;
    }
    final entries = query.entries.toList()
      ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key));
    final encoded = entries
        .map((MapEntry<String, String> e) =>
            '${encodeQueryComponent(e.key)}=${encodeQueryComponent(e.value)}')
        .join('&');
    return uri.replace(query: encoded);
  }

  Future<dynamic> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..followRedirects = true;
    if (body != null) {
      request.bodyBytes = body is List<int> ? body : utf8.encode('$body');
    }

    late final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on Exception catch (error) {
      throw ApiException('Could not reach the server ($error)');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  String _errorMessage(http.Response response) {
    String? message;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final value = decoded['error'];
        if (value is String && value.isNotEmpty) {
          message = value;
        }
      }
    } on FormatException {
      message = null;
    }

    if (response.statusCode == 401) {
      if (message != null && message.isNotEmpty && message != 'Unauthorized') {
        return message;
      }
      return 'Not authorized — sign in again and check your upload password';
    }
    return message ?? 'Server error: ${response.statusCode}';
  }

  T _decode<T>(dynamic payload, String typeName) {
    if (payload is Map<String, dynamic> || payload is List<dynamic>) {
      return payload as T;
    }
    throw ApiException("Couldn't read the server's $typeName response");
  }

  Map<String, dynamic> _decodeObject(dynamic payload) {
    final value = _decode<dynamic>(payload, 'JSON object');
    if (value is Map<String, dynamic>) {
      return value;
    }
    throw const ApiException("Couldn't read the server's response");
  }

  List<dynamic> _decodeList(dynamic payload, String typeName) {
    final value = _decode<dynamic>(payload, typeName);
    if (value is List<dynamic>) {
      return value;
    }
    throw ApiException("Couldn't read the server's $typeName response");
  }

  // MARK: - Shiurim

  Future<List<Shiur>> getAllShiurim({bool useCache = true}) async {
    if (useCache && _shiurCache.isNotEmpty) {
      return _shiurCache;
    }
    final payload = await _send('GET', _url('${ApiConfig.mainApi}/api/all-shiurim'));
    final shiurim = _decodeList(payload, 'shiur list')
        .whereType<Map<String, dynamic>>()
        .map(Shiur.fromJson)
        .toList();
    shiurim.sort((Shiur a, Shiur b) => (b.date ?? '').compareTo(a.date ?? ''));
    _shiurCache = shiurim;
    return shiurim;
  }

  Future<Shiur> getShiur(String id) async {
    final payload = await _send(
      'GET',
      _url('${ApiConfig.mainApi}/api/shiurim/id/${Uri.encodeComponent(id)}'),
    );
    return Shiur.fromJson(_decodeObject(payload));
  }

  // MARK: - Community posts

  Future<List<Post>> getPosts() async {
    final payload = await _send('GET', _url('${ApiConfig.communityApi}/api/posts'));
    return _decodeList(payload, 'post list')
        .whereType<Map<String, dynamic>>()
        .map(Post.fromJson)
        .toList(growable: false);
  }

  /// The worker derives the author from the verified ID token, so only the
  /// content is sent.
  Future<void> createPost({
    required String content,
    required UserProfile user,
  }) async {
    await _send(
      'POST',
      _url('${ApiConfig.communityApi}/api/posts'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (user.idToken.isNotEmpty) 'Authorization': 'Bearer ${user.idToken}',
      },
      body: jsonEncode(<String, dynamic>{'content': content}),
    );
  }

  Future<void> deletePost({required int id, required UserProfile user}) async {
    await _send(
      'DELETE',
      _url('${ApiConfig.communityApi}/api/posts/$id'),
      headers: <String, String>{
        if (user.idToken.isNotEmpty) 'Authorization': 'Bearer ${user.idToken}',
      },
    );
  }

  // MARK: - Comments

  Future<List<Comment>> getComments(String shiurId) async {
    final payload = await _send(
      'GET',
      _url(
        '${ApiConfig.videoApi}/api/comments/${Uri.encodeComponent(shiurId)}',
      ),
    );
    return CommentResponse.fromJson(_decodeObject(payload)).comments;
  }

  Future<void> postComment({
    required String shiurId,
    required String text,
    required String email,
  }) async {
    await _send(
      'POST',
      _url(
        '${ApiConfig.videoApi}/api/comments/${Uri.encodeComponent(shiurId)}',
      ),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'X-User-Email': email,
      },
      body: jsonEncode(<String, String>{'text': text}),
    );
  }

  Future<void> deleteComment({
    required String shiurId,
    required String commentId,
    required String email,
  }) async {
    await _send(
      'DELETE',
      _url(
        '${ApiConfig.videoApi}/api/comments/'
        '${Uri.encodeComponent(shiurId)}/${Uri.encodeComponent(commentId)}',
      ),
      headers: <String, String>{'X-User-Email': email},
    );
  }

  // MARK: - Likes and views

  Future<LikesResponse> getLikes(String shiurId) async {
    final payload = await _send(
      'GET',
      _url('${ApiConfig.videoApi}/api/likes/${Uri.encodeComponent(shiurId)}'),
    );
    return LikesResponse.fromJson(_decodeObject(payload));
  }

  Future<void> toggleLike({
    required String shiurId,
    required String email,
  }) async {
    await _send(
      'POST',
      _url('${ApiConfig.videoApi}/api/likes/${Uri.encodeComponent(shiurId)}'),
      headers: <String, String>{'X-User-Email': email},
    );
  }

  Future<ViewsResponse> getViews(String shiurId) async {
    final payload = await _send(
      'GET',
      _url('${ApiConfig.videoApi}/api/views/${Uri.encodeComponent(shiurId)}'),
    );
    return ViewsResponse.fromJson(_decodeObject(payload));
  }

  /// Best-effort: a missing view count must never break the player.
  Future<void> incrementViews(String shiurId) async {
    try {
      await _send(
        'POST',
        _url('${ApiConfig.videoApi}/api/views/increment'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'id': shiurId}),
      );
    } on ApiException {
      // Counting a view is not worth interrupting playback for.
    }
  }

  // MARK: - Admin: chunked upload
  //
  // Every admin route on the worker requires `X-Upload-Password` plus the Google
  // identity, so both travel with each request.

  Map<String, String> _adminHeaders(
    AdminCredentials credentials, {
    bool json = false,
  }) {
    return <String, String>{
      'X-Upload-Password': credentials.password,
      'X-User-Email': credentials.email,
      'X-User-Name': credentials.name,
      if (credentials.idToken.isNotEmpty)
        'Authorization': 'Bearer ${credentials.idToken}',
      if (json) 'Content-Type': 'application/json',
    };
  }

  /// Starts a multipart upload and returns the R2 key, upload id and thumbnail
  /// destination.
  Future<UploadTicket> prepareUpload({
    required String title,
    required String rabbi,
    required String date,
    required String fileName,
    required AdminCredentials credentials,
  }) async {
    final payload = await _send(
      'POST',
      _url('${ApiConfig.mainApi}/api/admin/prepare-upload'),
      headers: _adminHeaders(credentials, json: true),
      body: jsonEncode(<String, String>{
        'title': title,
        'rabbi': rabbi,
        'date': date,
        'fileName': fileName,
      }),
    );
    final json = _decodeObject(payload);
    return UploadTicket(
      r2Key: json['r2Key'] as String? ?? '',
      uploadId: json['uploadId'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  /// Uploads one part and returns R2's ETag, which completion needs.
  Future<String> uploadPart({
    required String r2Key,
    required String uploadId,
    required int partNumber,
    required List<int> data,
    required AdminCredentials credentials,
  }) async {
    final payload = await _send(
      'PUT',
      _url(
        '${ApiConfig.mainApi}/api/admin/upload-part',
        query: <String, String>{
          'key': r2Key,
          'uploadId': uploadId,
          'partNumber': '$partNumber',
        },
      ),
      headers: <String, String>{
        ..._adminHeaders(credentials),
        'Content-Type': 'application/octet-stream',
      },
      body: data,
      timeout: const Duration(seconds: 180),
    );
    final json = _decodeObject(payload);
    return json['etag'] as String? ?? '';
  }

  Future<void> completeUpload({
    required String r2Key,
    required String uploadId,
    required List<UploadPart> parts,
    required AdminCredentials credentials,
  }) async {
    await _send(
      'POST',
      _url('${ApiConfig.mainApi}/api/admin/complete-upload'),
      headers: _adminHeaders(credentials, json: true),
      body: jsonEncode(<String, dynamic>{
        'r2Key': r2Key,
        'uploadId': uploadId,
        'parts': parts
            .map((UploadPart part) => <String, dynamic>{
                  'partNumber': part.partNumber,
                  'etag': part.etag,
                })
            .toList(),
      }),
      timeout: const Duration(seconds: 120),
    );
  }

  /// Uploads a JPEG thumbnail to the destination the worker prepared for it.
  Future<void> uploadThumbnail({
    required String url,
    required List<int> jpegBytes,
    required AdminCredentials credentials,
  }) async {
    await _send(
      'PUT',
      Uri.parse(url),
      headers: <String, String>{
        ..._adminHeaders(credentials),
        'Content-Type': 'image/jpeg',
      },
      body: jpegBytes,
      timeout: const Duration(seconds: 120),
    );
  }

  // MARK: - Admin: library management

  Future<List<UploadLog>> getUploadLogs({
    int limit = 50,
    required AdminCredentials credentials,
  }) async {
    final payload = await _send(
      'GET',
      _url(
        '${ApiConfig.mainApi}/api/admin/upload-logs',
        query: <String, String>{'limit': '$limit'},
      ),
      headers: _adminHeaders(credentials),
    );
    return _decodeList(payload, 'upload log list')
        .whereType<Map<String, dynamic>>()
        .map(UploadLog.fromJson)
        .toList(growable: false);
  }

  /// Deletes by library id, which for R2 uploads is the object key.
  Future<void> deleteShiur({
    required String id,
    required AdminCredentials credentials,
  }) async {
    await _send(
      'DELETE',
      _url('${ApiConfig.mainApi}/api/admin/shiurim/${Uri.encodeComponent(id)}'),
      headers: _adminHeaders(credentials),
      timeout: const Duration(seconds: 60),
    );
  }
}
