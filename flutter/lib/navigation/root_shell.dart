import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../state/app_state.dart';
import '../widgets/account_widgets.dart';
import '../widgets/bottom_nav.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/browse_screen.dart';
import '../screens/community_screen.dart';
import '../screens/home_screen.dart';
import '../screens/speakers_screen.dart';
import '../screens/time4mishna_screen.dart';
import 'app_routes.dart';

/// The root of the app: one tab at a time, with the Forui header and tab bar.
///
/// Detail screens are pushed as full routes on top, which is what keeps the
/// header honest — a root page has no back button, a pushed page has exactly
/// one.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    return StateBuilder(
      builder: (BuildContext context, AppState state) => _shell(context, state),
    );
  }

  Widget _shell(BuildContext context, AppState state) {
    return FScaffold(
      header: FHeader(
        title: Text(state.tab.title),
        suffixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.refreshCw),
            onPress: state.refresh,
            semanticsLabel: 'Refresh library',
          ),
          if (state.isAdmin)
            FHeaderAction(
              icon: const Icon(FLucideIcons.arrowUpFromLine),
              onPress: () => AppRoutes.openUpload(context),
              semanticsLabel: 'Upload a shiur',
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: AccountToolbarButton(
              onPressed: () => AppRoutes.openAccount(context),
            ),
          ),
        ],
      ),
      footer: const BottomNavView(),
      child: _tabBody(state.tab),
    );
  }

  Widget _tabBody(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return const HomeScreen();
      case AppTab.browse:
        return const BrowseScreen();
      case AppTab.community:
        return const CommunityScreen();
      case AppTab.speakers:
        return const SpeakersScreen();
      case AppTab.bookmarks:
        return const BookmarksScreen();
      case AppTab.time4mishna:
        return const Time4MishnaScreen();
    }
  }
}
