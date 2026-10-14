import 'package:flutter/material.dart';

import '../models/shiur.dart';
import '../theme/app_theme.dart';
import 'audio_artwork.dart';
import 'remote_image.dart';

/// A shiur's 16:9 artwork: the stored still for video, designed artwork for
/// audio or when the still is missing.
class ShiurThumbnail extends StatelessWidget {
  const ShiurThumbnail({super.key, required this.shiur, this.compact = false});

  final Shiur shiur;
  final bool compact;

  /// Cards are at most ~400 logical pixels wide, so decoding the stored frame at
  /// its full 1280–1920px costs an order of magnitude more memory than any card
  /// can show. 800 covers a 3x phone card and keeps the decoded cache useful.
  static const int _decodeWidth = 800;

  @override
  Widget build(BuildContext context) {
    final accent = colorFromHex(shiur.rabbiColorHex);
    final source = shiur.thumbnailSource;

    if (shiur.isTime4Mishna || source == null) {
      return AudioArtwork(accent: accent, compact: compact);
    }

    return Image(
      image: ResizeImage.resizeIfNeeded(
        _decodeWidth,
        null,
        RemoteImage(source),
      ),
      fit: BoxFit.cover,
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? progress) {
            if (progress == null) {
              return child;
            }
            return ColoredBox(
              color: context.palette.surfaceTertiary,
              child: const SizedBox.expand(),
            );
          },
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          AudioArtwork(accent: accent, compact: compact),
    );
  }
}
