import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/mokuro_models.dart';
import '../../data/services/ocr_background_worker.dart';
import '../../data/services/ocr_page_selection.dart';
import '../providers/local_ocr_providers.dart';
import '../providers/ocr_progress_provider.dart';
import '../services/ocr_purchase_flow.dart';
import 'local_ocr_widgets.dart';

Future<void> showOcrActionSheet(
  BuildContext context,
  Book book, {
  List<int> visiblePages = const [],
  MokuroBook? initialManga,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => OcrActionSheet(
      book: book,
      visiblePages: visiblePages,
      initialManga: initialManga,
    ),
  );
}

const ocrPreferredBackendKey = 'ocr.preferred_backend';

/// The backend the user last started a scan with, or null if they never have.
Future<OcrBackend?> rememberedOcrBackend() async {
  final prefs = await SharedPreferences.getInstance();
  return OcrBackend.values.asNameMap()[prefs.getString(ocrPreferredBackendKey)];
}

/// The backend the user last chose, else remote for manga with remote history.
Future<OcrBackend> preferredOcrBackend(MokuroBook manga) async {
  final remembered = await rememberedOcrBackend();
  if (remembered != null) return remembered;
  final prefs = await SharedPreferences.getInstance();
  final usedRemote =
      prefs.getKeys().any(
        (key) =>
            key.startsWith(ocrProgressKeyPrefix) ||
            key.startsWith(ocrActiveJobKeyPrefix),
      ) ||
      manga.ocrSource == 'custom_ocr' ||
      manga.pages.any((page) => page.ocr?['source'] == 'remote');
  return usedRemote ? OcrBackend.remote : OcrBackend.onDevice;
}

/// Starts OCR for [pages] of [book]. Returns true once a job is launched and
/// false when the user was sent to the Pro or Downloads screen instead; other
/// failures throw (see [localOcrReason]).
Future<bool> startOcr(
  BuildContext context,
  WidgetRef ref,
  Book book,
  MokuroBook manga, {
  required OcrBackend backend,
  required List<int> pages,
  OcrExistingPolicy policy = OcrExistingPolicy.missingOnly,
  bool onlyWhileCharging = false,
}) async {
  final cachePath = p.join(book.filePath, mangaPagesCacheFileName);
  final replace = policy == OcrExistingPolicy.replace;

  /// The Dart page loop: a server per page, or Apple Vision when [onDevice].
  Future<bool> runPageLoop({bool onDevice = false}) async {
    if (replace) {
      await ref
          .read(bookRepositoryProvider)
          .backupOriginalMokuroOcrIfNeeded(book);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ocrPreferredBackendKey, backend.name);
    await scheduleOcrTask(
      bookId: book.id,
      cacheFilePath: cachePath,
      imageDir: manga.imageDirPath,
      selectedPages: pages,
      replace: replace,
      onDevice: onDevice,
    );
    ref.invalidate(ocrProgressProvider(book.id));
    return true;
  }

  if (backend == OcrBackend.remote) {
    final ready = await OcrPurchaseFlow.instance.ensureProAndCustomOcrReady(
      context,
      getServerUrl: () => ref.read(ocrServerUrlProvider),
    );
    if (!ready) return false;
    return runPageLoop();
  }
  if (!await OcrPurchaseFlow.instance.ensurePro(context, source: 'local_ocr')) {
    return false;
  }
  // iOS has no native OCR job service or model pack: Apple Vision reads each
  // page inside the page loop, while the app is open.
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return runPageLoop(onDevice: true);
  }
  final client = ref.read(localOcrClientProvider);
  final model = await client.modelState();
  if (!context.mounted) return false;
  if (!model.supported) throw PlatformException(code: 'unsupported_device');
  if (!model.installed) {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.proFeatureLocalOcrTitle),
        content: Text(dialogContext.l10n.localOcrModelsMissingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.commonOpenDownloads),
          ),
        ],
      ),
    );
    if (open != true || !context.mounted) return false;
    await Navigator.of(
      context,
    ).push(namedRoute('downloads', (_) => const DownloadsScreen()));
    return false;
  }
  final spec = OcrJobSpec(
    bookId: book.id,
    title: book.title,
    cachePath: cachePath,
    pages: pages,
    policy: policy,
    onlyWhileCharging: onlyWhileCharging,
  );
  final repository = replace ? ref.read(bookRepositoryProvider) : null;
  // Publish preparation before the caller leaves its route. All asynchronous
  // work is owned by the provider, so a popped sheet cannot drop a job or use
  // a disposed WidgetRef. Cancel also works before native Start returns.
  unawaited(
    ref.read(localOcrLaunchesProvider.notifier).start(spec, () async {
      if (repository != null) {
        await repository.backupOriginalMokuroOcrIfNeeded(book);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ocrPreferredBackendKey, OcrBackend.onDevice.name);
      await client.requestNotifications();
    }),
  );
  return true;
}

class OcrActionSheet extends ConsumerStatefulWidget {
  final Book book;
  final List<int> visiblePages;
  final MokuroBook? initialManga;
  const OcrActionSheet({
    super.key,
    required this.book,
    this.visiblePages = const [],
    this.initialManga,
  });
  @override
  ConsumerState<OcrActionSheet> createState() => _OcrActionSheetState();
}

class _OcrActionSheetState extends ConsumerState<OcrActionSheet> {
  MokuroBook? _manga;
  OcrBackend _backend = OcrBackend.onDevice;
  OcrExistingPolicy _policy = OcrExistingPolicy.missingOnly;
  int? _page;
  bool _charging = false;
  bool _busy = true;
  String? _error;
  String get _cachePath =>
      p.join(widget.book.filePath, mangaPagesCacheFileName);
  @override
  void initState() {
    super.initState();
    _page = widget.visiblePages.firstOrNull;
    _load();
  }

  Future<void> _load() async {
    try {
      final cached =
          widget.initialManga ??
          await ref.read(ocrBookLoaderProvider)(_cachePath);
      final backend = await preferredOcrBackend(cached);
      if (!mounted) return;
      setState(() {
        _manga = cached;
        _backend = backend;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _start() async {
    final manga = _manga;
    if (manga == null) return;
    final pages = selectOcrPages(manga, pageIndex: _page, policy: _policy);
    if (pages.isEmpty) {
      setState(() => _error = context.l10n.localOcrNothingToDo);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final started = await startOcr(
        context,
        ref,
        widget.book,
        manga,
        backend: _backend,
        pages: pages,
        policy: _policy,
        onlyWhileCharging: _page == null && _charging,
      );
      if (started && mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = localOcrReason(
            context,
            error is PlatformException ? error.code : '$error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final job = ref.watch(localOcrJobProvider(widget.book.id));
    final remote = ref.watch(ocrProgressProvider(widget.book.id)).asData?.value;
    final remoteRunning = remote?.status == OcrStatus.running;
    final manga = _manga;
    final targets = manga == null
        ? const <int>[]
        : selectOcrPages(manga, pageIndex: _page, policy: _policy);
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.localOcrRecognize,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            // Collapse on Dismiss instead of waiting for the next one-second
            // journal poll and then blinking out, which read as a glitch.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: job == null
                  ? const SizedBox.shrink()
                  : LocalOcrJobCard(
                      job: job,
                      onDismissed: () => ref.invalidate(localOcrJobsProvider),
                    ),
            ),
            if (remoteRunning) ...[
              Text(l.localOcrRemote),
              Text(
                l.localOcrProgress(
                  processed: remote!.completed,
                  total: remote.total,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await cancelOcrTask(widget.book.id);
                  ref.invalidate(ocrProgressProvider(widget.book.id));
                },
                child: Text(l.localOcrPause),
              ),
            ],
            if (!(job?.isActive ?? false) && !remoteRunning) ...[
              SegmentedButton<OcrBackend>(
                segments: [
                  ButtonSegment(
                    value: OcrBackend.onDevice,
                    label: Text(l.localOcrOnDevice),
                  ),
                  ButtonSegment(
                    value: OcrBackend.remote,
                    label: Text(l.localOcrRemote),
                  ),
                ],
                selected: {_backend},
                onSelectionChanged: _busy
                    ? null
                    : (v) => setState(() => _backend = v.single),
              ),
              const SizedBox(height: 8),
              Text(
                _backend == OcrBackend.remote
                    ? l.localOcrRemoteSubtitle
                    : defaultTargetPlatform == TargetPlatform.iOS
                    ? l.localOcrOnDeviceSubtitleIos
                    : l.localOcrOnDeviceSubtitle,
              ),
              if (widget.visiblePages.isNotEmpty)
                DropdownButton<int>(
                  isExpanded: true,
                  value: _page ?? -1,
                  items: [
                    for (final index in widget.visiblePages)
                      DropdownMenuItem(
                        value: index,
                        child: Text(l.localOcrThisPage(page: index + 1)),
                      ),
                    DropdownMenuItem(
                      value: -1,
                      child: Text(l.localOcrEntireManga),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _page = v == -1 ? null : v),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l.localOcrEntireManga),
                ),
              if (manga != null)
                Text(
                  l.localOcrCoverage(
                    done: manga.pages.where((p) => p.hasOcr(manga)).length,
                    total: manga.pages.length,
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.localOcrReplace),
                subtitle: Text(
                  _policy == OcrExistingPolicy.replace
                      ? l.localOcrReplaceDescription
                      : l.localOcrMissingOnly,
                ),
                value: _policy == OcrExistingPolicy.replace,
                onChanged: _busy
                    ? null
                    : (v) => setState(
                        () => _policy = v
                            ? OcrExistingPolicy.replace
                            : OcrExistingPolicy.missingOnly,
                      ),
              ),
              // The iOS page loop has no charging condition to honour.
              if (_backend == OcrBackend.onDevice &&
                  _page == null &&
                  defaultTargetPlatform != TargetPlatform.iOS)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.localOcrChargingOnly),
                  value: _charging,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _charging = v ?? false),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || manga == null ? null : _start,
                child: Text(l.localOcrStartPages(count: targets.length)),
              ),
            ],
            if (kDebugMode)
              TextButton.icon(
                icon: const Icon(Icons.bug_report_outlined),
                label: Text(l.localOcrCopyDiagnostics),
                onPressed: () => runLocalOcrAction(context, () async {
                  final report = await LocalMangaOcr.channel
                      .invokeMapMethod<String, dynamic>('diagnostics');
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert(report),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.localOcrDiagnosticsCopied)),
                    );
                  }
                }),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
              ),
          ],
        ),
      ),
    );
  }
}
