import 'package:intl/intl.dart';

/// A shiur as the library API returns it.
///
/// Field-for-field the same as `Shiur.swift`, including the derived display
/// values, so the Flutter screens can read the same way the SwiftUI ones did.
class Shiur {
  const Shiur({
    required this.id,
    required this.title,
    this.rabbi,
    this.description,
    this.date,
    this.tags,
    this.thumbnailUrl,
    this.thumbnailDataUrl,
    this.playbackUrl,
  });

  final String id;
  final String title;
  final String? rabbi;
  final String? description;
  final String? date;
  final List<String>? tags;
  final String? thumbnailUrl;
  final String? thumbnailDataUrl;
  final String? playbackUrl;

  factory Shiur.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    return Shiur(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      rabbi: json['rabbi'] as String?,
      description: json['description'] as String?,
      date: json['date'] as String?,
      tags: rawTags is List
          ? rawTags.map((dynamic tag) => '$tag').toList(growable: false)
          : null,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      thumbnailDataUrl: json['thumbnailDataUrl'] as String?,
      playbackUrl: json['playbackUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'rabbi': rabbi,
        'description': description,
        'date': date,
        'tags': tags,
        'thumbnailUrl': thumbnailUrl,
        'thumbnailDataUrl': thumbnailDataUrl,
        'playbackUrl': playbackUrl,
      };

  /// "Rabbi Hartman", "Guest Speakers", "Time4Mishna" — matches `rabbiDisplayName`.
  String get rabbiDisplayName {
    final value = rabbi;
    if (value == null || value.isEmpty) {
      return 'Unknown';
    }
    final lower = value.toLowerCase();
    if (lower == 'guests') {
      return 'Guest Speakers';
    }
    if (lower == 'time4mishna') {
      return 'Time4Mishna';
    }
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((String word) => word.isNotEmpty)
        .map((String word) =>
            word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  /// The shiur's date in the same medium style the SwiftUI app used.
  ///
  /// The API sends plain `yyyy-MM-dd` values, so this parses those as well as
  /// full ISO-8601 timestamps. (`ISO8601DateFormatter` in the native app only
  /// accepted the timestamp form, which silently hid every date.)
  String get dateDisplay {
    final parsed = parseApiDate(date);
    if (parsed == null) {
      return '';
    }
    return DateFormat.yMMMd().format(parsed);
  }

  bool get isTime4Mishna => rabbi?.toLowerCase() == 'time4mishna';

  /// The server only stores thumbnails for video, so audio shiurim fall back to
  /// designed artwork (see [AudioArtwork]).
  String? get thumbnailSource {
    final dataUrl = thumbnailDataUrl;
    if (dataUrl != null && dataUrl.isNotEmpty) {
      return dataUrl;
    }
    final url = thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      return url;
    }
    return null;
  }

  /// Speaker accent colour, used for the dot on cards and the player meta pill.
  String get rabbiColorHex {
    switch (rabbi?.toLowerCase()) {
      case 'rabbi_hartman':
      case 'rabbi hartman':
        return '#3B82F6';
      case 'rabbi_rosenfeld':
      case 'rabbi rosenfeld':
        return '#22C55E';
      case 'rabbi_golker':
      case 'rabbi golker':
        return '#F59E0B';
      case 'guests':
        return '#A855F7';
      case 'time4mishna':
        return '#F59E0B';
      default:
        return '#64748B';
    }
  }

  @override
  bool operator ==(Object other) => other is Shiur && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Parses `yyyy-MM-dd` or a full ISO-8601 timestamp into a local date.
///
/// Returns `null` when the value is missing or unreadable.
DateTime? parseApiDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final trimmed = value.trim();
  final full = DateTime.tryParse(trimmed);
  if (full != null) {
    return full;
  }
  try {
    return DateFormat('yyyy-MM-dd').parseStrict(trimmed);
  } on FormatException {
    return null;
  }
}
