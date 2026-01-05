/// Search scoring system for ranking search results.
///
/// Provides advanced text matching including:
/// - Stopword removal ("the Ramones" finds "Ramones")
/// - Fuzzy matching (typo tolerance)
/// - N-gram matching (partial matches)
/// - Reverse matching (query contains result)
library;

export 'scoring_config.dart';
export 'text_normalizer.dart';
export 'fuzzy_matcher.dart';
export 'ngram_matcher.dart';

import 'dart:math';

import '../../models/media_item.dart';
import 'scoring_config.dart';
import 'text_normalizer.dart';
import 'fuzzy_matcher.dart';
import 'ngram_matcher.dart';

/// Main search scorer that combines all matching strategies.
///
/// Usage:
/// ```dart
/// final scorer = SearchScorer();
/// final score = scorer.scoreItem(mediaItem, query);
/// ```
class SearchScorer {
  final TextNormalizer _normalizer;
  final FuzzyMatcher _fuzzyMatcher;
  final NgramMatcher _ngramMatcher;
  final ScoringConfig _config;

  // Cache for normalized query (reused across items in same search)
  String? _cachedQueryString;
  NormalizedQuery? _cachedQuery;

  SearchScorer({ScoringConfig? config})
      : _normalizer = TextNormalizer(),
        _fuzzyMatcher = FuzzyMatcher(),
        _ngramMatcher = NgramMatcher(),
        _config = config ?? ScoringConfig.defaults;

  /// Access to the normalizer for external use
  TextNormalizer get normalizer => _normalizer;

  /// Clear the query cache (call when starting a new search)
  void clearCache() {
    _cachedQueryString = null;
    _cachedQuery = null;
  }

  /// Score a media item against a search query.
  ///
  /// Returns a score where higher values indicate better matches.
  /// Score components:
  /// - Primary name matching (0-100)
  /// - Secondary field bonuses (0-20)
  /// - Library/favorite bonuses (0-15)
  double scoreItem(MediaItem item, String query) {
    // Use cached normalized query if available
    if (_cachedQueryString != query) {
      _cachedQueryString = query;
      _cachedQuery = _normalizer.normalizeQuery(query);
    }

    final nq = _cachedQuery!;
    if (nq.isEmpty) return 0;

    final nameLower = item.name.toLowerCase();
    final nameNoStopwords = _normalizer.normalizeTextNoStopwords(item.name);

    // Calculate primary score based on name matching
    double score = _calculatePrimaryScore(nameLower, nameNoStopwords, nq);

    // Add secondary field bonuses based on media type
    score += _calculateSecondaryScore(item, nq);

    // Add library/favorite bonuses
    score += _calculateBonuses(item);

    return score;
  }

  /// Calculate primary score based on name matching.
  double _calculatePrimaryScore(
    String nameLower,
    String nameNoStopwords,
    NormalizedQuery nq,
  ) {
    // Tier 1: Exact match (highest priority)
    if (nameLower == nq.normalized) {
      return _config.exactMatch;
    }
    if (nameNoStopwords == nq.withoutStopwords) {
      return _config.exactMatchNoStopwords;
    }

    // Tier 2: Starts with
    if (nameLower.startsWith(nq.normalized)) {
      return _config.startsWithMatch;
    }
    if (nameNoStopwords.startsWith(nq.withoutStopwords)) {
      return _config.startsWithNoStopwords;
    }

    // Tier 3: Word boundary match
    if (_matchesWordBoundary(nameLower, nq.normalized)) {
      return _config.wordBoundaryMatch;
    }
    if (_matchesWordBoundary(nameNoStopwords, nq.withoutStopwords)) {
      return _config.wordBoundaryNoStopwords;
    }

    // Tier 4: Reverse contains (result name IN query)
    // This solves "the ramones" finding "Ramones"
    if (_reverseContains(nq.normalized, nameLower)) {
      return _config.reverseContainsMatch;
    }
    if (_reverseContains(nq.withoutStopwords, nameNoStopwords)) {
      return _config.reverseContainsNoStopwords;
    }

    // Tier 5: Contains anywhere
    if (nameLower.contains(nq.normalized)) {
      return _config.containsMatch;
    }
    if (nameNoStopwords.contains(nq.withoutStopwords)) {
      return _config.containsNoStopwords;
    }

    // Tier 6: Fuzzy matching (typo tolerance)
    final fuzzyScore = _fuzzyMatcher.jaroWinklerSimilarity(
      nq.withoutStopwords,
      nameNoStopwords,
    );
    if (fuzzyScore >= _config.fuzzyHighThreshold) {
      // Scale score based on similarity (0.90-1.0 -> 40-45)
      return _config.fuzzyMatchHigh +
          ((fuzzyScore - _config.fuzzyHighThreshold) * 50);
    }
    if (fuzzyScore >= _config.fuzzyMediumThreshold) {
      return _config.fuzzyMatchMedium;
    }

    // Tier 7: Token-level fuzzy (individual words)
    final tokenFuzzy = _fuzzyMatcher.bestTokenMatch(
      nq.tokensNoStop,
      _normalizer.tokenize(nameNoStopwords),
    );
    if (tokenFuzzy >= _config.fuzzyHighThreshold) {
      return _config.fuzzyMatchMedium;
    }

    // Tier 8: N-gram partial matching
    final ngramScore = _ngramMatcher.bigramSimilarity(
      nq.withoutStopwords,
      nameNoStopwords,
    );
    if (ngramScore >= _config.ngramThreshold) {
      // Scale: 0.5-1.0 -> 25-35
      return _config.ngramMatch + (ngramScore * 10);
    }

    // Baseline: Music Assistant API returned it, so some relevance
    return _config.baseline;
  }

  /// Check if query matches at word boundary in text.
  bool _matchesWordBoundary(String text, String query) {
    if (query.contains(' ')) {
      // Multi-word query: check if at start or after space
      if (text.startsWith(query)) return true;
      if (text.contains(' $query')) return true;
      return false;
    }

    // Single-word query: check if any word starts with query
    final words = text.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.startsWith(query)) return true;
    }
    return false;
  }

  /// Check if text is contained within query (reverse matching).
  ///
  /// Solves: "the ramones" query finding "Ramones" artist
  bool _reverseContains(String query, String text) {
    if (text.length < _config.minReverseMatchLength) return false;

    // Direct containment
    if (query.contains(text)) return true;

    // Token-level: any query token equals text
    final queryTokens = query.split(RegExp(r'\s+'));
    for (final token in queryTokens) {
      if (token.length >= _config.minReverseMatchLength && text == token) {
        return true;
      }
    }

    return false;
  }

  /// Calculate secondary field bonuses based on media type.
  double _calculateSecondaryScore(MediaItem item, NormalizedQuery nq) {
    double bonus = 0;

    if (item is Album) {
      bonus += _scoreArtistField(item.artistsString, nq);
    } else if (item is Track) {
      bonus += _scoreArtistField(item.artistsString, nq);
      // Also check album name
      if (item.album?.name != null) {
        final albumLower = item.album!.name.toLowerCase();
        if (albumLower.contains(nq.withoutStopwords)) {
          bonus += _config.albumFieldBonus;
        }
      }
    } else if (item is Audiobook) {
      // Check authors
      final authorLower = item.authorsString.toLowerCase();
      if (authorLower == nq.withoutStopwords) {
        bonus += _config.authorFieldExactBonus;
      } else if (authorLower.contains(nq.withoutStopwords)) {
        bonus += _config.authorFieldPartialBonus;
      }
      // Check narrators
      final narratorLower = item.narratorsString.toLowerCase();
      if (narratorLower.contains(nq.withoutStopwords)) {
        bonus += _config.narratorFieldBonus;
      }
    } else if (item.mediaType == MediaType.podcast || item.mediaType == MediaType.podcastEpisode) {
      bonus += _scorePodcastFields(item, nq);
    }

    return bonus;
  }

  /// Score artist field for albums and tracks.
  double _scoreArtistField(String artistsString, NormalizedQuery nq) {
    final artistLower = artistsString.toLowerCase();
    if (artistLower == nq.withoutStopwords) {
      return _config.artistFieldExactBonus;
    }
    if (artistLower.contains(nq.withoutStopwords)) {
      return _config.artistFieldPartialBonus;
    }
    return 0;
  }

  /// Score podcast-specific fields (creator, description).
  double _scorePodcastFields(MediaItem item, NormalizedQuery nq) {
    double bonus = 0;
    final metadata = item.metadata;

    if (metadata != null) {
      // Check creator fields
      final creatorFields = [
        metadata['author'] as String?,
        metadata['publisher'] as String?,
        metadata['owner'] as String?,
        metadata['creator'] as String?,
      ].where((s) => s != null && s.isNotEmpty).map((s) => s!.toLowerCase());

      bool foundExact = false;
      bool foundContains = false;
      for (final field in creatorFields) {
        if (field == nq.withoutStopwords) {
          foundExact = true;
          break;
        } else if (field.contains(nq.withoutStopwords)) {
          foundContains = true;
        }
      }

      if (foundExact) {
        bonus += _config.creatorFieldExactBonus;
      } else if (foundContains) {
        bonus += _config.creatorFieldPartialBonus;
      }

      // Check description
      final description =
          (metadata['description'] as String? ?? '').toLowerCase();
      if (description.contains(nq.withoutStopwords)) {
        bonus += _config.descriptionBonus;
      }
    }

    // Fallback: podcast name prominence check
    if (bonus == 0) {
      final nameLower = item.name.toLowerCase();
      if (nameLower.contains(nq.withoutStopwords)) {
        if (nq.withoutStopwords.contains(' ')) {
          // Multi-word query prominence
          final prominence = nq.withoutStopwords.length / nameLower.length;
          if (prominence >= 0.5) {
            bonus += _config.creatorFieldExactBonus;
          } else if (prominence >= 0.3) {
            bonus += _config.creatorFieldPartialBonus + 4;
          } else {
            bonus += _config.creatorFieldPartialBonus;
          }
        } else {
          bonus += _config.descriptionBonus;
        }
      }
    }

    return bonus;
  }

  /// Calculate library and favorite bonuses.
  double _calculateBonuses(MediaItem item) {
    double bonus = 0;

    // Library bonus (Album has inLibrary property)
    if (item is Album && item.inLibrary) {
      bonus += _config.libraryBonus;
    }

    // Favorite bonus
    if (item.favorite == true) {
      bonus += _config.favoriteBonus;
    }

    return bonus;
  }
}
