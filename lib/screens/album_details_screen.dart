import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailsScreen({super.key, required this.album});

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.album.favorite ?? false;
    _loadTracks();
    _extractColors();
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);

    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        NetworkImage(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      print('⚠️ Failed to extract colors for album: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    try {
      final newState = await maProvider.api!.toggleFavorite(
        'album',
        widget.album.itemId,
        widget.album.provider,
      );

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
      print('Error toggling favorite: $e');
    }
  }

  Future<void> _loadTracks() async {
    final provider = context.read<MusicAssistantProvider>();
    final tracks = await provider.getAlbumTracks(
      widget.album.provider,
      widget.album.itemId,
    );

    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
  }

  Future<void> _playAlbum() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      print('🎵 Queueing album on ${player.name}: ${player.playerId}');

      // Queue all tracks via Music Assistant
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      print('✓ Album queued on ${player.name}');

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error playing album: $e');
      _showError('Failed to play album: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError('No player selected');
        return;
      }

      print('🎵 Queueing tracks on ${player.name} starting at index $index');

      // Queue tracks starting at the selected index
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      print('✓ Tracks queued on ${player.name}');

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final imageUrl = maProvider.getImageUrl(widget.album, size: 512);
    
    // Use theme colors
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350, // Increased height for bigger art
            pinned: true,
            backgroundColor: colorScheme.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
              color: colorScheme.onBackground,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Hero(
                    tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId),
                    child: Container(
                      width: 280, // Increased size
                      height: 280,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(16), // Slightly more rounded
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        image: imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(imageUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: imageUrl == null
                          ? Icon(
                              Icons.album_rounded,
                              size: 120,
                              color: colorScheme.onSurfaceVariant,
                            )
                          : null,
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
                  Hero(
                    tag: HeroTags.albumTitle + (widget.album.uri ?? widget.album.itemId),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.name,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Hero(
                    tag: HeroTags.artistName + (widget.album.uri ?? widget.album.itemId),
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.artistsString,
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onBackground.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      // Main Play Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              disabledBackgroundColor: colorScheme.primary.withOpacity(0.38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // "Play on..." Button
                      Expanded(
                        flex: 1,
                        child: SizedBox(
                          height: 50,
                          child: FilledButton.tonal(
                            onPressed: _isLoading || _tracks.isEmpty ? null : () => _showPlayOnMenu(context),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.speaker_group_outlined),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Favorite Button
                      Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(
                          color: _isFavorite ? colorScheme.errorContainer : colorScheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _toggleFavorite,
                          icon: Icon(
                            _isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: _isFavorite ? colorScheme.error : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tracks',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onBackground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            )
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${track.position ?? index + 1}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      track.name,
                      style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artistsString,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: track.duration != null
                        ? Text(
                            _formatDuration(track.duration!),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          )
                        : null,
                    onTap: () => _playTrack(index),
                  );
                },
                childCount: _tracks.length,
              ),
            ),
        ],
      ),
    );
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Play on...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No players available'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker, 
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () {
                        Navigator.pop(context);
                        // Play on this specific player
                        maProvider.playTracks(player.playerId, _tracks);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
