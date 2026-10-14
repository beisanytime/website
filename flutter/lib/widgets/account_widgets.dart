import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../models/user_profile.dart';
import '../services/google_auth_service.dart';

/// Circular avatar with a graceful placeholder.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.picture, required this.size});

  final String picture;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (picture.isEmpty) {
      // An empty URL is not an image, and handing one to an [FAvatar] would
      // surface as a load error; the icon is the honest fallback.
      return FAvatar.raw(
        size: size,
        child: Icon(FLucideIcons.userRound, size: size * 0.6),
      );
    }
    return FAvatar(
      image: NetworkImage(picture),
      size: size,
      fallback: Icon(FLucideIcons.userRound, size: size * 0.6),
    );
  }
}

/// Account affordance for the header: the signed-in avatar with an Admin badge,
/// or a Sign In prompt.
class AccountToolbarLabel extends StatelessWidget {
  const AccountToolbarLabel({
    super.key,
    required this.user,
    required this.isAdmin,
  });

  final UserProfile? user;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final signedIn = user;
    if (signedIn == null) {
      return const Text('Sign In', style: TextStyle(fontSize: 13));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UserAvatar(picture: signedIn.picture, size: 28),
        if (isAdmin) ...<Widget>[
          const SizedBox(width: 6),
          FBadge(
            variant: FBadgeVariant.secondary,
            child: const Text('Admin', style: TextStyle(fontSize: 10)),
          ),
        ],
      ],
    );
  }
}

/// The header's account button, wired to the account sheet.
class AccountToolbarButton extends StatelessWidget {
  const AccountToolbarButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: AccountToolbarLabel(user: state.user, isAdmin: state.isAdmin),
      ),
    );
  }
}

/// "Sign in with Google" with inline diagnostics.
///
/// When the iOS OAuth client ID hasn't been configured yet, the reason is shown
/// here rather than failing silently behind a browser that can never call back.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, this.title = 'Sign in with Google'});

  final String title;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final problem = GoogleAuthConfig.configurationProblem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FButton(
          onPress: state.isSigningIn ? null : state.signInWithGoogle,
          prefix: state.isSigningIn
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: FCircularProgress(
                    size: FCircularProgressSizeVariant.sm,
                  ),
                )
              : const Icon(FLucideIcons.externalLink, size: 16),
          child: Text(state.isSigningIn ? 'Signing in…' : title),
        ),
        if (state.authError != null) ...<Widget>[
          const SizedBox(height: 10),
          FAlert(
            title: const Text('Sign-in failed'),
            subtitle: Text(state.authError!),
            icon: const Icon(FLucideIcons.circleAlert),
            variant: FAlertVariant.destructive,
          ),
        ] else if (problem != null) ...<Widget>[
          const SizedBox(height: 10),
          FAlert(
            title: const Text('Not configured'),
            subtitle: Text(problem),
            icon: const Icon(FLucideIcons.badgeInfo),
          ),
        ],
      ],
    );
  }
}

/// The destructive "are you sure" dialog used for deletes.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FAlert(
            title: Text(title),
            subtitle: Text(message),
            icon: const Icon(FLucideIcons.triangleAlert),
            variant: FAlertVariant.destructive,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
