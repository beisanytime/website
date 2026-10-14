import 'dart:convert';

import 'package:beisanytime/app.dart';
import 'package:beisanytime/services/api_client.dart';
import 'package:beisanytime/state/app_state.dart';
import 'package:beisanytime/state/playback_store.dart';
import 'package:beisanytime/state/toast_controller.dart';
import 'package:beisanytime/widgets/bottom_nav.dart';
import 'package:beisanytime/widgets/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<Map<String, dynamic>> _library = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': '2026-10-14-Rabbi_Hartman-Parsha.mov',
    'title': 'Parsha',
    'rabbi': 'Rabbi Hartman',
    'date': '2026-10-14',
    'playbackUrl': 'https://example.test/api/video-proxy?key=parsha.mov',
  },
  <String, dynamic>{
    'id': '2026-10-01-Rabbi_Golker-Chumash.mov',
    'title': 'Chumash',
    'rabbi': 'rabbi_golker',
    'date': '2026-10-01',
    'playbackUrl': 'https://example.test/api/video-proxy?key=chumash.mov',
  },
  <String, dynamic>{
    'id': '2026-03-05-time4mishna-Peah_7.MP3',
    'title': 'Peah 7',
    'rabbi': 'time4mishna',
    'date': '2026-03-05',
    'playbackUrl': 'https://example.test/api/video-proxy?key=peah.mp3',
  },
];

String _detailFor(String path) {
  final id = Uri.decodeComponent(path.split('/').last);
  final match = _library.firstWhere(
    (Map<String, dynamic> row) => row['id'] == id,
    orElse: () => _library.first,
  );
  return jsonEncode(match);
}

Future<AppState> _pumpApp(WidgetTester tester) async {
  // The default 800x600 test surface is wider and shorter than any phone, so
  // a full-height card's centre lands under the tab bar and taps miss it.
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final api = ApiClient(
    client: MockClient((http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('all-shiurim')) {
        return http.Response(jsonEncode(_library), 200);
      }
      if (path.contains('/api/shiurim/id/')) {
        return http.Response(_detailFor(path), 200);
      }
      if (path.contains('/api/views/')) {
        return http.Response(jsonEncode(<String, dynamic>{'count': 7}), 200);
      }
      if (path.contains('/api/likes/')) {
        return http.Response(
          jsonEncode(<String, dynamic>{'count': 3, 'userLiked': false}),
          200,
        );
      }
      if (path.contains('/api/comments/')) {
        return http.Response(
          jsonEncode(<String, dynamic>{'comments': <dynamic>[]}),
          200,
        );
      }
      return http.Response('{}', 200);
    }),
  );

  final state = AppState(prefs: prefs, api: api, playback: PlaybackStore(prefs));
  final toast = ToastController();
  addTearDown(state.dispose);
  addTearDown(toast.dispose);

  await tester.pumpWidget(BeisAnytimeApp(state: state, toast: toast));
  await state.loadLibrary();
  await tester.pump();
  return state;
}

/// The back chevron the pushed header renders.
Finder _backButtons() => find.byIcon(FLucideIcons.arrowLeft);

/// Forui's tappable keeps a 100 ms ripple timer alive, so a bare `pump()`
/// leaves the test with pending timers. Every tap goes through here, and the
/// trailing pump lets a pushed route finish leaving the tree.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('opens on Home with no back button', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('Home'), findsWidgets);
    // The original bug: a tab page pushed onto its own stack put a stray back
    // button on every root screen.
    expect(_backButtons(), findsNothing);
    expect(find.byType(BottomNavView), findsOneWidget);
    expect(find.byType(VideoCard), findsWidgets);
  });

  testWidgets('the tab bar switches sections without a back button',
      (WidgetTester tester) async {
    final state = await _pumpApp(tester);

    await _tap(tester, find.text('Mishna'));
    expect(state.tab, AppTab.time4mishna);
    expect(find.text('Time4Mishna'), findsWidgets);
    expect(_backButtons(), findsNothing);

    await _tap(tester, find.text('Feed'));
    expect(state.tab, AppTab.community);
    expect(_backButtons(), findsNothing);
  });

  testWidgets('a shiur card pushes exactly one back button and hides the tabs',
      (WidgetTester tester) async {
    await _pumpApp(tester);

    await _tap(tester, find.byType(VideoCard).first);

    // One back control, not the two the player used to show.
    expect(_backButtons(), findsOneWidget);
    expect(find.byType(BottomNavView), findsNothing);
    expect(find.text('Parsha'), findsWidgets);

    await _tap(tester, _backButtons());

    expect(_backButtons(), findsNothing);
    expect(find.byType(BottomNavView), findsOneWidget);
  });

  testWidgets('a speaker card pushes a detail page that can go back',
      (WidgetTester tester) async {
    final state = await _pumpApp(tester);

    state.setTab(AppTab.speakers);
    await tester.pump();

    await _tap(tester, find.text('Rabbi Hartman'));

    expect(_backButtons(), findsOneWidget);
    expect(find.textContaining('Shiurim available'), findsWidgets);

    await _tap(tester, _backButtons());
    expect(_backButtons(), findsNothing);
  });

  testWidgets('bookmarking from a card survives a rebuild',
      (WidgetTester tester) async {
    final state = await _pumpApp(tester);

    final firstId = _library.first['id']! as String;
    expect(state.isBookmarked(firstId), isFalse);

    await _tap(tester, find.byIcon(FLucideIcons.bookmark).first);

    expect(state.isBookmarked(firstId), isTrue);
    expect(find.byIcon(FLucideIcons.bookMarked), findsWidgets);
  });

  testWidgets('the account sheet opens and closes', (WidgetTester tester) async {
    await _pumpApp(tester);

    await _tap(tester, find.text('Sign In'));

    expect(find.text('Account'), findsWidgets);
    expect(find.text('Sign in with Google'), findsOneWidget);

    await _tap(tester, find.byIcon(FLucideIcons.x));
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('dark mode switches the Forui theme', (WidgetTester tester) async {
    final state = await _pumpApp(tester);

    final lightTheme = FTheme.of(
      tester.element(find.byType(VideoCard).first),
    );
    state.toggleDarkMode();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final darkTheme = FTheme.of(
      tester.element(find.byType(VideoCard).first),
    );
    expect(state.isDarkMode, isTrue);
    expect(darkTheme.colors.background, isNot(lightTheme.colors.background));
  });
}
