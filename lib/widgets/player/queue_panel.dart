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
  final ValueChanged<bool>? onDraggingChanged;

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
    this.onDraggingChanged,
  });

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  List<QueueItem> _items = [];

  // Drag state
  int? _dragIndex;
  int? _dragStartIndex;
  double _dragY = 0; // Y position of dragged item relative to screen
  double _dragStartY = 0; // Y position when drag started
  double _itemStartY = 0; // Initial Y of the item being dragged
  QueueItem? _dragItem;
  double _itemHeight = 64.0;
  double _listTopOffset = 0; // Offset of the list from top of stack
  bool _pendingReorder = false; // True while waiting for API confirmation

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

    // Don't update items while dragging or waiting for reorder confirmation
    if (_dragIndex != null || _pendingReorder) return;

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

  void _startDrag(int index, BuildContext itemContext, Offset globalPosition) {
    if (_dragIndex != null) return;

    final RenderBox box = itemContext.findRenderObject() as RenderBox;
    final Offset globalPos = box.localToGlobal(Offset.zero);
    _itemHeight = box.size.height;
    _itemStartY = globalPos.dy;
    _dragStartY = globalPosition.dy;
    _dragY = globalPos.dy;

    // Find the stack's position to calculate relative offset
    // The stack is the Expanded widget's child, we need its global offset
    _listTopOffset = globalPos.dy - (index * _itemHeight);

    setState(() {
      _dragIndex = index;
      _dragStartIndex = index;
      _dragItem = _items[index];
    });

    // Notify parent that drag started
    widget.onDraggingChanged?.call(true);
  }

  void _updateDragPointer(Offset globalPosition) {
    if (_dragIndex == null) return;

    // Move overlay to follow finger
    _dragY = _itemStartY + (globalPosition.dy - _dragStartY);

    // Calculate which index we're hovering over based on movement
    final totalOffset = globalPosition.dy - _dragStartY;
    final indexOffset = (totalOffset / _itemHeight).round();
    final targetIndex = (_dragStartIndex! + indexOffset).clamp(0, _items.length - 1);

    if (targetIndex != _dragIndex) {
      // Reorder items in the list
      setState(() {
        final item = _items.removeAt(_dragIndex!);
        _items.insert(targetIndex, item);
        _dragIndex = targetIndex;
      });
    } else {
      // Just update position
      setState(() {});
    }
  }

  void _endDrag() async {
    if (_dragIndex == null || _dragStartIndex == null) return;

    final newIndex = _dragIndex!;
    final originalIndex = _dragStartIndex!;
    final item = _items[newIndex];
    final positionChanged = originalIndex != newIndex;

    setState(() {
      _dragIndex = null;
      _dragStartIndex = null;
      _dragItem = null;
      // Block didUpdateWidget while waiting for server confirmation
      if (positionChanged) _pendingReorder = true;
    });

    // Notify parent that drag ended
    widget.onDraggingChanged?.call(false);

    // Call API if position changed
    if (positionChanged) {
      final playerId = widget.queue?.playerId;
      debugPrint('QueuePanel: Moving ${item.track.name} from $originalIndex to $newIndex (queueItemId: ${item.queueItemId})');
      if (playerId != null) {
        try {
          await widget.maProvider.api?.queueCommandMoveItem(playerId, item.queueItemId, newIndex);
          debugPrint('QueuePanel: Move API call completed');
        } catch (e) {
          debugPrint('QueuePanel: Move API error: $e');
        }
      } else {
        debugPrint('QueuePanel: playerId is null, cannot move');
      }
      // Allow updates again after a delay for server state to propagate
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _pendingReorder = false;
        });
      }
    }
  }

  void _cancelDrag() {
    if (_dragStartIndex == null) return;

    // Restore original position
    if (_dragIndex != null && _dragIndex != _dragStartIndex) {
      setState(() {
        final item = _items.removeAt(_dragIndex!);
        _items.insert(_dragStartIndex!, item);
      });
    }

    setState(() {
      _dragIndex = null;
      _dragStartIndex = null;
      _dragItem = null;
    });

    // Notify parent that drag ended
    widget.onDraggingChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        // Don't track swipe-to-close while dragging
        if (_dragIndex == null) {
          _pointerStart = event.position;
        }
      },
      onPointerMove: (event) {
        // Only check swipe-to-close if not dragging
        if (_pointerStart != null && _dragIndex == null) {
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
                      : Listener(
                          // Capture pointer events anywhere while dragging
                          onPointerMove: (event) {
                            if (_dragIndex != null) {
                              _updateDragPointer(event.position);
                            }
                          },
                          onPointerUp: (event) {
                            if (_dragIndex != null) {
                              _endDrag();
                            }
                          },
                          onPointerCancel: (event) {
                            if (_dragIndex != null) {
                              _cancelDrag();
                            }
                          },
                          child: Stack(
                            children: [
                              _buildQueueList(),
                              // Dragged item overlay
                              if (_dragIndex != null && _dragItem != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  top: _dragY - _listTopOffset,
                                  child: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(8),
                                    child: _buildQueueItemContent(_dragItem!, _dragIndex!, false, false),
                                  ),
                                ),
                            ],
                          ),
                        ),
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
      // Disable scrolling while dragging to prevent gesture conflict
      physics: _dragIndex != null
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
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
    return Builder(
      builder: (itemContext) => _buildQueueItemContent(
        item,
        index,
        isCurrentItem,
        isPastItem,
        dragHandle: isCurrentItem
            ? Icon(Icons.play_arrow_rounded, color: widget.primaryColor, size: 20)
            : Listener(
                onPointerDown: (event) {
                  _startDrag(index, itemContext, event.position);
                },
                // Move/up/cancel handled by parent Listener on Stack
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
