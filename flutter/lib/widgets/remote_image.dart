import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

/// An image loaded from a URL that accepts any successful response.
///
/// Every still in the library comes from the worker's `/api/video-proxy`, which
/// answers a whole-file request with `206 Partial Content` because it forwards
/// the request's `Range` header to R2. Flutter's [NetworkImage] rejects anything
/// that is not exactly `200`, so each thumbnail silently fell back to the
/// designed artwork even though the JPEG was sitting in the bucket. This fetches
/// the bytes itself and treats the whole 2xx range as success.
///
/// It also decodes `data:` URLs, which older rows use for their thumbnails, and
/// is keyed by URL so Flutter's image cache still dedupes and retains results.
@immutable
class RemoteImage extends ImageProvider<RemoteImage> {
  const RemoteImage(this.url, {this.scale = 1.0});

  /// The absolute image URL, or a `data:image/…;base64,…` URL.
  final String url;
  final double scale;

  /// Shared client, so connections to the worker are reused across thumbnails.
  static final http.Client _client = http.Client();

  @override
  Future<RemoteImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<RemoteImage>(this);

  @override
  ImageStreamCompleter loadImage(RemoteImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _codec(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('URL: ${key.url}'),
      ],
    );
  }

  Future<ui.Codec> _codec(RemoteImage key, ImageDecoderCallback decode) async {
    final bytes = await _fetch(key.url);
    if (bytes.isEmpty) {
      throw StateError('Empty image response');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  static Future<Uint8List> _fetch(String url) async {
    if (url.startsWith('data:')) {
      return _decodeDataUrl(url);
    }
    final uri = Uri.parse(url);
    final response = await _client.get(uri);
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw NetworkImageLoadException(statusCode: status, uri: uri);
    }
    return response.bodyBytes;
  }

  static Uint8List _decodeDataUrl(String url) {
    final comma = url.indexOf(',');
    if (comma < 0 || !url.substring(0, comma).contains('base64')) {
      return Uint8List(0);
    }
    try {
      return base64Decode(url.substring(comma + 1).trim());
    } on FormatException {
      return Uint8List(0);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'RemoteImage("$url", scale: $scale)';
}
