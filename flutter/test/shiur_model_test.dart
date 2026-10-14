import 'package:beisanytime/models/shiur.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shiur.fromJson', () {
    test('reads the library API payload', () {
      final shiur = Shiur.fromJson(<String, dynamic>{
        'id': '2026-10-14-Rabbi_Hartman-Parsha.mov',
        'title': 'Parsha',
        'rabbi': 'Rabbi Hartman',
        'date': '2026-10-14',
        'thumbnailUrl': 'https://example.test/thumb.jpg',
        'playbackUrl': 'https://example.test/api/video-proxy?key=parsha.mov',
        'source': 'r2',
      });

      expect(shiur.id, '2026-10-14-Rabbi_Hartman-Parsha.mov');
      expect(shiur.title, 'Parsha');
      expect(shiur.rabbiDisplayName, 'Rabbi Hartman');
      expect(shiur.isTime4Mishna, isFalse);
      expect(shiur.thumbnailSource, 'https://example.test/thumb.jpg');
      expect(shiur.playbackUrl, contains('video-proxy'));
    });

    test('tolerates missing optional fields', () {
      final shiur = Shiur.fromJson(<String, dynamic>{
        'id': 'x',
        'title': 'Untitled',
      });

      expect(shiur.rabbi, isNull);
      expect(shiur.tags, isNull);
      expect(shiur.thumbnailSource, isNull);
      expect(shiur.rabbiDisplayName, 'Unknown');
      expect(shiur.dateDisplay, isEmpty);
    });

    test('coerces non-string tags rather than failing the row', () {
      final shiur = Shiur.fromJson(<String, dynamic>{
        'id': 'x',
        'title': 'T',
        'tags': <dynamic>['yomi', 42],
      });

      expect(shiur.tags, <String>['yomi', '42']);
    });
  });

  group('display helpers', () {
    test('prettifies underscore speaker ids', () {
      final shiur = Shiur.fromJson(<String, dynamic>{
        'id': 'a',
        'title': 'T',
        'rabbi': 'rabbi_golker',
      });
      expect(shiur.rabbiDisplayName, 'Rabbi Golker');
      expect(shiur.rabbiColorHex, '#F59E0B');
    });

    test('maps the special speaker names', () {
      expect(
        Shiur.fromJson(<String, dynamic>{
          'id': 'a',
          'title': 'T',
          'rabbi': 'guests',
        }).rabbiDisplayName,
        'Guest Speakers',
      );
      final mishna = Shiur.fromJson(<String, dynamic>{
        'id': 'a',
        'title': 'T',
        'rabbi': 'time4mishna',
      });
      expect(mishna.rabbiDisplayName, 'Time4Mishna');
      expect(mishna.isTime4Mishna, isTrue);
    });

    test('formats the plain ISO dates the API actually sends', () {
      // The API sends yyyy-MM-dd, which the native ISO8601 parser rejected,
      // silently hiding every date.
      final shiur = Shiur.fromJson(<String, dynamic>{
        'id': 'a',
        'title': 'T',
        'date': '2026-10-14',
      });

      expect(shiur.dateDisplay, isNotEmpty);
      expect(shiur.dateDisplay, contains('2026'));
    });

    test('still parses full timestamps', () {
      expect(parseApiDate('2026-10-14T09:30:00Z'), isNotNull);
      expect(parseApiDate('2026-10-14'), isNotNull);
      expect(parseApiDate('not-a-date'), isNull);
      expect(parseApiDate(null), isNull);
      expect(parseApiDate('  '), isNull);
    });

    test('prefers an inline data thumbnail', () {
      final shiur = Shiur.fromJson(<String, dynamic>{
        'id': 'a',
        'title': 'T',
        'thumbnailUrl': 'https://example.test/a.jpg',
        'thumbnailDataUrl': 'data:image/jpeg;base64,AAA',
      });
      expect(shiur.thumbnailSource, 'data:image/jpeg;base64,AAA');
    });
  });
}
