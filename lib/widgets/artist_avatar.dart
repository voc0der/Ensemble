import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/metadata_service.dart';
import 'package:ensemble/services/image_cache_service.dart';

/// A CircleAvatar that shows artist image with automatic fallback to Deezer/Fanart.tv
class ArtistAvatar extends StatefulWidget {
  final Artist artist;
  final double radius;
  final int imageSize;
  final String? heroTag;
  final ValueChanged<String?>? onImageLoaded;

  const ArtistAvatar({
    super.key,
    required this.artist,
    this.radius = 24,
    this.imageSize = 128,
    this.heroTag,
    this.onImageLoaded,
  });

  @override
  State<ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<ArtistAvatar> {
  String? _imageUrl;
  String? _maImageUrl;
  String? _fallbackImageUrl;
  bool _triedFallback = false;
  bool _maImageFailed = false;
  Timer? _fallbackTimer;

  /// Delay before fetching fallback images to avoid requests during fast scroll
  static const _fallbackDelay = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final provider = context.read<MusicAssistantProvider>();

    // Try MA first
    final maUrl = provider.getImageUrl(widget.artist, size: widget.imageSize);
    _maImageUrl = maUrl;

    if (maUrl != null) {
      if (mounted) {
        setState(() {
          _imageUrl = maUrl;
        });
        widget.onImageLoaded?.call(maUrl);
      }
      return;
    }

    // Fallback to external sources (MA returned null) - with delay
    _scheduleFallbackFetch();
  }

  /// Schedule fallback fetch with delay to avoid requests during fast scroll
  void _scheduleFallbackFetch() {
    if (_triedFallback) return;
    _triedFallback = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(_fallbackDelay, () {
      if (mounted) {
        _fetchFallbackImage();
      }
    });
  }

  Future<void> _fetchFallbackImage() async {
    final fallbackUrl = await MetadataService.getArtistImageUrl(widget.artist.name);
    _fallbackImageUrl = fallbackUrl;

    if (fallbackUrl != null && mounted) {
      setState(() {
        _imageUrl = fallbackUrl;
      });
      widget.onImageLoaded?.call(fallbackUrl);
    }
  }

  void _onImageError() {
    // When MA image fails to load, try Deezer fallback
    if (!_maImageFailed) {
      _maImageFailed = true;
      _scheduleFallbackFetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Use fallback if MA image failed
    final displayUrl = (_maImageFailed && _fallbackImageUrl != null)
        ? _fallbackImageUrl
        : _imageUrl;

    Widget avatarContent;
    if (displayUrl != null) {
      avatarContent = ClipOval(
        child: CachedNetworkImage(
      cacheManager: AuthenticatedCacheManager.instance,
      imageUrl: displayUrl,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          // PERF: Use imageSize for memory cache to reduce decode overhead
          memCacheWidth: widget.imageSize,
          memCacheHeight: widget.imageSize,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => Container(
            color: colorScheme.surfaceVariant,
            child: Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant),
          ),
          errorWidget: (context, url, error) {
            // Try fallback on error (only for MA URLs, not fallback URLs)
            if (!_maImageFailed && url == _maImageUrl) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _onImageError();
              });
            }
            return Container(
              color: colorScheme.surfaceVariant,
              child: Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant),
            );
          },
        ),
      );
    } else {
      avatarContent = CircleAvatar(
        radius: widget.radius,
        backgroundColor: colorScheme.surfaceVariant,
        child: Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant),
      );
    }

    final avatar = SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: avatarContent,
    );

    if (widget.heroTag != null) {
      return Hero(
        tag: widget.heroTag!,
        child: avatar,
      );
    }

    return avatar;
  }
}
