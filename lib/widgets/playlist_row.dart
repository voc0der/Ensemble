import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'playlist_card.dart';

class PlaylistRow extends StatefulWidget {
  final String title;
  final Future<List<Playlist>> Function() loadPlaylists;
  final String? heroTagSuffix;
  final double? rowHeight;
  final List<Playlist>? Function()? getCachedPlaylists;

  const PlaylistRow({
    super.key,
    required this.title,
    required this.loadPlaylists,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedPlaylists,
  });

  @override
  State<PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends State<PlaylistRow> with AutomaticKeepAliveClientMixin {
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedPlaylists?.call();
    if (cached != null && cached.isNotEmpty) {
      _playlists = cached;
      _isLoading = false;
    }
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data
    try {
      final freshPlaylists = await widget.loadPlaylists();
      if (mounted && freshPlaylists.isNotEmpty) {
        setState(() {
          _playlists = freshPlaylists;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precachePlaylistImages(freshPlaylists);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  void _precachePlaylistImages(List<Playlist> playlists) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    final playlistsToCache = playlists.take(10);

    for (final playlist in playlistsToCache) {
      final imageUrl = maProvider.api?.getImageUrl(playlist, size: 256);
      if (imageUrl != null) {
        precacheImage(
          CachedNetworkImageProvider(imageUrl),
          context,
        ).catchError((_) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Don't render if empty and done loading
    if (_playlists.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Calculate card dimensions
    // Default: 44 for title, remaining for content (artwork + 2 lines of text)
    final rowHeight = widget.rowHeight ?? 237.0;
    final titleHeight = 44.0;
    final contentHeight = rowHeight - titleHeight;
    // Artwork is square, text takes ~50px (8 padding + title + owner)
    final artworkSize = contentHeight - 50;
    final cardWidth = artworkSize;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              widget.title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Horizontal list of playlists
          SizedBox(
            height: contentHeight,
            child: _isLoading && _playlists.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    itemCount: _playlists.length,
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    itemBuilder: (context, index) {
                      final playlist = _playlists[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: SizedBox(
                          width: cardWidth,
                          child: PlaylistCard(
                            playlist: playlist,
                            heroTagSuffix: widget.heroTagSuffix,
                            imageCacheSize: 256,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
