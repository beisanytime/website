import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../theme/app_theme.dart';

/// Loading, failure and empty states for the shiur library.
///
/// A failed or slow load used to render nothing at all, which read as "the app
/// is broken" — so every list that can be empty says why.
class LibraryStatusView extends StatelessWidget {
  const LibraryStatusView({
    super.key,
    this.emptyIcon = FLucideIcons.bookMarked,
    this.emptyTitle = 'No Shiurim Yet',
    this.emptyMessage = 'New shiurim will appear here.',
    this.onRetry,
  });

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final palette = context.palette;

    Widget reload() => FButton(
          onPress: () async {
            final handler = onRetry;
            if (handler != null) {
              await handler();
            } else {
              await state.refresh();
            }
          },
          child: const Text('Reload'),
        );

    final Widget body;
    if (state.isLoadingLibrary && !state.hasLibrary) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const FCircularProgress(),
          const SizedBox(height: 12),
          Text(
            'Loading library…',
            style: TextStyle(fontSize: 14, color: palette.textMuted),
          ),
        ],
      );
    } else if (state.libraryError != null && !state.hasLibrary) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(FLucideIcons.wifiOff, size: 34),
          const SizedBox(height: 12),
          FAlert(
            title: const Text("Couldn't Load Shiurim"),
            subtitle: Text(state.libraryError!),
            icon: const Icon(FLucideIcons.triangleAlert),
            variant: FAlertVariant.destructive,
          ),
          const SizedBox(height: 14),
          reload(),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(emptyIcon, size: 38, color: palette.textMuted),
          const SizedBox(height: 12),
          FAlert(
            title: Text(emptyTitle),
            subtitle: Text(emptyMessage),
            icon: Icon(emptyIcon),
          ),
          const SizedBox(height: 14),
          reload(),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
      child: Center(child: body),
    );
  }
}
