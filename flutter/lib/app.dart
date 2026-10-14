import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_scope.dart';
import 'navigation/root_shell.dart';
import 'state/app_state.dart';
import 'state/toast_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/toast_overlay.dart';

/// The app shell.
///
/// [MaterialApp] is only the host: it supplies the navigator, localisations and
/// route transitions. Everything the user sees is Forui, installed once by
/// [FTheme] with [FToaster] for transient messages — Forui's own recommended
/// composition.
///
/// The theme lives in [MaterialApp.builder] rather than in `home` on purpose.
/// A widget passed as `home` is memoised inside the initial route, so a new
/// instance never reaches the screen that is already on display; the builder
/// wraps the navigator itself, which means a brightness change or a new library
/// actually reaches every route.
class BeisAnytimeApp extends StatelessWidget {
  const BeisAnytimeApp({super.key, required this.state, required this.toast});

  final AppState state;
  final ToastController toast;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      toast: toast,
      child: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, Widget? _) {
          final dark = state.isDarkMode;

          return MaterialApp(
            title: 'Beis Anytime',
            debugShowCheckedModeBanner: false,
            theme: hostTheme(dark: dark),
            home: const RootShell(),
            builder: (BuildContext context, Widget? child) {
              return FTheme(
                data: foruiThemeData(dark: dark),
                platform: FPlatformVariant.iOS,
                child: FToaster(
                  child: Stack(
                    children: <Widget>[
                      ?child,
                      ToastBridge(toast: toast),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
