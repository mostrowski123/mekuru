import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/services/epub_manga_converter.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/blocking_progress_dialog.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Confirm dialog → progress dialog → off-isolate conversion → SnackBar.
/// A non-manga EPUB gets its own message; other failures end in the generic
/// error SnackBar.
Future<void> runEpubMangaConversion(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.libraryConvertToMangaConfirmTitle),
      content: _confirmBodyWithMokuroLink(ctx),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.libraryConvertToMangaAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  showBlockingProgressDialog(context, l10n.libraryConvertToMangaProgress);

  Object? failure;
  StackTrace? failureStack;
  var pageCount = 0;
  try {
    final converted = await tracedOperation(
      'epub_manga_convert.duration_ms',
      action: () => ref.read(bookRepositoryProvider).convertEpubToManga(book),
    );
    pageCount = converted.totalPages;
  } catch (e, st) {
    failure = e;
    failureStack = st;
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // spinner

  switch (failure) {
    case null:
      logUsage('epub_manga_convert.completed', attrs: {'pages': pageCount});
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryConvertToMangaDone)),
      );
    case EpubNotMangaException():
      logUsage('epub_manga_convert.not_eligible');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryConvertToMangaNotEligible)),
      );
    default:
      Sentry.captureException(failure, stackTrace: failureStack);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.commonErrorWithDetails(details: failure.toString()),
          ),
        ),
      );
  }
}

/// Dialog body with the word "mokuro" linking to the mokuro project.
/// Falls back to plain text if a translation drops the word.
Widget _confirmBodyWithMokuroLink(BuildContext context) {
  final body = context.l10n.libraryConvertToMangaConfirmBody;
  const word = 'mokuro';
  final index = body.indexOf(word);
  if (index < 0) return Text(body);
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: body.substring(0, index)),
        TextSpan(
          text: word,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(
              Uri.parse('https://github.com/kha-white/mokuro'),
              mode: LaunchMode.externalApplication,
            ),
        ),
        TextSpan(text: body.substring(index + word.length)),
      ],
    ),
  );
}
