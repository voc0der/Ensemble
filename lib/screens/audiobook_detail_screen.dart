import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/debug_logger.dart';
import '../constants/hero_tags.dart';

class AudiobookDetailScreen extends StatefulWidget {
  final Audiobook audiobook;
  final String? heroTagSuffix;

  const AudiobookDetailScreen({
    super.key,
    required this.audiobook,
    this.heroTagSuffix,
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
    if (maProvider.api == null) return;

    try {
      final newState = !_isFavorite;

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
          actualProvider = mapping.providerInstance;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding audiobook to favorites: provider=$actualProvider, itemId=$actualItemId');
        await maProvider.api!.addToFavorites('audiobook', actualItemId, actualProvider);
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

        _logger.log('Removing audiobook from favorites: libraryItemId=$libraryItemId');
        await maProvider.api!.removeFromFavorites('audiobook', libraryItemId);
      }

      setState(() {
        _isFavorite = newState;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFavorite ? 'Added to favorites' : 'Removed from favorites',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error toggling audiobook favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update favorite: $e'),
            duration: const Duration(seconds: 2),
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
        const SnackBar(content: Text('No player selected')),
      );
      return;
    }

    try {
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
            content: Text('Playing ${widget.audiobook.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error playing audiobook: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.audiobook, size: 512);

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
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 320,
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
                      tag: HeroTags.audiobookCover + (widget.audiobook.uri ?? widget.audiobook.itemId) + _heroTagSuffix,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 280,
                          height: 280,
                          color: colorScheme.surfaceContainerHighest,
                          child: imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Center(
                                    child: Icon(
                                      MdiIcons.bookOutline,
                                      size: 120,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Icon(
                                      MdiIcons.bookOutline,
                                      size: 120,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    MdiIcons.bookOutline,
                                    size: 120,
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
                      'By ${book.authorsString}',
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),

                    // Narrator
                    if (book.narratorsString != 'Unknown Narrator') ...[
                      const SizedBox(height: 4),
                      Text(
                        'Narrated by ${book.narratorsString}',
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
                            '${(book.progress * 100).toInt()}% complete',
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
                              label: Text(hasResumePosition ? 'Resume' : 'Play'),
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
                        'About',
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
                      'Chapters',
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
                    'Loading chapters...',
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
              'No chapter information available',
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
          subtitle: Text(
            isInProgress
                ? 'In progress • ${_formatPositionTime(chapter.positionMs)}'
                : _formatPositionTime(chapter.positionMs),
            style: textTheme.bodySmall?.copyWith(
              color: isInProgress ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          trailing: chapter.duration != null
              ? Text(
                  _formatDuration(chapter.duration!),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
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
                              Text(isInProgress ? 'Resume' : 'Play'),
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
