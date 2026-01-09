import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import 'radio_station_card.dart';

class RadioStationRow extends StatefulWidget {
  final String title;
  final Future<List<MediaItem>> Function() loadRadioStations;
  final String? heroTagSuffix;
  final double? rowHeight;
  final List<MediaItem>? Function()? getCachedRadioStations;

  const RadioStationRow({
    super.key,
    required this.title,
    required this.loadRadioStations,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedRadioStations,
  });

  @override
  State<RadioStationRow> createState() => _RadioStationRowState();
}

class _RadioStationRowState extends State<RadioStationRow> with AutomaticKeepAliveClientMixin {
  List<MediaItem> _radioStations = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedRadioStations?.call();
    if (cached != null && cached.isNotEmpty) {
      _radioStations = cached;
      _isLoading = false;
    }
    _loadRadioStations();
  }

  Future<void> _loadRadioStations() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data
    try {
      final freshStations = await widget.loadRadioStations();
      if (mounted && freshStations.isNotEmpty) {
        setState(() {
          _radioStations = freshStations;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precacheRadioImages(freshStations);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  void _precacheRadioImages(List<MediaItem> stations) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    final stationsToCache = stations.take(10);

    for (final station in stationsToCache) {
      final imageUrl = maProvider.api?.getImageUrl(station, size: 256);
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
    if (_radioStations.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Calculate card dimensions - similar to ArtistRow for circular items
    // Default: 44 for title, remaining for content (circular image + name)
    final rowHeight = widget.rowHeight ?? 207.0;
    final titleHeight = 44.0;
    final contentHeight = rowHeight - titleHeight;
    // Circular artwork, text takes ~40px (8 padding + name lines)
    final artworkSize = contentHeight - 40;
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
          // Horizontal list of radio stations
          SizedBox(
            height: contentHeight,
            child: _isLoading && _radioStations.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    itemCount: _radioStations.length,
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    itemBuilder: (context, index) {
                      final station = _radioStations[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: SizedBox(
                          width: cardWidth,
                          child: RadioStationCard(
                            radioStation: station,
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
