import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';

final userFontStoreProvider = Provider<UserFontStore>((ref) => UserFontStore());

/// The fonts the user added. Invalidate after an import or a removal.
final userFontsProvider = FutureProvider<List<UserFont>>(
  (ref) => ref.watch(userFontStoreProvider).list(),
);
