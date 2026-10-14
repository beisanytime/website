import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'state/toast_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs: prefs);
  final toast = ToastController();

  runApp(BeisAnytimeApp(state: state, toast: toast));

  // Restoring the session and loading the library happens off the first frame,
  // so the shell paints immediately and shows its own loading state.
  await state.restore();
}
