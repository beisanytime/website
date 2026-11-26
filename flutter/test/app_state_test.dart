import 'dart:convert';

import 'package:beisanytime/models/user_profile.dart';
import 'package:beisanytime/services/api_client.dart';
import 'package:beisanytime/services/secure_store.dart';
import 'package:beisanytime/state/app_state.dart';
import 'package:beisanytime/state/playback_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the keychain, which has no platform in unit tests.
class FakeSecureStore extends SecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> saveUser(UserProfile user) async {
    values['googleUser'] = jsonEncode(user.toJson());
  }

  @override
  Future<UserProfile?> loadUser() async {
    final raw = values['googleUser'];
    if (raw == null) {
      return null;
    }
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> clearUser() async => values.remove('googleUser');

  @override
  Future<void> saveUploadPassword(String password) async {
    values['uploadPassword'] = password;
  }

  @override
  Future<String?> loadUploadPassword() async => values['uploadPassword'];

  @override
  Future<void> clearUploadPassword() async => values.remove('uploadPassword');
}

const List<Map<String, dynamic>> _library = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': '1',
    'title': 'Parsha',
    'rabbi': 'Rabbi Hartman',
    'date': '2026-10-14',
  },
  <String, dynamic>{
    'id': '2',
    'title': 'Chumash',
    'rabbi': 'rabbi_golker',
    'date': '2026-10-01',
  },
  <String, dynamic>{
    'id': '3',
    'title': 'Peah 7',
    'rabbi': 'time4mishna',
    'date': '2026-03-05',
  },
];

late FakeSecureStore secureStore;

Future<AppState> makeState() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  secureStore = FakeSecureStore();
  final api = ApiClient(
    client: MockClient((http.Request request) async {
      if (request.url.path.endsWith('all-shiurim')) {
        return http.Response(jsonEncode(_library), 200);
      }
      return http.Response('{}', 200);
    }),
  );
  return AppState(
    prefs: prefs,
    api: api,
    secureStore: secureStore,
    playback: PlaybackStore(prefs),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts on the home tab', () async {
    final state = await makeState();
    expect(state.tab, AppTab.home);
  });

  test('loads the library and exposes derived views', () async {
    final state = await makeState();
    await state.loadLibrary();

    expect(state.shiurim, hasLength(3));
    expect(state.time4MishnaShiurim.map((dynamic s) => s.id), <String>['3']);
    // Time4Mishna is a shelf of its own, not a speaker.
    expect(
      state.uniqueSpeakers.map((Speaker s) => s.name),
      <String>['Rabbi Golker', 'Rabbi Hartman'],
    );
    expect(state.shiurimForRabbi('rabbi hartman'), hasLength(1));
    expect(state.shiurimForRabbi('Rabbi Hartman'), hasLength(1));
  });

  test('search matches title, speaker and description', () async {
    final state = await makeState();
    await state.loadLibrary();

    expect(state.filterShiurim('parsha'), hasLength(1));
    expect(state.filterShiurim('golker'), hasLength(1));
    expect(state.filterShiurim('nope'), isEmpty);
    expect(state.filterShiurim('  '), hasLength(3));
  });

  test('bookmarks persist across restarts', () async {
    final state = await makeState();
    await state.loadLibrary();

    state.toggleBookmark('1');
    expect(state.isBookmarked('1'), isTrue);
    expect(state.bookmarkedShiurim.map((dynamic s) => s.id), <String>['1']);

    final reopened = AppState(
      prefs: await SharedPreferences.getInstance(),
      api: state.api,
      secureStore: secureStore,
    );
    await reopened.restore();
    expect(reopened.isBookmarked('1'), isTrue);

    state.toggleBookmark('1');
    expect(state.isBookmarked('1'), isFalse);
  });

  test('theme choice persists', () async {
    final state = await makeState();
    expect(state.isDarkMode, isFalse);

    state.toggleDarkMode();
    expect(state.isDarkMode, isTrue);

    final reopened = AppState(
      prefs: await SharedPreferences.getInstance(),
      api: state.api,
      secureStore: secureStore,
    );
    await reopened.restore();
    expect(reopened.isDarkMode, isTrue);
  });

  test('admin gate follows the allow-list, not just sign-in', () async {
    final state = await makeState();

    await state.signIn(
      const UserProfile(name: 'Someone', email: 'someone@example.com', picture: ''),
    );
    expect(state.isSignedIn, isTrue);
    expect(state.isAdmin, isFalse);
    expect(state.adminCredentials, isNull);

    await state.signIn(
      const UserProfile(
        name: 'Josh',
        email: 'joshuacalvert1@gmail.com',
        picture: '',
      ),
    );
    expect(state.isAdmin, isTrue);
    // Still no credentials: the upload password is missing.
    expect(state.adminCredentials, isNull);

    await state.setUploadPassword('  hunter2  ');
    expect(state.uploadPassword, 'hunter2');
    expect(state.adminCredentials?.password, 'hunter2');
    expect(state.adminCredentials?.email, 'joshuacalvert1@gmail.com');

    await state.setUploadPassword('   ');
    expect(state.uploadPassword, isNull);
    expect(state.adminCredentials, isNull);
  });

  test('continue watching only lists real progress', () async {
    final state = await makeState();
    await state.loadLibrary();

    // Under 10 seconds is not worth resuming.
    state.playback.save('1', const Duration(seconds: 5), const Duration(minutes: 40));
    expect(state.continueWatching(), isEmpty);

    state.playback.save(
      '1',
      const Duration(minutes: 10),
      const Duration(minutes: 40),
    );
    expect(state.continueWatching().map((dynamic s) => s.id), <String>['1']);
    expect(state.playback.fraction('1'), closeTo(0.25, 0.01));

    // Within 10 seconds of the end means finished, not resumable.
    state.playback.save(
      '1',
      const Duration(minutes: 39, seconds: 55),
      const Duration(minutes: 40),
    );
    expect(state.continueWatching(), isEmpty);
  });

  test('a failed library load surfaces the reason', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(
      prefs: prefs,
      api: ApiClient(
        client: MockClient(
          (http.Request request) async => http.Response('', 503),
        ),
      ),
      secureStore: FakeSecureStore(),
      playback: PlaybackStore(prefs),
    );

    await state.loadLibrary();
    expect(state.libraryError, 'Server error: 503');
    expect(state.hasLibrary, isFalse);
    expect(state.isLoadingLibrary, isFalse);
  });

  test('switching tabs notifies listeners', () async {
    final state = await makeState();
    var notifications = 0;
    state.addListener(() => notifications++);

    state.setTab(AppTab.browse);
    expect(state.tab, AppTab.browse);
    expect(notifications, 1);

    // Re-selecting the same tab should not churn the tree.
    state.setTab(AppTab.browse);
    expect(notifications, 1);
  });
}
