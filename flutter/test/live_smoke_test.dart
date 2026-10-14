@Tags(<String>['live'])
library;

import 'package:beisanytime/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hits the production API, so it is opt-in:
/// `flutter test --tags live --run-skipped`.
void main() {
  test('live library loads through ApiClient', () async {
    final api = ApiClient();
    final shiurim = await api.getAllShiurim();
    // ignore: avoid_print
    print('LIVE COUNT=${shiurim.length}');
    if (shiurim.isNotEmpty) {
      final first = shiurim.first;
      // ignore: avoid_print
      print('FIRST=${first.id} date=${first.dateDisplay} '
          'playback=${first.playbackUrl != null} thumb=${first.thumbnailSource != null}');
    }
    expect(shiurim, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
