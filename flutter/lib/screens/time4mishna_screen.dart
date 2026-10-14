import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../widgets/library_status.dart';
import '../widgets/shiur_grid.dart';

/// The Time4Mishna shelf: audio shiurim, which never have a stored thumbnail.
class Time4MishnaScreen extends StatelessWidget {
  const Time4MishnaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final shiurim = state.time4MishnaShiurim;
    final palette = context.palette;

    if (!state.hasLibrary) {
      return const LibraryStatusView(
        emptyIcon: FLucideIcons.headphones,
        emptyTitle: 'No Mishnayot Yet',
        emptyMessage: 'Audio shiurim will appear here.',
      );
    }

    if (shiurim.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 60),
          child: FAlert(
            title: Text('No Mishnayot Yet'),
            icon: Icon(FLucideIcons.headphones),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Text(
                  '${shiurim.length} Shiurim available',
                  style: TextStyle(fontSize: 14, color: palette.textMuted),
                ),
              ),
            ),
            SliverShiurGrid(
              shiurim: shiurim,
              delegate: shiurGridDelegateFor(constraints.maxWidth),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}
