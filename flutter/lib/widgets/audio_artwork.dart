import 'package:flutter/material.dart';

/// Artwork for audio shiurim.
///
/// The server only stores first-frame thumbnails for video, so audio items used
/// to request a JPEG that 404s and fall back to an empty grey box. This draws
/// intentional artwork instead — the same fix the native app shipped.
class AudioArtwork extends StatelessWidget {
  const AudioArtwork({super.key, required this.accent, this.compact = false});

  final Color accent;
  final bool compact;

  static const List<double> _waveform = <double>[
    14, 30, 52, 26, 66, 38, 74, 30, 56, 22, 42, 16,
  ];

  @override
  Widget build(BuildContext context) {
    final scale = compact ? 0.62 : 1.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _waveform
                  .map(
                    (double height) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 5 * (compact ? 0.8 : 1),
                        height: height * scale,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          Center(
            child: Icon(
              Icons.headphones,
              size: compact ? 28 : 40,
              color: Colors.white,
              shadows: const <Shadow>[
                Shadow(
                  color: Color(0x40000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
