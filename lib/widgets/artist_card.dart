import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final maImageUrl = maProvider.api?.getImageUrl(widget.artist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

    // Use MA image if available, otherwise try fallback
    final imageUrl = maImageUrl ?? _fallbackImageUrl;

    // Try to fetch fallback image if MA doesn't have one and we haven't tried yet
    if (maImageUrl == null && !_triedFallback) {
      _triedFallback = true;
      _logger.debug('No MA image for "${widget.artist.name}", trying fallback', context: 'ArtistCard');
      _fetchFallbackImage();
    }

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
            // Artist image - circular, scales with imageSize
            Expanded(
              child: Hero(
                tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId) + suffix,
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: ClipOval(
                    child: Container(
                      color: colorScheme.surfaceVariant,
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 256,
                              cacheHeight: 256,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.person_rounded,
                                size: (widget.imageSize ?? 110) * 0.55,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : Icon(Icons.person_rounded, size: (widget.imageSize ?? 110) * 0.55, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Artist name
          Hero(
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
