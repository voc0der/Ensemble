import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../screens/audiobook_detail_screen.dart';
import '../constants/hero_tags.dart';

class AudiobookRow extends StatefulWidget {
  final String title;
  final Future<List<Audiobook>> Function() loadAudiobooks;
  final String? heroTagSuffix;
  final double? rowHeight;

  const AudiobookRow({
    super.key,
    required this.title,
    required this.loadAudiobooks,
    this.heroTagSuffix,
    this.rowHeight,
  });

  @override
  State<AudiobookRow> createState() => _AudiobookRowState();
}

class _AudiobookRowState extends State<AudiobookRow> with AutomaticKeepAliveClientMixin {
  late Future<List<Audiobook>> _audiobooksFuture;
  List<Audiobook>? _cachedAudiobooks;
  bool _hasLoaded = false;
  bool _hasPrecachedAudiobooks = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAudiobooksOnce();
  }

  void _loadAudiobooksOnce() {
    if (!_hasLoaded) {
      _audiobooksFuture = widget.loadAudiobooks().then((audiobooks) {
        _cachedAudiobooks = audiobooks;
        // Pre-cache images for smooth Hero animations
        _precacheAudiobookImages(audiobooks);
        return audiobooks;
      });
      _hasLoaded = true;
    }
  }

  /// Pre-cache audiobook images so Hero animations are smooth on first tap
  void _precacheAudiobookImages(List<Audiobook> audiobooks) {
    if (!mounted || _hasPrecachedAudiobooks) return;
    _hasPrecachedAudiobooks = true;

    final maProvider = context.read<MusicAssistantProvider>();

    // Only precache first ~10 visible items
    final audiobooksToCache = audiobooks.take(10);

    for (final audiobook in audiobooksToCache) {
      final imageUrl = maProvider.api?.getImageUrl(audiobook, size: 256);
      if (imageUrl != null) {
        precacheImage(
          CachedNetworkImageProvider(imageUrl),
          context,
        ).catchError((_) {
          // Silently ignore precache errors
          return false;
        });
      }
    }
  }

  static final _logger = DebugLogger();

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('AudiobookRow:${widget.title}');
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
              child: FutureBuilder<List<Audiobook>>(
                future: _audiobooksFuture,
                builder: (context, snapshot) {
                  final audiobooks = snapshot.data ?? _cachedAudiobooks;

                  if (audiobooks == null && snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError && audiobooks == null) {
                    return Center(
                      child: Text('Error: ${snapshot.error}'),
                    );
                  }

                  if (audiobooks == null || audiobooks.isEmpty) {
                    return Center(
                      child: Text(
                        'No audiobooks found',
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
                      itemCount: audiobooks.length,
                      itemExtent: itemExtent,
                      cacheExtent: 500,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      itemBuilder: (context, index) {
                        final audiobook = audiobooks[index];
                        return Container(
                          key: ValueKey(audiobook.uri ?? audiobook.itemId),
                          width: cardWidth,
                          margin: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: _AudiobookCard(
                            audiobook: audiobook,
                            heroTagSuffix: widget.heroTagSuffix ?? 'home_${widget.title.replaceAll(' ', '_').toLowerCase()}',
                            maProvider: maProvider,
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
    _logger.endBuild('AudiobookRow:${widget.title}');
    return result;
  }
}

class _AudiobookCard extends StatelessWidget {
  final Audiobook audiobook;
  final String heroTagSuffix;
  final MusicAssistantProvider maProvider;

  const _AudiobookCard({
    required this.audiobook,
    required this.heroTagSuffix,
    required this.maProvider,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final imageUrl = maProvider.getImageUrl(audiobook, size: 256);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AudiobookDetailScreen(
              audiobook: audiobook,
              heroTagSuffix: heroTagSuffix,
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (audiobook.uri ?? audiobook.itemId) + '_$heroTagSuffix',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: colorScheme.surfaceContainerHighest,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              // PERF: Duration.zero for hero-wrapped images
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              memCacheWidth: 256,
                              memCacheHeight: 256,
                              placeholder: (_, __) => Center(
                                child: Icon(
                                  MdiIcons.bookOutline,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Center(
                                child: Icon(
                                  MdiIcons.bookOutline,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                MdiIcons.bookOutline,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ),
                // Progress indicator
                if (audiobook.progress > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value: audiobook.progress,
                        backgroundColor: Colors.black54,
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.audiobookTitle + (audiobook.uri ?? audiobook.itemId) + '_$heroTagSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                audiobook.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Text(
            audiobook.authorsString,
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
