import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_cache_service.dart';

/// A wrapper around CachedNetworkImage for consistent image caching throughout the app.
///
/// Benefits over NetworkImage:
/// - Disk caching (persists across app restarts)
/// - Memory caching with configurable limits
/// - Placeholder and error widgets
/// - Fade-in animation
class CachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? cacheWidth;
  final int? cacheHeight;
  final BorderRadius? borderRadius;

  const CachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.cacheWidth,
    this.cacheHeight,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 150),
      cacheManager: AuthenticatedCacheManager.instance,
      placeholder: (context, url) => placeholder ?? Container(
        color: colorScheme.surfaceVariant,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
      ),
      errorWidget: (context, url, error) => errorWidget ?? Container(
        color: colorScheme.surfaceVariant,
        child: Icon(
          Icons.broken_image_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return image;
  }
}

/// A circular cached image, perfect for artist avatars
class CachedCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final Widget? fallbackIcon;
  final Color? backgroundColor;

  const CachedCircleAvatar({
    super.key,
    this.imageUrl,
    this.radius = 24,
    this.fallbackIcon,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = backgroundColor ?? colorScheme.surfaceVariant;

    if (imageUrl == null || imageUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        child: fallbackIcon ?? Icon(
          Icons.person_rounded,
          color: colorScheme.onSurfaceVariant,
          size: radius,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      memCacheWidth: (radius * 4).toInt(),
      memCacheHeight: (radius * 4).toInt(),
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 150),
      cacheManager: AuthenticatedCacheManager.instance,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        child: SizedBox(
          width: radius,
          height: radius,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        child: fallbackIcon ?? Icon(
          Icons.person_rounded,
          color: colorScheme.onSurfaceVariant,
          size: radius,
        ),
      ),
    );
  }
}

/// Get a CachedNetworkImageProvider for use with DecorationImage, CircleAvatar, etc.
/// This is useful when you need an ImageProvider rather than a widget.
CachedNetworkImageProvider? cachedImageProvider(String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) return null;
  return CachedNetworkImageProvider(
    imageUrl,
    cacheManager: AuthenticatedCacheManager.instance,
  );
}
