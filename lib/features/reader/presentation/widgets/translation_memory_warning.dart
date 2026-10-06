import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/platform/device_memory.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Before sentence translation is set up on a phone low on memory, says it
/// may be slow or close Mekuru and where to turn it off. True to go ahead;
/// "Turn off" switches the Sentence tab off and returns false, as does
/// dismissing the dialog.
Future<bool> confirmTranslationMemory(BuildContext context) async {
  if (!await deviceLowOnMemory()) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.sentenceTranslationLowMemoryTitle),
      content: Text(l.sentenceTranslationLowMemoryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.sentenceTranslationTurnOff),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.commonContinue),
        ),
      ],
    ),
  );
  if (proceed == false && context.mounted) {
    ProviderScope.containerOf(context, listen: false)
        .read(sentenceTranslationModeProvider.notifier)
        .setMode(SentenceTranslationMode.off);
  }
  return proceed == true;
}

/// Before High quality is set up on a phone with under 8 GB or 3 GB free.
/// True to go ahead; "Use Standard" or dismissing switches the model to
/// Standard (it may already be High) and returns false.
Future<bool> confirmHighQualityMemory(BuildContext context) async {
  if (!await deviceLowOnMemory(minTotalMb: 7168, minFreeMb: 3072)) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.sentenceTranslationLowMemoryTitle),
      content: Text(l.translationHighQualityLowMemoryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.translationHighQualityUseStandard),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.commonContinue),
        ),
      ],
    ),
  );
  if (proceed != true && context.mounted) {
    ProviderScope.containerOf(context, listen: false)
        .read(translationModelProvider.notifier)
        .setChoice(TranslationModelChoice.standard);
    unawaited(GemmaTranslation.instance.close());
  }
  return proceed == true;
}
