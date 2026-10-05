import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/widgets/aozora_tab.dart';
import 'package:mekuru/features/free_books/presentation/widgets/tadoku_tab.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Free books to download straight into the library: graded readers, then
/// the Aozora Bunko classics. Reopens on the tab last shown.
class FreeBooksScreen extends ConsumerStatefulWidget {
  const FreeBooksScreen({super.key});

  @override
  ConsumerState<FreeBooksScreen> createState() => _FreeBooksScreenState();
}

class _FreeBooksScreenState extends ConsumerState<FreeBooksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(
        length: 2,
        vsync: this,
        initialIndex: ref.read(freeBooksTabProvider),
      )..addListener(
        () => ref.read(freeBooksTabProvider.notifier).state = _tabs.index,
      );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.freeBooksTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.freeBooksTabGradedReaders),
            Tab(text: l10n.freeBooksTabAozora),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // Kept once built, so going back to a tab doesn't parse its catalog
        // again (Aozora's takes a moment).
        children: const [
          _KeptAlive(child: TadokuTab()),
          _KeptAlive(child: AozoraTab()),
        ],
      ),
    );
  }
}

class _KeptAlive extends StatefulWidget {
  const _KeptAlive({required this.child});

  final Widget child;

  @override
  State<_KeptAlive> createState() => _KeptAliveState();
}

class _KeptAliveState extends State<_KeptAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
