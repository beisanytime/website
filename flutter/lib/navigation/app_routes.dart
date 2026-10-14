import 'package:flutter/material.dart';

import '../screens/account_screen.dart';
import '../screens/shiur_player_screen.dart';
import '../screens/speaker_detail_screen.dart';
import '../screens/upload_screen.dart';

/// Detail screens, pushed above the tab shell.
///
/// A pushed route covers the shell, so the tab bar disappears and the app bar
/// grows a back button by itself — the behaviour the native `NavigationStack`
/// only achieved once the tabs stopped being pushed too.
class AppRoutes {
  const AppRoutes._();

  static Route<void> shiur(String id) => MaterialPageRoute<void>(
        builder: (_) => ShiurPlayerScreen(shiurId: id),
        settings: RouteSettings(name: '/shiur/$id'),
      );

  static Route<void> speaker(String rabbi) => MaterialPageRoute<void>(
        builder: (_) => SpeakerDetailScreen(rabbi: rabbi),
        settings: RouteSettings(name: '/speaker/$rabbi'),
      );

  static Route<void> upload() => MaterialPageRoute<void>(
        builder: (_) => const UploadScreen(),
        settings: const RouteSettings(name: '/upload'),
      );

  static Route<void> account() => MaterialPageRoute<void>(
        builder: (_) => const AccountScreen(),
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/account'),
      );

  static Future<void> openShiur(BuildContext context, String id) =>
      Navigator.of(context).push(shiur(id));

  /// Replaces the player in place, so tapping "Up Next" never stacks players
  /// and Back still returns to the tab the listener came from.
  static Future<void> replaceShiur(BuildContext context, String id) =>
      Navigator.of(context).pushReplacement(shiur(id));

  static Future<void> openSpeaker(BuildContext context, String rabbi) =>
      Navigator.of(context).push(speaker(rabbi));

  static Future<void> openUpload(BuildContext context) =>
      Navigator.of(context).push(upload());

  static Future<void> openAccount(BuildContext context) =>
      Navigator.of(context).push(account());
}
