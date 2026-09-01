import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/data/repositories/server_connection_repository.dart';
import 'package:mekuru/features/sync/data/services/server_client.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';

void _openBookReader(BuildContext context, Book book) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => book.bookType == 'manga'
          ? MangaReaderScreen(book: book)
          : ReaderScreen(book: book),
    ),
  );
}

/// Entry point of server browsing: the connection's libraries.
class ServerBrowseScreen extends ConsumerWidget {
  final ServerConnection connection;

  const ServerBrowseScreen({super.key, required this.connection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(serverClientProvider(connection.id));

    return Scaffold(
      appBar: AppBar(title: Text(connection.name)),
      body: client.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(serverClientProvider(connection.id)),
        ),
        data: (client) => FutureBuilder<List<RemoteLibrary>>(
          future: client.listLibraries(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorRetry(
                error: snapshot.error!,
                onRetry: () =>
                    ref.invalidate(serverClientProvider(connection.id)),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final libraries = snapshot.data!;
            if (libraries.isEmpty) {
              return const Center(child: Text('No libraries on this server'));
            }
            return ListView(
              children: [
                for (final library in libraries)
                  ListTile(
                    leading: const Icon(Icons.collections_bookmark),
                    title: Text(library.name),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _SeriesListScreen(
                          connection: connection,
                          client: client,
                          library: library,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SeriesListScreen extends StatefulWidget {
  final ServerConnection connection;
  final ServerClient client;
  final RemoteLibrary library;

  const _SeriesListScreen({
    required this.connection,
    required this.client,
    required this.library,
  });

  @override
  State<_SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<_SeriesListScreen> {
  final TextEditingController _searchController = TextEditingController();
  // ponytail: in-memory cover cache per screen visit; a disk cache can come
  // later if browsing feels slow on big libraries.
  final Map<String, Uint8List?> _coverCache = {};
  late Future<List<RemoteSeries>> _series;

  @override
  void initState() {
    super.initState();
    _series = widget.client.listSeries(widget.library.id);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String query) {
    setState(() {
      _series = widget.client.listSeries(
        widget.library.id,
        search: query.trim().isEmpty ? null : query.trim(),
      );
    });
  }

  Future<Uint8List?> _cover(RemoteSeries series) async {
    if (_coverCache.containsKey(series.id)) return _coverCache[series.id];
    final bytes = await widget.client.fetchSeriesCover(series);
    final data = bytes == null ? null : Uint8List.fromList(bytes);
    if (mounted) _coverCache[series.id] = data;
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.library.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search this server',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _search('');
                  },
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RemoteSeries>>(
              future: _series,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorRetry(
                    error: snapshot.error!,
                    onRetry: () => _search(_searchController.text),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final series = snapshot.data!;
                if (series.isEmpty) {
                  return const Center(child: Text('No series found'));
                }
                return ListView.builder(
                  itemCount: series.length,
                  itemBuilder: (context, index) {
                    final item = series[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 56,
                        child: FutureBuilder<Uint8List?>(
                          future: _cover(item),
                          builder: (context, cover) => cover.data != null
                              ? Image.memory(
                                  cover.data!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : const Icon(Icons.book_outlined),
                        ),
                      ),
                      title: Text(item.title),
                      subtitle: item.bookCount > 0
                          ? Text('${item.bookCount} books')
                          : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _BookListScreen(
                            connection: widget.connection,
                            client: widget.client,
                            series: item,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BookListScreen extends ConsumerStatefulWidget {
  final ServerConnection connection;
  final ServerClient client;
  final RemoteSeries series;

  const _BookListScreen({
    required this.connection,
    required this.client,
    required this.series,
  });

  @override
  ConsumerState<_BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends ConsumerState<_BookListScreen> {
  late Future<List<RemoteBook>> _books;

  @override
  void initState() {
    super.initState();
    _books = widget.client.listBooks(widget.series);
  }

  Future<void> _startDownload(RemoteBook book) async {
    final repo = ref.read(serverConnectionRepositoryProvider);

    // An unlinked local copy with the same title: offer link-instead.
    final localType = book.format == RemoteBookFormat.epub ? 'epub' : 'manga';
    final titleMatch = await repo.findUnlinkedTitleMatch(book.title, localType);
    if (!mounted) return;
    if (titleMatch != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already in your library?'),
          content: Text(
            '"${titleMatch.title}" is already on this device. Link the '
            'existing copy to sync its progress with the server, or '
            'download a separate copy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('download'),
              child: const Text('Download anyway'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('link'),
              child: const Text('Link existing copy'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'link') {
        await repo.linkBook(titleMatch.id, widget.connection.id, book.ids);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Linked "${titleMatch.title}"')),
          );
        }
        return;
      }
    }

    try {
      final imported = await ref
          .read(serverDownloadProvider.notifier)
          .download(
            connection: widget.connection,
            client: widget.client,
            book: book,
          );
      if (mounted && imported != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${imported.title}" added to library!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _openLinked(RemoteBook book) async {
    final linked = await ref
        .read(serverConnectionRepositoryProvider)
        .findLinkedBook(widget.connection.id, book.ids);
    if (!mounted) return;
    if (linked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book is no longer on this device')),
      );
      return;
    }
    _openBookReader(context, linked);
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(serverDownloadProvider);
    final linkedIds = ref
        .watch(linkedRemoteIdsProvider(widget.connection.id))
        .asData
        ?.value;

    return Scaffold(
      appBar: AppBar(title: Text(widget.series.title)),
      body: FutureBuilder<List<RemoteBook>>(
        future: _books,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorRetry(
              error: snapshot.error!,
              onRetry: () => setState(() {
                _books = widget.client.listBooks(widget.series);
              }),
            );
          }
          if (!snapshot.hasData || linkedIds == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final books = snapshot.data!;
          if (books.isEmpty) {
            return const Center(child: Text('No books in this series'));
          }
          return ListView.builder(
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              final key = ServerConnectionRepository.primaryRemoteId(book.ids);
              final progress = key != null ? downloads[key] : null;
              final isLinked = key != null && linkedIds.contains(key);

              final Widget trailing;
              if (progress != null) {
                trailing = SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 2.5,
                  ),
                );
              } else if (isLinked) {
                trailing = const Icon(Icons.check_circle, color: Colors.green);
              } else {
                trailing = const Icon(Icons.download);
              }

              return ListTile(
                leading: Icon(
                  book.format == RemoteBookFormat.epub
                      ? Icons.menu_book
                      : Icons.photo_library_outlined,
                ),
                title: Text(book.title),
                subtitle: Text(
                  book.format == RemoteBookFormat.epub
                      ? 'EPUB'
                      : '${book.pageCount} pages',
                ),
                trailing: trailing,
                onTap: progress != null
                    ? null
                    : isLinked
                    ? () => _openLinked(book)
                    : () => _startDownload(book),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
