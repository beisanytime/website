import 'dart:async';
import 'package:flutter/foundation.dart';

enum ToastKind { success, error }

/// Transient bottom-of-screen messages, replacing `ToastManager` + `ToastView`.
class ToastController extends ChangeNotifier {
  String? _message;
  ToastKind _kind = ToastKind.success;
  bool _visible = false;
  Timer? _timer;

  String? get message => _message;
  ToastKind get kind => _kind;
  bool get isVisible => _visible;

  void show(String message, {ToastKind kind = ToastKind.success}) {
    _message = message;
    _kind = kind;
    _visible = true;
    notifyListeners();

    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      _visible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
