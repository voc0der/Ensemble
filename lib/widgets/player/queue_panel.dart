import 'dart:async';

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
  final VoidCallback? onSwipeStart;
  final ValueChanged<double>? onSwipeUpdate; // dx delta from start
  final ValueChanged<double>? onSwipeEnd; // velocity

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
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
  });

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  List<QueueItem> _items = [];
  final GlobalKey _stackKey = GlobalKey();

  // Drag state
  int? _dragIndex;
  int? _dragStartIndex;
  double _dragY = 0; // Y position of dragged item relative to Stack
  double _dragStartY = 0; // Y position when drag started (global)
  double _dragOffsetInItem = 0; // Offset of touch point within item
  QueueItem? _dragItem;
  double _itemHeight = 64.0;
  bool _pendingReorder = false; // True while waiting for API confirmation
  Timer? _pendingReorderTimer;

  // Optimistic update for tap-to-skip
  int? _optimisticCurrentIndex;

  // Swipe-to-close tracking (raw pointer events to bypass gesture arena)
  Offset? _swipeStart;
  Offset? _swipeLast;
  int? _swipeLastTime; // milliseconds since epoch
  bool _isSwiping = false;
  static const _swipeMinDistance = 10.0; // Min distance to start tracking


  @override
  void initState() {
    super.initState();
    _items = List.from(widget.queue?.items ?? []);
  }

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Clear optimistic state when server catches up
    if (_optimisticCurrentIndex != null) {
      final serverIndex = widget.queue?.currentIndex;
      if (serverIndex == _optimisticCurrentIndex) {
        // Server caught up - clear optimistic state
        _optimisticCurrentIndex = null;
      }
    }

    // Don't update items while dragging or waiting for reorder confirmation
    if (_dragIndex != null || _pendingReorder) return;

    final newItems = widget.queue?.items ?? [];

    // Only sync when player changes or item count changes (additions/deletions)
    // Don't sync on order changes - trust our local order after user reorders
    // This prevents stale server state from overwriting recent local changes
    final playerChanged = widget.queue?.playerId != oldWidget.queue?.playerId;
    final countChanged = newItems.length != _items.length;

    if (playerChanged || countChanged) {
      setState(() {
        _items = List.from(newItems);
      });
    }
  }

  @override
  void dispose() {
    _pendingReorderTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleDelete(QueueItem item, int index) async {
    // Remove from local list - Dismissible handles the animation
    setState(() {
      _items.removeAt(index);
    });

    // Call API
    final playerId = widget.queue?.playerId;
    if (playerId != null) {
      widget.maProvider.api?.queueCommandDeleteItem(playerId, item.queueItemId);
    }
  }

  void _handleClearQueue() async {
    final playerId = widget.queue?.playerId;
    if (playerId == null) return;

    // Optimistic update - clear local list
    setState(() {
      _items.clear();
    });

    // Call API
    try {
      await widget.maProvider.api?.queueCommandClear(playerId);
    } catch (e) {
      debugPrint('QueuePanel: Error clearing queue: $e');
      // Refresh to restore if failed
      widget.onRefresh();
    }
  }

  void _resetSwipeState() {
    _swipeStart = null;
    _swipeLast = null;
    _swipeLastTime = null;
    _isSwiping = false;
  }

  void _startDrag(int index, BuildContext itemContext, Offset globalPosition) {
    if (_dragIndex != null) return;

    // Clear any pending swipe state to prevent conflicts
    _resetSwipeState();

    final RenderBox itemBox = itemContext.findRenderObject() as RenderBox;
    final Offset itemGlobalPos = itemBox.localToGlobal(Offset.zero);
    _itemHeight = itemBox.size.height;

    // Get Stack's global position for proper coordinate conversion
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final stackGlobalPos = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    // Calculate initial position relative to Stack
    _dragY = itemGlobalPos.dy - stackGlobalPos.dy;
    _dragStartY = globalPosition.dy;
    // Remember where in the item the touch started (for smooth following)
    _dragOffsetInItem = globalPosition.dy - itemGlobalPos.dy;

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

    // Get Stack's global position
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final stackGlobalPos = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    // Calculate overlay position relative to Stack, accounting for touch offset
    _dragY = globalPosition.dy - stackGlobalPos.dy - _dragOffsetInItem;

    // Calculate which index we're hovering over based on movement from start
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

    // Cancel any existing timer to prevent stacking
    _pendingReorderTimer?.cancel();

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
      // API uses relative shift: positive = down, negative = up
      final posShift = newIndex - originalIndex;
      debugPrint('QueuePanel: Moving ${item.track.name} from $originalIndex to $newIndex (shift: $posShift, queueItemId: ${item.queueItemId})');
      if (playerId != null) {
        try {
          await widget.maProvider.api?.queueCommandMoveItem(playerId, item.queueItemId, posShift);
          debugPrint('QueuePanel: Move API call completed');
        } catch (e) {
          debugPrint('QueuePanel: Move API error: $e');
        }
      } else {
        debugPrint('QueuePanel: playerId is null, cannot move');
      }
      // Allow updates again after a delay for server state to propagate
      _pendingReorderTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            _pendingReorder = false;
          });
        }
      });
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

  void _handleTapToSkip(QueueItem item, int index, bool isCurrentItem) async {
    if (isCurrentItem) return;

    final playerId = widget.queue?.playerId;
    if (playerId == null) return;

    // Optimistic update: immediately show tapped track as current
    setState(() {
      _optimisticCurrentIndex = index;
    });

    // Call API
    try {
      await widget.maProvider.api?.queueCommandPlayIndex(playerId, item.queueItemId);
    } catch (e) {
      debugPrint('QueuePanel: Error playing index: $e');
    }

    // Clear optimistic state after delay - server state will take over
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _optimisticCurrentIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Listener for raw pointer events to bypass gesture arena
    // This allows swipe-to-close to work even over ListView/Dismissible
    return Listener(
      onPointerDown: (event) {
        // Don't track swipe while dragging a queue item
        if (_dragIndex == null) {
          _swipeStart = event.position;
          _swipeLast = event.position;
          _swipeLastTime = DateTime.now().millisecondsSinceEpoch;
          _isSwiping = false;
        }
      },
      onPointerMove: (event) {
        if (_swipeStart == null || _dragIndex != null) return;

        final dx = event.position.dx - _swipeStart!.dx;
        final dy = (event.position.dy - _swipeStart!.dy).abs();

        // Check if this is a horizontal swipe (dx > dy * 1.5 for more tolerance)
        final isHorizontal = dx.abs() > _swipeMinDistance && dx.abs() > dy * 1.5;

        if (isHorizontal && dx > 0) {
          // Horizontal swipe right - close gesture
          if (!_isSwiping) {
            _isSwiping = true;
            widget.onSwipeStart?.call();
          }
          // Track position for velocity calculation
          _swipeLast = event.position;
          _swipeLastTime = DateTime.now().millisecondsSinceEpoch;
          widget.onSwipeUpdate?.call(dx);
        } else if (_isSwiping && !isHorizontal) {
          // Was swiping but direction changed to vertical - cancel
          widget.onSwipeEnd?.call(0); // Zero velocity = snap back
          _isSwiping = false;
        }
      },
      onPointerUp: (event) {
        if (_isSwiping && _swipeLast != null && _swipeLastTime != null) {
          // Calculate instantaneous velocity from recent movement
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsed = now - _swipeLastTime!;
          final dx = event.position.dx - _swipeLast!.dx;
          // Use instantaneous velocity, fallback to reasonable default
          final velocity = elapsed > 0 && elapsed < 100
              ? (dx / elapsed) * 1000
              : (event.position.dx - _swipeStart!.dx) > 100 ? 500.0 : 0.0;
          widget.onSwipeEnd?.call(velocity);
        }
        _resetSwipeState();
      },
      onPointerCancel: (_) {
        if (_isSwiping) {
          widget.onSwipeEnd?.call(0); // Cancel with zero velocity = snap back
        }
        _resetSwipeState();
      },
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
                  // Clear queue button
                  IconButton(
                    icon: Icon(Icons.delete_sweep_rounded, color: widget.textColor.withOpacity(0.7), size: IconSizes.sm),
                    onPressed: _handleClearQueue,
                    padding: Spacing.paddingAll12,
                    tooltip: 'Clear queue',
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
                            key: _stackKey,
                            children: [
                              _buildQueueList(),
                              // Dragged item overlay
                              if (_dragIndex != null && _dragItem != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  top: _dragY,
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
    // Use optimistic index if set, otherwise use server state
    final currentIndex = _optimisticCurrentIndex ?? widget.queue!.currentIndex ?? 0;

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
            : SizedBox(
                width: 32,
                height: 48,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _startDrag(index, itemContext, event.position);
                  },
                  // Move/up/cancel handled by parent Listener on Stack
                  child: Center(
                    child: Icon(Icons.drag_handle, color: widget.textColor.withOpacity(0.3), size: 20),
                  ),
                ),
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
          margin: isCurrentItem ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isCurrentItem ? widget.primaryColor.withOpacity(0.15) : widget.backgroundColor,
            borderRadius: isCurrentItem ? BorderRadius.circular(12) : BorderRadius.zero,
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
            onTap: () => _handleTapToSkip(item, index, isCurrentItem),
          ),
        ),
      ),
    );
  }
}
