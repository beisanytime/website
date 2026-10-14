import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../models/post.dart';
import '../services/api_client.dart';
import '../state/toast_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/account_widgets.dart';
import '../widgets/forui_kit.dart';

/// The community feed: admin announcements, with a composer for admins.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<Post> _posts = const <Post>[];
  bool _isLoading = true;
  String? _loadError;
  bool _isPosting = false;
  final TextEditingController _composer = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPosts());
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final posts = await AppScope.of(context).api.getPosts();
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = posts;
        _loadError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // Surface the real reason rather than a generic "failed" message.
      setState(() => _loadError = error.message);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitPost() async {
    final state = AppScope.of(context);
    final toast = AppScope.toastOf(context);
    final user = state.user;
    final text = _composer.text.trim();
    if (user == null || text.isEmpty) {
      return;
    }
    setState(() => _isPosting = true);
    try {
      await state.api.createPost(content: text, user: user);
      _composer.clear();
      toast.show('Posted!');
      await _loadPosts();
    } on ApiException {
      toast.show('Failed to post', kind: ToastKind.error);
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  Future<void> _deletePost(Post post) async {
    final state = AppScope.of(context);
    final toast = AppScope.toastOf(context);
    final email = state.user?.email;
    if (email == null) {
      return;
    }
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete this announcement?',
      message: 'It will be removed for everyone. This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await state.api.deletePost(id: post.id, email: email);
      toast.show('Post deleted');
      await _loadPosts();
    } on ApiException {
      toast.show('Failed to delete', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      children: <Widget>[
        if (state.isAdmin && state.user != null)
          _Composer(
            controller: _composer,
            picture: state.user!.picture,
            isPosting: _isPosting,
            onSubmit: _submitPost,
          )
        else
          const _AnnouncementNotice(),
        if (_isLoading)
          ...List<Widget>.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: context.palette.surfaceTertiary,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
        else if (_loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              children: <Widget>[
                FAlert(
                  title: const Text("Couldn't Load the Feed"),
                  subtitle: Text(_loadError!),
                  icon: const Icon(FLucideIcons.wifiOff),
                  variant: FAlertVariant.destructive,
                ),
                const SizedBox(height: 14),
                FButton(onPress: _loadPosts, child: const Text('Reload')),
              ],
            ),
          )
        else if (_posts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 40, 16, 0),
            child: FAlert(
              title: Text('No Announcements Yet'),
              icon: Icon(FLucideIcons.megaphone),
            ),
          )
        else
          ..._posts.map(
            (Post post) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: PostCardView(
                post: post,
                isAdmin: state.isAdmin,
                onDelete: () => _deletePost(post),
              ),
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.picture,
    required this.isPosting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String picture;
  final bool isPosting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Tint(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Post Announcement',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                UserAvatar(picture: picture, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(controller: controller),
                    hint: 'Write an announcement…',
                    minLines: 3,
                    maxLines: 6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                onPress: isPosting
                    ? null
                    : () {
                        if (controller.text.trim().isEmpty) {
                          return;
                        }
                        onSubmit();
                      },
                child: Text(isPosting ? 'Posting…' : 'Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementNotice extends StatelessWidget {
  const _AnnouncementNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Tint(
        padding: const EdgeInsets.all(14),
        color: context.palette.surfaceTertiary,
        child: const Row(
          children: <Widget>[
            Icon(FLucideIcons.megaphone, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Official Announcements and Updates',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One announcement.
class PostCardView extends StatelessWidget {
  const PostCardView({
    super.key,
    required this.post,
    required this.isAdmin,
    required this.onDelete,
  });

  final Post post;
  final bool isAdmin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AppCard(
      color: palette.surfaceSecondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                UserAvatar(picture: post.avatarUrl, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              post.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(FLucideIcons.badgeCheck, size: 14),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        post.formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              post.content,
              style: TextStyle(
                fontSize: 15,
                color: palette.textMain,
                height: 1.35,
              ),
            ),
            if (isAdmin) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FButton(
                  variant: FButtonVariant.destructive,
                  size: FButtonSizeVariant.sm,
                  onPress: onDelete,
                  child: const Text('Delete'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
