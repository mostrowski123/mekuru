import 'package:flutter/material.dart';
import 'package:mekuru/features/free_books/presentation/widgets/aozora_tab.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Free public-domain books to download straight into the library.
class FreeBooksScreen extends StatelessWidget {
  const FreeBooksScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.freeBooksTitle)),
    body: const AozoraTab(),
  );
}
