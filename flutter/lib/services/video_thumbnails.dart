import 'package:flutter/services.dart';

/// Generates a first-frame JPEG for an uploaded video.
///
/// The worker expects the client to supply the thumbnail (the web app posts one
/// to `/api/admin/refresh-thumbnails`, and `prepare-upload` hands back a
/// destination for it), so this is the counterpart of the native
/// `AVAssetImageGenerator` call in `ShiurUploader.swift`.
///
/// Implemented natively because Flutter has no built-in frame grabber and the
/// alternatives on pub are unmaintained.
class VideoThumbnails {
  const VideoThumbnails._();

  static const MethodChannel _channel =
      MethodChannel('beisanytime/video_thumbnail');

  /// Reads a frame at [seconds] and encodes it as JPEG.
  ///
  /// Returns `null` when the platform has no implementation or the frame could
  /// not be decoded — an upload without a thumbnail is still a valid upload.
  static Future<Uint8List?> fromVideo(
    String path, {
    double seconds = 1.0,
    int maxWidth = 1280,
  }) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'createThumbnail',
        <String, dynamic>{
          'path': path,
          'timeMs': (seconds * 1000).round(),
          'maxWidth': maxWidth,
        },
      );
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Duration of the media at [path], or 0 when it cannot be read.
  static Future<double> durationSeconds(String path) async {
    try {
      final millis = await _channel.invokeMethod<int>(
        'durationMs',
        <String, dynamic>{'path': path},
      );
      final value = millis ?? 0;
      return value > 0 ? value / 1000 : 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
}

/// True for the extensions the worker accepts as a video upload.
bool isVideoFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.m4v');
}

/// True for the extensions the worker accepts as an audio upload.
bool isAudioFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.mp3') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.aac');
}
