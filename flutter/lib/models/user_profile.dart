import 'package:intl/intl.dart';

/// The signed-in Google account, persisted in secure storage.
class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.picture,
  });

  final String name;
  final String email;
  final String picture;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      picture: json['picture'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'email': email,
        'picture': picture,
      };
}

/// Everything an admin request needs: the verified Google identity plus the
/// server-side upload password the worker validates.
class AdminCredentials {
  const AdminCredentials({
    required this.email,
    required this.name,
    required this.password,
  });

  final String email;
  final String name;
  final String password;
}

/// One row of the admin upload history.
class UploadLog {
  const UploadLog({
    required this.timestamp,
    required this.email,
    required this.name,
    required this.filename,
    required this.type,
  });

  final String timestamp;
  final String email;
  final String name;
  final String filename;
  final String type;

  factory UploadLog.fromJson(Map<String, dynamic> json) {
    return UploadLog(
      timestamp: json['timestamp'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }

  String get id => '$timestamp-$filename';

  String get formattedDate {
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return timestamp;
    }
    return DateFormat.yMMMd().add_jm().format(parsed.toLocal());
  }
}
