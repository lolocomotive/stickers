import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

enum _CropHandle {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
  center,
}

class VideoCropOverlay extends StatefulWidget {
  const VideoCropOverlay({
    super.key,
    required this.aspectRatio,
    required this.onCropChanged,
    this.onTapVideo,
  });

  final double? aspectRatio;
  final ValueChanged<Rect> onCropChanged;
  final VoidCallback? onTapVideo;

  static Rect calculateAspectCropRect(Size size, double? targetRatio) {
    if (size.width <= 0 || size.height <= 0) return Rect.zero;
    if (targetRatio == null) {
      return Offset.zero & size;
    }
    double w, h;
    final containerRatio = size.width / size.height;
    if (containerRatio > targetRatio) {
      h = size.height;
      w = h * targetRatio;
    } else {
      w = size.width;
      h = w / targetRatio;
    }
    final left = (size.width - w) / 2.0;
    final top = (size.height - h) / 2.0;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  State<VideoCropOverlay> createState() => VideoCropOverlayState();
}

class VideoCropOverlayState extends State<VideoCropOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _maskColorController;
  Rect? _cropRect;
  Size _lastSize = Size.zero;
  _CropHandle _activeHandle = _CropHandle.none;
  Offset _dragStart = Offset.zero;
  Rect _rectAtStart = Rect.zero;
  bool _pointerDown = false;
  double _totalDragDist = 0;

  Rect? get currentCropRect => _cropRect;

  @override
  void initState() {
    super.initState();
    _maskColorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );
    _maskColorController.addListener(() {
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(VideoCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.aspectRatio != oldWidget.aspectRatio && _lastSize != Size.zero) {
      _applyAspectRatio(widget.aspectRatio);
    }
  }

  @override
  void dispose() {
    _maskColorController.dispose();
    super.dispose();
  }

  void _applyAspectRatio(double? ratio) {
    if (_lastSize == Size.zero) return;
    final newRect = VideoCropOverlay.calculateAspectCropRect(_lastSize, ratio);
    setState(() {
      _cropRect = newRect;
    });
    widget.onCropChanged(newRect);
  }

  _CropHandle _hitTest(Offset pos, Rect rect) {
    const handleRadius = 32.0;
    const edgeRadius = 20.0;

    if ((pos - rect.topLeft).distance <= handleRadius) return _CropHandle.topLeft;
    if ((pos - rect.topRight).distance <= handleRadius) return _CropHandle.topRight;
    if ((pos - rect.bottomLeft).distance <= handleRadius) return _CropHandle.bottomLeft;
    if ((pos - rect.bottomRight).distance <= handleRadius) return _CropHandle.bottomRight;

    if ((pos.dy - rect.top).abs() <= edgeRadius && pos.dx >= rect.left && pos.dx <= rect.right) {
      return _CropHandle.top;
    }
    if ((pos.dy - rect.bottom).abs() <= edgeRadius && pos.dx >= rect.left && pos.dx <= rect.right) {
      return _CropHandle.bottom;
    }
    if ((pos.dx - rect.left).abs() <= edgeRadius && pos.dy >= rect.top && pos.dy <= rect.bottom) {
      return _CropHandle.left;
    }
    if ((pos.dx - rect.right).abs() <= edgeRadius && pos.dy >= rect.top && pos.dy <= rect.bottom) {
      return _CropHandle.right;
    }

    if (rect.contains(pos)) return _CropHandle.center;

    return _CropHandle.none;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_cropRect == null) return;
    _dragStart = event.localPosition;
    _rectAtStart = _cropRect!;
    _totalDragDist = 0;
    _activeHandle = _hitTest(event.localPosition, _cropRect!);
    _pointerDown = true;
    _maskColorController.animateTo(0);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_cropRect == null || _activeHandle == _CropHandle.none) return;
    final delta = event.localPosition - _dragStart;
    _totalDragDist += event.delta.distance;
    final updated = _calculateNewRect(_activeHandle, _rectAtStart, delta, _lastSize, widget.aspectRatio);
    setState(() {
      _cropRect = updated;
    });
    widget.onCropChanged(updated);
  }

  void _releasePointer() {
    _activeHandle = _CropHandle.none;
    _pointerDown = false;
    _maskColorController.animateTo(1);
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) => _releasePointer();

  void _onPointerUp(PointerUpEvent event) {
    final wasActive = _activeHandle;
    _releasePointer();

    if (_totalDragDist < 8 && (wasActive == _CropHandle.center || wasActive == _CropHandle.none)) {
      widget.onTapVideo?.call();
    }
  }

  Rect _calculateNewRect(
    _CropHandle handle,
    Rect startRect,
    Offset delta,
    Size bounds,
    double? targetRatio,
  ) {
    const minSize = 40.0;
    double left = startRect.left;
    double top = startRect.top;
    double right = startRect.right;
    double bottom = startRect.bottom;

    if (handle == _CropHandle.center) {
      final w = startRect.width;
      final h = startRect.height;
      left = (startRect.left + delta.dx).clamp(0.0, max(0.0, bounds.width - w));
      top = (startRect.top + delta.dy).clamp(0.0, max(0.0, bounds.height - h));
      right = left + w;
      bottom = top + h;
      return Rect.fromLTRB(left, top, right, bottom);
    }

    if (targetRatio == null) {
      switch (handle) {
        case _CropHandle.topLeft:
          left = (startRect.left + delta.dx).clamp(0.0, right - minSize);
          top = (startRect.top + delta.dy).clamp(0.0, bottom - minSize);
          break;
        case _CropHandle.topRight:
          right = (startRect.right + delta.dx).clamp(left + minSize, bounds.width);
          top = (startRect.top + delta.dy).clamp(0.0, bottom - minSize);
          break;
        case _CropHandle.bottomLeft:
          left = (startRect.left + delta.dx).clamp(0.0, right - minSize);
          bottom = (startRect.bottom + delta.dy).clamp(top + minSize, bounds.height);
          break;
        case _CropHandle.bottomRight:
          right = (startRect.right + delta.dx).clamp(left + minSize, bounds.width);
          bottom = (startRect.bottom + delta.dy).clamp(top + minSize, bounds.height);
          break;
        case _CropHandle.top:
          top = (startRect.top + delta.dy).clamp(0.0, bottom - minSize);
          break;
        case _CropHandle.bottom:
          bottom = (startRect.bottom + delta.dy).clamp(top + minSize, bounds.height);
          break;
        case _CropHandle.left:
          left = (startRect.left + delta.dx).clamp(0.0, right - minSize);
          break;
        case _CropHandle.right:
          right = (startRect.right + delta.dx).clamp(left + minSize, bounds.width);
          break;
        default:
          break;
      }
      return Rect.fromLTRB(left, top, right, bottom);
    }

    // Ratio-constrained resizing
    switch (handle) {
      case _CropHandle.bottomRight:
      case _CropHandle.right:
      case _CropHandle.bottom: {
        double w = (startRect.width + delta.dx).clamp(minSize, bounds.width - startRect.left);
        double h = w / targetRatio;
        if (startRect.top + h > bounds.height) {
          h = bounds.height - startRect.top;
          w = h * targetRatio;
        }
        return Rect.fromLTWH(startRect.left, startRect.top, max(minSize, w), max(minSize / targetRatio, h));
      }
      case _CropHandle.bottomLeft:
      case _CropHandle.left: {
        double w = (startRect.width - delta.dx).clamp(minSize, startRect.right);
        double h = w / targetRatio;
        if (startRect.top + h > bounds.height) {
          h = bounds.height - startRect.top;
          w = h * targetRatio;
        }
        return Rect.fromLTWH(startRect.right - max(minSize, w), startRect.top, max(minSize, w), max(minSize / targetRatio, h));
      }
      case _CropHandle.topRight:
      case _CropHandle.top: {
        double w = (startRect.width + delta.dx).clamp(minSize, bounds.width - startRect.left);
        double h = w / targetRatio;
        if (startRect.bottom - h < 0) {
          h = startRect.bottom;
          w = h * targetRatio;
        }
        return Rect.fromLTWH(startRect.left, startRect.bottom - max(minSize / targetRatio, h), max(minSize, w), max(minSize / targetRatio, h));
      }
      case _CropHandle.topLeft: {
        double w = (startRect.width - delta.dx).clamp(minSize, startRect.right);
        double h = w / targetRatio;
        if (startRect.bottom - h < 0) {
          h = startRect.bottom;
          w = h * targetRatio;
        }
        return Rect.fromLTWH(startRect.right - max(minSize, w), startRect.bottom - max(minSize / targetRatio, h), max(minSize, w), max(minSize / targetRatio, h));
      }
      default:
        return startRect;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final currentSize = constraints.biggest;
        if (_lastSize != currentSize && currentSize.width > 0 && currentSize.height > 0) {
          _lastSize = currentSize;
          if (_cropRect == null) {
            _cropRect = VideoCropOverlay.calculateAspectCropRect(currentSize, widget.aspectRatio);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _cropRect != null) {
                widget.onCropChanged(_cropRect!);
              }
            });
          }
        }

        if (_cropRect == null) {
          return const SizedBox.expand();
        }

        final maskColor = Color.lerp(
          Theme.of(context).colorScheme.surface.withAlpha(50),
          Theme.of(context).colorScheme.surface.withAlpha(200),
          _maskColorController.value,
        )!;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: CustomPaint(
            size: currentSize,
            painter: ExtendedImageCropLayerPainter(
              cropRect: _cropRect!,
              cropLayerPainter: const EditorCropLayerPainter(),
              lineColor: Theme.of(context).colorScheme.primary.withAlpha(100),
              cornerColor: Theme.of(context).colorScheme.primary,
              cornerSize: const Size(30, 5),
              lineHeight: 3,
              maskColor: maskColor,
              pointerDown: _pointerDown,
              rotateRadians: 0,
            ),
          ),
        );
      },
    );
  }
}
