import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

import '../providers/wanikani_providers.dart';
import '../screens/wanikani_settings_screen.dart';

/// WaniKani SRS-stage thresholds offered for
/// [ReaderSettings.furiganaWanikaniMinStage], lowest first: Apprentice I,
/// Guru I, Master, Enlightened, Burned.
const wanikaniStageValues = [1, 5, 7, 8, 9];

/// "Guru and up", "Burned" — the threshold as a range, so a user never has
/// to guess which side of the stage counts.
String wanikaniStageLabel(AppLocalizations l10n, int stage) => switch (stage) {
  1 => l10n.wanikaniStageApprentice,
  5 => l10n.wanikaniStageGuru,
  7 => l10n.wanikaniStageMaster,
  8 => l10n.wanikaniStageEnlightened,
  _ => l10n.wanikaniStageBurned,
};

/// The row the reader's furigana setting shows while WaniKani is selected:
/// the stage threshold picker once kanji stages are synced, otherwise a
/// button to the WaniKani settings screen. A picker (not a segmented row)
/// because five stage names overflow a 360 dp segmented button.
class WanikaniFuriganaRow extends ConsumerWidget {
  const WanikaniFuriganaRow({super.key, required this.onSettingChanged});

  /// Telemetry callback fired once per completed threshold change.
  final void Function(String setting, Object value) onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hasKanji = ref.watch(wanikaniProvider.select((s) => s.hasKanji));
    if (!hasKanji) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('reader-wanikani-link-prompt'),
          onPressed: () {
            AppHaptics.light();
            Navigator.of(context).push(
              namedRoute(
                'wanikani_settings',
                (_) => const WanikaniSettingsScreen(),
              ),
            );
          },
          icon: const Icon(Icons.link),
          label: Text(l10n.readerFuriganaWanikaniLinkPrompt),
        ),
      );
    }

    final theme = Theme.of(context);
    final minStage = ref.watch(
      readerSettingsProvider.select((s) => s.furiganaWanikaniMinStage),
    );
    return ListTile(
      key: const Key('reader-wanikani-stage'),
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.readerFuriganaWanikaniStageTitle),
      trailing: Text(
        wanikaniStageLabel(l10n, minStage),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      onTap: () => showSettingsOptionPickerSheet<int>(
        context: context,
        title: l10n.readerFuriganaWanikaniStagePickerTitle,
        values: wanikaniStageValues,
        selected: minStage,
        labelOf: (stage) => wanikaniStageLabel(l10n, stage),
        onSelected: (stage) {
          ref
              .read(readerSettingsProvider.notifier)
              .setFuriganaWanikaniMinStage(stage);
          onSettingChanged('furigana_wanikani_stage', stage);
        },
      ),
    );
  }
}
