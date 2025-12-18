import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../services/debug_logger.dart';
import 'audiobook_detail_screen.dart';

class AudiobookSeriesScreen extends StatefulWidget {
  final AudiobookSeries series;

  const AudiobookSeriesScreen({
    super.key,
    required this.series,
  });

  @override
  State<AudiobookSeriesScreen> createState() => _AudiobookSeriesScreenState();
}

class _AudiobookSeriesScreenState extends State<AudiobookSeriesScreen> {
  final _logger = DebugLogger();
  List<Audiobook> _audiobooks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _logger.log('📚 SeriesScreen initState for: ${widget.series.name}');
    // Defer loading until after first frame to allow UI to render first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadSeriesBooks();
      }
    });
  }

  Future<void> _loadSeriesBooks() async {
    _logger.log('📚 SeriesScreen _loadSeriesBooks START');
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      _logger.log('📚 SeriesScreen setState done, getting provider...');

      final maProvider = context.read<MusicAssistantProvider>();
      _logger.log('📚 SeriesScreen got provider, api=${maProvider.api != null}');

      if (maProvider.api == null) {
        setState(() {
          _error = 'Not connected to Music Assistant';
          _isLoading = false;
        });
        return;
      }

      _logger.log('📚 SeriesScreen calling getSeriesAudiobooks: path=${widget.series.id}');
      final books = await maProvider.api!.getSeriesAudiobooks(widget.series.id);
      _logger.log('📚 SeriesScreen got ${books.length} books');

      if (mounted) {
        setState(() {
          _audiobooks = books;
          _isLoading = false;
        });
        _logger.log('📚 SeriesScreen setState complete');
      }
    } catch (e, stack) {
      _logger.log('📚 SeriesScreen error: $e');
      _logger.log('📚 SeriesScreen stack: $stack');
      if (mounted) {
        setState(() {
          _error = 'Failed to load books: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.watch<MusicAssistantProvider>();

    return GlobalPlayerOverlay(
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            // App bar with series image
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  widget.series.name,
                  style: const TextStyle(
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                background: widget.series.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: widget.series.thumbnailUrl!,
                        fit: BoxFit.cover,
                        color: Colors.black.withOpacity(0.3),
                        colorBlendMode: BlendMode.darken,
                      )
                    : Container(
                        color: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.library_books,
                          size: 64,
                          color: colorScheme.onPrimaryContainer.withOpacity(0.5),
                        ),
                      ),
              ),
            ),

            // Book count
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _isLoading
                      ? 'Loading...'
                      : '${_audiobooks.length} ${_audiobooks.length == 1 ? 'book' : 'books'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),

            // Content
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSeriesBooks,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_audiobooks.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 48, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        'No books found in this series',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final book = _audiobooks[index];
                    final imageUrl = maProvider.getImageUrl(book);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(Icons.book,
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(Icons.book,
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                )
                              : Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.book,
                                      color: colorScheme.onSurfaceVariant),
                                ),
                        ),
                      ),
                      title: Text(
                        book.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: book.authors?.isNotEmpty == true
                          ? Text(
                              book.authors!.map((a) => a.name).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: book.duration != null
                          ? Text(
                              _formatDuration(book.duration!),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AudiobookDetailScreen(
                              audiobook: book,
                              heroTagSuffix: 'series_${widget.series.id}_$index',
                            ),
                          ),
                        );
                      },
                    );
                  },
                  childCount: _audiobooks.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
