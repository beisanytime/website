import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Playback positions, replacing the `@Published` progress dictionaries.
///
/// Kept apart from [AppState] on purpose: the player writes a position every
/// few hundred milliseconds, and folding that into the app-wide notifier would
/// rebuild every screen that listens to it. Only the percentage actually
/// rendered is watched, so a listener wakes up when a bar moves, not per tick.
class PlaybackStore extends ChangeNotifier {
  PlaybackStore(this._prefs);

  final SharedPreferences _prefs;

  final Map<String, double> _position = <String, double>{};
  final Map<String, double> _duration = <String, double>{};

  static String _positionKey(String id) => 'vid_progress_$id';
  static String _durationKey(String id) => 'vid_duration_$id';

  double position(String id) =>
      _position[id] ?? _prefs.getDouble(_positionKey(id)) ?? 0;

  double duration(String id) =>
      _duration[id] ?? _prefs.getDouble(_durationKey(id)) ?? 0;

  /// How far through a shiur the listener is, in 0…1, or 0 when it is not worth
  /// resuming (the native app ignored the first and last 10 seconds).
  double fraction(String id) {
    final total = duration(id);
    final done = position(id);
    if (total <= 0 || done <= 10 || done >= total - 10) {
      return 0;
    }
    return done / total;
  }

  /// The position to resume from, or 0 to start at the beginning.
  Duration resumePosition(String id) {
    final seconds = position(id);
    if (seconds <= 10) {
      return Duration.zero;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  bool hasProgress(String id) => fraction(id) > 0;

  /// Records a position. Persisting is cheap and silent; listeners only hear
  /// about it when the visible progress bar changes.
  void save(String id, Duration position, Duration duration) {
    final seconds = position.inMilliseconds / 1000;
    final totalSeconds = duration.inMilliseconds / 1000;

    final previousPercent = (fraction(id) * 100).floor();
    _position[id] = seconds;
    if (totalSeconds > 0) {
      _duration[id] = totalSeconds;
    }

    _prefs.setDouble(_positionKey(id), seconds);
    if (totalSeconds > 0) {
      _prefs.setDouble(_durationKey(id), totalSeconds);
    }

    final newPercent = (fraction(id) * 100).floor();
    if (newPercent != previousPercent) {
      notifyListeners();
    }
  }

  /// Clears the saved position so a finished shiur stops offering to resume.
  void clear(String id) {
    _position.remove(id);
    _duration.remove(id);
    _prefs.remove(_positionKey(id));
    _prefs.remove(_durationKey(id));
    notifyListeners();
  }
}
