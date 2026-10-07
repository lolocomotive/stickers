import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Lets the user select a range of [DragSelectItem]s by long-pressing one and dragging.
///
/// Items start a drag by calling [DragSelectRegion.start] from their long press handler.
class DragSelectRegion extends StatefulWidget {
  final Widget child;
  final Set<int> Function() selection;
  final ValueChanged<Set<int>> onSelectionChanged;

  const DragSelectRegion({
    super.key,
    required this.child,
    required this.selection,
    required this.onSelectionChanged,
  });

  /// Starts a drag selection anchored at [index]. [context] must be below the scrollable holding the items.
  static void start(BuildContext context, int index) {
    context.findAncestorStateOfType<_DragSelectRegionState>()?._start(context, index);
  }

  @override
  State<DragSelectRegion> createState() => _DragSelectRegionState();
}

class _DragSelectRegionState extends State<DragSelectRegion> {
  static const double _edgeSize = 64;
  static const double _maxScrollSpeed = 14;

  int? _anchor;
  int? _current;
  bool _selecting = true;
  Set<int> _initial = {};
  ScrollPosition? _position;
  Offset? _lastGlobal;
  Timer? _scrollTimer;

  void _start(BuildContext itemContext, int index) {
    _initial = widget.selection().toSet();
    _anchor = index;
    _current = index;
    _selecting = !_initial.contains(index);
    _position = Scrollable.maybeOf(itemContext)?.position;
    _apply();
  }

  void _end() {
    _anchor = null;
    _current = null;
    _lastGlobal = null;
    _position = null;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _apply() {
    final low = min(_anchor!, _current!);
    final high = max(_anchor!, _current!);
    final next = _initial.toSet();
    for (int i = low; i <= high; i++) {
      _selecting ? next.add(i) : next.remove(i);
    }
    widget.onSelectionChanged(next);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_anchor == null) return;
    _lastGlobal = event.position;
    _updateAt(event.position);
    if (_scrollTimer == null && _scrollSpeed() != 0) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScroll());
    }
  }

  void _updateAt(Offset global) {
    if (_anchor == null || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderDragSelectItem) {
        if (target.index != _current) {
          _current = target.index;
          _apply();
        }
        return;
      }
    }
  }

  double _scrollSpeed() {
    final box = context.findRenderObject() as RenderBox?;
    if (_lastGlobal == null || _position == null || box == null || !box.hasSize) return 0;
    final dy = box.globalToLocal(_lastGlobal!).dy;
    final height = box.size.height;
    if (dy < _edgeSize) {
      return -_maxScrollSpeed * ((_edgeSize - dy) / _edgeSize).clamp(0.0, 1.0);
    }
    if (dy > height - _edgeSize) {
      return _maxScrollSpeed * ((dy - (height - _edgeSize)) / _edgeSize).clamp(0.0, 1.0);
    }
    return 0;
  }

  void _autoScroll() {
    final speed = _scrollSpeed();
    final position = _position;
    if (speed == 0 || position == null) {
      _scrollTimer?.cancel();
      _scrollTimer = null;
      return;
    }
    final target = (position.pixels + speed).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    position.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lastGlobal != null) _updateAt(_lastGlobal!);
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: widget.child,
    );
  }
}

/// The highlight drawn over selected items, shared so every selectable list looks the same.
BoxDecoration selectionDecoration(BuildContext context, {required double radius}) {
  final Color primary = Theme.of(context).colorScheme.primary;
  return BoxDecoration(
    color: primary.withValues(alpha: 0.2),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: primary, width: 3),
  );
}

/// Marks [child] as the item at [index] for an enclosing [DragSelectRegion].
class DragSelectItem extends SingleChildRenderObjectWidget {
  final int index;

  const DragSelectItem({super.key, required this.index, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderDragSelectItem(index);

  @override
  void updateRenderObject(BuildContext context, RenderDragSelectItem renderObject) {
    renderObject.index = index;
  }
}

class RenderDragSelectItem extends RenderProxyBoxWithHitTestBehavior {
  int index;

  RenderDragSelectItem(this.index) : super(behavior: HitTestBehavior.opaque);
}
