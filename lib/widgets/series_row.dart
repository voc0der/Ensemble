import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import '../screens/audiobook_series_screen.dart';

class SeriesRow extends StatefulWidget {
  final String title;
  final Future<List<AudiobookSeries>> Function() loadSeries;
  final double? rowHeight;

  const SeriesRow({
    super.key,
    required this.title,
    required this.loadSeries,
    this.rowHeight,
  });

  @override
  State<SeriesRow> createState() => _SeriesRowState();
}

class _SeriesRowState extends State<SeriesRow> with AutomaticKeepAliveClientMixin {
  late Future<List<AudiobookSeries>> _seriesFuture;
  List<AudiobookSeries>? _cachedSeries;
  bool _hasLoaded = false;

  // Cache for series cover images
  final Map<String, List<String>> _seriesCovers = {};
  final Set<String> _loadingCovers = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSeriesOnce();
  }

  void _loadSeriesOnce() {
    if (!_hasLoaded) {
      _seriesFuture = widget.loadSeries().then((series) {
        _cachedSeries = series;
        return series;
      });
      _hasLoaded = true;
    }
  }

  Future<void> _loadSeriesCovers(String seriesId, MusicAssistantProvider maProvider) async {
    if (_loadingCovers.contains(seriesId) || _seriesCovers.containsKey(seriesId)) {
      return;
    }

    _loadingCovers.add(seriesId);

    try {
      final books = await maProvider.api?.getSeriesAudiobooks(seriesId);
      if (books != null && books.isNotEmpty && mounted) {
        final covers = <String>[];
        for (final book in books.take(9)) {
          final imageUrl = maProvider.getImageUrl(book);
          if (imageUrl != null) {
            covers.add(imageUrl);
          }
        }
        if (mounted) {
          setState(() {
            _seriesCovers[seriesId] = covers;
          });
        }
      }
    } finally {
      _loadingCovers.remove(seriesId);
    }
  }

  static final _logger = DebugLogger();

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('SeriesRow:${widget.title}');
    super.build(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();

    final totalHeight = widget.rowHeight ?? 237.0;
    const titleHeight = 44.0;
    final contentHeight = totalHeight - titleHeight;

    final result = RepaintBoundary(
      child: SizedBox(
        height: totalHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: Text(
                widget.title,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onBackground,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AudiobookSeries>>(
                future: _seriesFuture,
                builder: (context, snapshot) {
                  final series = snapshot.data ?? _cachedSeries;

                  if (series == null && snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError && series == null) {
                    return Center(
                      child: Text('Error: ${snapshot.error}'),
                    );
                  }

                  if (series == null || series.isEmpty) {
                    return Center(
                      child: Text(
                        'No series found',
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                      ),
                    );
                  }

                  const textAreaHeight = 44.0;
                  final artworkSize = contentHeight - textAreaHeight;
                  final cardWidth = artworkSize;
                  final itemExtent = cardWidth + 12;

                  return ScrollConfiguration(
                    behavior: const _StretchScrollBehavior(),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      itemCount: series.length,
                      itemExtent: itemExtent,
                      cacheExtent: 500,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      itemBuilder: (context, index) {
                        final s = series[index];

                        // Load covers if not cached
                        if (!_seriesCovers.containsKey(s.id) && !_loadingCovers.contains(s.id)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _loadSeriesCovers(s.id, maProvider);
                          });
                        }

                        return Container(
                          key: ValueKey(s.id),
                          width: cardWidth,
                          margin: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: _SeriesCard(
                            series: s,
                            covers: _seriesCovers[s.id],
                            colorScheme: colorScheme,
                            textTheme: textTheme,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    _logger.endBuild('SeriesRow:${widget.title}');
    return result;
  }
}

class _SeriesCard extends StatelessWidget {
  final AudiobookSeries series;
  final List<String>? covers;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _SeriesCard({
    required this.series,
    required this.covers,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AudiobookSeriesScreen(series: series),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: colorScheme.surfaceVariant,
                child: _buildCoverGrid(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.name,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (series.bookCount != null)
            Text(
              '${series.bookCount} ${series.bookCount == 1 ? 'book' : 'books'}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildCoverGrid() {
    if (covers == null || covers!.isEmpty) {
      // Static placeholder - no animation
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.collections_bookmark_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
      );
    }

    // Determine grid size
    int gridSize;
    if (covers!.length == 1) {
      gridSize = 1;
    } else if (covers!.length <= 4) {
      gridSize = 2;
    } else {
      gridSize = 3;
    }

    final displayCovers = covers!.take(gridSize * gridSize).toList();

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridSize,
        childAspectRatio: 1,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: displayCovers.length,
      itemBuilder: (context, index) {
        return CachedNetworkImage(
          imageUrl: displayCovers[index],
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) => Container(
            color: colorScheme.surfaceContainerHighest,
          ),
        );
      },
    );
  }
}

class _StretchScrollBehavior extends ScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
