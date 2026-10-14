import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../state/toast_controller.dart';

/// Bridges [ToastController] onto Forui's toast system.
///
/// The controller stays a plain notifier so the state layer does not import
/// widgets; this is the one place that turns a notification into an
/// [showFToast] call.
class ToastBridge extends StatefulWidget {
  const ToastBridge({super.key, required this.toast});

  final ToastController toast;

  @override
  State<ToastBridge> createState() => _ToastBridgeState();
}

class _ToastBridgeState extends State<ToastBridge> {
  String? _lastShown;

  @override
  void initState() {
    super.initState();
    widget.toast.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.toast.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final toast = widget.toast;
    final message = toast.message;
    if (!toast.isVisible || message == null) {
      return;
    }
    // The controller keeps the message around while it animates out; a toast
    // should only be raised once per notification.
    _toastCount++;
    final stamp = '$_toastCount:$message';
    if (_lastShown == stamp) {
      return;
    }
    _lastShown = stamp;

    if (!mounted) {
      return;
    }
    showFToast(
      context: context,
      title: Text(message),
      icon: Icon(
        toast.kind == ToastKind.error
            ? FLucideIcons.circleAlert
            : FLucideIcons.circleCheck,
      ),
      variant: toast.kind == ToastKind.error
          ? FToastVariant.destructive
          : FToastVariant.primary,
      duration: const Duration(seconds: 3),
    );
  }

  int _toastCount = 0;

  /// Exposed for tests: how many toasts have been raised.

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
