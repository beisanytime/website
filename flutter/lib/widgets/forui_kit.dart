import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme.dart';

/// A playback scrubber.
///
/// Forui's [FSlider] is uncontrolled — its value comes from a controller the
/// player would have to mirror on every tick — so this draws a track that
/// follows playback and reports drags. It is styled from the palette, so it
/// sits next to Forui components without looking borrowed.
class SeekBar extends StatelessWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onDragStart,
    this.onDragUpdate,
    this.onDark = false,
    this.height = 22,
  });

  final Duration position;
  final Duration duration;
  final void Function(Duration target) onSeek;
  final VoidCallback? onDragStart;
  final ValueChanged<Duration>? onDragUpdate;
  final bool onDark;
  final double height;

  double _seconds(Duration value) => value.inMilliseconds / 1000;

  @override
  Widget build(BuildContext context) {
    final total = _seconds(duration);
    final current = _seconds(position).clamp(0, total <= 0 ? 0 : total);
    final fraction = total <= 0 ? 0.0 : current / total;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth;

        void report(double dx, {required bool commit}) {
          if (total <= 0 || width <= 0) {
            return;
          }
          final ratio = (dx / width).clamp(0.0, 1.0);
          final target = Duration(milliseconds: (ratio * total * 1000).round());
          if (commit) {
            onSeek(target);
          } else {
            onDragUpdate?.call(target);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (DragStartDetails details) {
            onDragStart?.call();
            report(details.localPosition.dx, commit: false);
          },
          onHorizontalDragUpdate: (DragUpdateDetails details) =>
              report(details.localPosition.dx, commit: false),
          onHorizontalDragEnd: (DragEndDetails details) =>
              report(details.localPosition.dx, commit: true),
          onTapDown: (TapDownDetails details) {
            report(details.localPosition.dx, commit: true);
          },
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _SeekBarPainter(
                fraction: fraction,
                track: onDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : context.palette.borderLight,
                active: onDark ? Colors.white : AppPalette.accent,
                thumb: onDark ? Colors.white : AppPalette.accent,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  const _SeekBarPainter({
    required this.fraction,
    required this.track,
    required this.active,
    required this.thumb,
  });

  final double fraction;
  final Color track;
  final Color active;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.height / 2;
    final radius = 2.0;
    final trackRect = Rect.fromLTWH(0, centre - radius, size.width, radius * 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(2)),
      Paint()..color = track,
    );

    final filledWidth = size.width * fraction;
    if (filledWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, centre - radius, filledWidth, radius * 2),
          const Radius.circular(2),
        ),
        Paint()..color = active,
      );
    }

    final thumbCentre = Offset(filledWidth.clamp(6.0, size.width - 6.0), centre);
    canvas.drawCircle(thumbCentre, 6, Paint()..color = thumb);
    canvas.drawCircle(
      thumbCentre,
      10,
      Paint()..color = thumb.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.active != active ||
      old.thumb != thumb;
}

/// A section heading with the app's sizing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: context.palette.textMain,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The bordered, rounded surface the app uses for cards and panels.
///
/// Forui's [FCard] styles itself from the theme's card style, which fights the
/// per-speaker artwork and surface colours here, so cards are plain framed
/// containers while every control inside them is a Forui widget.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.color,
    this.radius = 12,
    this.border = true,
  });

  final Widget child;
  final Color? color;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: palette.borderLight) : null,
      ),
      child: child,
    );
  }
}

/// The blurred pill that labels a card with its speaker.
class OverlayPill extends StatelessWidget {
  const OverlayPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A speaker colour dot.
class AccentDot extends StatelessWidget {
  const AccentDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4),
        ],
      ),
    );
  }
}

/// A soft tinted container, used for notices and metadata pills.
class Tint extends StatelessWidget {
  const Tint({
    super.key,
    required this.child,
    this.color,
    this.radius = 12,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
