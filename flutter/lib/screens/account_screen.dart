import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../models/user_profile.dart';
import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../state/toast_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/account_widgets.dart';
import '../widgets/forui_kit.dart';

/// Account: who is signed in, what an admin can publish, and the settings that
/// belong to this device.
///
/// The page is one scrolling list of labelled Forui tile groups, so the reading
/// order is the same as the native sheet's: identity first, then the actions
/// that change something, then the device settings, then the way out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _password = TextEditingController();
  List<UploadLog> _recentUploads = const <UploadLog>[];
  bool _isLoadingLogs = false;
  bool _seededPassword = false;

  /// The list is a comfortable single column on a phone and stops growing on an
  /// iPad, where full-width rows read as a table rather than a settings page.
  static const double _contentWidth = 560;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededPassword) {
      return;
    }
    _seededPassword = true;
    final state = AppScope.of(context);
    _password.text = state.uploadPassword ?? '';
    if (state.isAdmin) {
      _loadUploads();
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  // MARK: - Actions

  Future<void> _loadUploads() async {
    final state = AppScope.of(context);
    final credentials = state.adminCredentials;
    if (credentials == null) {
      return;
    }
    setState(() => _isLoadingLogs = true);
    try {
      final logs = await state.api.getUploadLogs(credentials: credentials);
      if (mounted) {
        setState(() => _recentUploads = logs);
      }
    } on ApiException catch (error) {
      if (mounted) {
        AppScope.toastOf(context).show(error.message, kind: ToastKind.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingLogs = false);
      }
    }
  }

  Future<void> _savePassword(AppState state) async {
    final toast = AppScope.toastOf(context);
    await state.setUploadPassword(_password.text);
    toast.show(
      _password.text.trim().isEmpty
          ? 'Upload password cleared'
          : 'Upload password saved',
    );
    await _loadUploads();
  }

  Future<void> _deleteUpload(UploadLog log) async {
    final state = AppScope.of(context);
    final toast = AppScope.toastOf(context);
    final credentials = state.adminCredentials;
    if (credentials == null) {
      toast.show('Save the upload password first', kind: ToastKind.error);
      return;
    }
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete this shiur?',
      message: '${log.filename} will be removed from the library.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await state.api.deleteShiur(id: log.filename, credentials: credentials);
      if (!mounted) {
        return;
      }
      setState(() {
        _recentUploads = _recentUploads
            .where((UploadLog item) => item.id != log.id)
            .toList(growable: false);
      });
      await state.refresh();
      toast.show('Deleted');
    } on ApiException catch (error) {
      toast.show(error.message, kind: ToastKind.error);
    }
  }

  Future<void> _signOut(AppState state) async {
    await state.signOut();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // MARK: - Layout

  @override
  Widget build(BuildContext context) {
    return StateBuilder(
      builder: (BuildContext context, AppState state) =>
          _screen(context, state),
    );
  }

  Widget _screen(BuildContext context, AppState state) {
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Account'),
        prefixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.x),
            onPress: () => Navigator.of(context).pop(),
            semanticsLabel: 'Close',
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 56),
            children: <Widget>[
              _IdentityCard(state: state),
              ..._adminSections(state),
              const SizedBox(height: 26),
              _Group(
                label: 'Library',
                children: <FTile>[
                  FTile(
                    prefix: const Icon(FLucideIcons.library, size: 16),
                    title: const Text('Shiurim in the library'),
                    subtitle: state.libraryError == null
                        ? null
                        : Text(state.libraryError!),
                    details: Text('${state.shiurim.length}'),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.refreshCw, size: 16),
                    title: const Text('Refresh library'),
                    subtitle: const Text('Re-fetch the catalogue'),
                    onPress: () async {
                      final toast = AppScope.toastOf(context);
                      await state.refresh();
                      toast.show('Library refreshed');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 26),
              _Group(
                label: 'Appearance',
                children: <FTile>[
                  FTile(
                    prefix: Icon(
                      state.isDarkMode ? FLucideIcons.sun : FLucideIcons.moon,
                      size: 16,
                    ),
                    title: const Text('Dark mode'),
                    suffix: FSwitch(
                      value: state.isDarkMode,
                      onChange: (_) => state.toggleDarkMode(),
                    ),
                    onPress: state.toggleDarkMode,
                  ),
                ],
              ),
              if (state.isSignedIn) ...<Widget>[
                const SizedBox(height: 26),
                _Group(
                  label: 'Session',
                  children: <FTile>[
                    FTile(
                      variant: FItemVariant.destructive,
                      prefix: const Icon(FLucideIcons.logOut, size: 16),
                      title: const Text('Sign out'),
                      subtitle: const Text(
                        'Forgot on this device; the library stays',
                      ),
                      onPress: () => _signOut(state),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              const _Footer(),
            ],
          ),
        ),
      ),
    );
  }

  /// Publishing controls, only for an admin account.
  List<Widget> _adminSections(AppState state) {
    if (!state.isAdmin) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: 26),
      _Group(
        label: 'Publishing',
        description:
            'Shiurim you upload appear in the library once the worker '
            'has them.',
        children: <FTile>[
          FTile(
            prefix: const Icon(FLucideIcons.arrowUpFromLine, size: 16),
            title: const Text('Upload a shiur'),
            subtitle: const Text('Video or audio, with a generated thumbnail'),
            onPress: () {
              Navigator.of(context).pop();
              AppRoutes.openUpload(context);
            },
          ),
        ],
      ),
      const SizedBox(height: 26),
      _AdminPasswordCard(
        controller: _password,
        ready: state.adminCredentials != null,
        hasStoredPassword: state.uploadPassword != null,
        onSave: () => _savePassword(state),
        onClear: () {
          _password.clear();
          _savePassword(state);
        },
      ),
      const SizedBox(height: 26),
      if (_isLoadingLogs)
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
          ),
        )
      else
        _Group(
          label: 'Recent uploads',
          description: _recentUploads.isEmpty
              ? 'Nothing recorded yet.'
              : 'The worker keeps the last year of uploads.',
          children: <FTile>[
            if (_recentUploads.isEmpty)
              FTile(
                prefix: const Icon(FLucideIcons.upload, size: 16),
                title: const Text('No uploads recorded yet'),
                enabled: false,
              )
            else
              ..._recentUploads.map(
                (UploadLog log) => FTile(
                  title: Text(
                    log.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${log.name} · ${log.formattedDate}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  suffix: FHeaderAction(
                    icon: const Icon(FLucideIcons.trash2, size: 16),
                    onPress: () => _deleteUpload(log),
                    semanticsLabel: 'Delete shiur',
                  ),
                ),
              ),
            FTile(
              prefix: const Icon(FLucideIcons.refreshCw, size: 16),
              title: const Text('Reload uploads'),
              onPress: _loadUploads,
            ),
          ],
        ),
    ];
  }
}

/// Who is signed in, or the invitation to sign in.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final user = state.user;
    if (user == null) {
      return const _SignedOutCard();
    }

    final palette = context.palette;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            UserAvatar(picture: user.picture, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: palette.textMain,
                          ),
                        ),
                      ),
                      if (state.isAdmin) ...<Widget>[
                        const SizedBox(width: 8),
                        FBadge(
                          variant: FBadgeVariant.secondary,
                          child: const Text(
                            'Admin',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.isAdmin
                        ? 'Signed in with Google · can publish'
                        : 'Signed in with Google',
                    style: TextStyle(fontSize: 11, color: palette.textFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signed-out state: why signing in is worth it, then the button.
class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(FLucideIcons.circleUser, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Sign in to sync your activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: palette.textMain,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Likes, comments and bookmarks use the same Google '
                        'account as the website.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const GoogleSignInButton(),
          ],
        ),
      ),
    );
  }
}

/// The admin upload password: the field, the save action and why it is needed.
class _AdminPasswordCard extends StatelessWidget {
  const _AdminPasswordCard({
    required this.controller,
    required this.ready,
    required this.hasStoredPassword,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool ready;
  final bool hasStoredPassword;
  final Future<void> Function() onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(FLucideIcons.shieldCheck, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Admin access',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (ready)
                  FBadge(
                    variant: FBadgeVariant.secondary,
                    child: const Text('Active', style: TextStyle(fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FTextField(
              control: FTextFieldControl.managed(controller: controller),
              label: const Text('Upload password'),
              obscureText: true,
              hint: 'The worker checks this on every admin request',
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder:
                  (BuildContext context, TextEditingValue value, Widget? _) {
                    final typed = value.text.trim().isNotEmpty;
                    return Row(
                      children: <Widget>[
                        FButton(
                          onPress: typed ? () => onSave() : null,
                          prefix: const Icon(FLucideIcons.key, size: 16),
                          child: const Text('Save'),
                        ),
                        if (hasStoredPassword) ...<Widget>[
                          const SizedBox(width: 10),
                          FButton(
                            variant: FButtonVariant.outline,
                            onPress: onClear,
                            child: const Text('Clear'),
                          ),
                        ],
                      ],
                    );
                  },
            ),
            const SizedBox(height: 12),
            Text(
              'Kept in the platform keychain, never in the app bundle. Only '
              'admin accounts can publish, and the library stays readable '
              'without it.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled group of tiles.
///
/// The group's own scrollable is switched off: it is laid out inside the page's
/// list, and a nested scrollable of the same axis would swallow the drag that
/// belongs to the page.
class _Group extends StatelessWidget {
  const _Group({required this.label, this.description, required this.children});

  final String label;
  final String? description;
  final List<FTile> children;

  @override
  Widget build(BuildContext context) {
    return FTileGroup(
      label: Text(label),
      description: description == null ? null : Text(description!),
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Text(
          'Beis Anytime',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Library and community data from beisanytime.com',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: palette.textFaint),
        ),
      ],
    );
  }
}
