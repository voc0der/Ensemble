import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_assistant_provider.dart';
import '../../models/player.dart';
import '../../theme/design_tokens.dart';
import '../common/empty_state.dart';

/// Panel that displays the current playback queue with drag-to-reorder
/// and swipe-left-to-delete functionality.
///
/// Uses custom AnimatedList implementation instead of great_list_view
/// to avoid grey screen bugs (ReorderableListView) and drag duplication bugs (great_list_view).
class QueuePanel extends StatefulWidget {
  final MusicAssistantProvider maProvider;
  final PlayerQueue? queue;
  final bool isLoading;
  final Color textColor;
  final Color primaryColor;
  final Color backgroundColor;
  final double topPadding;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  const QueuePanel({
    super.key,
    required this.maProvider,
    required this.queue,
    required this.isLoading,
    required this.textColor,
    required this.primaryColor,
    required this.backgroundColor,
    required this.topPadding,
    required this.onClose,
    required this.onRefresh,
  });

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  List<QueueItem> _items = [];

  // Drag state
  int? _dragIndex;
  double _dragOffsetY = 0;
  OverlayEntry? _dragOverlay;
  QueueItem? _dragItem;
  double _itemHeight = 64.0; // Approximate, updated on build

  // Track pointer for right-swipe-to-close
  Offset? _pointerStart;
  static const _swipeThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.queue?.items ?? []);
  }

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newItems = widget.queue?.items ?? [];

    // Sync items when player/queue changes
    final playerChanged = widget.queue?.playerId != oldWidget.queue?.playerId;
    final countChanged = newItems.length != _items.length;
    final orderChanged = !_itemListsEqual(newItems, _items);

    if (playerChanged || countChanged || orderChanged) {
      setState(() {
        _items = List.from(newItems);
      });
    }
  }

  @override
  void dispose() {
    _removeDragOverlay();
    super.dispose();
  }

  bool _itemListsEqual(List<QueueItem> a, List<QueueItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].queueItemId != b[i].queueItemId) return false;
    }
    return true;
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleDelete(QueueItem item, int index) async {
    // Remove from local list with animation
    setState(() {
      _items.removeAt(index);
    });
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAnimatedItem(item, index, animation, removing: true),
      duration: const Duration(milliseconds: 200),
    );

    // Call API
    final playerId = widget.queue?.playerId;
    if (playerId != null) {
      widget.maProvider.api?.queueCommandDeleteItem(playerId, item.queueItemId);
    }
  }

  void _startDrag(int index, BuildContext itemContext, double localY) {
    if (_dragIndex != null) return;

    final RenderBox box = itemContext.findRenderObject() as RenderBox;
    final Offset globalPos = box.localToGlobal(Offset.zero);
    _itemHeight = box.size.height;

    setState(() {
      _dragIndex = index;
      _dragItem = _items[index];
      _dragOffsetY = 0;
    });

    _dragOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPos.dx,
        top: globalPos.dy + _dragOffsetY,
        width: box.size.width,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: _buildQueueItemContent(_dragItem!, index, false, false),
        ),
      ),
    );
    Overlay.of(context).insert(_dragOverlay!);
  }

  void _updateDrag(double deltaY) {
    if (_dragIndex == null || _dragOverlay == null) return;

    _dragOffsetY += deltaY;
    _dragOverlay!.markNeedsBuild();

    // Check if we should swap with adjacent items
    final threshold = _itemHeight / 2;

    if (_dragOffsetY > threshold && _dragIndex! < _items.length - 1) {
      // Moving down - swap with next item
      final oldIndex = _dragIndex!;
      final newIndex = oldIndex + 1;
      setState(() {
        final item = _items.removeAt(oldIndex);
        _items.insert(newIndex, item);
        _dragIndex = newIndex;
        _dragOffsetY -= _itemHeight;
      });
    } else if (_dragOffsetY < -threshold && _dragIndex! > 0) {
      // Moving up - swap with previous item
      final oldIndex = _dragIndex!;
      final newIndex = oldIndex - 1;
      setState(() {
        final item = _items.removeAt(oldIndex);
        _items.insert(newIndex, item);
        _dragIndex = newIndex;
        _dragOffsetY += _itemHeight;
      });
    }
  }

  void _endDrag(int originalIndex) async {
    if (_dragIndex == null) return;

    final newIndex = _dragIndex!;
    _removeDragOverlay();

    setState(() {
      _dragIndex = null;
      _dragItem = null;
      _dragOffsetY = 0;
    });

    // Call API if position changed
    if (originalIndex != newIndex) {
      final playerId = widget.queue?.playerId;
      final item = _items[newIndex];
      if (playerId != null) {
        await widget.maProvider.api?.queueCommandMoveItem(playerId, item.queueItemId, newIndex);
      }
    }
  }

  void _cancelDrag() {
    _removeDragOverlay();
    setState(() {
      _dragIndex = null;
      _dragItem = null;
      _dragOffsetY = 0;
    });
    // Refresh to restore original order
    widget.onRefresh();
  }

  void _removeDragOverlay() {
    _dragOverlay?.remove();
    _dragOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointerStart = event.position;
      },
      onPointerMove: (event) {
        if (_pointerStart != null) {
          final dx = event.position.dx - _pointerStart!.dx;
          final dy = (event.position.dy - _pointerStart!.dy).abs();
          if (dx > _swipeThreshold && dx > dy * 2) {
            _pointerStart = null;
            widget.onClose();
          }
        }
      },
      onPointerUp: (_) => _pointerStart = null,
      onPointerCancel: (_) => _pointerStart = null,
      child: Container(
        color: widget.backgroundColor,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.only(top: widget.topPadding + 4, left: 4, right: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: widget.textColor, size: IconSizes.md),
                    onPressed: widget.onClose,
                    padding: Spacing.paddingAll12,
                  ),
                  const Spacer(),
                  Text(
                    'Queue',
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: widget.textColor.withOpacity(0.7), size: IconSizes.sm),
                    onPressed: widget.onRefresh,
                    padding: Spacing.paddingAll12,
                  ),
                ],
              ),
            ),

            // Queue content
            Expanded(
              child: widget.isLoading
                  ? Center(child: CircularProgressIndicator(color: widget.primaryColor))
                  : widget.queue == null || _items.isEmpty
                      ? EmptyState.queue(context: context)
                      : _buildQueueList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueList() {
    final currentIndex = widget.queue!.currentIndex ?? 0;

    return ListView.builder(
      key: const PageStorageKey('queue_list'),
      padding: Spacing.paddingH8,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isCurrentItem = index == currentIndex;
        final isPastItem = index < currentIndex;
        final isDragging = _dragIndex == index;

        return Opacity(
          opacity: isDragging ? 0.3 : 1.0,
          child: _buildDismissibleItem(item, index, isCurrentItem, isPastItem),
        );
      },
    );
  }

  Widget _buildDismissibleItem(QueueItem item, int index, bool isCurrentItem, bool isPastItem) {
    return Dismissible(
      key: ValueKey(item.queueItemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.zero,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      confirmDismiss: (direction) async => !isCurrentItem,
      onDismissed: (direction) => _handleDelete(item, index),
      child: _buildQueueItemWithDragHandle(item, index, isCurrentItem, isPastItem),
    );
  }

  Widget _buildQueueItemWithDragHandle(QueueItem item, int index, bool isCurrentItem, bool isPastItem) {
    final originalIndex = index; // Capture for drag end

    return Builder(
      builder: (itemContext) => _buildQueueItemContent(
        item,
        index,
        isCurrentItem,
        isPastItem,
        dragHandle: isCurrentItem
            ? Icon(Icons.play_arrow_rounded, color: widget.primaryColor, size: 20)
            : GestureDetector(
                onVerticalDragStart: (details) {
                  _startDrag(index, itemContext, details.localPosition.dy);
                },
                onVerticalDragUpdate: (details) {
                  _updateDrag(details.delta.dy);
                },
                onVerticalDragEnd: (details) {
                  _endDrag(originalIndex);
                },
                onVerticalDragCancel: () {
                  _cancelDrag();
                },
                child: Icon(Icons.drag_handle, color: widget.textColor.withOpacity(0.3), size: 20),
              ),
      ),
    );
  }

  Widget _buildQueueItemContent(QueueItem item, int index, bool isCurrentItem, bool isPastItem, {Widget? dragHandle}) {
    final imageUrl = widget.maProvider.api?.getImageUrl(item.track, size: 80);
    final duration = _formatDuration(item.track.duration);

    return RepaintBoundary(
      child: Opacity(
        opacity: isPastItem ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: isCurrentItem ? widget.primaryColor.withOpacity(0.15) : widget.backgroundColor,
            borderRadius: BorderRadius.zero,
          ),
          child: ListTile(
            dense: true,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(
                width: 44,
                height: 44,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 176,
                        memCacheHeight: 176,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => Container(
                          color: widget.textColor.withOpacity(0.1),
                          child: Icon(Icons.music_note, color: widget.textColor.withOpacity(0.3), size: 20),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: widget.textColor.withOpacity(0.1),
                          child: Icon(Icons.music_note, color: widget.textColor.withOpacity(0.3), size: 20),
                        ),
                      )
                    : Container(
                        color: widget.textColor.withOpacity(0.1),
                        child: Icon(Icons.music_note, color: widget.textColor.withOpacity(0.3), size: 20),
                      ),
              ),
            ),
            title: Text(
              item.track.name,
              style: TextStyle(
                color: isCurrentItem ? widget.primaryColor : widget.textColor,
                fontSize: 14,
                fontWeight: isCurrentItem ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: item.track.artists != null && item.track.artists!.isNotEmpty
                ? Text(
                    item.track.artists!.first.name,
                    style: TextStyle(
                      color: widget.textColor.withOpacity(0.6),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (duration.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      duration,
                      style: TextStyle(
                        color: widget.textColor.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                dragHandle ?? Icon(Icons.drag_handle, color: widget.textColor.withOpacity(0.3), size: 20),
              ],
            ),
            onTap: () {
              // TODO: Jump to this track in queue if MA API supports it
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(QueueItem item, int index, Animation<double> animation, {bool removing = false}) {
    return SizeTransition(
      sizeFactor: animation,
      child: _buildQueueItemContent(item, index, false, false),
    );
  }
}
