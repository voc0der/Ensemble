import 'dart:convert';
import 'package:http/http.dart' as http;
import 'debug_logger.dart';
import 'settings_service.dart';

class MetadataService {
  static final _logger = DebugLogger();
  // Cache to avoid repeated API calls for the same artist/album
  static final Map<String, String> _cache = {};

  // Cache for artist images
  static final Map<String, String?> _artistImageCache = {};

  /// Fetches artist biography/description with fallback chain:
  /// 1. Music Assistant metadata (passed in)
  /// 2. Last.fm API (if key configured)
  /// 3. TheAudioDB API (if key configured)
  static Future<String?> getArtistDescription(
    String artistName,
    Map<String, dynamic>? musicAssistantMetadata,
  ) async {
    // Try Music Assistant metadata first
    if (musicAssistantMetadata != null) {
      final maDescription = musicAssistantMetadata['description'] ??
          musicAssistantMetadata['biography'] ??
          musicAssistantMetadata['wiki'] ??
          musicAssistantMetadata['bio'] ??
          musicAssistantMetadata['summary'];

      if (maDescription != null && (maDescription as String).trim().isNotEmpty) {
        return maDescription;
      }
    }

    // Check cache
    final cacheKey = 'artist:$artistName';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Try Last.fm API
    final lastFmKey = await SettingsService.getLastFmApiKey();
    if (lastFmKey != null && lastFmKey.isNotEmpty) {
      final lastFmDesc = await _fetchFromLastFm(artistName, null, lastFmKey);
      if (lastFmDesc != null) {
        _cache[cacheKey] = lastFmDesc;
        return lastFmDesc;
      }
    }

    // Try TheAudioDB API
    final audioDbKey = await SettingsService.getTheAudioDbApiKey();
    if (audioDbKey != null && audioDbKey.isNotEmpty) {
      final audioDbDesc = await _fetchFromTheAudioDb(artistName, audioDbKey);
      if (audioDbDesc != null) {
        _cache[cacheKey] = audioDbDesc;
        return audioDbDesc;
      }
    }

    return null;
  }

  /// Fetches album description with fallback chain:
  /// 1. Music Assistant metadata (passed in)
  /// 2. Last.fm API (if key configured)
  static Future<String?> getAlbumDescription(
    String artistName,
    String albumName,
    Map<String, dynamic>? musicAssistantMetadata,
  ) async {
    // Try Music Assistant metadata first
    if (musicAssistantMetadata != null) {
      final maDescription = musicAssistantMetadata['description'] ??
          musicAssistantMetadata['wiki'] ??
          musicAssistantMetadata['biography'] ??
          musicAssistantMetadata['summary'];

      if (maDescription != null && (maDescription as String).trim().isNotEmpty) {
        return maDescription;
      }
    }

    // Check cache
    final cacheKey = 'album:$artistName:$albumName';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Try Last.fm API (TheAudioDB doesn't have good album info)
    final lastFmKey = await SettingsService.getLastFmApiKey();
    if (lastFmKey != null && lastFmKey.isNotEmpty) {
      final lastFmDesc = await _fetchFromLastFm(artistName, albumName, lastFmKey);
      if (lastFmDesc != null) {
        _cache[cacheKey] = lastFmDesc;
        return lastFmDesc;
      }
    }

    return null;
  }

  static Future<String?> _fetchFromLastFm(
    String artistName,
    String? albumName,
    String apiKey,
  ) async {
    try {
      final String method;
      final Map<String, String> params = {
        'api_key': apiKey,
        'format': 'json',
      };

      if (albumName != null) {
        // Album info
        method = 'album.getinfo';
        params['artist'] = artistName;
        params['album'] = albumName;
      } else {
        // Artist info
        method = 'artist.getinfo';
        params['artist'] = artistName;
      }

      params['method'] = method;

      final uri = Uri.https('ws.audioscrobbler.com', '/2.0/', params);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (albumName != null) {
          // Parse album response
          final album = data['album'];
          if (album != null) {
            final wiki = album['wiki'];
            if (wiki != null) {
              // Prefer summary, fall back to content
              return _cleanLastFmText(wiki['summary'] ?? wiki['content']);
            }
          }
        } else {
          // Parse artist response
          final artist = data['artist'];
          if (artist != null) {
            final bio = artist['bio'];
            if (bio != null) {
              // Prefer summary, fall back to content
              return _cleanLastFmText(bio['summary'] ?? bio['content']);
            }
          }
        }
      }
    } catch (e) {
      _logger.warning('Last.fm API error: $e', context: 'Metadata');
    }
    return null;
  }

  static Future<String?> _fetchFromTheAudioDb(
    String artistName,
    String apiKey,
  ) async {
    try {
      final uri = Uri.https(
        'theaudiodb.com',
        '/api/v1/json/$apiKey/search.php',
        {'s': artistName},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final artists = data['artists'];

        if (artists != null && artists.isNotEmpty) {
          final artist = artists[0];
          // Try multiple language fields
          return artist['strBiographyEN'] ??
              artist['strBiographyDE'] ??
              artist['strBiographyFR'] ??
              artist['strBiographyIT'] ??
              artist['strBiographyES'];
        }
      }
    } catch (e) {
      _logger.warning('TheAudioDB API error: $e', context: 'Metadata');
    }
    return null;
  }

  /// Removes Last.fm HTML tags and links
  static String? _cleanLastFmText(String? text) {
    if (text == null) return null;

    // Remove <a href...> tags
    text = text.replaceAll(RegExp(r'<a[^>]*>'), '');
    text = text.replaceAll('</a>', '');

    // Remove "Read more on Last.fm" footer
    text = text.replaceAll(RegExp(r'\s*<a[^>]*>.*?</a>.*$'), '');

    // Clean up any remaining HTML
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    return text.trim();
  }

  /// Fetches artist image URL from Deezer (free, no API key required)
  /// Returns the image URL if found, null otherwise
  static Future<String?> getArtistImageUrl(String artistName) async {
    // Check cache first
    final cacheKey = 'artistImage:$artistName';
    if (_artistImageCache.containsKey(cacheKey)) {
      return _artistImageCache[cacheKey];
    }

    // Use Deezer API (free, no key, excellent coverage)
    try {
      final uri = Uri.https(
        'api.deezer.com',
        '/search/artist',
        {
          'q': artistName,
          'limit': '1',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final artists = data['data'] as List?;
        if (artists != null && artists.isNotEmpty) {
          final artist = artists[0];
          // Use picture_xl for high quality, fall back to picture_medium
          final imageUrl = artist['picture_xl'] ?? artist['picture_medium'] ?? artist['picture'];
          _artistImageCache[cacheKey] = imageUrl;
          return imageUrl;
        }
      }
    } catch (e) {
      _logger.warning('Deezer artist image error: $e', context: 'Metadata');
    }

    // Cache the null result to avoid repeated failed lookups
    _artistImageCache[cacheKey] = null;
    return null;
  }

  // Cache for album images
  static final Map<String, String?> _albumImageCache = {};

  // Cache for author images (audiobooks)
  static final Map<String, String?> _authorImageCache = {};

  /// Fetches album cover URL from Deezer (free, no API key required)
  /// Returns the image URL if found, null otherwise
  static Future<String?> getAlbumImageUrl(String albumName, String? artistName) async {
    // Build cache key
    final cacheKey = 'albumImage:${artistName ?? ""}:$albumName';
    if (_albumImageCache.containsKey(cacheKey)) {
      return _albumImageCache[cacheKey];
    }

    // Use Deezer API (free, no key, excellent coverage)
    try {
      // Search with both album and artist if available for better matching
      final query = artistName != null && artistName.isNotEmpty
          ? '$artistName $albumName'
          : albumName;

      final uri = Uri.https(
        'api.deezer.com',
        '/search/album',
        {
          'q': query,
          'limit': '5', // Get a few results to find best match
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final albums = data['data'] as List?;
        if (albums != null && albums.isNotEmpty) {
          // Try to find exact match first
          Map<String, dynamic>? bestMatch;
          for (final album in albums) {
            final deezerAlbumName = (album['title'] as String?)?.toLowerCase();
            final deezerArtistName = (album['artist']?['name'] as String?)?.toLowerCase();

            if (deezerAlbumName == albumName.toLowerCase()) {
              // Album name matches
              if (artistName == null || artistName.isEmpty ||
                  deezerArtistName == artistName.toLowerCase()) {
                // And artist matches (or we don't have artist to match)
                bestMatch = album;
                break;
              }
              // Album matches but artist doesn't - keep as candidate
              bestMatch ??= album;
            }
          }

          // Fall back to first result if no good match
          final album = bestMatch ?? albums[0] as Map<String, dynamic>;

          // Use cover_xl for high quality, fall back to cover_medium
          final imageUrl = album['cover_xl'] ?? album['cover_big'] ??
              album['cover_medium'] ?? album['cover'];
          _albumImageCache[cacheKey] = imageUrl;
          return imageUrl;
        }
      }
    } catch (e) {
      _logger.warning('Deezer album image error: $e', context: 'Metadata');
    }

    // Cache the null result to avoid repeated failed lookups
    _albumImageCache[cacheKey] = null;
    return null;
  }

  /// Generate name variations for fuzzy matching
  /// Returns a list of name variations to try, in priority order
  static List<String> _generateNameVariations(String authorName) {
    final variations = <String>[];
    final original = authorName.trim();

    // Always try original first
    variations.add(original);

    // Handle "Lastname, Firstname" format
    if (original.contains(',')) {
      final parts = original.split(',').map((p) => p.trim()).toList();
      if (parts.length == 2) {
        variations.add('${parts[1]} ${parts[0]}'); // "Firstname Lastname"
      }
    }

    // Expand condensed initials like "J.R.R." to "J. R. R." for better splitting
    // This handles "J.R.R. Tolkien" -> "J. R. R. Tolkien"
    final expandedInitials = original.replaceAllMapped(
      RegExp(r'([A-Z])\.([A-Z])'),
      (m) => '${m.group(1)}. ${m.group(2)}',
    );
    if (expandedInitials != original && !variations.contains(expandedInitials)) {
      variations.add(expandedInitials);
    }

    // Remove common titles
    final titles = ['Dr.', 'Dr', 'Mr.', 'Mr', 'Mrs.', 'Mrs', 'Ms.', 'Ms',
                    'Prof.', 'Prof', 'Professor', 'Sir', 'Dame', 'Lord', 'Lady'];
    String withoutTitle = original;
    for (final title in titles) {
      if (withoutTitle.toLowerCase().startsWith(title.toLowerCase() + ' ')) {
        withoutTitle = withoutTitle.substring(title.length).trim();
        if (withoutTitle != original) {
          variations.add(withoutTitle);
        }
        break;
      }
    }

    // Remove suffixes
    final suffixes = [', Jr.', ', Jr', ' Jr.', ' Jr', ', Sr.', ', Sr', ' Sr.', ' Sr',
                      ', III', ' III', ', II', ' II', ', IV', ' IV', ', PhD', ', Ph.D.'];
    String withoutSuffix = withoutTitle;
    for (final suffix in suffixes) {
      if (withoutSuffix.toLowerCase().endsWith(suffix.toLowerCase())) {
        withoutSuffix = withoutSuffix.substring(0, withoutSuffix.length - suffix.length).trim();
        if (withoutSuffix != withoutTitle && !variations.contains(withoutSuffix)) {
          variations.add(withoutSuffix);
        }
        break;
      }
    }

    // Split into parts for further variations (use expanded initials for better splitting)
    final nameToSplit = expandedInitials != original ? expandedInitials : withoutSuffix;
    final parts = nameToSplit.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 2) {
      // Try first + last only (skip middle names/initials)
      final firstLast = '${parts.first} ${parts.last}';
      if (!variations.contains(firstLast)) {
        variations.add(firstLast);
      }

      // Check if name starts with initials (single letter or letter with period)
      bool isInitial(String s) => s.length == 1 || (s.length == 2 && s.endsWith('.'));

      // If first part looks like an initial, try just the last name
      if (isInitial(parts.first)) {
        if (!variations.contains(parts.last)) {
          variations.add(parts.last);
        }
      }

      // Handle multiple initials like "J. K. Rowling" or "J. R. R. Tolkien"
      // Find where initials end and actual name begins
      int initialsEnd = 0;
      for (int i = 0; i < parts.length - 1; i++) {
        if (isInitial(parts[i])) {
          initialsEnd = i + 1;
        } else {
          break;
        }
      }

      if (initialsEnd > 0 && initialsEnd < parts.length) {
        // Try the non-initial part of the name
        final restOfName = parts.sublist(initialsEnd).join(' ');
        if (restOfName.isNotEmpty && !variations.contains(restOfName)) {
          variations.add(restOfName);
        }

        // Also try initials without periods + last name (e.g., "JRR Tolkien", "JK Rowling")
        final initialsNoPeriods = parts.sublist(0, initialsEnd)
            .map((s) => s.replaceAll('.', ''))
            .join('');
        final compactInitials = '$initialsNoPeriods ${parts.last}';
        if (!variations.contains(compactInitials)) {
          variations.add(compactInitials);
        }
      }
    }

    // Remove duplicates while preserving order
    return variations.toSet().toList();
  }

  /// Try to fetch author image from Audnexus
  static Future<String?> _tryAudnexus(String name) async {
    try {
      final uri = Uri.https('api.audnex.us', '/authors', {'name': name});
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final imageUrl = data[0]['image'] as String?;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            return imageUrl;
          }
        }
      }
    } catch (e) {
      _logger.warning('Audnexus author image error for "$name": $e', context: 'Metadata');
    }
    return null;
  }

  /// Try to fetch author image from Open Library
  static Future<String?> _tryOpenLibrary(String name) async {
    try {
      final uri = Uri.https('openlibrary.org', '/search/authors.json', {
        'q': name,
        'limit': '1',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final authors = data['docs'] as List?;
        if (authors != null && authors.isNotEmpty) {
          final authorKey = authors[0]['key'] as String?;
          if (authorKey != null) {
            final olid = authorKey.replaceAll('/authors/', '');
            final imageUrl = 'https://covers.openlibrary.org/a/olid/$olid-L.jpg';

            // Verify image exists
            try {
              final check = await http.head(Uri.parse(imageUrl)).timeout(const Duration(seconds: 3));
              if (check.statusCode == 200) {
                return imageUrl;
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      _logger.warning('Open Library author image error for "$name": $e', context: 'Metadata');
    }
    return null;
  }

  /// Try to fetch author image from Wikipedia
  static Future<String?> _tryWikipedia(String name) async {
    try {
      // Search for author
      final searchUri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': '$name writer author',
        'srlimit': '1',
        'format': 'json',
      });
      final searchResponse = await http.get(searchUri).timeout(const Duration(seconds: 5));

      if (searchResponse.statusCode == 200) {
        final searchData = json.decode(searchResponse.body);
        final results = searchData['query']?['search'] as List?;
        if (results != null && results.isNotEmpty) {
          final pageTitle = results[0]['title'] as String?;
          if (pageTitle != null) {
            // Get page image
            final imageUri = Uri.https('en.wikipedia.org', '/w/api.php', {
              'action': 'query',
              'titles': pageTitle,
              'prop': 'pageimages',
              'pithumbsize': '500',
              'format': 'json',
            });
            final imageResponse = await http.get(imageUri).timeout(const Duration(seconds: 5));

            if (imageResponse.statusCode == 200) {
              final imageData = json.decode(imageResponse.body);
              final pages = imageData['query']?['pages'] as Map<String, dynamic>?;
              if (pages != null && pages.isNotEmpty) {
                final page = pages.values.first as Map<String, dynamic>?;
                final thumbnail = page?['thumbnail'] as Map<String, dynamic>?;
                final imageUrl = thumbnail?['source'] as String?;
                if (imageUrl != null && imageUrl.isNotEmpty) {
                  return imageUrl;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      _logger.warning('Wikipedia author image error for "$name": $e', context: 'Metadata');
    }
    return null;
  }

  /// Fetches author image URL from multiple sources with fuzzy name matching
  /// Priority: 1. Audnexus, 2. Open Library, 3. Wikipedia
  /// Tries name variations if exact match fails
  static Future<String?> getAuthorImageUrl(String authorName) async {
    // Check cache first
    final cacheKey = 'authorImage:$authorName';
    if (_authorImageCache.containsKey(cacheKey)) {
      return _authorImageCache[cacheKey];
    }

    // Generate name variations for fuzzy matching
    final variations = _generateNameVariations(authorName);

    // Try each source with all variations before moving to next source
    // This prioritizes source quality over name variation

    // 1. Try Audnexus (best for audiobook authors)
    for (final name in variations) {
      final result = await _tryAudnexus(name);
      if (result != null) {
        _authorImageCache[cacheKey] = result;
        return result;
      }
    }

    // 2. Try Open Library
    for (final name in variations) {
      final result = await _tryOpenLibrary(name);
      if (result != null) {
        _authorImageCache[cacheKey] = result;
        return result;
      }
    }

    // 3. Try Wikipedia (try top 3 variations - best source for famous authors)
    for (final name in variations.take(3)) {
      final wikiResult = await _tryWikipedia(name);
      if (wikiResult != null) {
        _authorImageCache[cacheKey] = wikiResult;
        return wikiResult;
      }
    }

    // Cache the null result to avoid repeated failed lookups
    _authorImageCache[cacheKey] = null;
    return null;
  }

  /// Clears the metadata cache
  static void clearCache() {
    _cache.clear();
    _artistImageCache.clear();
    _albumImageCache.clear();
    _authorImageCache.clear();
  }
}
