import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/settings_service.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../l10n/app_localizations.dart';
import 'audiobook_detail_screen.dart';

class AudiobookAuthorScreen extends StatefulWidget {
  final String authorName;
  final List<Audiobook> audiobooks;
  final String? heroTagSuffix;
  final String? initialAuthorImageUrl;

  const AudiobookAuthorScreen({
    super.key,
    required this.authorName,
    required this.audiobooks,
    this.heroTagSuffix,
    this.initialAuthorImageUrl,
  });

  @override
  State<AudiobookAuthorScreen> createState() => _AudiobookAuthorScreenState();
}

class _AudiobookAuthorScreenState extends State<AudiobookAuthorScreen> {
  final _logger = DebugLogger();
  late List<Audiobook> _audiobooks;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _authorImageUrl;

  // View preferences
  String _sortOrder = 'alpha'; // 'alpha' or 'year'
  String _viewMode = 'grid2'; // 'grid2', 'grid3', 'list'

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _audiobooks = List.from(widget.audiobooks);
    // Use initial image URL immediately for smooth hero animation
    _authorImageUrl = widget.initialAuthorImageUrl;
    _loadViewPreferences();
    _sortAudiobooks();
    _loadAuthorImage();
  }

  Future<void> _loadAuthorImage() async {
    final imageUrl = await MetadataService.getAuthorImageUrl(widget.authorName);
    if (mounted && imageUrl != null) {
      setState(() {
        _authorImageUrl = imageUrl;
      });
    }
  }

  Future<void> _loadViewPreferences() async {
    final sortOrder = await SettingsService.getAuthorAudiobooksSortOrder();
    final viewMode = await SettingsService.getAuthorAudiobooksViewMode();
    if (mounted) {
      setState(() {
        _sortOrder = sortOrder;
        _viewMode = viewMode;
        _sortAudiobooks();
      });
    }
  }

  void _toggleSortOrder() {
    final newOrder = _sortOrder == 'alpha' ? 'year' : 'alpha';
    setState(() {
      _sortOrder = newOrder;
      _sortAudiobooks();
    });
    SettingsService.setAuthorAudiobooksSortOrder(newOrder);
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
    SettingsService.setAuthorAudiobooksViewMode(newMode);
  }

  void _sortAudiobooks() {
    if (_sortOrder == 'year') {
      _audiobooks.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      _audiobooks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  @override
  Widget build(BuildContext context) {
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
              expandedHeight: 200,
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
                      tag: HeroTags.authorImage + widget.authorName + _heroTagSuffix,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: _authorImageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: _authorImageUrl!,
                                  fit: BoxFit.cover,
                                  width: 200,
                                  height: 200,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  placeholder: (_, __) => Icon(
                                    MdiIcons.accountOutline,
                                    size: 100,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                  errorWidget: (_, __, ___) => Icon(
                                    MdiIcons.accountOutline,
                                    size: 100,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                )
                              : Icon(
                                  MdiIcons.accountOutline,
                                  size: 100,
                                  color: colorScheme.onPrimaryContainer,
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
                    Text(
                      widget.authorName,
                      style: textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context)!.audiobookCount(_audiobooks.length),
                      style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Audiobooks Section Header with controls
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 8.0, 12.0, 8.0),
                child: Row(
                  children: [
                    Text(
                      S.of(context)!.audiobooks,
                      style: textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Sort toggle
                    IconButton(
                      icon: Icon(
                        _sortOrder == 'alpha' ? Icons.sort_by_alpha : Icons.calendar_today,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                      tooltip: _sortOrder == 'alpha' ? S.of(context)!.sortByYear : S.of(context)!.sortAlphabetically,
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
            _buildAudiobookSliver(),
            SliverToBoxAdapter(child: SizedBox(height: BottomSpacing.withMiniPlayer)),
          ],
        ),
      ),
    );
  }

  Widget _buildAudiobookSliver() {
    if (_viewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAudiobookListTile(_audiobooks[index]),
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
          (context, index) => _buildAudiobookCard(_audiobooks[index]),
          childCount: _audiobooks.length,
        ),
      ),
    );
  }

  Widget _buildAudiobookCard(Audiobook book) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(book, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = 'author${_heroTagSuffix}';

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
          if (book.narratorsString != S.of(context)!.unknownNarrator)
            Text(
              S.of(context)!.narratedBy(book.narratorsString),
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

  Widget _buildAudiobookListTile(Audiobook book) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(book, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = 'author${_heroTagSuffix}';

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
        book.narratorsString != S.of(context)!.unknownNarrator
            ? S.of(context)!.narratedBy(book.narratorsString)
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
