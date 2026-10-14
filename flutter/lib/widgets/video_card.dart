import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../models/shiur.dart';
import '../navigation/app_routes.dart';
import '../theme/app_theme.dart';
import 'forui_kit.dart';
import 'shiur_thumbnail.dart';

/// The library card: artwork, speaker pill, resume bar and bookmark.
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.shiur, this.showBookmark = true});

  final Shiur shiur;
  final bool showBookmark;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final palette = context.palette;
    final accent = colorFromHex(shiur.rabbiColorHex);

    return GestureDetector(
      onTap: () => AppRoutes.openShiur(context, shiur.id),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ShiurThumbnail(shiur: shiur),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: OverlayPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            AccentDot(color: accent),
                            const SizedBox(width: 6),
                            Text(
                              shiur.rabbiDisplayName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showBookmark)
                      Positioned(
                        right: 12,
                        top: 12,
                        child: GestureDetector(
                          onTap: () => state.toggleBookmark(shiur.id),
                          child: OverlayPill(
                            child: Icon(
                              state.isBookmarked(shiur.id)
                                  ? FLucideIcons.bookMarked
                                  : FLucideIcons.bookmark,
                              size: 15,
                              color: state.isBookmarked(shiur.id)
                                  ? AppPalette.warning
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ListenableBuilder(
                        listenable: state.playback,
                        builder: (BuildContext context, Widget? child) {
                          final fraction = state.playback.fraction(shiur.id);
                          if (fraction <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: fraction,
                              child: Container(
                                height: 4,
                                color: AppPalette.danger,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    shiur.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.textMain,
                      height: 1.25,
                    ),
                  ),
                  if (shiur.tags != null && shiur.tags!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 22,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: shiur.tags!.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (BuildContext context, int index) => FBadge(
                          variant: FBadgeVariant.outline,
                          child: Text(
                            shiur.tags![index],
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (shiur.dateDisplay.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      shiur.dateDisplay,
                      style: TextStyle(fontSize: 12, color: palette.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
