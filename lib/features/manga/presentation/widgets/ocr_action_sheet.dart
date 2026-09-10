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
      final prefs = await SharedPreferences.getInstance();
      final cached =
          widget.initialManga ??
          await ref.read(ocrBookLoaderProvider)(_cachePath);
      final remembered = prefs.getString('ocr.preferred_backend');
      final usedRemote =
          prefs.getKeys().any(
            (key) =>
                key.startsWith(ocrProgressKeyPrefix) ||
                key.startsWith(ocrActiveJobKeyPrefix),
          ) ||
          cached.ocrSource == 'custom_ocr' ||
          cached.pages.any((page) => page.ocr?['source'] == 'remote');
      if (!mounted) return;
      setState(() {
        _manga = cached;
        _backend = remembered == 'remote' || (remembered == null && usedRemote)
            ? OcrBackend.remote
            : OcrBackend.onDevice;
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

  Future<void> _startLocal() async {
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
      final client = ref.read(localOcrClientProvider);
      final model = await client.modelState();
      if (!mounted) return;
      if (!model.supported) {
        setState(() => _error = context.l10n.localOcrUnsupported);
        return;
      }
      if (!model.installed) {
        await Navigator.of(
          context,
        ).push(namedRoute('downloads', (_) => const DownloadsScreen()));
        return;
      }
      final spec = OcrJobSpec(
        bookId: widget.book.id,
        title: widget.book.title,
        cachePath: _cachePath,
        pages: pages,
        policy: _policy,
        onlyWhileCharging: _page == null && _charging,
      );
      final launches = ref.read(localOcrLaunchesProvider.notifier);
      final repository = _policy == OcrExistingPolicy.replace
          ? ref.read(bookRepositoryProvider)
          : null;
      final book = widget.book;
      // Publish preparation before dismissing the sheet. All asynchronous work
      // is owned by the provider, so leaving this route cannot drop a job or use
      // a disposed WidgetRef. Cancel also works before native Start returns.
      unawaited(
        launches.start(spec, () async {
          if (repository != null) {
            await repository.backupOriginalMokuroOcrIfNeeded(book);
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('ocr.preferred_backend', 'onDevice');
          await client.requestNotifications();
        }),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = localOcrReason(
            context,
            error is PlatformException ? error.code : error.toString(),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_backend == OcrBackend.onDevice) return _startLocal();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final manga = await ref.read(ocrBookLoaderProvider)(_cachePath);
      final pages = selectOcrPages(manga, pageIndex: _page, policy: _policy);
      if (pages.isEmpty) {
        setState(() => _error = context.l10n.localOcrNothingToDo);
        return;
      }
      if (!mounted) return;
      final ready = await OcrPurchaseFlow.instance.ensureProAndCustomOcrReady(
        context,
        getServerUrl: () => ref.read(ocrServerUrlProvider),
      );
      if (!ready) return;
      if (!mounted) return;
      if (_policy == OcrExistingPolicy.replace) {
        await ref
            .read(bookRepositoryProvider)
            .backupOriginalMokuroOcrIfNeeded(widget.book);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ocr.preferred_backend', _backend.name);
      await scheduleOcrTask(
        bookId: widget.book.id,
        cacheFilePath: _cachePath,
        imageDir: manga.imageDirPath,
        selectedPages: pages,
        replace: _policy == OcrExistingPolicy.replace,
      );
      ref.invalidate(ocrProgressProvider(widget.book.id));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = localOcrReason(
            context,
            e is PlatformException ? e.code : '$e',
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
            if (job != null) LocalOcrJobCard(job: job),
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
                _backend == OcrBackend.onDevice
                    ? l.localOcrOnDeviceSubtitle
                    : l.localOcrRemoteSubtitle,
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
              if (_backend == OcrBackend.onDevice && _page == null)
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
