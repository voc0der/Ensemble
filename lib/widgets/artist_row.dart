import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'artist_card.dart';

class ArtistRow extends StatefulWidget {
  final String title;
  final Future<List<Artist>> Function() loadArtists;
  final String? heroTagSuffix;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<Artist>? Function()? getCachedArtists;

  const ArtistRow({
    super.key,
    required this.title,
    required this.loadArtists,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedArtists,
  });

  @override
  State<ArtistRow> createState() => _ArtistRowState();
}

class _ArtistRowState extends State<ArtistRow> with AutomaticKeepAliveClientMixin {
  List<Artist> _artists = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // 1. Try to get cached data synchronously for instant display
    final cachedArtists = widget.getCachedArtists?.call();
    if (cachedArtists != null && cachedArtists.isNotEmpty) {
      if (mounted) {
        setState(() {
          _artists = cachedArtists;
          _isLoading = false;
        });
      }
    }

    // 2. Load fresh data (silent background refresh if we had cache)
    try {
      final freshArtists = await widget.loadArtists();
      if (mounted && freshArtists.isNotEmpty) {
        // Only update if data actually changed
        final hasChanged = _artists.isEmpty ||
            _artists.length != freshArtists.length ||
            (_artists.isNotEmpty && freshArtists.isNotEmpty &&
             _artists.first.itemId != freshArtists.first.itemId);
        if (hasChanged) {
          setState(() {
            _artists = freshArtists;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  static final _logger = DebugLogger();

  Widget _buildContent(double contentHeight, ColorScheme colorScheme) {
    // Only show loading if we have no data at all
    if (_artists.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found',
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    // Card layout: circle image + name below
    // Text area: 8px gap + ~36px for 2-line name = ~44px
    const textAreaHeight = 44.0;
    final imageSize = contentHeight - textAreaHeight;
    final cardWidth = imageSize; // Card width = image width (circle)
    final itemExtent = cardWidth + 16; // width + horizontal margins

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _artists.length,
        itemExtent: itemExtent,
        cacheExtent: 500, // Preload ~3 items ahead for smoother scrolling
        addAutomaticKeepAlives: false, // Row already uses AutomaticKeepAliveClientMixin
        addRepaintBoundaries: false, // Cards already have RepaintBoundary
        itemBuilder: (context, index) {
          final artist = _artists[index];
          return Container(
            key: ValueKey(artist.uri ?? artist.itemId),
            width: cardWidth,
            margin: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ArtistCard(
              artist: artist,
              heroTagSuffix: widget.heroTagSuffix,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('ArtistRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Total row height includes title + content
    final totalHeight = widget.rowHeight ?? 207.0; // Default: 44 title + 163 content
    const titleHeight = 44.0; // 12 top padding + ~24 text + 8 bottom padding
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
            child: _buildContent(contentHeight, colorScheme),
          ),
          ],
        ),
      ),
    );
    _logger.endBuild('ArtistRow:${widget.title}');
    return result;
  }
}

/// Custom scroll behavior that uses Android 12+ stretch overscroll effect
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
