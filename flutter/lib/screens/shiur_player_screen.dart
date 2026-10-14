import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/post.dart';
import '../models/shiur.dart';
import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../state/toast_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/account_widgets.dart';
import '../widgets/forui_kit.dart';
import '../widgets/shiur_thumbnail.dart';

/// Plays one shiur and shows everything around it: meta, likes, comments and
/// what to listen to next.
///
/// Video uses the platform player view; audio (Time4Mishna) uses the same
/// controller with designed artwork instead of a video surface, which is how
/// the native app handled both with one `AVPlayer`.
class ShiurPlayerScreen extends StatefulWidget {
  const ShiurPlayerScreen({super.key, required this.shiurId});

  final String shiurId;

  @override
  State<ShiurPlayerScreen> createState() => _ShiurPlayerScreenState();
}

class _ShiurPlayerScreenState extends State<ShiurPlayerScreen> {
  Shiur? _shiur;
  bool _isLoading = true;

  /// Captured once the screen is live, so teardown never has to reach for the
  /// inherited scope while the element is being deactivated.
  AppState? _appState;

  VideoPlayerController? _controller;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1;
  Duration _scrubPosition = Duration.zero;
  bool _isScrubbing = false;
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  int _likeCount = 0;
  bool _userLiked = false;
  int _viewCount = 0;
  List<Comment> _comments = const <Comment>[];
  final TextEditingController _commentText = TextEditingController();
  bool _isPostingComment = false;

  List<Shiur> _related = const <Shiur>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _commentText.dispose();
    unawaited(_teardownPlayer());
    super.dispose();
  }

  // MARK: - Loading

  Future<void> _load() async {
    await _teardownPlayer();
    if (!mounted) {
      return;
    }
    final state = AppScope.of(context);
    _appState = state;
    setState(() => _isLoading = true);

    final loaded = await state.loadShiur(widget.shiurId);
    if (!mounted) {
      return;
    }
    setState(() {
      _shiur = loaded;
      _isLoading = false;
    });
    if (loaded == null) {
      return;
    }

    _buildRelated(loaded, state);
    await _setUpPlayer(loaded);
    unawaited(_loadSocial(loaded));
  }

  void _buildRelated(Shiur shiur, AppState state) {
    final others = state.shiurim
        .where((Shiur item) => item.id != shiur.id)
        .toList();
    // Same speaker first, matching the native ordering.
    others.sort((Shiur a, Shiur b) {
      final aSame = a.rabbi == shiur.rabbi ? 0 : 1;
      final bSame = b.rabbi == shiur.rabbi ? 0 : 1;
      return aSame.compareTo(bSame);
    });
    _related = others.take(8).toList(growable: false);
  }

  Future<void> _setUpPlayer(Shiur shiur) async {
    final url = shiur.playbackUrl;
    if (url == null || url.isEmpty) {
      _showToast('This shiur has no playable media', kind: ToastKind.error);
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
    } catch (error) {
      // `UnimplementedError` means no platform implementation is registered at
      // all (desktop, tests), and `MissingPluginException` means only the
      // channel is absent. Neither is something the listener can act on, so the
      // artwork stands in silently; anything else is a real playback failure
      // worth reporting.
      final unavailable =
          error is UnimplementedError || error is MissingPluginException;
      if (!mounted) {
        await _disposeQuietly(controller);
        return;
      }
      setState(() => _controller = null);
      if (!unavailable) {
        _showToast("Couldn't play this shiur", kind: ToastKind.error);
      }
      return;
    }

    // A newer load may have replaced this controller while we awaited setup.
    if (!mounted || _controller != controller) {
      await controller.dispose();
      return;
    }

    final resume = _appState?.playback.resumePosition(shiur.id) ?? Duration.zero;
    if (resume > Duration.zero) {
      await controller.seekTo(resume);
    }
    await controller.setPlaybackSpeed(_speed);
    controller.addListener(_onTick);

    setState(() {
      _duration = controller.value.duration;
      _position = controller.value.position;
      _scrubPosition = controller.value.position;
    });

    await controller.play();
    if (mounted) {
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _teardownPlayer() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _controller = null;
    _appState?.playback.save(widget.shiurId, _position, _duration);
    controller.removeListener(_onTick);
    await _disposeQuietly(controller);
    _isPlaying = false;
  }

  /// Releases a controller that may never have finished initialising.
  ///
  /// Disposing one whose platform is missing fails the same way `initialize`
  /// did, and there is no resource behind it to release, so the failure is
  /// swallowed here rather than escaping into the framework.
  Future<void> _disposeQuietly(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // Nothing was allocated on the platform; there is nothing to release.
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    final value = controller.value;
    setState(() {
      _position = value.position;
      _duration = value.duration;
      _isPlaying = value.isPlaying;
      if (!_isScrubbing) {
        _scrubPosition = value.position;
      }
    });

    // Writing a position twice a second would be a lot of platform traffic for
    // no benefit; two seconds is finer than the bar it drives.
    final now = DateTime.now();
    if (now.difference(_lastSaved).inSeconds >= 2) {
      _lastSaved = now;
      _appState?.playback
          .save(widget.shiurId, value.position, value.duration);
    }
  }

  // MARK: - Social

  Future<void> _loadSocial(Shiur shiur) async {
    final api = _appState?.api ?? AppScope.of(context).api;
    final id = shiur.id;

    try {
      final views = await api.getViews(id);
      if (mounted) {
        setState(() => _viewCount = views.count);
      }
    } on ApiException {
      // Counts are decorative; the player must still work without them.
    }
    unawaited(api.incrementViews(id));

    try {
      final likes = await api.getLikes(id);
      if (mounted) {
        setState(() {
          _likeCount = likes.count;
          _userLiked = likes.userLiked ?? false;
        });
      }
    } on ApiException {
      // Ignore.
    }

    await _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments =
          await AppScope.of(context).api.getComments(widget.shiurId);
      if (mounted) {
        setState(() => _comments = comments);
      }
    } on ApiException {
      // Ignore.
    }
  }

  Future<void> _toggleLike() async {
    final state = AppScope.of(context);
    final email = state.user?.email;
    if (email == null) {
      _showToast('Please sign in', kind: ToastKind.error);
      return;
    }
    try {
      await state.api.toggleLike(shiurId: widget.shiurId, email: email);
      final likes = await state.api.getLikes(widget.shiurId);
      if (mounted) {
        setState(() {
          _likeCount = likes.count;
          _userLiked = likes.userLiked ?? false;
        });
      }
    } on ApiException {
      _showToast('Failed to like', kind: ToastKind.error);
    }
  }

  Future<void> _postComment() async {
    final state = AppScope.of(context);
    final email = state.user?.email;
    final text = _commentText.text.trim();
    if (email == null || text.isEmpty) {
      return;
    }
    setState(() => _isPostingComment = true);
    try {
      await state.api.postComment(
        shiurId: widget.shiurId,
        text: text,
        email: email,
      );
      _commentText.clear();
      await _loadComments();
    } on ApiException {
      _showToast('Failed to post comment', kind: ToastKind.error);
    } finally {
      if (mounted) {
        setState(() => _isPostingComment = false);
      }
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    final state = AppScope.of(context);
    final email = state.user?.email;
    if (email == null) {
      return;
    }
    try {
      await state.api.deleteComment(
        shiurId: widget.shiurId,
        commentId: comment.id,
        email: email,
      );
      await _loadComments();
    } on ApiException {
      _showToast("Couldn't delete that comment", kind: ToastKind.error);
    }
  }

  Future<void> _share() async {
    final title = _shiur?.title;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: ApiConfig.shareUrlFor(widget.shiurId).toString(),
          subject: title,
        ),
      );
    } on Exception {
      _showToast("Couldn't open the share sheet", kind: ToastKind.error);
    }
  }

  void _showToast(String message, {ToastKind kind = ToastKind.success}) {
    if (!mounted) {
      return;
    }
    AppScope.toastOf(context).show(message, kind: kind);
  }

  // MARK: - Playback actions

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
      await controller.setPlaybackSpeed(_speed);
    }
    if (mounted) {
      setState(() => _isPlaying = controller.value.isPlaying);
    }
  }

  Future<void> _seekTo(Duration target) async {
    await _controller?.seekTo(target);
  }

  Future<void> _skip(Duration delta) async {
    final target = _position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    await _seekTo(clamped);
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    return StateBuilder(
      builder: (BuildContext context, AppState state) =>
          _screen(context, state),
    );
  }

  Widget _screen(BuildContext context, AppState state) {
    final shiur = _shiur;

    return FScaffold(
      header: FHeader.nested(
        title: Text(
          shiur == null ? 'Shiur' : shiur.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        prefixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.arrowLeft),
            onPress: () => Navigator.of(context).pop(),
            semanticsLabel: 'Back',
          ),
        ],
        suffixes: <Widget>[
          FHeaderAction(
            icon: Icon(
              state.isBookmarked(widget.shiurId)
                  ? FLucideIcons.bookMarked
                  : FLucideIcons.bookmark,
            ),
            onPress: () => state.toggleBookmark(widget.shiurId),
            semanticsLabel: state.isBookmarked(widget.shiurId)
                ? 'Remove bookmark'
                : 'Bookmark',
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.share2),
            onPress: _share,
            semanticsLabel: 'Share',
          ),
        ],
      ),
      child: _buildBody(state, shiur),
    );
  }

  Widget _buildBody(AppState state, Shiur? shiur) {
    if (_isLoading) {
      return const Center(child: FCircularProgress());
    }
    if (shiur == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const FAlert(
                title: Text("Couldn't load this shiur"),
                icon: Icon(FLucideIcons.circleAlert),
                variant: FAlertVariant.destructive,
              ),
              const SizedBox(height: 16),
              FButton(onPress: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final palette = context.palette;

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: <Widget>[
        _playerSection(shiur),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                shiur.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: palette.textMain,
                ),
              ),
              const SizedBox(height: 12),
              _metaRow(shiur),
              if ((shiur.description ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  shiur.description!,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: palette.textMain.withValues(alpha: 0.9),
                  ),
                ),
              ],
              if (shiur.tags != null && shiur.tags!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: shiur.tags!
                      .map(
                        (String tag) => FBadge(
                          variant: FBadgeVariant.outline,
                          child: Text(tag, style: const TextStyle(fontSize: 11)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (!shiur.isTime4Mishna) ...<Widget>[
                const SizedBox(height: 22),
                _speedControls(),
              ],
            ],
          ),
        ),
        _divider(),
        _commentsSection(state),
        if (_related.isNotEmpty) ...<Widget>[
          _divider(),
          const SectionHeader('Up Next'),
          ..._related.map(_relatedRow),
        ],
      ],
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
        child: FDivider(),
      );

  Widget _metaRow(Shiur shiur) {
    final palette = context.palette;
    final date = shiur.dateDisplay;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Tint(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: palette.surfaceTertiary,
          radius: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AccentDot(color: colorFromHex(shiur.rabbiColorHex), size: 10),
              const SizedBox(width: 6),
              Text(
                shiur.rabbiDisplayName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (date.isNotEmpty)
          Text(date, style: TextStyle(fontSize: 12, color: palette.textMuted)),
        if (_viewCount > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(FLucideIcons.eye, size: 14, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                '$_viewCount',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ),
        FButton(
          variant: _userLiked
              ? FButtonVariant.primary
              : FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          onPress: _toggleLike,
          prefix: Icon(
            _userLiked ? FLucideIcons.thumbsUp : FLucideIcons.thumbsUp,
            size: 14,
          ),
          child: Text('$_likeCount'),
        ),
      ],
    );
  }

  Widget _speedControls() {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Playback Speed',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: <Widget>[
            for (final double speed in <double>[1, 1.25, 1.5, 2])
              FButton(
                variant: _speed == speed
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                onPress: () => _setSpeed(speed),
                child: Text(
                  speed == speed.roundToDouble()
                      ? '${speed.toInt()}x'
                      : '${speed}x',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _relatedRow(Shiur related) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => AppRoutes.replaceShiur(context, related.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 132,
                height: 74,
                child: ShiurThumbnail(shiur: related, compact: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    related.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    related.rabbiDisplayName,
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Player surfaces

  Widget _playerSection(Shiur shiur) {
    if (shiur.isTime4Mishna) {
      return _audioPlayer(shiur);
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: _isLoading
                    ? const FCircularProgress()
                    : Icon(
                        FLucideIcons.squarePlay,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 36,
                      ),
              ),
            ),
          ),
        ),
      );
    }

    final aspect = controller.value.aspectRatio <= 0
        ? 16 / 9
        : controller.value.aspectRatio;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: <Widget>[
            AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  VideoPlayer(controller),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _togglePlayPause,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x66000000),
                            Color(0x00000000),
                            Color(0x99000000),
                          ],
                          stops: <double>[0, 0.45, 1],
                        ),
                      ),
                      child: Column(
                        children: <Widget>[
                          const Spacer(),
                          Icon(
                            _isPlaying
                                ? FLucideIcons.pause
                                : FLucideIcons.play,
                            color: Colors.white,
                            size: 46,
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _transportRow(onDark: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioPlayer(Shiur shiur) {
    final accent = colorFromHex(shiur.rabbiColorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: <Widget>[
            GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      accent.withValues(alpha: 0.9),
                      accent.withValues(alpha: 0.5),
                    ],
                  ),
                ),
                child: Icon(
                  _isPlaying ? FLucideIcons.pause : FLucideIcons.headphones,
                  size: 38,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              shiur.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Time4Mishna',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppPalette.warning,
              ),
            ),
            const SizedBox(height: 16),
            SeekBar(
              position: _scrubPosition,
              duration: _duration,
              onDark: true,
              onDragStart: () => setState(() => _isScrubbing = true),
              onDragUpdate: (Duration target) =>
                  setState(() => _scrubPosition = target),
              onSeek: (Duration target) async {
                setState(() {
                  _isScrubbing = false;
                  _scrubPosition = target;
                });
                await _seekTo(target);
              },
            ),
            Row(
              children: <Widget>[
                Text(
                  _format(_scrubPosition),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  _format(_duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _transportRow(onDark: true),
          ],
        ),
      ),
    );
  }

  Widget _transportRow({required bool onDark}) {
    final color = onDark ? Colors.white : context.palette.textMain;
    return Row(
      children: <Widget>[
        GestureDetector(
          onTap: () => _skip(const Duration(seconds: -15)),
          child: Icon(FLucideIcons.skipBack, size: 20, color: color),
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: _togglePlayPause,
          child: Icon(
            _isPlaying ? FLucideIcons.pause : FLucideIcons.play,
            size: 22,
            color: color,
          ),
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: () => _skip(const Duration(seconds: 15)),
          child: Icon(FLucideIcons.skipForward, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SeekBar(
            position: _scrubPosition,
            duration: _duration,
            onDark: onDark,
            onDragStart: () => setState(() => _isScrubbing = true),
            onDragUpdate: (Duration target) =>
                setState(() => _scrubPosition = target),
            onSeek: (Duration target) async {
              setState(() {
                _isScrubbing = false;
                _scrubPosition = target;
              });
              await _seekTo(target);
            },
          ),
        ),
        Text(
          '${_format(_scrubPosition)} / ${_format(_duration)}',
          style: TextStyle(color: color, fontSize: 11),
        ),
        GestureDetector(
          onTap: () {
            final controller = _controller;
            if (controller == null) {
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _FullscreenVideoPage(controller: controller),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Icon(FLucideIcons.maximize, size: 18, color: color),
          ),
        ),
      ],
    );
  }

  // MARK: - Comments

  Widget _commentsSection(AppState state) {
    final palette = context.palette;
    final user = state.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Comments',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: palette.textMain,
            ),
          ),
          const SizedBox(height: 16),
          if (user != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                UserAvatar(picture: user.picture, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      FTextField(
                        control:
                            FTextFieldControl.managed(controller: _commentText),
                        hint: 'Add a comment...',
                        minLines: 2,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FButton(
                          onPress: _isPostingComment ? null : _postComment,
                          child: Text(
                            _isPostingComment ? 'Posting…' : 'Post Comment',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            const FAlert(
              title: Text('Sign in to join the conversation.'),
              icon: Icon(FLucideIcons.userRound),
            ),
          const SizedBox(height: 16),
          if (_comments.isEmpty)
            Text(
              'No comments yet.',
              style: TextStyle(fontSize: 14, color: palette.textMuted),
            )
          else
            ..._comments.map(
              (Comment comment) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Tint(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              comment.authorLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            comment.formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        comment.text,
                        style: TextStyle(fontSize: 15, color: palette.textMain),
                      ),
                      if (state.isAdmin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: FButton(
                            variant: FButtonVariant.ghost,
                            size: FButtonSizeVariant.sm,
                            onPress: () => _deleteComment(comment),
                            child: const Text('Delete'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    if (duration.inMilliseconds <= 0) {
      return '0:00';
    }
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Full-screen playback on the same controller, so the position carries over.
class _FullscreenVideoPage extends StatelessWidget {
  const _FullscreenVideoPage({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final aspect = controller.value.aspectRatio <= 0
        ? 16 / 9
        : controller.value.aspectRatio;

    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: <Widget>[
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      FLucideIcons.x,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
