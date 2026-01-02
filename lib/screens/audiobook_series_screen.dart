import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart' show BottomSpacing;
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import 'audiobook_detail_screen.dart';
import '../l10n/app_localizations.dart';

class AudiobookSeriesScreen extends StatefulWidget {
  final AudiobookSeries series;
  final String? heroTag;
  /// Pre-loaded cover URLs from the library screen for smooth Hero animation
  final List<String>? initialCovers;

  const AudiobookSeriesScreen({
    super.key,
    required this.series,
    this.heroTag,
    this.initialCovers,
  });

  @override
  State<AudiobookSeriesScreen> createState() => _AudiobookSeriesScreenState();
}

class _AudiobookSeriesScreenState extends State<AudiobookSeriesScreen> {
  final _logger = DebugLogger();
  List<Audiobook> _audiobooks = [];
  bool _isLoading = true;
  String? _error;

  // View preferences
  String _sortOrder = 'series'; // 'series' (by series number) or 'alpha'
  String _viewMode = 'grid2'; // 'grid2', 'grid3', 'list'

  // Extracted colors from book covers
  List<Color> _extractedColors = [];

  // Cover URLs - start with initial covers, update when books load
  List<String> _coverUrls = [];

  @override
  void initState() {
    super.initState();
    // Use initial covers immediately for smooth Hero animation
    if (widget.initialCovers != null && widget.initialCovers!.isNotEmpty) {
      _coverUrls = List.from(widget.initialCovers!);
      // Start color extraction from initial covers
      _extractColorsFromUrls(widget.initialCovers!);
    }
    _loadViewPreferences();
    // Defer loading until after first frame to ensure UI renders first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadSeriesBooks();
      }
    });
  }

  /// Extract colors from cover URLs (used for initial covers)
  Future<void> _extractColorsFromUrls(List<String> coverUrls) async {
    final extractedColors = <Color>[];

    for (final url in coverUrls.take(4)) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(url),
          maximumColorCount: 8,
        );

        if (palette.darkMutedColor != null) {
          extractedColors.add(palette.darkMutedColor!.color);
        }
        if (palette.mutedColor != null) {
          extractedColors.add(palette.mutedColor!.color);
        }
        if (palette.darkVibrantColor != null) {
          extractedColors.add(palette.darkVibrantColor!.color);
        }
        if (palette.dominantColor != null) {
          final hsl = HSLColor.fromColor(palette.dominantColor!.color);
          extractedColors.add(hsl.withLightness((hsl.lightness * 0.4).clamp(0.1, 0.3)).toColor());
        }
      } catch (e) {
        _logger.log('📚 Error extracting colors: $e');
      }
    }

    if (extractedColors.isNotEmpty && mounted) {
      setState(() {
        _extractedColors = extractedColors;
      });
    }
  }

  Future<void> _loadViewPreferences() async {
    final sortOrder = await SettingsService.getSeriesAudiobooksSortOrder();
    final viewMode = await SettingsService.getSeriesAudiobooksViewMode();
    if (mounted) {
      setState(() {
        _sortOrder = sortOrder;
        _viewMode = viewMode;
      });
    }
  }

  void _toggleSortOrder() {
    final newOrder = _sortOrder == 'series' ? 'alpha' : 'series';
    setState(() {
      _sortOrder = newOrder;
      _sortAudiobooks();
    });
    SettingsService.setSeriesAudiobooksSortOrder(newOrder);
  }

  void _cycleViewMode() {
    String newMode;
    switch (_viewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() {
      _viewMode = newMode;
    });
    SettingsService.setSeriesAudiobooksViewMode(newMode);
  }

  void _sortAudiobooks() {
    if (_sortOrder == 'series') {
      // Sort by series number (sequence), falling back to name for books without sequence
      _audiobooks.sort((a, b) {
        final seqA = a.seriesSequence;
        final seqB = b.seriesSequence;
        if (seqA == null && seqB == null) return a.name.compareTo(b.name);
        if (seqA == null) return 1; // Books without sequence go to end
        if (seqB == null) return -1;
        return seqA.compareTo(seqB);
      });
    } else {
      // Sort alphabetically
      _audiobooks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  Future<void> _loadSeriesBooks() async {
    _logger.log('📚 SeriesScreen _loadSeriesBooks START');
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      _logger.log('📚 SeriesScreen setState done, getting provider...');

      final maProvider = context.read<MusicAssistantProvider>();
      _logger.log('📚 SeriesScreen got provider, api=${maProvider.api != null}');

      if (maProvider.api == null) {
        setState(() {
          _error = S.of(context)!.notConnected;
          _isLoading = false;
        });
        return;
      }

      _logger.log('📚 SeriesScreen calling getSeriesAudiobooks: path=${widget.series.id}');
      final books = await maProvider.api!.getSeriesAudiobooks(widget.series.id);
      _logger.log('📚 SeriesScreen got ${books.length} books');

      // Debug: Log sequence data for each book
      for (final book in books) {
        _logger.log('📚 Book: "${book.name}" | position=${book.position} | browseOrder=${book.browseOrder} | sortName=${book.sortName} | seq=${book.seriesSequence} | metadata.series=${book.metadata?['series']}');
      }

      if (mounted) {
        // Update cover URLs from loaded books
        final newCovers = <String>[];
        for (final book in books.take(9)) {
          final imageUrl = maProvider.getImageUrl(book);
          if (imageUrl != null) {
            newCovers.add(imageUrl);
          }
        }

        setState(() {
          _audiobooks = books;
          _sortAudiobooks(); // Sort inside setState so UI updates
          // Update covers if we got new ones (may have more than initial)
          if (newCovers.isNotEmpty) {
            _coverUrls = newCovers;
          }
          _isLoading = false;
        });
        // Debug: Log sorted order
        _logger.log('📚 Sorted order ($_sortOrder):');
        for (final book in _audiobooks) {
          _logger.log('  - ${book.seriesSequence ?? "null"}: ${book.name}');
        }

        // Extract colors from book covers asynchronously
        _extractCoverColors(maProvider);
      }
    } catch (e, stack) {
      _logger.log('📚 SeriesScreen error: $e');
      _logger.log('📚 SeriesScreen stack: $stack');
      if (mounted) {
        setState(() {
          _error = 'Failed to load books: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Extract colors from book covers for empty grid cells
  Future<void> _extractCoverColors(MusicAssistantProvider maProvider) async {
    final extractedColors = <Color>[];

    // Extract colors from first few book covers
    for (final book in _audiobooks.take(4)) {
      final imageUrl = maProvider.getImageUrl(book);
      if (imageUrl == null) continue;

      try {
        final palette = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(imageUrl),
          maximumColorCount: 8,
        );

        // Get dark muted colors for grid squares
        if (palette.darkMutedColor != null) {
          extractedColors.add(palette.darkMutedColor!.color);
        }
        if (palette.mutedColor != null) {
          extractedColors.add(palette.mutedColor!.color);
        }
        if (palette.darkVibrantColor != null) {
          extractedColors.add(palette.darkVibrantColor!.color);
        }
        if (palette.dominantColor != null) {
          // Darken the dominant color for better appearance
          final hsl = HSLColor.fromColor(palette.dominantColor!.color);
          extractedColors.add(hsl.withLightness((hsl.lightness * 0.4).clamp(0.1, 0.3)).toColor());
        }
      } catch (e) {
        _logger.log('📚 Error extracting colors: $e');
      }
    }

    if (extractedColors.isNotEmpty && mounted) {
      setState(() {
        _extractedColors = extractedColors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.watch<MusicAssistantProvider>();
    final l10n = S.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive cover size: 70% of screen width, clamped between 200-320
          final coverSize = (constraints.maxWidth * 0.7).clamp(200.0, 320.0);
          final expandedHeight = coverSize + 70;

          return CustomScrollView(
        slivers: [
          // App bar with series cover collage (matches audiobook detail screen)
          SliverAppBar(
            expandedHeight: expandedHeight,
            pinned: true,
            backgroundColor: colorScheme.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: colorScheme.onSurface,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  // Series cover collage - responsive size
                  Hero(
                    tag: widget.heroTag ?? 'series_cover_${widget.series.id}',
                    child: Container(
                      width: coverSize,
                      height: coverSize,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildSeriesCover(colorScheme, maProvider),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Title and count
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.series.name,
                    style: textTheme.headlineMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoading
                        ? l10n.loading
                        : l10n.bookCount(_audiobooks.length),
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Books section header with controls
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 8.0, 12.0, 8.0),
              child: Row(
                children: [
                  Text(
                    l10n.books,
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Sort toggle
                  IconButton(
                    icon: Icon(
                      _sortOrder == 'series' ? Icons.format_list_numbered : Icons.sort_by_alpha,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    tooltip: _sortOrder == 'series' ? S.of(context)!.sortAlphabetically : S.of(context)!.sortBySeriesOrder,
                    onPressed: _toggleSortOrder,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  // View mode toggle
                  IconButton(
                    icon: Icon(
                      _viewMode == 'list'
                          ? Icons.view_list
                          : _viewMode == 'grid3'
                              ? Icons.grid_view
                              : Icons.grid_on,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    tooltip: _viewMode == 'grid2'
                        ? S.of(context)!.threeColumnGrid
                        : _viewMode == 'grid3'
                            ? S.of(context)!.listView
                            : S.of(context)!.twoColumnGrid,
                    onPressed: _cycleViewMode,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),

          // Content
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadSeriesBooks,
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            )
          else if (_audiobooks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.library_books_outlined,
                        size: 48, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      S.of(context)!.noBooksInSeries,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildAudiobookSliver(maProvider),

          // Bottom padding for mini player
          SliverToBoxAdapter(
            child: SizedBox(height: BottomSpacing.withMiniPlayer),
          ),
        ],
      );
        },
      ),
    );
  }

  // Dark pastel colors for empty cells - muted and book-like
  static const _emptyColors = [
    Color(0xFF2D3436), // Dark slate
    Color(0xFF34495E), // Dark blue-grey
    Color(0xFF4A3728), // Dark brown
    Color(0xFF2C3E50), // Midnight blue
    Color(0xFF3D3D3D), // Charcoal
    Color(0xFF4A4458), // Dark purple-grey
    Color(0xFF3E4A47), // Dark teal-grey
    Color(0xFF4A3F35), // Dark warm grey
  ];

  Widget _buildSeriesCover(ColorScheme colorScheme, MusicAssistantProvider maProvider) {
    // Use _coverUrls which may have initial covers or loaded covers
    // Only show placeholder if we truly have no covers
    if (_coverUrls.isEmpty) {
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.collections_bookmark_rounded,
            size: 64,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
      );
    }

    final covers = _coverUrls;

    // Dynamic grid size based on number of covers (matches library screen)
    // 1 cover = 1x1, 2-4 covers = 2x2, 5+ covers = 3x3
    int gridSize;
    if (covers.length == 1) {
      gridSize = 1;
    } else if (covers.length <= 4) {
      gridSize = 2;
    } else {
      gridSize = 3;
    }

    // Use series ID to pick consistent colors and nested grid patterns
    final colorSeed = widget.series.id.hashCode;

    // Pad covers to fill grid
    final displayCovers = List<String?>.filled(gridSize * gridSize, null);
    for (var i = 0; i < covers.length && i < displayCovers.length; i++) {
      displayCovers[i] = covers[i];
    }

    // Build grid using Column/Row for proper sizing (no scrolling issues)
    return Column(
      children: List.generate(gridSize, (row) {
        return Expanded(
          child: Row(
            children: List.generate(gridSize, (col) {
              final index = row * gridSize + col;
              final coverUrl = displayCovers[index];

              return Expanded(
                child: coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (_, __) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.book,
                              color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                              size: 20,
                            ),
                          ),
                        )
                      : _buildEmptyCell(colorSeed, index),
              );
            }),
          ),
        );
      }),
    );
  }

  /// Builds an empty cell with either a solid color or a nested grid
  /// The pattern is deterministic based on series ID and cell index
  Widget _buildEmptyCell(int colorSeed, int cellIndex) {
    // Use extracted colors if available, otherwise fall back to static palette
    final baseColors = _extractedColors.isNotEmpty ? _extractedColors : _emptyColors;
    // Tone down colors - reduce saturation and darken
    final colors = baseColors.map((c) {
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withSaturation((hsl.saturation * 0.5).clamp(0.05, 0.25))
          .withLightness((hsl.lightness * 0.7).clamp(0.08, 0.20))
          .toColor();
    }).toList();

    // Use combined seed for deterministic but varied patterns
    final seed = colorSeed + cellIndex * 17; // Prime multiplier for better distribution

    // Determine nested grid size: 1 (solid), 2 (2x2), or 3 (3x3)
    // Distribution: ~50% solid, ~30% 2x2, ~20% 3x3
    final sizeRoll = seed.abs() % 100;
    int nestedSize;
    if (sizeRoll < 50) {
      nestedSize = 1; // Solid color
    } else if (sizeRoll < 80) {
      nestedSize = 2; // 2x2 grid
    } else {
      nestedSize = 3; // 3x3 grid
    }

    if (nestedSize == 1) {
      // Solid color
      final colorIndex = seed.abs() % colors.length;
      return Container(color: colors[colorIndex]);
    }

    // Build nested grid (no margins - seamless)
    return Column(
      children: List.generate(nestedSize, (row) {
        return Expanded(
          child: Row(
            children: List.generate(nestedSize, (col) {
              final nestedIndex = row * nestedSize + col;
              // Use different seed for each nested cell
              final nestedSeed = seed + nestedIndex * 7;
              final colorIndex = nestedSeed.abs() % colors.length;
              return Expanded(
                child: Container(color: colors[colorIndex]),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildAudiobookSliver(MusicAssistantProvider maProvider) {
    if (_viewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAudiobookListTile(_audiobooks[index], maProvider),
            childCount: _audiobooks.length,
          ),
        ),
      );
    }

    final crossAxisCount = _viewMode == 'grid3' ? 3 : 2;
    final childAspectRatio = _viewMode == 'grid3' ? 0.65 : 0.70;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAudiobookCard(_audiobooks[index], maProvider),
          childCount: _audiobooks.length,
        ),
      ),
    );
  }

  Widget _buildAudiobookCard(Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = 'series_${widget.series.id}';

    return InkWell(
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: heroSuffix, initialImageUrl: imageUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_$heroSuffix',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
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
                if (book.progress > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: book.progress,
                      backgroundColor: Colors.black54,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      minHeight: 3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                book.name,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (book.authorsString.isNotEmpty && book.authorsString != S.of(context)!.unknownAuthor)
            Text(
              book.authorsString,
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

  Widget _buildAudiobookListTile(Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = 'series_${widget.series.id}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_$heroSuffix',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                color: colorScheme.surfaceContainerHighest,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) => Icon(
                          MdiIcons.bookOutline,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          MdiIcons.bookOutline,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        MdiIcons.bookOutline,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
              if (book.progress > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: book.progress,
                    backgroundColor: Colors.black54,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    minHeight: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Hero(
        tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_$heroSuffix',
        child: Material(
          color: Colors.transparent,
          child: Text(
            book.name,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      subtitle: Text(
        book.authorsString.isNotEmpty && book.authorsString != S.of(context)!.unknownAuthor
            ? book.authorsString
            : book.duration != null
                ? _formatDuration(book.duration!)
                : '',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: book.progress > 0
          ? Text(
              '${(book.progress * 100).toInt()}%',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
              ),
            )
          : null,
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: heroSuffix, initialImageUrl: imageUrl),
    );
  }

  void _navigateToAudiobook(Audiobook book, {String? heroTagSuffix, String? initialImageUrl}) {
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookDetailScreen(
          audiobook: book,
          heroTagSuffix: heroTagSuffix,
          initialImageUrl: initialImageUrl,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
