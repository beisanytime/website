import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../models/shiur.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shiur_grid.dart';

/// One speaker's shiurim, pushed on top of the tab it was opened from.
class SpeakerDetailScreen extends StatelessWidget {
  const SpeakerDetailScreen({super.key, required this.rabbi});

  final String rabbi;

  @override
  Widget build(BuildContext context) {
    return StateBuilder(
      builder: (BuildContext context, AppState state) =>
          _detail(context, state),
    );
  }

  Widget _detail(BuildContext context, AppState state) {
    final filtered = state.shiurimForRabbi(rabbi);
    final palette = context.palette;
    final displayName = displayNameForRabbi(filtered, rabbi);

    return FScaffold(
      header: FHeader.nested(
        title: Text(displayName),
        prefixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.arrowLeft),
            onPress: () => Navigator.of(context).pop(),
            semanticsLabel: 'Back',
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: palette.textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filtered.length} Shiurim available',
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: FAlert(
                      title: Text('Nothing here yet'),
                      subtitle: Text('No shiurim found for this speaker.'),
                      icon: Icon(FLucideIcons.searchX),
                    ),
                  ),
                )
              else
                SliverShiurGrid(
                  shiurim: filtered,
                  delegate: shiurGridDelegateFor(constraints.maxWidth),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}

/// Reads the prettified name off the first shiur, falling back to the id so the
/// header never shows a raw identifier.
String displayNameForRabbi(List<Shiur> shiurim, String rabbi) {
  if (shiurim.isNotEmpty) {
    return shiurim.first.rabbiDisplayName;
  }
  return rabbi
      .replaceAll('_', ' ')
      .split(' ')
      .where((String word) => word.isNotEmpty)
      .map((String word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
