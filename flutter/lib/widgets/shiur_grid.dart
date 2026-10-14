import 'package:flutter/material.dart';

import '../models/shiur.dart';
import 'video_card.dart';

/// Card height that leaves room for the artwork plus a two-line title, tags and
/// a date. Reserving it keeps every cell the same shape, and cells that do not
/// use all of it simply sit top-aligned.
const double kShiurCardContentHeight = 118;

/// A grid delegate whose cells are `maxItemWidth` wide at most, matching
/// SwiftUI's `GridItem(.adaptive(minimum: 300))`.
///
/// The width has to be known up front because a fixed aspect ratio cannot be
/// derived per item inside a delegate.
SliverGridDelegateWithFixedCrossAxisCount shiurGridDelegateFor(
  double maxWidth, {
  double horizontalPadding = 32,
  double spacing = 20,
  double maxItemWidth = 320,
  double contentHeight = kShiurCardContentHeight,
}) {
  final available = (maxWidth - horizontalPadding).clamp(1.0, double.infinity);
  final columns = (available / maxItemWidth).floor().clamp(1, 6);
  final itemWidth = columns <= 1
      ? available
      : (available - spacing * (columns - 1)) / columns;
  final safeWidth = itemWidth <= 1 ? 1.0 : itemWidth;
  final itemHeight = safeWidth * 9 / 16 + contentHeight;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    childAspectRatio: safeWidth / itemHeight,
  );
}

/// The speaker grid delegate, sized for the taller speaker cards.
SliverGridDelegateWithFixedCrossAxisCount speakerGridDelegateFor(
  double maxWidth, {
  double horizontalPadding = 32,
  double spacing = 16,
}) {
  final available = (maxWidth - horizontalPadding).clamp(1.0, double.infinity);
  final columns = (available / 190).floor().clamp(1, 6);
  final itemWidth = columns <= 1
      ? available
      : (available - spacing * (columns - 1)) / columns;
  final safeWidth = itemWidth <= 1 ? 1.0 : itemWidth;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    childAspectRatio: safeWidth / 172,
  );
}

/// A lazy grid of shiur cards that fits whatever width it is given.
class SliverShiurGrid extends StatelessWidget {
  const SliverShiurGrid({
    super.key,
    required this.shiurim,
    required this.delegate,
    this.horizontalPadding = 16,
    this.showBookmark = true,
  });

  final List<Shiur> shiurim;
  final SliverGridDelegate delegate;
  final double horizontalPadding;
  final bool showBookmark;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverGrid(
        gridDelegate: delegate,
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) => VideoCard(
            shiur: shiurim[index],
            showBookmark: showBookmark,
          ),
          childCount: shiurim.length,
        ),
      ),
    );
  }
}

/// A horizontal row of cards, used by the "Continue Watching" shelf.
class ShiurCardRow extends StatelessWidget {
  const ShiurCardRow({super.key, required this.shiurim, this.cardWidth = 260});

  final List<Shiur> shiurim;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final cardHeight = cardWidth * 9 / 16 + kShiurCardContentHeight;
    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: shiurim.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (BuildContext context, int index) => SizedBox(
          width: cardWidth,
          child: VideoCard(shiur: shiurim[index]),
        ),
      ),
    );
  }
}
