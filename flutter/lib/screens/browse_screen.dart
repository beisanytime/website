import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../app_scope.dart';
import '../models/shiur.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/library_status.dart';
import '../widgets/shiur_grid.dart';
import 'speakers_screen.dart';

enum _BrowseMode { shiurim, speakers }

/// Library browsing: search over all shiurim, or the speaker grid.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _search = TextEditingController();
  _BrowseMode _mode = _BrowseMode.shiurim;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final delegate = shiurGridDelegateFor(constraints.maxWidth);
        final speakerDelegate = speakerGridDelegateFor(constraints.maxWidth);
        final results = state.filterShiurim(_search.text);

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: <Widget>[
                    for (final _BrowseMode mode in _BrowseMode.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: FButton(
                          variant: _mode == mode
                              ? FButtonVariant.primary
                              : FButtonVariant.outline,
                          onPress: () => setState(() => _mode = mode),
                          child: Text(
                            mode == _BrowseMode.shiurim ? 'Shiurim' : 'Speakers',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_mode == _BrowseMode.speakers)
              SliverPadding(
                padding: const EdgeInsets.only(top: 20),
                sliver: SliverSpeakersGrid(delegate: speakerDelegate),
              )
            else ..._shiurimSlivers(state, results, delegate),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  List<Widget> _shiurimSlivers(
    AppState state,
    List<Shiur> results,
    SliverGridDelegate delegate,
  ) {
    final palette = context.palette;
    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: FTextField(
            control: FTextFieldControl.managed(
              controller: _search,
              onChange: (_) => setState(() {}),
            ),
            hint: 'Search shiurim...',
          ),
        ),
      ),
      if (!state.hasLibrary)
        const SliverToBoxAdapter(child: LibraryStatusView())
      else if (results.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: FAlert(
              title: const Text('No Results Found'),
              subtitle: const Text('Try a different search term'),
              icon: const Icon(FLucideIcons.searchX),
            ),
          ),
        )
      else ...<Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              '${results.length} Shiurim',
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ),
        ),
        SliverShiurGrid(shiurim: results, delegate: delegate),
      ],
    ];
  }
}
