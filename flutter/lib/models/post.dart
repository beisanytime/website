import 'package:intl/intl.dart';

/// A community announcement. Mirrors `Post.swift`, including the snake_case
/// wire keys.
class Post {
  const Post({
    required this.id,
    required this.content,
    required this.displayName,
    required this.avatarUrl,
    required this.createdAt,
  });

  final int id;
  final String content;
  final String displayName;
  final String avatarUrl;
  final double createdAt;

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: (json['id'] as num?)?.toInt() ?? 0,
      content: json['content'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0,
    );
  }

  /// `created_at` is in seconds.
  String get formattedDate {
    final date = DateTime.fromMillisecondsSinceEpoch(
      (createdAt * 1000).round(),
    );
    return DateFormat.yMMMd().add_jm().format(date);
  }
}

/// A comment on a shiur from the views worker.
class Comment {
  const Comment({
    required this.id,
    required this.text,
    required this.email,
    this.displayName,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String email;
  final String? displayName;
  final double createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: '${json['id'] ?? ''}',
      text: json['text'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String?,
      createdAt: (json['createdAt'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Comment timestamps arrive in milliseconds, unlike post timestamps.
  String get formattedDate {
    final date = DateTime.fromMillisecondsSinceEpoch(
      (createdAt / 1000).round(),
    );
    return DateFormat.yMMMd().format(date);
  }

  String get authorLabel {
    final name = displayName;
    if (name != null && name.trim().isNotEmpty) {
      return name;
    }
    return email;
  }
}

class CommentResponse {
  const CommentResponse(this.comments);

  final List<Comment> comments;

  factory CommentResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['comments'];
    return CommentResponse(
      raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(Comment.fromJson)
              .toList(growable: false)
          : const <Comment>[],
    );
  }
}

class LikesResponse {
  const LikesResponse({required this.count, this.userLiked});

  final int count;
  final bool? userLiked;

  factory LikesResponse.fromJson(Map<String, dynamic> json) {
    return LikesResponse(
      count: (json['count'] as num?)?.toInt() ?? 0,
      userLiked: json['userLiked'] as bool?,
    );
  }
}

class ViewsResponse {
  const ViewsResponse(this.count);

  final int count;

  factory ViewsResponse.fromJson(Map<String, dynamic> json) {
    return ViewsResponse((json['count'] as num?)?.toInt() ?? 0);
  }
}
