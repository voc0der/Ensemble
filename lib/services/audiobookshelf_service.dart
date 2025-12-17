import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';
import 'debug_logger.dart';

/// Direct Audiobookshelf API service for enhanced audiobook features
/// Provides: author images, chapters, series data, and detailed metadata
class AudiobookshelfService {
  static final _logger = DebugLogger();

  String? _serverUrl;
  String? _apiToken;
  bool _isConfigured = false;

  // Singleton pattern
  static final AudiobookshelfService _instance = AudiobookshelfService._internal();
  factory AudiobookshelfService() => _instance;
  AudiobookshelfService._internal();

  /// Initialize the service with stored settings
  Future<void> initialize() async {
    _serverUrl = await SettingsService.getAbsServerUrl();
    _apiToken = await SettingsService.getAbsApiToken();
    _isConfigured = await SettingsService.getAbsEnabled();

    if (_isConfigured && _serverUrl != null && _apiToken != null) {
      _logger.log('📖 Audiobookshelf service initialized: $_serverUrl');
    } else {
      _logger.log('📖 Audiobookshelf service not configured');
    }
  }

  /// Check if the service is configured and ready
  bool get isConfigured => _isConfigured && _serverUrl != null && _apiToken != null;

  /// Configure the service with new settings
  Future<void> configure(String serverUrl, String apiToken) async {
    _serverUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    _apiToken = apiToken;
    _isConfigured = true;

    await SettingsService.setAbsServerUrl(_serverUrl!);
    await SettingsService.setAbsApiToken(_apiToken!);
    await SettingsService.setAbsEnabled(true);

    _logger.log('📖 Audiobookshelf service configured: $_serverUrl');
  }

  /// Login with username/password to get API token
  Future<String?> login(String serverUrl, String username, String password) async {
    final url = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;

    try {
      final response = await http.post(
        Uri.parse('$url/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['user']?['token'] as String?;
        if (token != null) {
          _logger.log('📖 Audiobookshelf login successful');
          return token;
        }
      }
      _logger.log('📖 Audiobookshelf login failed: ${response.statusCode}');
      return null;
    } catch (e) {
      _logger.log('📖 Audiobookshelf login error: $e');
      return null;
    }
  }

  /// Test connection to server
  Future<bool> testConnection() async {
    if (!isConfigured) return false;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/me'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      _logger.log('📖 Connection test failed: $e');
      return false;
    }
  }

  /// Get all libraries
  Future<List<AbsLibrary>> getLibraries() async {
    if (!isConfigured) return [];

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/libraries'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final libraries = (data['libraries'] as List?)
            ?.map((lib) => AbsLibrary.fromJson(lib))
            .toList() ?? [];
        _logger.log('📖 Got ${libraries.length} libraries');
        return libraries;
      }
    } catch (e) {
      _logger.log('📖 Error getting libraries: $e');
    }
    return [];
  }

  /// Get library item details including chapters
  Future<AbsLibraryItem?> getLibraryItem(String itemId) async {
    if (!isConfigured) return null;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/items/$itemId?expanded=1'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final item = AbsLibraryItem.fromJson(data);
        _logger.log('📖 Got library item: ${item.title}, chapters: ${item.chapters?.length ?? 0}');
        return item;
      }
    } catch (e) {
      _logger.log('📖 Error getting library item: $e');
    }
    return null;
  }

  /// Get author details including image
  Future<AbsAuthor?> getAuthor(String authorId) async {
    if (!isConfigured) return null;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/authors/$authorId'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AbsAuthor.fromJson(data);
      }
    } catch (e) {
      _logger.log('📖 Error getting author: $e');
    }
    return null;
  }

  /// Search for author by name and get their image
  Future<String?> getAuthorImageUrl(String authorName) async {
    if (!isConfigured) return null;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/search/authors?q=${Uri.encodeComponent(authorName)}'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final authors = data['authors'] as List?;
        if (authors != null && authors.isNotEmpty) {
          final author = authors.first;
          final authorId = author['id'] as String?;
          final imagePath = author['imagePath'] as String?;

          if (imagePath != null && imagePath.isNotEmpty) {
            // Return full URL to author image
            return '$_serverUrl/api/authors/$authorId/image';
          }
        }
      }
    } catch (e) {
      _logger.log('📖 Error searching author: $e');
    }
    return null;
  }

  /// Search for a book by title in a library
  /// Returns the library item with full details including chapters
  Future<AbsLibraryItem?> searchBookByTitle(String libraryId, String bookTitle, {String? authorName}) async {
    if (!isConfigured) return null;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/libraries/$libraryId/search?q=${Uri.encodeComponent(bookTitle)}&limit=10'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final books = data['book'] as List?;

        if (books != null && books.isNotEmpty) {
          // Find best match
          AbsLibraryItem? bestMatch;
          final bookTitleLower = bookTitle.toLowerCase();
          final authorNameLower = authorName?.toLowerCase();

          for (final bookResult in books) {
            final libraryItem = bookResult['libraryItem'] as Map<String, dynamic>?;
            if (libraryItem == null) continue;

            final media = libraryItem['media'] as Map<String, dynamic>?;
            final metadata = media?['metadata'] as Map<String, dynamic>?;
            final absTitle = (metadata?['title'] as String?)?.toLowerCase() ?? '';
            final absAuthor = (metadata?['authorName'] as String?)?.toLowerCase() ?? '';

            // Check for title match
            if (absTitle.contains(bookTitleLower) || bookTitleLower.contains(absTitle)) {
              // If author provided, also check author match
              if (authorNameLower == null ||
                  absAuthor.contains(authorNameLower) ||
                  authorNameLower.contains(absAuthor)) {
                // Get full library item with chapters
                final itemId = libraryItem['id'] as String?;
                if (itemId != null) {
                  final fullItem = await getLibraryItem(itemId);
                  if (fullItem != null && fullItem.chapters != null && fullItem.chapters!.isNotEmpty) {
                    _logger.log('📖 Found matching book: ${fullItem.title} with ${fullItem.chapters!.length} chapters');
                    return fullItem;
                  }
                  bestMatch ??= fullItem;
                }
              }
            }
          }

          return bestMatch;
        }
      }
    } catch (e) {
      _logger.log('📖 Error searching books: $e');
    }
    return null;
  }

  /// Get all series
  Future<List<AbsSeries>> getSeries() async {
    if (!isConfigured) return [];

    try {
      // First get all libraries
      final libraries = await getLibraries();
      final allSeries = <AbsSeries>[];

      for (final library in libraries) {
        if (library.mediaType == 'book') {
          final response = await http.get(
            Uri.parse('$_serverUrl/api/libraries/${library.id}/series'),
            headers: {'Authorization': 'Bearer $_apiToken'},
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final results = data['results'] as List?;
            if (results != null) {
              allSeries.addAll(results.map((s) => AbsSeries.fromJson(s)));
            }
          }
        }
      }

      _logger.log('📖 Got ${allSeries.length} series');
      return allSeries;
    } catch (e) {
      _logger.log('📖 Error getting series: $e');
    }
    return [];
  }

  /// Get series by ID with books
  Future<AbsSeries?> getSeriesById(String seriesId, String libraryId) async {
    if (!isConfigured) return null;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/libraries/$libraryId/series/$seriesId'),
        headers: {'Authorization': 'Bearer $_apiToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AbsSeries.fromJson(data);
      }
    } catch (e) {
      _logger.log('📖 Error getting series: $e');
    }
    return null;
  }

  /// Get all authors
  Future<List<AbsAuthor>> getAuthors() async {
    if (!isConfigured) return [];

    try {
      // First get all libraries
      final libraries = await getLibraries();
      final allAuthors = <AbsAuthor>[];

      for (final library in libraries) {
        if (library.mediaType == 'book') {
          final response = await http.get(
            Uri.parse('$_serverUrl/api/libraries/${library.id}/authors'),
            headers: {'Authorization': 'Bearer $_apiToken'},
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final authors = data['authors'] as List?;
            if (authors != null) {
              allAuthors.addAll(authors.map((a) => AbsAuthor.fromJson(a)));
            }
          }
        }
      }

      _logger.log('📖 Got ${allAuthors.length} authors');
      return allAuthors;
    } catch (e) {
      _logger.log('📖 Error getting authors: $e');
    }
    return [];
  }

  /// Build image URL for author
  String? buildAuthorImageUrl(String authorId) {
    if (!isConfigured) return null;
    return '$_serverUrl/api/authors/$authorId/image?token=$_apiToken';
  }

  /// Build image URL for book cover
  String? buildCoverUrl(String itemId) {
    if (!isConfigured) return null;
    return '$_serverUrl/api/items/$itemId/cover?token=$_apiToken';
  }
}

/// Audiobookshelf Library model
class AbsLibrary {
  final String id;
  final String name;
  final String mediaType; // 'book' or 'podcast'

  AbsLibrary({
    required this.id,
    required this.name,
    required this.mediaType,
  });

  factory AbsLibrary.fromJson(Map<String, dynamic> json) {
    return AbsLibrary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      mediaType: json['mediaType'] as String? ?? 'book',
    );
  }
}

/// Audiobookshelf Library Item (Audiobook) model
class AbsLibraryItem {
  final String id;
  final String title;
  final String? authorName;
  final String? narratorName;
  final String? description;
  final String? publisher;
  final String? publishedYear;
  final String? seriesName;
  final String? seriesSequence;
  final List<AbsChapter>? chapters;
  final Duration? duration;
  final String? coverPath;

  AbsLibraryItem({
    required this.id,
    required this.title,
    this.authorName,
    this.narratorName,
    this.description,
    this.publisher,
    this.publishedYear,
    this.seriesName,
    this.seriesSequence,
    this.chapters,
    this.duration,
    this.coverPath,
  });

  factory AbsLibraryItem.fromJson(Map<String, dynamic> json) {
    final media = json['media'] as Map<String, dynamic>?;
    final metadata = media?['metadata'] as Map<String, dynamic>?;
    final chaptersJson = media?['chapters'] as List?;
    final durationSeconds = media?['duration'] as num?;

    // Parse series info
    String? seriesName;
    String? seriesSequence;
    final seriesList = metadata?['series'] as List?;
    if (seriesList != null && seriesList.isNotEmpty) {
      final firstSeries = seriesList.first as Map<String, dynamic>?;
      seriesName = firstSeries?['name'] as String?;
      seriesSequence = firstSeries?['sequence'] as String?;
    }

    return AbsLibraryItem(
      id: json['id'] as String? ?? '',
      title: metadata?['title'] as String? ?? json['name'] as String? ?? 'Unknown',
      authorName: metadata?['authorName'] as String?,
      narratorName: metadata?['narratorName'] as String?,
      description: metadata?['description'] as String?,
      publisher: metadata?['publisher'] as String?,
      publishedYear: metadata?['publishedYear'] as String?,
      seriesName: seriesName,
      seriesSequence: seriesSequence,
      chapters: chaptersJson?.map((c) => AbsChapter.fromJson(c as Map<String, dynamic>)).toList(),
      duration: durationSeconds != null ? Duration(milliseconds: (durationSeconds * 1000).round()) : null,
      coverPath: json['coverPath'] as String?,
    );
  }
}

/// Audiobookshelf Chapter model
class AbsChapter {
  final int id;
  final String title;
  final double start; // Start time in seconds
  final double end; // End time in seconds

  AbsChapter({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  Duration get duration => Duration(milliseconds: ((end - start) * 1000).round());
  int get startMs => (start * 1000).round();
  int get endMs => (end * 1000).round();

  factory AbsChapter.fromJson(Map<String, dynamic> json) {
    return AbsChapter(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Chapter ${json['id'] ?? 0}',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Audiobookshelf Author model
class AbsAuthor {
  final String id;
  final String name;
  final String? description;
  final String? imagePath;
  final int numBooks;

  AbsAuthor({
    required this.id,
    required this.name,
    this.description,
    this.imagePath,
    this.numBooks = 0,
  });

  factory AbsAuthor.fromJson(Map<String, dynamic> json) {
    return AbsAuthor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      description: json['description'] as String?,
      imagePath: json['imagePath'] as String?,
      numBooks: json['numBooks'] as int? ?? 0,
    );
  }
}

/// Audiobookshelf Series model
class AbsSeries {
  final String id;
  final String name;
  final String? description;
  final int numBooks;
  final List<AbsLibraryItem>? books;

  AbsSeries({
    required this.id,
    required this.name,
    this.description,
    this.numBooks = 0,
    this.books,
  });

  factory AbsSeries.fromJson(Map<String, dynamic> json) {
    final booksJson = json['books'] as List?;

    return AbsSeries(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Series',
      description: json['description'] as String?,
      numBooks: json['numBooks'] as int? ?? booksJson?.length ?? 0,
      books: booksJson?.map((b) => AbsLibraryItem.fromJson(b as Map<String, dynamic>)).toList(),
    );
  }
}
