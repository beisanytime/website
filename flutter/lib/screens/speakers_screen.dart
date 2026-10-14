import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../navigation/app_routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/forui_kit.dart';
import '../widgets/shiur_grid.dart';

/// The speaker grid on its own, so Browse can embed it as well as the tab.
class SliverSpeakersGrid extends StatelessWidget {
  const SliverSpeakersGrid({super.key, required this.delegate});

  final SliverGridDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final speakers = AppScope.of(context).uniqueSpeakers;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: delegate,
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) =>
              SpeakerCard(speaker: speakers[index]),
          childCount: speakers.length,
        ),
      ),
    );
  }
}

/// One speaker tile.
class SpeakerCard extends StatelessWidget {
  const SpeakerCard({super.key, required this.speaker});

  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isGroup = speaker.id.toLowerCase().contains('guest');

    return GestureDetector(
      onTap: () => AppRoutes.openSpeaker(context, speaker.id),
      child: AppCard(
        color: palette.surfaceSecondary,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: palette.surfaceTertiary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isGroup ? FLucideIcons.users : FLucideIcons.userRound,
                  size: 26,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                speaker.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.textMain,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${speaker.shiurCount} Shiurim',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Speakers tab.
class SpeakersScreen extends StatelessWidget {
  const SpeakersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return CustomScrollView(
          slivers: <Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverSpeakersGrid(
              delegate: speakerGridDelegateFor(constraints.maxWidth),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}
