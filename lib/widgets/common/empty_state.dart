import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/design_tokens.dart';

/// A reusable empty state widget for displaying when no data is available.
///
/// Shows an icon, message, and optional action button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconSize = 64,
  });

  /// Creates an empty state for artists
  factory EmptyState.artists({VoidCallback? onRefresh, required BuildContext context}) {
    final s = S.of(context)!;
    return EmptyState(
      icon: Icons.person_outline_rounded,
      message: s.noArtistsFound,
      actionLabel: onRefresh != null ? s.refresh : null,
      onAction: onRefresh,
    );
  }

  /// Creates an empty state for albums
  factory EmptyState.albums({VoidCallback? onRefresh, required BuildContext context}) {
    final s = S.of(context)!;
    return EmptyState(
      icon: Icons.album_outlined,
      message: s.noAlbumsFound,
      actionLabel: onRefresh != null ? s.refresh : null,
      onAction: onRefresh,
    );
  }

  /// Creates an empty state for tracks
  factory EmptyState.tracks({VoidCallback? onRefresh, required BuildContext context}) {
    final s = S.of(context)!;
    return EmptyState(
      icon: Icons.music_note_outlined,
      message: s.noTracksFound,
      actionLabel: onRefresh != null ? s.refresh : null,
      onAction: onRefresh,
    );
  }

  /// Creates an empty state for playlists
  factory EmptyState.playlists({VoidCallback? onRefresh, required BuildContext context}) {
    final s = S.of(context)!;
    return EmptyState(
      icon: Icons.playlist_play_rounded,
      message: s.noPlaylistsFound,
      actionLabel: onRefresh != null ? s.refresh : null,
      onAction: onRefresh,
    );
  }

  /// Creates an empty state for queue
  factory EmptyState.queue({required BuildContext context}) {
    final s = S.of(context)!;
    return EmptyState(
      icon: Icons.queue_music,
      message: s.queueIsEmpty,
    );
  }

  /// Creates an empty state for search results
  factory EmptyState.search({required BuildContext context}) {
    final s = S.of(context)!;
    return EmptyState(
      icon: Icons.search_off_rounded,
      message: s.noResultsFound,
    );
  }

  /// Creates a custom empty state with title and subtitle
  factory EmptyState.custom({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onRefresh,
    required BuildContext context,
  }) =>
      _CustomEmptyState(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onRefresh: onRefresh,
        context: context,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Wrap in scrollable to allow PageView horizontal swipe detection
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: Spacing.paddingAll24,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: iconSize,
                    color: colorScheme.onSurface.withOpacity(0.38),
                  ),
                  Spacing.vGap16,
                  Text(
                    message,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    Spacing.vGap24,
                    ElevatedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(actionLabel!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.surfaceVariant,
                        foregroundColor: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A custom empty state with title and optional subtitle
class _CustomEmptyState extends EmptyState {
  final String title;
  final String? subtitle;
  final VoidCallback? onRefresh;
  final BuildContext context;

  const _CustomEmptyState({
    required super.icon,
    required this.title,
    this.subtitle,
    this.onRefresh,
    required this.context,
  }) : super(message: title);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = S.of(context)!;

    // Wrap in scrollable to allow PageView horizontal swipe detection
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: Spacing.paddingAll24,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: iconSize,
                    color: colorScheme.onSurface.withOpacity(0.38),
                  ),
                  Spacing.vGap16,
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (subtitle != null) ...[
                    Spacing.vGap8,
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.4),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (onRefresh != null) ...[
                    Spacing.vGap24,
                    ElevatedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(s.refresh),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.surfaceVariant,
                        foregroundColor: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
