import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
    this.controller,
    this.customPreview,
    this.rotationDegrees = 0,
    required this.aspectRatio,
    required this.onCropChanged,
    this.onTapVideo,
    this.btnOpacity = 1.0,
    this.videoAspectRatio,
  });

  final VideoPlayerController? controller;
  final Widget? customPreview;
  final int rotationDegrees;
  final double? aspectRatio;
  final ValueChanged<Rect> onCropChanged;
  final VoidCallback? onTapVideo;
  final double btnOpacity;
  final double? videoAspectRatio;

  static Rect calculateAspectCropRect(Rect bounds, double? targetRatio) {
    if (bounds.width <= 0 || bounds.height <= 0) return Rect.zero;
    if (targetRatio == null) {
      return bounds;
    }
    double w, h;
    final containerRatio = bounds.width / bounds.height;
    if (containerRatio > targetRatio) {
      h = bounds.height;
      w = h * targetRatio;
    } else {
      w = bounds.width;
      h = w / targetRatio;
    }
    final left = bounds.left + (bounds.width - w) / 2.0;
    final top = bounds.top + (bounds.height - h) / 2.0;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  State<VideoCropOverlay> createState() => VideoCropOverlayState();
}

class VideoCropOverlayState extends State<VideoCropOverlay> with TickerProviderStateMixin {
  static const EdgeInsets _cropPadding = EdgeInsets.all(32.0);

  late final AnimationController _maskColorController;
  late final AnimationController _autoCenterController;
  late final CurvedAnimation _autoCenterCurvedAnimation;

  Rect? _cropRect;
  Rect? _videoRect;
  Size _lastViewportSize = Size.zero;

  Rect _animStartCrop = Rect.zero;
  Rect _animEndCrop = Rect.zero;
  Rect _animStartVideo = Rect.zero;
  Rect _animEndVideo = Rect.zero;

  _CropHandle _activeHandle = _CropHandle.none;
  Offset _dragStart = Offset.zero;
  Rect _cropRectAtStart = Rect.zero;
  bool _pointerDown = false;
  double _totalDragDist = 0;

  double get _displayedAspectRatio {
    double baseAspect = 1.0;
    if (widget.videoAspectRatio != null && widget.videoAspectRatio! > 0) {
      baseAspect = widget.videoAspectRatio!;
    } else if (widget.controller != null &&
        widget.controller!.value.isInitialized &&
        widget.controller!.value.aspectRatio > 0) {
      baseAspect = widget.controller!.value.aspectRatio;
    }
    if (widget.rotationDegrees % 180 != 0) {
      return 1.0 / baseAspect;
    }
    return baseAspect;
  }

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

    _autoCenterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _autoCenterCurvedAnimation = CurvedAnimation(
      parent: _autoCenterController,
      curve: Curves.easeInOutCubic,
    );
    _autoCenterController.addListener(() {
      final t = _autoCenterCurvedAnimation.value;
      _cropRect = Rect.lerp(_animStartCrop, _animEndCrop, t)!;
      _videoRect = Rect.lerp(_animStartVideo, _animEndVideo, t)!;
      setState(() {});
    });
    _autoCenterController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _notifyCropChanged();
      }
    });
  }

  @override
  void didUpdateWidget(VideoCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.aspectRatio != oldWidget.aspectRatio &&
        _videoRect != null &&
        _cropRect != null &&
        _lastViewportSize != Size.zero) {
      _applyAspectRatio(widget.aspectRatio);
    }
  }

  @override
  void dispose() {
    _maskColorController.dispose();
    _autoCenterController.dispose();
    super.dispose();
  }

  void _initLayoutIfNeeded(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;

    if (_lastViewportSize != viewportSize) {
      _lastViewportSize = viewportSize;
      final layoutRect = _cropPadding.deflateRect(Offset.zero & viewportSize);
      final videoAspect = _displayedAspectRatio;

      final initialVideo = getDestinationRect(
        rect: layoutRect,
        inputSize: Size(videoAspect, 1.0),
        fit: BoxFit.contain,
      );

      final initialCrop = VideoCropOverlay.calculateAspectCropRect(
        initialVideo,
        widget.aspectRatio,
      );

      // Auto-center initial crop so it fills layoutRect
      final (targetCrop, targetVideo) = _fitToViewport(initialCrop, initialVideo);
      _cropRect = targetCrop;
      _videoRect = targetVideo;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notifyCropChanged();
        }
      });
    }
  }

  void _applyAspectRatio(double? ratio) {
    if (_lastViewportSize == Size.zero || _videoRect == null || _cropRect == null) return;
    final newCrop = VideoCropOverlay.calculateAspectCropRect(_cropRect!, ratio);
    final (targetCrop, targetVideo) = _fitToViewport(newCrop, _videoRect!);
    _startAutoCenterAnimation(_cropRect!, targetCrop, _videoRect!, targetVideo);
  }

  /// Scales and moves [crop] so it fills the padded viewport, and applies the same transform to [video].
  (Rect, Rect) _fitToViewport(Rect crop, Rect video) {
    final layoutRect = _cropPadding.deflateRect(Offset.zero & _lastViewportSize);
    final targetCrop = getDestinationRect(
      rect: layoutRect,
      inputSize: crop.size,
      fit: BoxFit.contain,
    );
    final scale = targetCrop.width / crop.width;
    final targetVideo = Rect.fromLTWH(
      targetCrop.center.dx - (crop.center.dx - video.left) * scale,
      targetCrop.center.dy - (crop.center.dy - video.top) * scale,
      video.width * scale,
      video.height * scale,
    );
    return (targetCrop, targetVideo);
  }

  void _startAutoCenterAnimation(Rect startCrop, Rect endCrop, Rect startVideo, Rect endVideo) {
    _animStartCrop = startCrop;
    _animEndCrop = endCrop;
    _animStartVideo = startVideo;
    _animEndVideo = endVideo;
    _autoCenterController.forward(from: 0.0);
  }

  void _notifyCropChanged() {
    if (_cropRect == null || _videoRect == null || _videoRect!.width <= 0 || _videoRect!.height <= 0) return;
    final cropLeft = ((_cropRect!.left - _videoRect!.left) / _videoRect!.width).clamp(0.0, 1.0);
    final cropTop = ((_cropRect!.top - _videoRect!.top) / _videoRect!.height).clamp(0.0, 1.0);
    final cropRight = ((_cropRect!.right - _videoRect!.left) / _videoRect!.width).clamp(0.0, 1.0);
    final cropBottom = ((_cropRect!.bottom - _videoRect!.top) / _videoRect!.height).clamp(0.0, 1.0);
    final normalized = Rect.fromLTRB(cropLeft, cropTop, cropRight, cropBottom);
    widget.onCropChanged(normalized);
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
    if (_cropRect == null || _videoRect == null) return;
    if (_autoCenterController.isAnimating) {
      _autoCenterController.stop();
    }
    _dragStart = event.localPosition;
    _cropRectAtStart = _cropRect!;
    _totalDragDist = 0;
    _activeHandle = _hitTest(event.localPosition, _cropRect!);
    _pointerDown = true;
    _maskColorController.animateTo(0);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_cropRect == null || _videoRect == null || _activeHandle == _CropHandle.none) return;
    final delta = event.localPosition - _dragStart;
    _totalDragDist += event.delta.distance;
    final updated = _calculateNewRect(_activeHandle, _cropRectAtStart, delta, _videoRect!, widget.aspectRatio);
    setState(() {
      _cropRect = updated;
    });
    _notifyCropChanged();
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
      return;
    }

    if (_cropRect == null || _videoRect == null || _lastViewportSize == Size.zero) return;

    // Trigger auto-centering on release
    final (targetCrop, targetVideo) = _fitToViewport(_cropRect!, _videoRect!);

    final dx = (targetCrop.center.dx - _cropRect!.center.dx).abs();
    final dy = (targetCrop.center.dy - _cropRect!.center.dy).abs();
    final dw = (targetCrop.width - _cropRect!.width).abs();

    if (dx > 1.0 || dy > 1.0 || dw > 1.0) {
      _startAutoCenterAnimation(_cropRect!, targetCrop, _videoRect!, targetVideo);
    }
  }

  Rect _calculateNewRect(
    _CropHandle handle,
    Rect startRect,
    Offset delta,
    Rect bounds,
    double? targetRatio,
  ) {
    const minSize = 40.0;

    if (handle == _CropHandle.center) {
      final w = startRect.width;
      final h = startRect.height;
      final left = (startRect.left + delta.dx).clamp(bounds.left, max<double>(bounds.left, bounds.right - w));
      final top = (startRect.top + delta.dy).clamp(bounds.top, max<double>(bounds.top, bounds.bottom - h));
      return Rect.fromLTWH(left, top, w, h);
    }

    if (targetRatio == null) {
      double left = startRect.left;
      double top = startRect.top;
      double right = startRect.right;
      double bottom = startRect.bottom;

      switch (handle) {
        case _CropHandle.topLeft:
          left = (startRect.left + delta.dx).clamp(bounds.left, right - minSize);
          top = (startRect.top + delta.dy).clamp(bounds.top, bottom - minSize);
          break;
        case _CropHandle.topRight:
          right = (startRect.right + delta.dx).clamp(left + minSize, bounds.right);
          top = (startRect.top + delta.dy).clamp(bounds.top, bottom - minSize);
          break;
        case _CropHandle.bottomLeft:
          left = (startRect.left + delta.dx).clamp(bounds.left, right - minSize);
          bottom = (startRect.bottom + delta.dy).clamp(top + minSize, bounds.bottom);
          break;
        case _CropHandle.bottomRight:
          right = (startRect.right + delta.dx).clamp(left + minSize, bounds.right);
          bottom = (startRect.bottom + delta.dy).clamp(top + minSize, bounds.bottom);
          break;
        case _CropHandle.top:
          top = (startRect.top + delta.dy).clamp(bounds.top, bottom - minSize);
          break;
        case _CropHandle.bottom:
          bottom = (startRect.bottom + delta.dy).clamp(top + minSize, bounds.bottom);
          break;
        case _CropHandle.left:
          left = (startRect.left + delta.dx).clamp(bounds.left, right - minSize);
          break;
        case _CropHandle.right:
          right = (startRect.right + delta.dx).clamp(left + minSize, bounds.right);
          break;
        default:
          break;
      }
      return Rect.fromLTRB(left, top, right, bottom);
    }

    // Ratio-constrained resizing
    switch (handle) {
      case _CropHandle.bottomRight:
        {
          final maxW = min(bounds.right - startRect.left, (bounds.bottom - startRect.top) * targetRatio);
          final w = (startRect.width + delta.dx).clamp(minSize, max<double>(minSize, maxW));
          final h = w / targetRatio;
          return Rect.fromLTWH(startRect.left, startRect.top, w, h);
        }
      case _CropHandle.bottomLeft:
        {
          final maxW = min(startRect.right - bounds.left, (bounds.bottom - startRect.top) * targetRatio);
          final w = (startRect.width - delta.dx).clamp(minSize, max<double>(minSize, maxW));
          final h = w / targetRatio;
          return Rect.fromLTWH(startRect.right - w, startRect.top, w, h);
        }
      case _CropHandle.topRight:
        {
          final maxW = min(bounds.right - startRect.left, (startRect.bottom - bounds.top) * targetRatio);
          final w = (startRect.width + delta.dx).clamp(minSize, max<double>(minSize, maxW));
          final h = w / targetRatio;
          return Rect.fromLTWH(startRect.left, startRect.bottom - h, w, h);
        }
      case _CropHandle.topLeft:
        {
          final maxW = min(startRect.right - bounds.left, (startRect.bottom - bounds.top) * targetRatio);
          final w = (startRect.width - delta.dx).clamp(minSize, max<double>(minSize, maxW));
          final h = w / targetRatio;
          return Rect.fromLTWH(startRect.right - w, startRect.bottom - h, w, h);
        }
      case _CropHandle.bottom:
        {
          double h = (startRect.height + delta.dy).clamp(minSize / targetRatio, bounds.bottom - startRect.top);
          double w = h * targetRatio;
          if (w > bounds.width) {
            w = bounds.width;
            h = w / targetRatio;
          }
          double left = startRect.center.dx - w / 2.0;
          if (left < bounds.left) left = bounds.left;
          if (left + w > bounds.right) left = bounds.right - w;
          return Rect.fromLTWH(left, startRect.top, w, h);
        }
      case _CropHandle.top:
        {
          double h = (startRect.height - delta.dy).clamp(minSize / targetRatio, startRect.bottom - bounds.top);
          double w = h * targetRatio;
          if (w > bounds.width) {
            w = bounds.width;
            h = w / targetRatio;
          }
          double left = startRect.center.dx - w / 2.0;
          if (left < bounds.left) left = bounds.left;
          if (left + w > bounds.right) left = bounds.right - w;
          return Rect.fromLTWH(left, startRect.bottom - h, w, h);
        }
      case _CropHandle.right:
        {
          double w = (startRect.width + delta.dx).clamp(minSize, bounds.right - startRect.left);
          double h = w / targetRatio;
          if (h > bounds.height) {
            h = bounds.height;
            w = h * targetRatio;
          }
          double top = startRect.center.dy - h / 2.0;
          if (top < bounds.top) top = bounds.top;
          if (top + h > bounds.bottom) top = bounds.bottom - h;
          return Rect.fromLTWH(startRect.left, top, w, h);
        }
      case _CropHandle.left:
        {
          double w = (startRect.width - delta.dx).clamp(minSize, startRect.right - bounds.left);
          double h = w / targetRatio;
          if (h > bounds.height) {
            h = bounds.height;
            w = h * targetRatio;
          }
          double top = startRect.center.dy - h / 2.0;
          if (top < bounds.top) top = bounds.top;
          if (top + h > bounds.bottom) top = bounds.bottom - h;
          return Rect.fromLTWH(startRect.right - w, top, w, h);
        }
      default:
        return startRect;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        _initLayoutIfNeeded(viewportSize);

        if (_cropRect == null || _videoRect == null) {
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Video Player or Custom Preview positioned at _videoRect
              Positioned(
                left: _videoRect!.left,
                top: _videoRect!.top,
                width: _videoRect!.width,
                height: _videoRect!.height,
                child: RotatedBox(
                  quarterTurns: widget.rotationDegrees ~/ 90,
                  child: widget.controller != null
                      ? VideoPlayer(widget.controller!)
                      : widget.customPreview ?? Container(color: Colors.black),
                ),
              ),
              // 2. Crop layer painter with mask, grid lines, and corners
              Positioned.fill(
                child: CustomPaint(
                  size: viewportSize,
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
              ),
              // 3. Play / Pause button centered at cropRect.center
              if (widget.controller != null || widget.onTapVideo != null)
                Positioned(
                  left: _cropRect!.center.dx - 40,
                  top: _cropRect!.center.dy - 40,
                  width: 80,
                  height: 80,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: widget.btnOpacity,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        (widget.controller?.value.isPlaying ?? false) ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 32)],
                        size: 80,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
