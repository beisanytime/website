import 'package:flutter/widgets.dart';

import 'state/app_state.dart';
import 'state/toast_controller.dart';

/// Hands [AppState] and [ToastController] down the tree.
///
/// This is an [InheritedNotifier], not a plain [InheritedWidget]: reading it
/// registers a dependency, and every dependent is rebuilt when the state
/// notifies. That matters because screens are frequently created as `const`
/// widgets — a const instance is canonical, so an ancestor rebuild alone would
/// never reach it, and a screen would keep rendering the state it first saw.
/// This behaves like the `@EnvironmentObject` the SwiftUI screens relied on.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState state,
    required this.toast,
    required super.child,
  }) : super(notifier: state);

  final ToastController toast;

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!.notifier!;
  }

  static ToastController toastOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!.toast;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      super.updateShouldNotify(oldWidget) || oldWidget.toast != toast;
}

/// Rebuilds [builder] whenever the app state changes.
///
/// Explcit subscription for the places that must update at a specific point in
/// the tree (a pushed screen's chrome, for instance) rather than by dependency.
class StateBuilder extends StatelessWidget {
  const StateBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppState state) builder;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) => builder(context, state),
    );
  }
}
