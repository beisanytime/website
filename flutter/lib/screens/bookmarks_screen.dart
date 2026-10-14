import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../widgets/shiur_grid.dart';

/// "Watch Later" — the bookmarked shiurim.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final saved = state.bookmarkedShiurim;

    if (saved.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
          child: FAlert(
            title: const Text('No Saved Shiurim'),
            subtitle: const Text('Bookmark shiurim to watch later'),
            icon: const Icon(FLucideIcons.bookmark),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return CustomScrollView(
          slivers: <Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverShiurGrid(
              shiurim: saved,
              delegate: shiurGridDelegateFor(constraints.maxWidth),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}
