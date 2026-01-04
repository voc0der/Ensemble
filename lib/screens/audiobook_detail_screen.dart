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
import '../services/recently_played_service.dart';
import '../constants/hero_tags.dart';
import '../l10n/app_localizations.dart';

class AudiobookDetailScreen extends StatefulWidget {
  final Audiobook audiobook;
  final String? heroTagSuffix;
  /// Initial image URL from the source for seamless hero animation
  final String? initialImageUrl;

  const AudiobookDetailScreen({
    super.key,
    required this.audiobook,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<AudiobookDetailScreen> createState() => _AudiobookDetailScreenState();
}

class _AudiobookDetailScreenState extends State<AudiobookDetailScreen> {
  final _logger = DebugLogger();
  bool _isDescriptionExpanded = false;
  bool _isFavorite = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  int? _expandedChapterIndex;
  Audiobook? _fullAudiobook;
  bool _isLoadingDetails = false;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  // Use full audiobook if loaded, otherwise use widget audiobook
  Audiobook get _audiobook => _fullAudiobook ?? widget.audiobook;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.audiobook.favorite ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _extractColors();
        }
      });
      // Load full audiobook details with chapters
      _loadAudiobookDetails();
    });
  }

  Future<void> _loadAudiobookDetails() async {
    if (_isLoadingDetails) return;

    setState(() {
      _isLoadingDetails = true;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();

      if (maProvider.api != null) {
        final fullBook = await maProvider.api!.getAudiobookDetails(
          widget.audiobook.provider,
          widget.audiobook.itemId,
        );

        if (mounted && fullBook != null) {
          _logger.log('📚 Loaded full audiobook: ${fullBook.name}, chapters: ${fullBook.chapters?.length ?? 0}');
          setState(() {
            _fullAudiobook = fullBook;
          });
        }
      }

      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      _logger.log('Error loading audiobook details: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
    }
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.audiobook, size: 512);
    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      _logger.log('Failed to extract colors for audiobook: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final newState = !_isFavorite;
      bool success;

      if (newState) {
        String actualProvider = widget.audiobook.provider;
        String actualItemId = widget.audiobook.itemId;

        if (widget.audiobook.providerMappings != null && widget.audiobook.providerMappings!.isNotEmpty) {
          final mapping = widget.audiobook.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.audiobook.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.audiobook.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding audiobook to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'audiobook',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;

        if (widget.audiobook.provider == 'library') {
          libraryItemId = int.tryParse(widget.audiobook.itemId);
        } else if (widget.audiobook.providerMappings != null) {
          final libraryMapping = widget.audiobook.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.audiobook.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          throw Exception('Could not determine library ID for this audiobook');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'audiobook',
          libraryItemId: libraryItemId,
        );
      }

      if (success) {
        setState(() {
          _isFavorite = newState;
        });

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (_isFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      _logger.log('Error toggling audiobook favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        maProvider.setCurrentAudiobook(_audiobook);
        await maProvider.api?.playAudiobook(
          player.playerId,
          widget.audiobook,
        );
      },
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  Future<void> _markAsFinished() async {
    try {
      // Update local audiobook state to show as finished
      final updatedAudiobook = Audiobook(
        itemId: _audiobook.itemId,
        provider: _audiobook.provider,
        name: _audiobook.name,
        authors: _audiobook.authors,
        narrators: _audiobook.narrators,
        publisher: _audiobook.publisher,
        description: _audiobook.description,
        year: _audiobook.year,
        chapters: _audiobook.chapters,
        resumePositionMs: _audiobook.duration?.inMilliseconds, // Set to end
        fullyPlayed: true,
        sortName: _audiobook.sortName,
        uri: _audiobook.uri,
        providerMappings: _audiobook.providerMappings,
        metadata: _audiobook.metadata,
        favorite: _audiobook.favorite,
        duration: _audiobook.duration,
      );

      setState(() {
        _fullAudiobook = updatedAudiobook;
      });

      // TODO: Call MA/ABS API to update server-side progress when available
      _logger.log('📚 Marked audiobook as finished: ${_audiobook.name}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.markedAsFinished(_audiobook.name)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error marking audiobook as finished: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToMarkFinished(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markAsUnplayed() async {
    try {
      // Update local audiobook state to show as unplayed
      final updatedAudiobook = Audiobook(
        itemId: _audiobook.itemId,
        provider: _audiobook.provider,
        name: _audiobook.name,
        authors: _audiobook.authors,
        narrators: _audiobook.narrators,
        publisher: _audiobook.publisher,
        description: _audiobook.description,
        year: _audiobook.year,
        chapters: _audiobook.chapters,
        resumePositionMs: 0, // Reset to start
        fullyPlayed: false,
        sortName: _audiobook.sortName,
        uri: _audiobook.uri,
        providerMappings: _audiobook.providerMappings,
        metadata: _audiobook.metadata,
        favorite: _audiobook.favorite,
        duration: _audiobook.duration,
      );

      setState(() {
        _fullAudiobook = updatedAudiobook;
      });

      // TODO: Call MA/ABS API to update server-side progress when available
      _logger.log('📚 Marked audiobook as unplayed: ${_audiobook.name}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.markedAsUnplayed(_audiobook.name)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error marking audiobook as unplayed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToMarkUnplayed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _playAudiobook({int? startPositionMs}) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      // Set the audiobook context for player controls (uses full audiobook with chapters if available)
      maProvider.setCurrentAudiobook(_audiobook);

      // Record to local recently played (per-profile)
      RecentlyPlayedService.instance.recordAudiobookPlayed(_audiobook);

      // Play the audiobook
      await maProvider.api?.playAudiobook(
        selectedPlayer.playerId,
        widget.audiobook,
      );

      // If we have a resume position, seek to it
      if (startPositionMs != null && startPositionMs > 0) {
        await Future.delayed(const Duration(milliseconds: 500));
        await maProvider.api?.seek(
          selectedPlayer.playerId,
          startPositionMs ~/ 1000, // Convert to seconds
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playing(widget.audiobook.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error playing audiobook: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToPlay(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final providerImageUrl = maProvider.getImageUrl(widget.audiobook, size: 512);
    // Use initialImageUrl as fallback for seamless hero animation
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

    final book = _audiobook;
    final hasResumePosition = (book.resumePositionMs ?? 0) > 0;

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
            // Responsive cover size: 70% of screen width, clamped between 200-320
            final coverSize = (constraints.maxWidth * 0.7).clamp(200.0, 320.0);
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
              actions: [
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: colorScheme.onSurface,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'mark_finished':
                        _markAsFinished();
                        break;
                      case 'mark_unplayed':
                        _markAsUnplayed();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'mark_finished',
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: colorScheme.onSurface,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(S.of(context)!.markAsFinished),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'mark_unplayed',
                      child: Row(
                        children: [
                          Icon(
                            Icons.restart_alt,
                            color: colorScheme.onSurface,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(S.of(context)!.markAsUnplayed),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    Hero(
                      tag: HeroTags.audiobookCover + (widget.audiobook.uri ?? widget.audiobook.itemId) + _heroTagSuffix,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
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
                                      MdiIcons.bookOutline,
                                      size: coverSize * 0.43,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Icon(
                                      MdiIcons.bookOutline,
                                      size: coverSize * 0.43,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    MdiIcons.bookOutline,
                                    size: coverSize * 0.43,
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
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Hero(
                      tag: HeroTags.audiobookTitle + (widget.audiobook.uri ?? widget.audiobook.itemId) + _heroTagSuffix,
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          book.name,
                          style: textTheme.headlineMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Author
                    Text(
                      S.of(context)!.byAuthor(book.authorsString),
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),

                    // Narrator
                    if (book.narratorsString != S.of(context)!.unknownNarrator) ...[
                      const SizedBox(height: 4),
                      Text(
                        S.of(context)!.narratedBy(book.narratorsString),
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],

                    // Duration & Progress
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (book.duration != null) ...[
                          Icon(
                            Icons.schedule,
                            size: 16,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(book.duration!),
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                        if (book.progress > 0) ...[
                          const SizedBox(width: 16),
                          Icon(
                            Icons.bookmark,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            S.of(context)!.percentComplete((book.progress * 100).toInt()),
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Progress bar
                    if (book.progress > 0) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: book.progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                          minHeight: 6,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        // Play/Resume Button
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () => _playAudiobook(
                                startPositionMs: hasResumePosition ? book.resumePositionMs : null,
                              ),
                              icon: Icon(hasResumePosition ? Icons.play_arrow : Icons.play_arrow),
                              label: Text(hasResumePosition ? S.of(context)!.resume : S.of(context)!.play),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),

                        if (hasResumePosition) ...[
                          const SizedBox(width: 12),
                          // Start Over Button
                          SizedBox(
                            height: 50,
                            width: 50,
                            child: FilledButton.tonal(
                              onPressed: () => _playAudiobook(startPositionMs: 0),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Icon(Icons.replay),
                            ),
                          ),
                        ],

                        const SizedBox(width: 12),

                        // Play On Button
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: FilledButton.tonal(
                            onPressed: () => _showPlayOnMenu(context),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.speaker_group_outlined),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Favorite Button
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: FilledButton.tonal(
                            onPressed: _toggleFavorite,
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: Icon(
                              _isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: _isFavorite
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Description
                    if (book.description != null && book.description!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        S.of(context)!.about,
                        style: textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isDescriptionExpanded = !_isDescriptionExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            _stripHtml(book.description!),
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.8),
                            ),
                            maxLines: _isDescriptionExpanded ? null : 4,
                            overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],

                    // Chapters Header
                    const SizedBox(height: 24),
                    Text(
                      S.of(context)!.chapters,
                      style: textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // Chapter List or Loading/Empty State
            // Use MA chapters if available, otherwise use ABS chapters
            ..._buildChapterSection(book, colorScheme, textTheme),

            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        );
          },
        ),
      ),
    );
  }

  /// Build the chapter section with loading, chapters, or empty state
  List<Widget> _buildChapterSection(Audiobook book, ColorScheme colorScheme, TextTheme textTheme) {
    // Loading state
    if (_isLoadingDetails) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    S.of(context)!.loadingChapters,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    // Get chapters from MA
    final chapters = book.chapters;

    // Show chapters if available
    if (chapters != null && chapters.isNotEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildChapterTile(chapters[index], index, colorScheme, textTheme),
              childCount: chapters.length,
            ),
          ),
        ),
      ];
    }

    // Empty state
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              S.of(context)!.noChapterInfoAvailable,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildChapterTile(Chapter chapter, int index, ColorScheme colorScheme, TextTheme textTheme) {
    final book = _audiobook;
    final resumeMs = book.resumePositionMs ?? 0;
    final chapterEndMs = chapter.positionMs + (chapter.duration?.inMilliseconds ?? 0);

    // Determine if chapter is played, in progress, or not started
    final isPlayed = resumeMs >= chapterEndMs;
    final isInProgress = resumeMs >= chapter.positionMs && resumeMs < chapterEndMs;
    final isExpanded = _expandedChapterIndex == index;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isPlayed
                  ? colorScheme.primary
                  : isInProgress
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: isPlayed
                  ? Icon(Icons.check, size: 18, color: colorScheme.onPrimary)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isInProgress
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          title: Text(
            chapter.title,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: isInProgress ? FontWeight.bold : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: isInProgress
              ? Text(
                  S.of(context)!.inProgress,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                )
              : null,
          trailing: Text(
                  _formatPositionTime(chapter.positionMs),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
          onTap: () {
            if (isExpanded) {
              setState(() {
                _expandedChapterIndex = null;
              });
            } else {
              _playAudiobook(startPositionMs: chapter.positionMs);
            }
          },
          onLongPress: () {
            setState(() {
              _expandedChapterIndex = isExpanded ? null : index;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: isExpanded
              ? Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 12.0, top: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Play from here button
                      SizedBox(
                        height: 44,
                        child: FilledButton.tonal(
                          onPressed: () {
                            setState(() {
                              _expandedChapterIndex = null;
                            });
                            _playAudiobook(startPositionMs: chapter.positionMs);
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow, size: 20),
                              const SizedBox(width: 8),
                              Text(isInProgress ? S.of(context)!.resume : S.of(context)!.play),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Format position time in milliseconds as "h:mm:ss" or "m:ss"
  String _formatPositionTime(int positionMs) {
    final duration = Duration(milliseconds: positionMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  /// Strip HTML tags from text and clean up whitespace
  String _stripHtml(String htmlText) {
    // Remove HTML tags
    final withoutTags = htmlText.replaceAll(RegExp(r'<[^>]*>'), '');
    // Decode common HTML entities
    final decoded = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // Clean up multiple spaces/newlines
    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
