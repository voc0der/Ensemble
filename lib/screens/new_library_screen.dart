import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_avatar.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
import '../widgets/letter_scrollbar.dart';
import '../services/settings_service.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'settings_screen.dart';
import 'audiobook_author_screen.dart';
import 'audiobook_detail_screen.dart';
import 'audiobook_series_screen.dart';

/// Media type for the library
enum LibraryMediaType { music, books, podcasts, radio }

class NewLibraryScreen extends StatefulWidget {
  const NewLibraryScreen({super.key});

  @override
  State<NewLibraryScreen> createState() => _NewLibraryScreenState();
}

class _NewLibraryScreenState extends State<NewLibraryScreen>
    with RestorationMixin {
  late PageController _pageController;
  List<Playlist> _playlists = [];
  List<Track> _favoriteTracks = [];
  List<Audiobook> _audiobooks = [];
  bool _isLoadingPlaylists = true;
  bool _isLoadingTracks = false;
  bool _isLoadingAudiobooks = false;
  bool _showFavoritesOnly = false;

  // PERF: Pre-sorted lists - computed once on data load, not on every build
  List<Playlist> _sortedPlaylists = [];
  List<String> _playlistNames = [];
  List<Track> _sortedFavoriteTracks = [];
  List<Audiobook> _sortedAudiobooks = [];
  List<String> _audiobookNames = [];
  List<String> _sortedAuthorNames = [];
  Map<String, List<Audiobook>> _groupedAudiobooksByAuthor = {};
  List<AudiobookSeries> _sortedSeries = [];
  List<String> _seriesNames = [];

  // Media type selection (Music, Books, Podcasts)
  LibraryMediaType _selectedMediaType = LibraryMediaType.music;

  // View mode settings
  String _artistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _albumsViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _playlistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _audiobooksViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _authorsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _seriesViewMode = 'grid2'; // 'grid2', 'grid3'
  String _audiobooksSortOrder = 'alpha'; // 'alpha', 'year'

  // Author image cache
  final Map<String, String?> _authorImages = {};

  // Series state
  List<AudiobookSeries> _series = [];
  bool _isLoadingSeries = false;

  // Series book covers cache: seriesId -> list of book thumbnail URLs
  final Map<String, List<String>> _seriesBookCovers = {};
  final Set<String> _seriesCoversLoading = {};
  // Series extracted colors cache: seriesId -> list of colors from book covers
  final Map<String, List<Color>> _seriesExtractedColors = {};
  // Series book counts cache: seriesId -> number of books
  final Map<String, int> _seriesBookCounts = {};
  bool _seriesLoaded = false;
  // PERF: Debounce color extraction to avoid blocking UI during scroll
  Timer? _colorExtractionDebounce;
  final Map<String, List<String>> _pendingColorExtractions = {};

  // Restoration: Remember selected tab across app restarts
  final RestorableInt _selectedTabIndex = RestorableInt(0);
  // PERF: Separate ValueNotifier for efficient UI updates (RestorableInt doesn't implement ValueListenable)
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  // Scroll-to-hide filter bars
  bool _isFilterBarVisible = true;
  double _lastScrollOffset = 0;
  static const double _scrollThreshold = 10.0;
  bool _isLetterScrollbarDragging = false; // Disable scroll-to-hide while dragging

  // Scroll controllers for letter scrollbar
  final ScrollController _artistsScrollController = ScrollController();
  final ScrollController _albumsScrollController = ScrollController();
  final ScrollController _playlistsScrollController = ScrollController();
  final ScrollController _authorsScrollController = ScrollController();
  final ScrollController _audiobooksScrollController = ScrollController();
  final ScrollController _seriesScrollController = ScrollController();

  int get _tabCount {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return _showFavoritesOnly ? 4 : 3;
      case LibraryMediaType.books:
        return 3; // Authors, All Books, Series
      case LibraryMediaType.podcasts:
        return 1; // Coming soon placeholder
      case LibraryMediaType.radio:
        return 1; // Radio stations
    }
  }

  @override
  String? get restorationId => 'new_library_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedTabIndex, 'selected_tab_index');
    // Sync ValueNotifier with restored value
    _tabIndexNotifier.value = _selectedTabIndex.value;
    // Apply restored tab index after PageController is created
    if (_selectedTabIndex.value < _tabCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_selectedTabIndex.value);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPlaylists();
    _loadViewPreferences();
  }

  Future<void> _loadViewPreferences() async {
    final artistsMode = await SettingsService.getLibraryArtistsViewMode();
    final albumsMode = await SettingsService.getLibraryAlbumsViewMode();
    final playlistsMode = await SettingsService.getLibraryPlaylistsViewMode();
    final authorsMode = await SettingsService.getLibraryAuthorsViewMode();
    final audiobooksMode = await SettingsService.getLibraryAudiobooksViewMode();
    final audiobooksSortOrder = await SettingsService.getLibraryAudiobooksSortOrder();
    final seriesMode = await SettingsService.getLibrarySeriesViewMode();
    if (mounted) {
      setState(() {
        _artistsViewMode = artistsMode;
        _albumsViewMode = albumsMode;
        _playlistsViewMode = playlistsMode;
        _authorsViewMode = authorsMode;
        _audiobooksViewMode = audiobooksMode;
        _audiobooksSortOrder = audiobooksSortOrder;
        _seriesViewMode = seriesMode;
      });
    }
  }

  void _cycleArtistsViewMode() {
    String newMode;
    switch (_artistsViewMode) {
      case 'list':
        newMode = 'grid2';
        break;
      case 'grid2':
        newMode = 'grid3';
        break;
      default:
        newMode = 'list';
    }
    setState(() => _artistsViewMode = newMode);
    SettingsService.setLibraryArtistsViewMode(newMode);
  }

  void _cycleAlbumsViewMode() {
    String newMode;
    switch (_albumsViewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() => _albumsViewMode = newMode);
    SettingsService.setLibraryAlbumsViewMode(newMode);
  }

  void _cyclePlaylistsViewMode() {
    String newMode;
    switch (_playlistsViewMode) {
      case 'list':
        newMode = 'grid2';
        break;
      case 'grid2':
        newMode = 'grid3';
        break;
      default:
        newMode = 'list';
    }
    setState(() => _playlistsViewMode = newMode);
    SettingsService.setLibraryPlaylistsViewMode(newMode);
  }

  void _cycleAuthorsViewMode() {
    String newMode;
    switch (_authorsViewMode) {
      case 'list':
        newMode = 'grid2';
        break;
      case 'grid2':
        newMode = 'grid3';
        break;
      default:
        newMode = 'list';
    }
    setState(() => _authorsViewMode = newMode);
    SettingsService.setLibraryAuthorsViewMode(newMode);
  }

  void _cycleAudiobooksViewMode() {
    String newMode;
    switch (_audiobooksViewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() => _audiobooksViewMode = newMode);
    SettingsService.setLibraryAudiobooksViewMode(newMode);
  }

  void _toggleAudiobooksSortOrder() {
    final newOrder = _audiobooksSortOrder == 'alpha' ? 'year' : 'alpha';
    // PERF: Re-sort once on order change, not on every build
    final sorted = List<Audiobook>.from(_audiobooks);
    if (newOrder == 'year') {
      sorted.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    setState(() {
      _audiobooksSortOrder = newOrder;
      _sortedAudiobooks = sorted;
      _audiobookNames = sorted.map((a) => a.name).toList();
    });
    SettingsService.setLibraryAudiobooksSortOrder(newOrder);
  }

  void _cycleSeriesViewMode() {
    // Series now has grid2, grid3, and list view
    String newMode;
    switch (_seriesViewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() => _seriesViewMode = newMode);
    SettingsService.setLibrarySeriesViewMode(newMode);
  }

  IconData _getViewModeIcon(String mode) {
    switch (mode) {
      case 'list':
        return Icons.view_list;
      case 'grid3':
        return Icons.grid_view;
      default:
        return Icons.grid_on;
    }
  }

  String _getCurrentViewMode() {
    // Return the view mode for the currently selected tab
    final tabIndex = _selectedTabIndex.value;

    // Handle books media type
    if (_selectedMediaType == LibraryMediaType.books) {
      switch (tabIndex) {
        case 0:
          return _authorsViewMode;
        case 1:
          return _audiobooksViewMode;
        case 2:
          return _seriesViewMode;
        default:
          return 'list';
      }
    }

    // Handle music media type
    if (_showFavoritesOnly) {
      // Artists, Albums, Tracks, Playlists
      switch (tabIndex) {
        case 0:
          return _artistsViewMode;
        case 1:
          return _albumsViewMode;
        case 2:
          return 'list'; // Tracks always list
        case 3:
          return _playlistsViewMode;
        default:
          return 'list';
      }
    } else {
      // Artists, Albums, Playlists
      switch (tabIndex) {
        case 0:
          return _artistsViewMode;
        case 1:
          return _albumsViewMode;
        case 2:
          return _playlistsViewMode;
        default:
          return 'list';
      }
    }
  }

  void _cycleCurrentViewMode() {
    final tabIndex = _selectedTabIndex.value;

    // Handle books media type
    if (_selectedMediaType == LibraryMediaType.books) {
      switch (tabIndex) {
        case 0:
          _cycleAuthorsViewMode();
          break;
        case 1:
          _cycleAudiobooksViewMode();
          break;
        case 2:
          _cycleSeriesViewMode();
          break;
      }
      return;
    }

    // Handle music media type
    if (_showFavoritesOnly) {
      switch (tabIndex) {
        case 0:
          _cycleArtistsViewMode();
          break;
        case 1:
          _cycleAlbumsViewMode();
          break;
        case 2:
          // Tracks - no view toggle
          break;
        case 3:
          _cyclePlaylistsViewMode();
          break;
      }
    } else {
      switch (tabIndex) {
        case 0:
          _cycleArtistsViewMode();
          break;
        case 1:
          _cycleAlbumsViewMode();
          break;
        case 2:
          _cyclePlaylistsViewMode();
          break;
      }
    }
  }

  void _resetCategoryIndex() {
    // Reset to first category when media type changes
    if (_selectedTabIndex.value >= _tabCount) {
      _selectedTabIndex.value = 0;
      _tabIndexNotifier.value = 0;
    }
    // Jump to the selected category without animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedTabIndex.value);
      }
    });
  }

  void _changeMediaType(LibraryMediaType type) {
    _logger.log('📚 _changeMediaType called: $type (current: $_selectedMediaType)');
    if (_selectedMediaType == type) {
      _logger.log('📚 Same type, skipping');
      return;
    }
    setState(() {
      _selectedMediaType = type;
    });
    _selectedTabIndex.value = 0; // Reset to first category
    _tabIndexNotifier.value = 0;
    _resetCategoryIndex();
    // Load audiobooks when switching to books tab
    if (type == LibraryMediaType.books) {
      _logger.log('📚 Switched to Books, _audiobooks.isEmpty=${_audiobooks.isEmpty}');
      if (_audiobooks.isEmpty) {
        _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null);
      }
      // Load series from Music Assistant
      if (!_seriesLoaded) {
        _loadSeries();
      }
    }
    // Load radio stations when switching to radio tab
    if (type == LibraryMediaType.radio) {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.radioStations.isEmpty) {
        maProvider.loadRadioStations();
      }
    }
  }

  void _onPageChanged(int index) {
    // Update both: RestorableInt for persistence, ValueNotifier for UI
    // No setState needed - ValueListenableBuilder will rebuild only the filter chips
    _selectedTabIndex.value = index;
    _tabIndexNotifier.value = index;
  }

  /// Handle scroll notifications to hide/show filter bars
  bool _handleScrollNotification(ScrollNotification notification) {
    // Don't hide while dragging letter scrollbar
    if (_isLetterScrollbarDragging) {
      return false;
    }

    // Only respond to vertical scroll (not horizontal PageView swipe)
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final currentOffset = notification.metrics.pixels;
      final delta = currentOffset - _lastScrollOffset;

      if (delta.abs() > _scrollThreshold) {
        final shouldShow = delta < 0 || currentOffset <= 0;
        if (shouldShow != _isFilterBarVisible) {
          setState(() {
            _isFilterBarVisible = shouldShow;
          });
        }
        _lastScrollOffset = currentOffset;
      }
    }
    return false;
  }

  void _onLetterScrollbarDragChanged(bool isDragging) {
    setState(() {
      _isLetterScrollbarDragging = isDragging;
      // Show the filter bar when starting to drag
      if (isDragging) {
        _isFilterBarVisible = true;
      }
    });
  }

  void _animateToCategory(int index) {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    // Update both for persistence and UI
    _selectedTabIndex.value = index;
    _tabIndexNotifier.value = index;
  }

  @override
  void dispose() {
    _colorExtractionDebounce?.cancel();
    _pageController.dispose();
    _selectedTabIndex.dispose();
    _tabIndexNotifier.dispose();
    _artistsScrollController.dispose();
    _albumsScrollController.dispose();
    _playlistsScrollController.dispose();
    _authorsScrollController.dispose();
    _audiobooksScrollController.dispose();
    _seriesScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists({bool? favoriteOnly}) async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final playlists = await maProvider.api!.getPlaylists(
        limit: 100,
        favoriteOnly: favoriteOnly,
      );
      if (mounted) {
        // PERF: Pre-sort once on load, not on every build
        final sorted = List<Playlist>.from(playlists)
          ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        setState(() {
          _playlists = playlists;
          _sortedPlaylists = sorted;
          _playlistNames = sorted.map((p) => p.name ?? '').toList();
          _isLoadingPlaylists = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingPlaylists = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteTracks() async {
    if (_isLoadingTracks) return;

    setState(() {
      _isLoadingTracks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final tracks = await maProvider.api!.getTracks(
        limit: 500,
        favoriteOnly: true,
      );
      if (mounted) {
        // PERF: Pre-sort once on load, not on every build
        final sorted = List<Track>.from(tracks)
          ..sort((a, b) {
            final artistCompare = a.artistsString.compareTo(b.artistsString);
            if (artistCompare != 0) return artistCompare;
            return a.name.compareTo(b.name);
          });
        setState(() {
          _favoriteTracks = tracks;
          _sortedFavoriteTracks = sorted;
          _isLoadingTracks = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
        });
      }
    }
  }

  final _logger = DebugLogger();

  Future<void> _loadAudiobooks({bool? favoriteOnly}) async {
    _logger.log('📚 _loadAudiobooks called, favoriteOnly=$favoriteOnly');
    if (_isLoadingAudiobooks) {
      _logger.log('📚 Already loading, skipping');
      return;
    }

    setState(() {
      _isLoadingAudiobooks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      _logger.log('📚 Calling API getAudiobooks...');
      final audiobooks = await maProvider.api!.getAudiobooks(
        limit: 10000,  // Large limit to get all audiobooks
        favoriteOnly: favoriteOnly,
      );
      _logger.log('📚 API returned ${audiobooks.length} audiobooks');
      if (audiobooks.isNotEmpty) {
        _logger.log('📚 First audiobook: ${audiobooks.first.name} by ${audiobooks.first.authorsString}');
      }
      if (mounted) {
        // PERF: Pre-sort and pre-group once on load, not on every build
        final sortedAlpha = List<Audiobook>.from(audiobooks)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // Group audiobooks by author
        final authorMap = <String, List<Audiobook>>{};
        for (final book in audiobooks) {
          final authorName = book.authorsString;
          authorMap.putIfAbsent(authorName, () => []).add(book);
        }
        final sortedAuthors = authorMap.keys.toList()..sort();

        setState(() {
          _audiobooks = audiobooks;
          _sortedAudiobooks = sortedAlpha;
          _audiobookNames = sortedAlpha.map((a) => a.name).toList();
          _groupedAudiobooksByAuthor = authorMap;
          _sortedAuthorNames = sortedAuthors;
          _isLoadingAudiobooks = false;
        });
        _logger.log('📚 State updated, _audiobooks.length = ${_audiobooks.length}');
        // Fetch author images in background
        _fetchAuthorImages(audiobooks);
      }
    } else {
      _logger.log('📚 API is null!');
      if (mounted) {
        setState(() {
          _isLoadingAudiobooks = false;
        });
      }
    }
  }

  Future<void> _fetchAuthorImages(List<Audiobook> audiobooks) async {
    // Get unique author display strings and their primary author for image lookup
    final authorEntries = <String, String>{}; // displayName -> primaryAuthorName
    for (final book in audiobooks) {
      final displayName = book.authorsString;
      if (!authorEntries.containsKey(displayName)) {
        // Use first author's name for image lookup (API search works better with single names)
        final primaryAuthor = book.authors?.isNotEmpty == true
            ? book.authors!.first.name
            : displayName;
        authorEntries[displayName] = primaryAuthor;
      }
    }

    // Fetch images for authors not already cached
    for (final entry in authorEntries.entries) {
      final displayName = entry.key;
      final lookupName = entry.value;
      if (!_authorImages.containsKey(displayName)) {
        // Mark as loading to avoid duplicate requests
        _authorImages[displayName] = null;
        // Fetch in background using primary author name
        MetadataService.getAuthorImageUrl(lookupName).then((imageUrl) {
          if (mounted && imageUrl != null) {
            setState(() {
              _authorImages[displayName] = imageUrl;
            });
          }
        });
      }
    }
  }

  /// Load audiobook series from Music Assistant
  Future<void> _loadSeries() async {
    if (_isLoadingSeries) return;

    setState(() {
      _isLoadingSeries = true;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.api != null) {
        final series = await maProvider.api!.getAudiobookSeries();
        _logger.log('📚 Loaded ${series.length} series');

        if (mounted) {
          // PERF: Pre-sort once on load, not on every build
          final sorted = List<AudiobookSeries>.from(series)
            ..sort((a, b) => a.name.compareTo(b.name));
          setState(() {
            _series = series;
            _sortedSeries = sorted;
            _seriesNames = sorted.map((s) => s.name).toList();
            _isLoadingSeries = false;
            _seriesLoaded = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingSeries = false;
          });
        }
      }
    } catch (e) {
      _logger.log('📚 Error loading series: $e');
      if (mounted) {
        setState(() {
          _isLoadingSeries = false;
        });
      }
    }
  }

  /// Fetch book covers for a series (for 3x3 grid display)
  Future<void> _loadSeriesCovers(String seriesId, MusicAssistantProvider maProvider) async {
    // Already cached or loading
    if (_seriesBookCovers.containsKey(seriesId) || _seriesCoversLoading.contains(seriesId)) {
      return;
    }

    _seriesCoversLoading.add(seriesId);

    try {
      if (maProvider.api != null) {
        final books = await maProvider.api!.getSeriesAudiobooks(seriesId);
        final covers = <String>[];

        for (final book in books.take(9)) {
          final imageUrl = maProvider.getImageUrl(book);
          if (imageUrl != null) {
            covers.add(imageUrl);
          }
        }

        if (mounted) {
          setState(() {
            _seriesBookCovers[seriesId] = covers;
            _seriesBookCounts[seriesId] = books.length;
            _seriesCoversLoading.remove(seriesId);
          });

          // PERF: Queue color extraction with debounce to avoid blocking UI during scroll
          _queueColorExtraction(seriesId, covers);
        }
      }
    } catch (e) {
      _logger.log('📚 Error loading series covers for $seriesId: $e');
      _seriesCoversLoading.remove(seriesId);
    }
  }

  /// PERF: Queue color extraction requests - processed after scroll settles
  void _queueColorExtraction(String seriesId, List<String> coverUrls) {
    if (coverUrls.isEmpty) return;

    // Add to pending queue
    _pendingColorExtractions[seriesId] = coverUrls;

    // Cancel existing timer and start a new one
    _colorExtractionDebounce?.cancel();
    _colorExtractionDebounce = Timer(const Duration(milliseconds: 300), () {
      _processQueuedColorExtractions();
    });
  }

  /// PERF: Process all queued color extractions in batch after scroll settles
  Future<void> _processQueuedColorExtractions() async {
    if (_pendingColorExtractions.isEmpty || !mounted) return;

    // Copy and clear the queue to avoid processing new items added during extraction
    final toProcess = Map<String, List<String>>.from(_pendingColorExtractions);
    _pendingColorExtractions.clear();

    // Process each series sequentially to avoid overwhelming the UI thread
    for (final entry in toProcess.entries) {
      if (!mounted) break;
      await _extractSeriesColors(entry.key, entry.value);
      // Small yield between extractions to keep UI responsive
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Extract dominant colors from series book covers for empty cell backgrounds
  Future<void> _extractSeriesColors(String seriesId, List<String> coverUrls) async {
    if (coverUrls.isEmpty || !mounted) return;

    final extractedColors = <Color>[];

    // Extract colors from first few covers (limit to avoid too much processing)
    for (final url in coverUrls.take(4)) {
      if (!mounted) break;
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(url),
          maximumColorCount: 8,
        );

        // Get dark muted colors for grid squares (matches the aesthetic)
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
        _logger.log('📚 Error extracting colors from $url: $e');
      }
    }

    if (extractedColors.isNotEmpty && mounted) {
      setState(() {
        _seriesExtractedColors[seriesId] = extractedColors;
      });
    }
  }

  void _toggleFavoritesMode(bool value) {
    setState(() {
      _showFavoritesOnly = value;
    });
    _resetCategoryIndex();
    if (value) {
      _loadPlaylists(favoriteOnly: true);
      _loadFavoriteTracks();
    } else {
      _loadPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context)!;

    // Use Selector for targeted rebuilds - only rebuild when connection state changes
    return Selector<MusicAssistantProvider, bool>(
      selector: (_, provider) => provider.isConnected,
      builder: (context, isConnected, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final syncService = SyncService.instance;

        // Show cached data even when not connected (if we have cache)
        // Only show disconnected state if we have no cached data at all
        if (!isConnected && !syncService.hasCache) {
          return Scaffold(
            backgroundColor: colorScheme.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(
                l10n.library,
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w300,
                ),
              ),
              centerTitle: true,
            ),
            body: DisconnectedState.withSettingsAction(
              context: context,
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.background,
          body: SafeArea(
            child: Column(
              children: [
                // Two-row filter: Row 1 = Media types (hides on scroll), Row 2 = Sub-categories (always visible)
                _buildFilterRows(colorScheme, l10n, showLibraryTypeRow: _isFilterBarVisible),
                // Connecting banner when showing cached data
                // Hide when we have cached players - UI is functional during background reconnect
                if (!isConnected && syncService.hasCache && !context.read<MusicAssistantProvider>().hasCachedPlayers)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.connecting,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      // Main scrollable content
                      NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: _onPageChanged,
                          children: _buildTabViews(context, l10n),
                        ),
                      ),
                      // Fade gradient at top - content fades as it scrolls under filter bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 24,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colorScheme.background,
                                  colorScheme.background.withOpacity(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ FILTER ROWS ============
  // Consistent height for filter rows
  static const double _filterRowHeight = 36.0;

  Widget _buildFilterRows(ColorScheme colorScheme, S l10n, {required bool showLibraryTypeRow}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Media type chips (hides when scrolling)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: showLibraryTypeRow ? _filterRowHeight : 0,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildMediaTypeChips(colorScheme, l10n),
          ),
        ),
        if (showLibraryTypeRow) const SizedBox(height: 12), // Space between rows
        // Row 2: Sub-category chips (left) + action buttons (right) - always visible
        SizedBox(
          height: _filterRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: category chips - wrapped in ValueListenableBuilder for efficient rebuilds
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _tabIndexNotifier,
                      builder: (context, selectedIndex, _) {
                        return _buildCategoryChips(colorScheme, l10n, selectedIndex);
                      },
                    ),
                  ),
                ),
                // Right: action buttons
                _buildInlineActionButtons(colorScheme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTypeChips(ColorScheme colorScheme, S l10n) {
    String getMediaTypeLabel(LibraryMediaType type) {
      switch (type) {
        case LibraryMediaType.music:
          return l10n.music;
        case LibraryMediaType.books:
          return l10n.audiobooks;
        case LibraryMediaType.podcasts:
          return l10n.podcasts;
        case LibraryMediaType.radio:
          return l10n.radio;
      }
    }

    IconData getMediaTypeIcon(LibraryMediaType type) {
      switch (type) {
        case LibraryMediaType.music:
          return MdiIcons.musicNote;
        case LibraryMediaType.books:
          return MdiIcons.bookOpenPageVariant;
        case LibraryMediaType.podcasts:
          return MdiIcons.podcast;
        case LibraryMediaType.radio:
          return MdiIcons.radio;
      }
    }

    // Justify chips across full width
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: LibraryMediaType.values.map((type) {
        final isSelected = _selectedMediaType == type;
        return FilterChip(
          selected: isSelected,
          showCheckmark: false,
          // Only show icon when selected
          avatar: isSelected
              ? Icon(
                  getMediaTypeIcon(type),
                  size: 18,
                  color: colorScheme.onTertiaryContainer,
                )
              : null,
          label: Text(getMediaTypeLabel(type)),
          labelStyle: TextStyle(
            color: isSelected
                ? colorScheme.onTertiaryContainer
                : colorScheme.onSurface.withOpacity(0.7),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
          backgroundColor: colorScheme.surfaceVariant.withOpacity(0.5),
          selectedColor: colorScheme.tertiaryContainer,
          side: BorderSide.none,
          onSelected: (_) => _changeMediaType(type),
        );
      }).toList(),
    );
  }

  // Inline action buttons for favorites and view mode (right side of row 2)
  Widget _buildInlineActionButtons(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        // Favorites toggle (only for music and books)
        if (_selectedMediaType == LibraryMediaType.music || _selectedMediaType == LibraryMediaType.books)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: _showFavoritesOnly ? Colors.red : colorScheme.surface,
                elevation: 2,
                shadowColor: Colors.black26,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _toggleFavoritesMode(!_showFavoritesOnly),
                  customBorder: const CircleBorder(),
                  child: Icon(
                    _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: _showFavoritesOnly ? Colors.white : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        // View mode toggle
        SizedBox(
          width: 36,
          height: 36,
          child: Material(
            color: colorScheme.surface,
            elevation: 2,
            shadowColor: Colors.black26,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _cycleCurrentViewMode,
              customBorder: const CircleBorder(),
              child: Icon(
                _getViewModeIcon(_getCurrentViewMode()),
                size: 18,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChips(ColorScheme colorScheme, S l10n, int selectedIndex) {
    final categories = _getCategoryLabels(l10n);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: categories.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = selectedIndex == index;

          return Material(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceVariant.withOpacity(0.6),
            child: InkWell(
              onTap: () => _animateToCategory(index),
              child: Container(
                height: _filterRowHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<String> _getCategoryLabels(S l10n) {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return [
          l10n.artists,
          l10n.albums,
          if (_showFavoritesOnly) l10n.tracks,
          l10n.playlists,
        ];
      case LibraryMediaType.books:
        return [
          l10n.authors,
          l10n.books,
          l10n.series,
        ];
      case LibraryMediaType.podcasts:
        return [l10n.shows];
      case LibraryMediaType.radio:
        return [l10n.stations];
    }
  }

  // ============ PAGE VIEWS ============
  List<Widget> _buildTabViews(BuildContext context, S l10n) {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return [
          _buildArtistsTab(context, l10n),
          _buildAlbumsTab(context, l10n),
          if (_showFavoritesOnly) _buildTracksTab(context, l10n),
          _buildPlaylistsTab(context, l10n),
        ];
      case LibraryMediaType.books:
        return [
          _buildBooksAuthorsTab(context, l10n),
          _buildAllBooksTab(context, l10n),
          _buildSeriesTab(context, l10n),
        ];
      case LibraryMediaType.podcasts:
        return [
          _buildPodcastsComingSoonTab(context, l10n),
        ];
      case LibraryMediaType.radio:
        return [
          _buildRadioStationsTab(context, l10n),
        ];
    }
  }

  // ============ BOOKS TABS ============
  Widget _buildBooksAuthorsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingAudiobooks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    final audiobooks = _showFavoritesOnly
        ? _audiobooks.where((a) => a.favorite == true).toList()
        : _audiobooks;

    if (audiobooks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoriteAudiobooks,
          subtitle: l10n.tapHeartAudiobook,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.bookOutline,
        title: l10n.noAudiobooks,
        subtitle: l10n.addAudiobooksHint,
        onRefresh: () => _loadAudiobooks(),
      );
    }

    // PERF: Use pre-sorted and pre-grouped lists (computed once on load)
    // Match music artists tab layout - no header, direct list/grid
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null),
      child: LetterScrollbar(
        controller: _authorsScrollController,
        items: _sortedAuthorNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        child: _authorsViewMode == 'list'
            ? ListView.builder(
                controller: _authorsScrollController,
                key: const PageStorageKey<String>('books_authors_list'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: _sortedAuthorNames.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  final authorName = _sortedAuthorNames[index];
                  return _buildAuthorListTile(authorName, _groupedAudiobooksByAuthor[authorName]!, l10n);
                },
              )
            : GridView.builder(
                controller: _authorsScrollController,
                key: const PageStorageKey<String>('books_authors_grid'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _authorsViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _authorsViewMode == 'grid3' ? 0.75 : 0.80, // Match music artists
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _sortedAuthorNames.length,
                itemBuilder: (context, index) {
                  final authorName = _sortedAuthorNames[index];
                  return _buildAuthorCard(authorName, _groupedAudiobooksByAuthor[authorName]!, l10n);
                },
              ),
      ),
    );
  }

  Widget _buildAuthorListTile(String authorName, List<Audiobook> books, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authorImageUrl = _authorImages[authorName];
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.authorImage + authorName + '_library$heroSuffix',
        child: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          radius: 24,
          child: authorImageUrl != null
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: authorImageUrl,
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, __) => Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    errorWidget: (_, __, ___) => Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                )
              : Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
        ),
      ),
      title: Text(
        authorName,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${books.length} ${books.length == 1 ? l10n.audiobookSingular : l10n.audiobooks}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      onTap: () => _navigateToAuthor(authorName, books, heroTagSuffix: 'library$heroSuffix', initialAuthorImageUrl: authorImageUrl),
    );
  }

  Widget _buildAuthorCard(String authorName, List<Audiobook> books, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authorImageUrl = _authorImages[authorName];
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    // Match music artist card layout
    return GestureDetector(
      onTap: () => _navigateToAuthor(authorName, books, heroTagSuffix: 'library$heroSuffix', initialAuthorImageUrl: authorImageUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use LayoutBuilder to ensure proper circle (like music artists)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use the smaller dimension to ensure a circle
                final size = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                return Center(
                  child: Hero(
                    tag: HeroTags.authorImage + authorName + '_library$heroSuffix',
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: authorImageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: authorImageUrl,
                                fit: BoxFit.cover,
                                width: size,
                                height: size,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) => Center(
                                  child: Text(
                                    authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: _authorsViewMode == 'grid3' ? 28 : 36,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                    authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: _authorsViewMode == 'grid3' ? 28 : 36,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                    fontSize: _authorsViewMode == 'grid3' ? 28 : 36,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            authorName,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _navigateToAuthor(String authorName, List<Audiobook> books, {String? heroTagSuffix, String? initialAuthorImageUrl}) {
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookAuthorScreen(
          authorName: authorName,
          audiobooks: books,
          heroTagSuffix: heroTagSuffix,
          initialAuthorImageUrl: initialAuthorImageUrl,
        ),
      ),
    );
  }

  Widget _buildAudiobookListTile(BuildContext context, Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_library$heroSuffix',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SizedBox(),
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
        ),
      ),
      title: Hero(
        tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_library$heroSuffix',
        child: Material(
          color: Colors.transparent,
          child: Text(
            book.name,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      subtitle: Text(
        book.authorsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: book.progress > 0
          ? SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: book.progress,
                strokeWidth: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            )
          : null,
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: 'library$heroSuffix', initialImageUrl: imageUrl),
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

  Widget _buildAllBooksTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();

    if (_isLoadingAudiobooks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    var audiobooks = _showFavoritesOnly
        ? _audiobooks.where((a) => a.favorite == true).toList()
        : List<Audiobook>.from(_audiobooks);

    if (audiobooks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoriteAudiobooks,
          subtitle: l10n.tapHeartAudiobook,
        );
      }
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.bookOutline,
        title: l10n.noAudiobooks,
        subtitle: l10n.addAudiobooksHint,
        onRefresh: () => _loadAudiobooks(),
      );
    }

    // PERF: Use pre-sorted list (sorted once on load or when sort order changes)
    // Match music albums tab layout - no header, direct list/grid
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null),
      child: LetterScrollbar(
        controller: _audiobooksScrollController,
        items: _audiobookNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        child: _audiobooksViewMode == 'list'
            ? ListView.builder(
                controller: _audiobooksScrollController,
                key: PageStorageKey<String>('all_books_list_${_showFavoritesOnly ? 'fav' : 'all'}'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: _sortedAudiobooks.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  return _buildAudiobookListTile(context, _sortedAudiobooks[index], maProvider);
                },
              )
            : GridView.builder(
                controller: _audiobooksScrollController,
                key: PageStorageKey<String>('all_books_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_audiobooksViewMode'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _audiobooksViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _audiobooksViewMode == 'grid3' ? 0.70 : 0.75, // Match music albums
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _sortedAudiobooks.length,
                itemBuilder: (context, index) {
                  return _buildAudiobookCard(context, _sortedAudiobooks[index], maProvider);
                },
              ),
      ),
    );
  }

  Widget _buildAudiobookCard(BuildContext context, Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return GestureDetector(
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: 'library$heroSuffix', initialImageUrl: imageUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square artwork with progress inside
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_library$heroSuffix',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: colorScheme.surfaceVariant,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) => const SizedBox(),
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
                // Progress indicator overlay inside artwork
                if (book.progress > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: book.progress,
                        backgroundColor: Colors.black38,
                        color: colorScheme.primary,
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_library$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                book.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 2),
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

  Widget _buildSeriesTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();

    // Loading state
    if (_isLoadingSeries) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loading,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Empty state
    if (_series.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSeries,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.collections_bookmark_rounded,
                        size: 64,
                        color: colorScheme.primary.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noSeriesFound,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _seriesLoaded
                            ? l10n.noSeriesAvailable
                            : l10n.pullToLoadSeries,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.tonal(
                        onPressed: _loadSeries,
                        child: Text(l10n.loadSeries),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // PERF: Use pre-sorted list (sorted once on load)
    // Series view - supports grid2, grid3, and list modes
    return RefreshIndicator(
      onRefresh: _loadSeries,
      child: LetterScrollbar(
        controller: _seriesScrollController,
        items: _seriesNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        child: _seriesViewMode == 'list'
            ? ListView.builder(
                controller: _seriesScrollController,
                key: const PageStorageKey<String>('series_list'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: _sortedSeries.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.withMiniPlayer),
                itemBuilder: (context, index) {
                  return _buildSeriesListTile(context, _sortedSeries[index], maProvider, l10n);
                },
              )
            : GridView.builder(
                controller: _seriesScrollController,
                key: PageStorageKey<String>('series_grid_$_seriesViewMode'),
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.withMiniPlayer),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _seriesViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _seriesViewMode == 'grid3' ? 0.70 : 0.75,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _sortedSeries.length,
                itemBuilder: (context, index) {
                  final series = _sortedSeries[index];
                  return _buildSeriesCard(context, series, maProvider, l10n, maxCoverGridSize: _seriesViewMode == 'grid3' ? 2 : 3);
                },
              ),
      ),
    );
  }

  Widget _buildSeriesListTile(BuildContext context, AudiobookSeries series, MusicAssistantProvider maProvider, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Trigger loading of series covers if not cached
    if (!_seriesBookCovers.containsKey(series.id) && !_seriesCoversLoading.contains(series.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSeriesCovers(series.id, maProvider);
      });
    }

    final covers = _seriesBookCovers[series.id];
    final firstCover = covers != null && covers.isNotEmpty ? covers.first : null;
    final heroTag = 'series_cover_${series.id}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: firstCover != null
                ? CachedNetworkImage(
                    imageUrl: firstCover,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Icon(
                      Icons.collections_bookmark_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    errorWidget: (_, __, ___) => Icon(
                      Icons.collections_bookmark_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    Icons.collections_bookmark_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
      title: Text(
        series.name,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Builder(
        builder: (context) {
          final count = series.bookCount ?? _seriesBookCounts[series.id];
          if (count == null) return const SizedBox.shrink();
          return Text(
            '$count ${count == 1 ? l10n.book : l10n.books}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          );
        },
      ),
      onTap: () {
        _logger.log('📚 Tapped series: ${series.name}, path: ${series.id}');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AudiobookSeriesScreen(
              series: series,
              heroTag: heroTag,
              initialCovers: covers,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeriesCard(BuildContext context, AudiobookSeries series, MusicAssistantProvider maProvider, S l10n, {int maxCoverGridSize = 3}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Trigger loading of series covers if not cached
    if (!_seriesBookCovers.containsKey(series.id) && !_seriesCoversLoading.contains(series.id)) {
      // Use addPostFrameCallback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSeriesCovers(series.id, maProvider);
      });
    }

    // Matches books tab style - square artwork with text below
    final heroTag = 'series_cover_${series.id}';
    final cachedCovers = _seriesBookCovers[series.id];
    return GestureDetector(
      onTap: () {
        _logger.log('📚 Tapped series: ${series.name}, path: ${series.id}');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AudiobookSeriesScreen(
              series: series,
              heroTag: heroTag,
              initialCovers: cachedCovers,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square cover grid with Hero animation
          Hero(
            tag: heroTag,
            child: AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: colorScheme.surfaceVariant,
                  child: _buildSeriesCoverGrid(series, colorScheme, maProvider, maxGridSize: maxCoverGridSize),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.name,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Builder(
            builder: (context) {
              final count = series.bookCount ?? _seriesBookCounts[series.id];
              if (count == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$count ${count == 1 ? l10n.book : l10n.books}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesCoverGrid(AudiobookSeries series, ColorScheme colorScheme, MusicAssistantProvider maProvider, {int maxGridSize = 3}) {
    final covers = _seriesBookCovers[series.id];
    final isLoading = _seriesCoversLoading.contains(series.id);

    // If we have covers, show the grid
    if (covers != null && covers.isNotEmpty) {
      // Determine grid size based on number of covers
      // 1 cover = 1x1, 2-4 covers = 2x2, 5+ covers = 3x3
      int gridSize;
      if (covers.length == 1) {
        gridSize = 1;
      } else if (covers.length <= 4) {
        gridSize = 2;
      } else {
        gridSize = 3;
      }
      // Respect maxGridSize parameter (for smaller displays like 3-column grid)
      gridSize = gridSize.clamp(1, maxGridSize);
      final displayCovers = covers.take(gridSize * gridSize).toList();

      // Use extracted colors from book covers if available, otherwise fall back to static palette
      final extractedColors = _seriesExtractedColors[series.id];
      const fallbackColors = [
        Color(0xFF2D3436), // Dark slate
        Color(0xFF34495E), // Dark blue-grey
        Color(0xFF4A3728), // Dark brown
        Color(0xFF2C3E50), // Midnight blue
        Color(0xFF3D3D3D), // Charcoal
        Color(0xFF4A4458), // Dark purple-grey
        Color(0xFF3E4A47), // Dark teal-grey
        Color(0xFF4A3F35), // Dark warm grey
      ];
      final emptyColors = (extractedColors != null && extractedColors.isNotEmpty)
          ? extractedColors
          : fallbackColors;

      // Use series ID to pick consistent colors for this series
      final colorSeed = series.id.hashCode;

      // Use simple Column/Row layout instead of GridView to avoid scroll-related animations
      // No margins between cells for seamless appearance
      return Column(
        children: List.generate(gridSize, (row) {
          return Expanded(
            child: Row(
              children: List.generate(gridSize, (col) {
                final index = row * gridSize + col;
                if (index >= displayCovers.length) {
                  // Empty cell - use nested grid pattern
                  return Expanded(
                    child: _buildEmptyCell(colorSeed, index, emptyColors),
                  );
                }
                return Expanded(
                  child: CachedNetworkImage(
                    imageUrl: displayCovers[index],
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
                  ),
                );
              }),
            ),
          );
        }),
      );
    }

    // Show loading shimmer or placeholder
    if (isLoading) {
      return _buildSeriesLoadingGrid(colorScheme);
    }

    // Fallback placeholder
    return _buildSeriesPlaceholder(colorScheme);
  }

  Widget _buildSeriesLoadingGrid(ColorScheme colorScheme) {
    // Static placeholder grid using Column/Row - no animations, no grid lines
    return Container(
      color: colorScheme.surfaceContainerHighest,
    );
  }

  Widget _buildSeriesPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.collections_bookmark_rounded,
        size: 48,
        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
      ),
    );
  }

  /// Builds an empty cell with either a solid color or a nested grid
  /// The pattern is deterministic based on series ID and cell index
  Widget _buildEmptyCell(int colorSeed, int cellIndex, List<Color> emptyColors) {
    // Tone down colors - reduce saturation and darken
    final colors = emptyColors.map((c) {
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

  // ============ PODCASTS TAB (Placeholder) ============
  Widget _buildPodcastsComingSoonTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.podcasts_rounded,
            size: 64,
            color: colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.podcasts,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.podcastSupportComingSoon,
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ============ RADIO TAB ============
  Widget _buildRadioStationsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.watch<MusicAssistantProvider>();
    final radioStations = maProvider.radioStations;
    final isLoading = maProvider.isLoadingRadio;

    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (radioStations.isEmpty) {
      return EmptyState.custom(
        context: context,
        icon: MdiIcons.radio,
        title: l10n.noRadioStations,
        subtitle: l10n.addRadioStationsHint,
        onRefresh: () => maProvider.loadRadioStations(),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: BottomSpacing.withMiniPlayer),
      itemCount: radioStations.length,
      itemBuilder: (context, index) {
        final station = radioStations[index];
        final imageUrl = maProvider.getImageUrl(station, size: 256);

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 56,
                      height: 56,
                      color: colorScheme.surfaceVariant,
                      child: Icon(MdiIcons.radio, color: colorScheme.onSurfaceVariant),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 56,
                      height: 56,
                      color: colorScheme.surfaceVariant,
                      child: Icon(MdiIcons.radio, color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : Container(
                    width: 56,
                    height: 56,
                    color: colorScheme.surfaceVariant,
                    child: Icon(MdiIcons.radio, color: colorScheme.onSurfaceVariant),
                  ),
          ),
          title: Text(
            station.name,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: station.metadata?['description'] != null
              ? Text(
                  station.metadata!['description'] as String,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () {
            final selectedPlayer = maProvider.selectedPlayer;
            if (selectedPlayer != null) {
              maProvider.api?.playRadioStation(selectedPlayer.playerId, station);
            }
          },
        );
      },
    );
  }

  // ============ ARTISTS TAB ============
  Widget _buildArtistsTab(BuildContext context, S l10n) {
    // Use Selector for targeted rebuilds - only rebuild when artists or loading state changes
    return Selector<MusicAssistantProvider, (List<Artist>, bool)>(
      selector: (_, provider) => (provider.artists, provider.isLoading),
      builder: (context, data, _) {
        final (allArtists, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final artists = _showFavoritesOnly
            ? allArtists.where((a) => a.favorite == true).toList()
            : allArtists;

        if (artists.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              context: context,
              icon: Icons.favorite_border,
              title: l10n.noFavoriteArtists,
              subtitle: l10n.tapHeartArtist,
            );
          }
          return EmptyState.artists(
            context: context,
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        // Sort artists alphabetically for letter scrollbar
        final sortedArtists = List<Artist>.from(artists)
          ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        final artistNames = sortedArtists.map((a) => a.name ?? '').toList();

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: LetterScrollbar(
            controller: _artistsScrollController,
            items: artistNames,
            onDragStateChanged: _onLetterScrollbarDragChanged,
            child: _artistsViewMode == 'list'
                ? ListView.builder(
                    controller: _artistsScrollController,
                    key: PageStorageKey<String>('library_artists_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_artistsViewMode'),
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemCount: sortedArtists.length,
                    padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.navBarOnly),
                    itemBuilder: (context, index) {
                      final artist = sortedArtists[index];
                      return _buildArtistTile(
                        context,
                        artist,
                        key: ValueKey(artist.uri ?? artist.itemId),
                      );
                    },
                  )
                : GridView.builder(
                    controller: _artistsScrollController,
                    key: PageStorageKey<String>('library_artists_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_artistsViewMode'),
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _artistsViewMode == 'grid3' ? 3 : 2,
                      childAspectRatio: _artistsViewMode == 'grid3' ? 0.75 : 0.80,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: sortedArtists.length,
                    itemBuilder: (context, index) {
                      final artist = sortedArtists[index];
                      return _buildArtistGridCard(context, artist);
                    },
                  ),
          ),
        );
      },
    );
  }

  Widget _buildArtistTile(
    BuildContext context,
    Artist artist, {
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final suffix = '_library';
    // Get image URL for hero animation
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: ArtistAvatar(
          artist: artist,
          radius: 24,
          imageSize: 128,
          heroTag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
        ),
      title: Hero(
        tag: HeroTags.artistName + (artist.uri ?? artist.itemId) + suffix,
        child: Material(
          color: Colors.transparent,
          child: Text(
            artist.name,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
        onTap: () {
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: 'library',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistGridCard(BuildContext context, Artist artist) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: ArtistDetailsScreen(
              artist: artist,
              heroTagSuffix: 'library_grid',
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use LayoutBuilder to get available width for proper circle sizing
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use the smaller dimension to ensure a circle
                final size = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                return Center(
                  child: ArtistAvatar(
                    artist: artist,
                    radius: size / 2,
                    imageSize: 256,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            artist.name,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ============ ALBUMS TAB ============
  Widget _buildAlbumsTab(BuildContext context, S l10n) {
    // Use Selector for targeted rebuilds - only rebuild when albums or loading state changes
    return Selector<MusicAssistantProvider, (List<Album>, bool)>(
      selector: (_, provider) => (provider.albums, provider.isLoading),
      builder: (context, data, _) {
        final (allAlbums, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final albums = _showFavoritesOnly
            ? allAlbums.where((a) => a.favorite == true).toList()
            : allAlbums;

        if (albums.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              context: context,
              icon: Icons.favorite_border,
              title: l10n.noFavoriteAlbums,
              subtitle: l10n.tapHeartAlbum,
            );
          }
          return EmptyState.albums(
            context: context,
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        // Sort albums alphabetically for letter scrollbar
        final sortedAlbums = List<Album>.from(albums)
          ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        final albumNames = sortedAlbums.map((a) => a.name ?? '').toList();

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: LetterScrollbar(
            controller: _albumsScrollController,
            items: albumNames,
            onDragStateChanged: _onLetterScrollbarDragChanged,
            child: _albumsViewMode == 'list'
                ? ListView.builder(
                    controller: _albumsScrollController,
                    key: PageStorageKey<String>('library_albums_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_albumsViewMode'),
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.navBarOnly),
                    itemCount: sortedAlbums.length,
                    itemBuilder: (context, index) {
                      final album = sortedAlbums[index];
                      return _buildAlbumListTile(context, album);
                    },
                  )
                : GridView.builder(
                    controller: _albumsScrollController,
                    key: PageStorageKey<String>('library_albums_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_albumsViewMode'),
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _albumsViewMode == 'grid3' ? 3 : 2,
                      childAspectRatio: _albumsViewMode == 'grid3' ? 0.70 : 0.75,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: sortedAlbums.length,
                    itemBuilder: (context, index) {
                      final album = sortedAlbums[index];
                      return AlbumCard(
                        key: ValueKey(album.uri ?? album.itemId),
                        album: album,
                        heroTagSuffix: 'library_grid',
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumListTile(BuildContext context, Album album) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          height: 56,
          color: colorScheme.surfaceVariant,
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(),
                  errorWidget: (_, __, ___) => Icon(
                    Icons.album_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : Icon(
                  Icons.album_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
        ),
      ),
      title: Text(
        album.nameWithYear,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artistsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        updateAdaptiveColorsFromImage(context, imageUrl);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AlbumDetailsScreen(
              album: album,
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
    );
  }

  // ============ PLAYLISTS TAB ============
  Widget _buildPlaylistsTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingPlaylists) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_playlists.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          context: context,
          icon: Icons.favorite_border,
          title: l10n.noFavoritePlaylists,
          subtitle: l10n.tapHeartPlaylist,
        );
      }
      return EmptyState.playlists(context: context, onRefresh: () => _loadPlaylists());
    }

    // PERF: Use pre-sorted lists (sorted once on load)
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadPlaylists(favoriteOnly: _showFavoritesOnly ? true : null),
      child: LetterScrollbar(
        controller: _playlistsScrollController,
        items: _playlistNames,
        onDragStateChanged: _onLetterScrollbarDragChanged,
        child: _playlistsViewMode == 'list'
            ? ListView.builder(
                controller: _playlistsScrollController,
                key: PageStorageKey<String>('library_playlists_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_playlistsViewMode'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: _sortedPlaylists.length,
                padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.navBarOnly),
                itemBuilder: (context, index) {
                  final playlist = _sortedPlaylists[index];
                  return _buildPlaylistTile(context, playlist, l10n);
                },
              )
            : GridView.builder(
                controller: _playlistsScrollController,
                key: PageStorageKey<String>('library_playlists_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_playlistsViewMode'),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _playlistsViewMode == 'grid3' ? 3 : 2,
                  childAspectRatio: _playlistsViewMode == 'grid3' ? 0.75 : 0.80,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _sortedPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = _sortedPlaylists[index];
                  return _buildPlaylistGridCard(context, playlist, l10n);
                },
              ),
      ),
    );
  }

  Widget _buildPlaylistTile(BuildContext context, Playlist playlist, S l10n) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(playlist.itemId),
        leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(image: CachedNetworkImageProvider(imageUrl), fit: BoxFit.cover)
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.playlist_play_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        playlist.name,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        playlist.trackCount != null
            ? '${playlist.trackCount} ${l10n.tracks}'
            : playlist.owner ?? l10n.playlist,
        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
        trailing: playlist.favorite == true
            ? const Icon(Icons.favorite, color: Colors.red, size: 20)
            : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaylistDetailsScreen(
                playlist: playlist,
                provider: playlist.provider,
                itemId: playlist.itemId,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistGridCard(BuildContext context, Playlist playlist, S l10n) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaylistDetailsScreen(
              playlist: playlist,
              provider: playlist.provider,
              itemId: playlist.itemId,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: colorScheme.surfaceVariant,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) => const SizedBox(),
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(
                            Icons.playlist_play_rounded,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.playlist_play_rounded,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            playlist.trackCount != null
                ? '${playlist.trackCount} ${l10n.tracks}'
                : playlist.owner ?? l10n.playlist,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ============ TRACKS TAB (favorites only) ============
  Widget _buildTracksTab(BuildContext context, S l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingTracks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_favoriteTracks.isEmpty) {
      return EmptyState.custom(
        context: context,
        icon: Icons.favorite_border,
        title: l10n.noFavoriteTracks,
        subtitle: l10n.longPressTrackHint,
      );
    }

    // PERF: Use pre-sorted list (sorted once on load)
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: _loadFavoriteTracks,
      child: ListView.builder(
        key: const PageStorageKey<String>('library_tracks_list'),
        cacheExtent: 500,
        addAutomaticKeepAlives: false, // Tiles don't need individual keep-alive
        addRepaintBoundaries: false, // We add RepaintBoundary manually to tiles
        padding: EdgeInsets.only(left: 8, right: 8, top: 16, bottom: BottomSpacing.navBarOnly),
        itemCount: _sortedFavoriteTracks.length,
        itemBuilder: (context, index) {
          final track = _sortedFavoriteTracks[index];
          return _buildTrackTile(context, track);
        },
      ),
    );
  }

  Widget _buildTrackTile(BuildContext context, Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get image URL from track itself
    final imageUrl = maProvider.api?.getImageUrl(track, size: 128);

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(track.uri ?? track.itemId),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          image: imageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 24)
            : null,
      ),
      title: Text(
        track.artistsString,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.name,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.favorite,
        color: Colors.red,
        size: 20,
      ),
      onTap: () async {
        final player = maProvider.selectedPlayer;
        if (player == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
          );
          return;
        }

        try {
          // Start radio from this track
          await maProvider.api?.playRadio(player.playerId, track);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start radio: $e')),
            );
          }
        }
      },
      ),
    );
  }
}
