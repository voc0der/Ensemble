import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_picker_sheet.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/debug_logger.dart';
import '../constants/hero_tags.dart';
import '../l10n/app_localizations.dart';

class PodcastDetailScreen extends StatefulWidget {
  final MediaItem podcast;
  final String? heroTagSuffix;
  final String? initialImageUrl;

  const PodcastDetailScreen({
    super.key,
    required this.podcast,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen> {
  final _logger = DebugLogger();
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  List<MediaItem> _episodes = [];
  bool _isLoadingEpisodes = false;
  bool _isDescriptionExpanded = false;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _extractColors();
        }
      });
      _loadEpisodes();
    });
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.podcast, size: 1024) ?? widget.initialImageUrl;

    if (imageUrl != null) {
      try {
        final colorSchemes = await PaletteHelper.extractColorSchemes(
          CachedNetworkImageProvider(imageUrl),
        );
        if (mounted && colorSchemes != null) {
          setState(() {
            _lightColorScheme = colorSchemes.$1;
            _darkColorScheme = colorSchemes.$2;
          });
        }
      } catch (e) {
        _logger.log('🎙️ Error extracting colors: $e');
      }
    }
  }

  Future<void> _loadEpisodes() async {
    if (_isLoadingEpisodes) return;

    setState(() {
      _isLoadingEpisodes = true;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.api != null) {
        final episodes = await maProvider.api!.getPodcastEpisodes(
          widget.podcast.itemId,
          provider: widget.podcast.provider,
        );

        if (mounted) {
          _logger.log('🎙️ Loaded ${episodes.length} episodes for ${widget.podcast.name}');
          setState(() {
            _episodes = episodes;
          });
        }
      }
    } catch (e) {
      _logger.log('🎙️ Error loading episodes: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEpisodes = false;
        });
      }
    }
  }

  void _playEpisode(MediaItem episode) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer != null) {
      try {
        await maProvider.api?.playPodcastEpisode(selectedPlayer.playerId, episode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing: ${episode.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        _logger.log('🎙️ Error playing episode: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to play episode: $e')),
          );
        }
      }
    } else {
      _showPlayOnMenu(context, episode);
    }
  }

  void _showPlayOnMenu(BuildContext context, MediaItem episode) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.api?.playPodcastEpisode(player.playerId, episode);
      },
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration == Duration.zero) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final providerImageUrl = maProvider.getImageUrl(widget.podcast, size: 1024);
    final imageUrl = providerImageUrl ?? widget.initialImageUrl;

    final adaptiveTheme = context.select<ThemeProvider, bool>(
      (provider) => provider.adaptiveTheme,
    );
    final adaptiveLightScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveLightScheme,
    );
    final adaptiveDarkScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveDarkScheme,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      adaptiveScheme = isDark
          ? (_darkColorScheme ?? adaptiveDarkScheme)
          : (_lightColorScheme ?? adaptiveLightScheme);
    }
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final description = widget.podcast.metadata?['description'] as String?;
    final author = widget.podcast.metadata?['author'] as String?;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          clearAdaptiveColorsOnBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final coverSize = (constraints.maxWidth * 0.6).clamp(180.0, 280.0);
            final expandedHeight = coverSize + 70;

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: expandedHeight,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      clearAdaptiveColorsOnBack(context);
                      Navigator.pop(context);
                    },
                    color: colorScheme.onSurface,
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Hero(
                          tag: HeroTags.podcastCover + (widget.podcast.uri ?? widget.podcast.itemId) + _heroTagSuffix,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: coverSize,
                              height: coverSize,
                              color: colorScheme.surfaceContainerHighest,
                              child: imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                      placeholder: (_, __) => Center(
                                        child: Icon(
                                          MdiIcons.podcast,
                                          size: coverSize * 0.4,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Center(
                                        child: Icon(
                                          MdiIcons.podcast,
                                          size: coverSize * 0.4,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(
                                        MdiIcons.podcast,
                                        size: coverSize * 0.4,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Podcast title
                        Text(
                          widget.podcast.name,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (author != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            author,
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Description
                        if (description != null && description.isNotEmpty) ...[
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isDescriptionExpanded = !_isDescriptionExpanded;
                              });
                            },
                            child: AnimatedCrossFade(
                              firstChild: Text(
                                description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                              secondChild: Text(
                                description,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                              crossFadeState: _isDescriptionExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 200),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Episodes header
                        Row(
                          children: [
                            Text(
                              S.of(context)!.episodes,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_episodes.isNotEmpty)
                              Text(
                                '(${_episodes.length})',
                                style: textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Episodes list
                if (_isLoadingEpisodes)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: colorScheme.primary),
                      ),
                    ),
                  )
                else if (_episodes.isEmpty)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              MdiIcons.microphoneOff,
                              size: 48,
                              color: colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No episodes found',
                              style: textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final episode = _episodes[index];
                        final episodeDescription = episode.metadata?['description'] as String?;
                        final duration = episode.duration;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              MdiIcons.play,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            episode.name,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (episodeDescription != null && episodeDescription.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  episodeDescription,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                              if (duration != null && duration > Duration.zero) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatDuration(duration),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: () => _playEpisode(episode),
                        );
                      },
                      childCount: _episodes.length,
                    ),
                  ),

                // Bottom padding for mini player
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
