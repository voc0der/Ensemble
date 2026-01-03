import 'package:flutter/material.dart';

/// A scrollbar that shows a letter popup when dragging, for fast navigation
/// through alphabetically sorted lists.
class LetterScrollbar extends StatefulWidget {
  /// The scrollable child widget (ListView, GridView, etc.)
  final Widget child;

  /// The scroll controller for the child
  final ScrollController controller;

  /// List of items to extract letters from (must be sorted alphabetically)
  /// Each item's first character is used to determine the letter
  final List<String> items;

  /// Callback when user taps/drags to a specific index
  final void Function(int index)? onScrollToIndex;

  const LetterScrollbar({
    super.key,
    required this.child,
    required this.controller,
    required this.items,
    this.onScrollToIndex,
  });

  @override
  State<LetterScrollbar> createState() => _LetterScrollbarState();
}

class _LetterScrollbarState extends State<LetterScrollbar> {
  bool _isDragging = false;
  String _currentLetter = '';
  double _dragPosition = 0;

  // Build a map of letter -> first index for that letter
  Map<String, int> get _letterIndexMap {
    final map = <String, int>{};
    for (int i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      if (item.isNotEmpty) {
        final letter = item[0].toUpperCase();
        if (!map.containsKey(letter)) {
          map[letter] = i;
        }
      }
    }
    return map;
  }

  String _getLetterAtPosition(double position, double maxHeight) {
    if (widget.items.isEmpty || maxHeight <= 0) return '';

    // Calculate which item index corresponds to this position
    final fraction = (position / maxHeight).clamp(0.0, 1.0);
    final index = (fraction * (widget.items.length - 1)).round();

    if (index >= 0 && index < widget.items.length) {
      final item = widget.items[index];
      if (item.isNotEmpty) {
        return item[0].toUpperCase();
      }
    }
    return '';
  }

  void _scrollToLetter(String letter) {
    final letterMap = _letterIndexMap;
    if (letterMap.containsKey(letter)) {
      final index = letterMap[letter]!;
      if (widget.onScrollToIndex != null) {
        widget.onScrollToIndex!(index);
      } else {
        // Estimate scroll position based on index
        // This is approximate - works better with fixed height items
        final scrollController = widget.controller;
        if (scrollController.hasClients) {
          final maxScroll = scrollController.position.maxScrollExtent;
          final fraction = index / widget.items.length;
          final targetScroll = (fraction * maxScroll).clamp(0.0, maxScroll);
          scrollController.animateTo(
            targetScroll,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragPosition = details.localPosition.dy;
    });
    _updateLetterAndScroll(details.localPosition.dy);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition = details.localPosition.dy;
    });
    _updateLetterAndScroll(details.localPosition.dy);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
  }

  void _updateLetterAndScroll(double position) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      final letter = _getLetterAtPosition(position, height);
      if (letter.isNotEmpty && letter != _currentLetter) {
        setState(() {
          _currentLetter = letter;
        });
        _scrollToLetter(letter);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // The scrollable content
        widget.child,

        // The draggable scrollbar area (right edge)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            onVerticalDragStart: _handleDragStart,
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: _handleDragEnd,
            onTapDown: (details) {
              _handleDragStart(DragStartDetails(
                localPosition: details.localPosition,
                globalPosition: details.globalPosition,
              ));
            },
            onTapUp: (_) {
              setState(() {
                _isDragging = false;
              });
            },
            behavior: HitTestBehavior.translucent,
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _isDragging ? 4 : 3,
                  height: _isDragging ? 60 : 40,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),

        // The letter popup bubble
        if (_isDragging && _currentLetter.isNotEmpty)
          Positioned(
            right: 40,
            top: _dragPosition - 28,
            child: Material(
              elevation: 4,
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                child: Text(
                  _currentLetter,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
