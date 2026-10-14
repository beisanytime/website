import 'dart:io';
import 'dart:typed_data';

import '../config.dart';
import '../models/user_profile.dart';
import 'api_client.dart';

/// A file chosen for upload, plus how to interpret it.
class UploadSelection {
  const UploadSelection({
    required this.path,
    required this.fileName,
    required this.isVideo,
    this.isTemporary = false,
  });

  final String path;
  final String fileName;
  final bool isVideo;

  /// Photo-library imports are copied into the app's temp directory and must be
  /// cleaned up after the upload.
  final bool isTemporary;
}

/// Everything needed to publish one shiur.
class ShiurUploadRequest {
  const ShiurUploadRequest({
    required this.selection,
    required this.title,
    required this.rabbi,
    required this.date,
    this.thumbnailJpeg,
  });

  final UploadSelection selection;
  final String title;
  final String rabbi;
  final String date;

  /// First-frame JPEG for video uploads; the library expects one for video.
  final Uint8List? thumbnailJpeg;
}

class UploadFailure implements Exception {
  const UploadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Publishes a shiur to R2 using the worker's chunked multipart flow.
///
/// The web app and the native app upload 10 MB parts four at a time; this keeps
/// that window while reading each chunk straight off disk, so multi-gigabyte
/// videos never land in memory.
class ShiurUploader {
  ShiurUploader({required this.api});

  final ApiClient api;

  static const int concurrency = 4;

  Future<UploadTicket> upload({
    required ShiurUploadRequest request,
    required AdminCredentials credentials,
    required void Function(double fraction, String status) onProgress,
  }) async {
    final selection = request.selection;
    final file = File(selection.path);

    try {
      final size = await file.length();
      if (size <= 0) {
        throw const UploadFailure('That file is empty');
      }

      // Step 1: the worker creates the multipart upload and returns the R2 key.
      onProgress(0.02, 'Preparing upload…');
      final ticket = await api.prepareUpload(
        title: request.title,
        rabbi: request.rabbi,
        date: request.date,
        fileName: selection.fileName,
        credentials: credentials,
      );

      // Step 2: push the parts concurrently, a bounded window at a time.
      const chunkSize = ApiConfig.uploadChunkSize;
      final totalParts = size <= 0 ? 1 : ((size + chunkSize - 1) ~/ chunkSize);
      final uploadedParts = <UploadPart>[];

      var nextPartIndex = 0;
      while (nextPartIndex < totalParts) {
        final end =
            (nextPartIndex + concurrency) < totalParts ? nextPartIndex + concurrency : totalParts;
        final batch = <int>[
          for (int i = nextPartIndex; i < end; i++) i,
        ];
        nextPartIndex = end;

        final results = await Future.wait(batch.map((int partIndex) async {
          final partNumber = partIndex + 1;
          final offset = partIndex * chunkSize;
          final length =
              (size - offset) < chunkSize ? (size - offset) : chunkSize;

          final chunk = await _readChunk(selection.path, offset, length);
          final etag = await api.uploadPart(
            r2Key: ticket.r2Key,
            uploadId: ticket.uploadId,
            partNumber: partNumber,
            data: chunk,
            credentials: credentials,
          );
          return UploadPart(partNumber: partNumber, etag: etag);
        }));

        uploadedParts.addAll(results);
        final fraction = nextPartIndex / totalParts;
        onProgress(
          0.05 + fraction * 0.85,
          'Uploading $nextPartIndex/$totalParts parts…',
        );
      }

      // Step 3: finalize. R2 wants every part sorted by part number.
      uploadedParts.sort(
        (UploadPart a, UploadPart b) => a.partNumber.compareTo(b.partNumber),
      );
      onProgress(0.93, 'Finalizing…');
      await api.completeUpload(
        r2Key: ticket.r2Key,
        uploadId: ticket.uploadId,
        parts: uploadedParts,
        credentials: credentials,
      );

      // Step 4: the thumbnail goes through the small-file proxy.
      final thumbnail = request.thumbnailJpeg;
      final thumbnailUrl = ticket.thumbnailUrl;
      if (thumbnail != null && thumbnailUrl != null) {
        onProgress(0.97, 'Uploading thumbnail…');
        await api.uploadThumbnail(
          url: thumbnailUrl,
          jpegBytes: thumbnail,
          credentials: credentials,
        );
      }

      onProgress(1, 'Done');
      return ticket;
    } finally {
      if (selection.isTemporary) {
        await _deleteQuietly(file);
      }
    }
  }

  /// Reads one part straight from disk so the whole video never has to fit in
  /// memory.
  Future<Uint8List> _readChunk(String path, int offset, int length) async {
    final handle = await File(path).open();
    try {
      await handle.setPosition(offset);
      final builder = BytesBuilder(copy: false);
      var remaining = length;
      while (remaining > 0) {
        final chunk = await handle.read(remaining);
        if (chunk.isEmpty) {
          break;
        }
        builder.add(chunk);
        remaining -= chunk.length;
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        throw const UploadFailure("Couldn't read that file");
      }
      return bytes;
    } on FileSystemException {
      throw const UploadFailure("Couldn't read that file");
    } finally {
      await handle.close();
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A leftover temp file is harmless.
    }
  }
}
