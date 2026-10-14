import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../state/app_state.dart';

/// The tab bar, matching the five tabs in `BottomNavView`.
class BottomNavView extends StatelessWidget {
  const BottomNavView({super.key});

  static const List<AppTab> tabs = <AppTab>[
    AppTab.home,
    AppTab.browse,
    AppTab.community,
    AppTab.bookmarks,
    AppTab.time4mishna,
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final index = tabs.indexOf(state.tab);

    return FBottomNavigationBar(
      index: index < 0 ? 0 : index,
      onChange: (int next) {
        if (next >= 0 && next < tabs.length) {
          state.setTab(tabs[next]);
        }
      },
      children: const <FBottomNavigationBarItem>[
        FBottomNavigationBarItem(
          icon: Icon(FLucideIcons.house),
          label: Text('Home'),
        ),
        FBottomNavigationBarItem(
          icon: Icon(FLucideIcons.search),
          label: Text('Browse'),
        ),
        FBottomNavigationBarItem(
          icon: Icon(FLucideIcons.megaphone),
          label: Text('Feed'),
        ),
        FBottomNavigationBarItem(
          icon: Icon(FLucideIcons.bookmark),
          label: Text('Later'),
        ),
        FBottomNavigationBarItem(
          icon: Icon(FLucideIcons.clock3),
          label: Text('Mishna'),
        ),
      ],
    );
  }
}
