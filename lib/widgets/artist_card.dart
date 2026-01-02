import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/artist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';

class ArtistCard extends StatefulWidget {
  final Artist artist;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final double? imageSize;

  const ArtistCard({
    super.key,
    required this.artist,
    this.onTap,
    this.heroTagSuffix,
    this.imageSize,
  });

  @override
  State<ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<ArtistCard> {
  static final _logger = DebugLogger();
  String? _fallbackImageUrl;
  bool _triedFallback = false;
  bool _maImageFailed = false;
  String? _cachedMaImageUrl;

  @override
  void initState() {
    super.initState();
    // Fetch fallback image once in initState, not during build
    _initFallbackImage();
  }

  void _initFallbackImage() {
    // We'll check if MA has an image after first build, then fetch fallback if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maProvider = context.read<MusicAssistantProvider>();
      final maImageUrl = maProvider.api?.getImageUrl(widget.artist, size: 256);
      _cachedMaImageUrl = maImageUrl;

      if (maImageUrl == null && !_triedFallback) {
        _triedFallback = true;
        _logger.debug('No MA image for "${widget.artist.name}", trying fallback', context: 'ArtistCard');
        _fetchFallbackImage();
      }
    });
  }

  void _onImageError() {
    // When MA image fails to load, try Deezer fallback
    if (!_triedFallback && !_maImageFailed) {
      _maImageFailed = true;
      _triedFallback = true;
      _logger.debug('MA image failed for "${widget.artist.name}", trying fallback', context: 'ArtistCard');
      _fetchFallbackImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    // Use cached URL if available, otherwise get fresh (but don't trigger fetches during build)
    final maImageUrl = _cachedMaImageUrl ?? maProvider.api?.getImageUrl(widget.artist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

    // Use fallback if MA image failed or wasn't available
    final imageUrl = (_maImageFailed || maImageUrl == null) ? _fallbackImageUrl : maImageUrl;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: widget.artist,
                heroTagSuffix: widget.heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Artist image - circular
            // PERF: Use AspectRatio instead of LayoutBuilder to provide fixed geometry
            // before Hero animation starts. This prevents grey icon flash caused by
            // dynamic sizing inside the Hero widget.
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId) + suffix,
                child: ClipOval(
                  child: Container(
                    color: colorScheme.surfaceVariant,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 256,
                            memCacheHeight: 256,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => const SizedBox(),
                            errorWidget: (context, url, error) {
                              // Try fallback on error (only for MA URLs, not fallback URLs)
                              if (!_maImageFailed && url == maImageUrl) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _onImageError();
                                });
                              }
                              return Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Artist name - fixed height container so image size is consistent
          SizedBox(
            height: 36, // Fixed height for 2 lines of text
            child: Hero(
              tag: HeroTags.artistName + (widget.artist.uri ?? widget.artist.itemId) + suffix,
              child: Material(
                color: Colors.transparent,
                child: Text(
                  widget.artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchFallbackImage() async {
    final fallbackUrl = await MetadataService.getArtistImageUrl(widget.artist.name);
    if (fallbackUrl != null && mounted) {
      _logger.debug('Found fallback image for "${widget.artist.name}"', context: 'ArtistCard');
      setState(() {
        _fallbackImageUrl = fallbackUrl;
      });
    }
  }
}
