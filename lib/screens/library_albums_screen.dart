import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';

class LibraryAlbumsScreen extends StatelessWidget {
  const LibraryAlbumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: colorScheme.onBackground,
        ),
        title: Text(
          'Albums',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildAlbumsList(context, provider),
    );
  }

  Widget _buildAlbumsList(BuildContext context, MusicAssistantProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;

    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (provider.albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album_outlined,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.54),
            ),
            const SizedBox(height: 16),
            Text(
              'No albums found',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.surfaceVariant,
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () async {
        await provider.loadLibrary();
      },
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        padding: const EdgeInsets.all(12),
        itemCount: provider.albums.length,
        itemBuilder: (context, index) {
          final album = provider.albums[index];
          return _buildAlbumCard(context, album, provider);
        },
      ),
    );
  }

  Widget _buildAlbumCard(
      BuildContext context, Album album, MusicAssistantProvider provider) {
    final imageUrl = provider.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailsScreen(album: album),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: HeroTags.albumCover + (album.uri ?? album.itemId),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  image: imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: imageUrl == null
                    ? Center(
                        child: Icon(
                          Icons.album_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.albumTitle + (album.uri ?? album.itemId),
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.name,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Hero(
            tag: HeroTags.artistName + (album.uri ?? album.itemId),
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.artistsString,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
