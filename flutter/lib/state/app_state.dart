import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/shiur.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/google_auth_service.dart';
import '../services/secure_store.dart';
import 'playback_store.dart';

/// Root sections. Tab pages live at the root of the navigation stack; detail
/// pages are pushed on top of them.
enum AppTab { home, browse, community, speakers, bookmarks, time4mishna }

extension AppTabInfo on AppTab {
  /// Navigation-bar title, matching `AppPage.title`.
  String get title {
    switch (this) {
      case AppTab.home:
        return 'Home';
      case AppTab.browse:
        return 'Library';
      case AppTab.community:
        return 'Community';
      case AppTab.speakers:
        return 'Speakers';
      case AppTab.bookmarks:
        return 'Watch Later';
      case AppTab.time4mishna:
        return 'Time4Mishna';
    }
  }
}

/// A speaker row for the speakers grid.
class Speaker {
  const Speaker({
    required this.id,
    required this.name,
    required this.shiurCount,
  });

  final String id;
  final String name;
  final int shiurCount;
}

/// App-wide state: the library, the session, bookmarks and the theme.
///
/// The navigation split that fixed the native app is preserved here in spirit —
/// see `RootShell`, where the current tab and the pushed routes are separate
/// values so a tab can never be pushed on top of itself.
class AppState extends ChangeNotifier {
  AppState({
    required SharedPreferences prefs,
    ApiClient? api,
    SecureStore? secureStore,
    GoogleAuthService? googleAuth,
    PlaybackStore? playback,
  })  : _prefs = prefs,
        api = api ?? ApiClient(),
        _store = secureStore ?? SecureStore(),
        _googleAuth = googleAuth ?? GoogleAuthService(),
        playback = playback ?? PlaybackStore(prefs);

  final SharedPreferences _prefs;
  final ApiClient api;
  final SecureStore _store;
  final GoogleAuthService _googleAuth;
  final PlaybackStore playback;

  static const String _themeKey = 'theme';
  static const String _bookmarksKey = 'bookmarks';

  // MARK: - Navigation

  AppTab _tab = AppTab.home;

  AppTab get tab => _tab;

  /// Switches the visible root tab.
  ///
  /// Tabs are values, never pushed routes: that separation is what keeps a tab
  /// from landing on top of itself and adding a stray back button.
  void setTab(AppTab tab) {
    if (_tab == tab) {
      return;
    }
    _tab = tab;
    notifyListeners();
  }

  // MARK: - Library

  List<Shiur> _shiurim = const <Shiur>[];
  bool _isLoadingLibrary = false;
  String? _libraryError;

  List<Shiur> get shiurim => _shiurim;
  bool get isLoadingLibrary => _isLoadingLibrary;
  String? get libraryError => _libraryError;
  bool get hasLibrary => _shiurim.isNotEmpty;

  // MARK: - Session

  UserProfile? _user;
  bool _isSigningIn = false;
  String? _authError;
  String? _uploadPassword;

  UserProfile? get user => _user;
  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;
  String? get uploadPassword => _uploadPassword;

  bool get isSignedIn => _user != null;

  bool get isAdmin {
    final email = _user?.email.toLowerCase();
    if (email == null || email.isEmpty) {
      return false;
    }
    return ApiConfig.adminEmails.contains(email);
  }

  /// Credentials for admin requests, or `null` when the user isn't a signed-in
  /// admin or hasn't supplied the upload password yet.
  AdminCredentials? get adminCredentials {
    final currentUser = _user;
    final password = _uploadPassword;
    if (!isAdmin || currentUser == null || password == null || password.isEmpty) {
      return null;
    }
    return AdminCredentials(
      email: currentUser.email,
      name: currentUser.name,
      password: password,
      idToken: currentUser.idToken,
    );
  }

  // MARK: - Theme and bookmarks

  bool _isDarkMode = false;
  Set<String> _bookmarkedIds = <String>{};

  bool get isDarkMode => _isDarkMode;
  Set<String> get bookmarkedIds => _bookmarkedIds;

  bool isBookmarked(String id) => _bookmarkedIds.contains(id);

  // MARK: - Startup

  /// Restores the session, theme and bookmarks, then loads the library.
  Future<void> restore() async {
    _isDarkMode = _prefs.getBool(_themeKey) ?? false;
    _bookmarkedIds = (_prefs.getStringList(_bookmarksKey) ?? <String>[]).toSet();

    final savedUser = await _store.loadUser();
    if (savedUser != null) {
      _user = savedUser;
    }
    _uploadPassword = await _store.loadUploadPassword();
    notifyListeners();

    await loadLibrary();
  }

  // MARK: - Library loading

  Future<void> loadLibrary() async {
    _isLoadingLibrary = true;
    _libraryError = null;
    notifyListeners();
    try {
      _shiurim = await api.getAllShiurim();
    } on ApiException catch (error) {
      _libraryError = error.message;
    } finally {
      _isLoadingLibrary = false;
      notifyListeners();
    }
  }

  /// Drops the cache and reloads, so pulls and post-upload refreshes see new
  /// content.
  Future<void> refresh() async {
    api.invalidateCache();
    await loadLibrary();
  }

  /// Loads one shiur and folds it back into the library when it is already
  /// there, so a re-fetch refreshes the cached copy.
  Future<Shiur?> loadShiur(String id) async {
    try {
      final shiur = await api.getShiur(id);
      final index = _shiurim.indexWhere((Shiur item) => item.id == id);
      if (index >= 0) {
        final updated = List<Shiur>.of(_shiurim);
        updated[index] = shiur;
        _shiurim = updated;
      }
      notifyListeners();
      return shiur;
    } on ApiException catch (error) {
      _libraryError = error.message;
      notifyListeners();
      return null;
    }
  }

  // MARK: - Bookmarks

  void toggleBookmark(String id) {
    if (_bookmarkedIds.contains(id)) {
      _bookmarkedIds = <String>{..._bookmarkedIds}..remove(id);
    } else {
      _bookmarkedIds = <String>{..._bookmarkedIds, id};
    }
    _prefs.setStringList(_bookmarksKey, _bookmarkedIds.toList());
    notifyListeners();
  }

  // MARK: - Theme

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    _prefs.setBool(_themeKey, _isDarkMode);
    notifyListeners();
  }

  // MARK: - Auth

  Future<void> signInWithGoogle() async {
    if (_isSigningIn) {
      return;
    }
    _isSigningIn = true;
    _authError = null;
    notifyListeners();

    try {
      final profile = await _googleAuth.signIn();
      await _applySignedInUser(profile);
    } on AuthException catch (error) {
      if (!error.cancelled) {
        _authError = error.message;
      }
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  /// Used by tests and the sign-in flow alike.
  Future<void> signIn(UserProfile profile) => _applySignedInUser(profile);

  Future<void> _applySignedInUser(UserProfile profile) async {
    _user = profile;
    _authError = null;
    await _store.saveUser(profile);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _googleAuth.signOut();
    _user = null;
    _authError = null;
    await _store.clearUser();
    notifyListeners();
  }

  void clearAuthError() {
    if (_authError == null) {
      return;
    }
    _authError = null;
    notifyListeners();
  }

  /// Stores (or clears) the worker's upload password and persists it securely.
  Future<void> setUploadPassword(String password) async {
    final trimmed = password.trim();
    _uploadPassword = trimmed.isEmpty ? null : trimmed;
    if (_uploadPassword == null) {
      await _store.clearUploadPassword();
    } else {
      await _store.saveUploadPassword(_uploadPassword!);
    }
    notifyListeners();
  }

  // MARK: - Derived library views

  List<Shiur> filterShiurim(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return _shiurim;
    }
    return _shiurim.where((Shiur shiur) {
      return shiur.title.toLowerCase().contains(trimmed) ||
          (shiur.rabbi?.toLowerCase().contains(trimmed) ?? false) ||
          (shiur.description?.toLowerCase().contains(trimmed) ?? false);
    }).toList(growable: false);
  }

  List<Shiur> get bookmarkedShiurim =>
      _shiurim.where((Shiur shiur) => isBookmarked(shiur.id)).toList();

  List<Shiur> get time4MishnaShiurim =>
      _shiurim.where((Shiur shiur) => shiur.isTime4Mishna).toList();

  /// In-progress shiurim, newest position first, capped like the native app.
  List<Shiur> continueWatching({int limit = 5}) => _shiurim
      .where((Shiur shiur) => playback.hasProgress(shiur.id))
      .take(limit)
      .toList(growable: false);

  List<Speaker> get uniqueSpeakers {
    final map = <String, Speaker>{};
    for (final shiur in _shiurim) {
      final rabbi = shiur.rabbi;
      if (rabbi == null || rabbi.toLowerCase() == 'time4mishna') {
        continue;
      }
      final key = rabbi.toLowerCase().replaceAll('_', ' ');
      final existing = map[key];
      if (existing == null) {
        map[key] = Speaker(
          id: key,
          name: shiur.rabbiDisplayName,
          shiurCount: 1,
        );
      } else {
        map[key] = Speaker(
          id: existing.id,
          name: existing.name,
          shiurCount: existing.shiurCount + 1,
        );
      }
    }
    final speakers = map.values.toList()
      ..sort((Speaker a, Speaker b) => a.name.compareTo(b.name));
    return speakers;
  }

  List<Shiur> shiurimForRabbi(String rabbi) {
    final normalized = rabbi.toLowerCase().replaceAll('_', ' ');
    return _shiurim.where((Shiur shiur) {
      final value = shiur.rabbi?.toLowerCase().replaceAll('_', ' ');
      return value == normalized;
    }).toList(growable: false);
  }

  @override
  void dispose() {
    playback.dispose();
    api.dispose();
    super.dispose();
  }
}
