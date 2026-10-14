import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/forui_kit.dart';
import '../widgets/library_status.dart';
import '../widgets/shiur_grid.dart';

/// Home: hero, resume shelf and the newest shiurim.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final delegate = shiurGridDelegateFor(constraints.maxWidth);
        final latest = state.shiurim.take(20).toList(growable: false);

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            const SliverToBoxAdapter(child: _HeroCard()),
            SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: state.playback,
                builder: (BuildContext context, Widget? child) {
                  final continuing = state.continueWatching();
                  if (continuing.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SectionHeader('Continue Watching'),
                      ShiurCardRow(shiurim: continuing),
                    ],
                  );
                },
              ),
            ),
            if (!state.hasLibrary)
              const SliverToBoxAdapter(child: LibraryStatusView())
            else ...<Widget>[
              const SliverToBoxAdapter(
                child: SectionHeader('Latest Shiurim'),
              ),
              SliverShiurGrid(shiurim: latest, delegate: delegate),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[palette.surface, palette.surfaceSecondary],
            ),
            border: Border.all(color: palette.borderLight),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -200,
                top: -100,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    color: AppPalette.accent.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Torah Anytime, Anywhere.',
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: palette.textMain,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Explore a vast library of Shiurim from our esteemed '
                      'Rabbis. Watch, listen, and grow.',
                      style: TextStyle(
                        fontSize: 15,
                        color: palette.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        FButton(
                          onPress: () => state.setTab(AppTab.browse),
                          child: const Text('Browse Library'),
                        ),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: () => state.setTab(AppTab.speakers),
                          child: const Text('Meet the Rabbis'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
