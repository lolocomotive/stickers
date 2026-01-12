import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:stickers/src/video/frame_decoder.dart';

/// Controller for frame-based animation playback
/// Manages play/pause/seek state and frame timing
class FramePlayerController extends ChangeNotifier {
  final FrameDecoderService _decoder;

  bool _isPlaying = false;
  bool _isLooping = true;
  int _currentFrameIndex = 0;
  Duration _currentPosition = Duration.zero;
  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;
  // ignore: unused_field
  TickerProvider? _tickerProvider;
  bool _isDisposed = false;

  FramePlayerController(this._decoder);

  // Getters
  bool get isPlaying => _isPlaying;
  bool get isLooping => _isLooping;
  bool get isReady => _decoder.isReady;
  int get currentFrameIndex => _currentFrameIndex;
  Duration get currentPosition => _currentPosition;
  Duration get duration => _decoder.metadata?.totalDuration ?? Duration.zero;
  int get frameCount => _decoder.frames?.length ?? 0;
  double get fps => _decoder.metadata?.fps ?? 24;
  AnimationMetadata? get metadata => _decoder.metadata;
  List<DecodedFrame>? get frames => _decoder.frames;

  double get aspectRatio {
    final meta = _decoder.metadata;
    if (meta == null || meta.height == 0) return 1.0;
    return meta.width / meta.height;
  }

  /// Get the current frame to display
  DecodedFrame? get currentFrame {
    if (!isReady) return null;
    return _decoder.getFrame(_currentFrameIndex);
  }

  /// Initialize the controller with a TickerProvider
  void initialize(TickerProvider provider) {
    _tickerProvider = provider;
    _ticker = provider.createTicker(_onTick);
  }

  /// Start playback
  void play() {
    if (_isDisposed || !isReady || _isPlaying) return;
    _isPlaying = true;
    _lastTickTime = Duration.zero;
    _ticker?.start();
    _safeNotifyListeners();
  }

  /// Pause playback
  void pause() {
    if (_isDisposed) return;
    if (!_isPlaying) return;
    _isPlaying = false;
    _ticker?.stop();
    _safeNotifyListeners();
  }

  /// Toggle play/pause
  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Set looping enabled/disabled
  void setLooping(bool loop) {
    if (_isDisposed) return;
    _isLooping = loop;
    _safeNotifyListeners();
  }

  /// Seek to a specific frame
  void seekToFrame(int frameIndex) {
    if (_isDisposed || !isReady) return;
    _currentFrameIndex = frameIndex.clamp(0, frameCount - 1);
    final frameDuration = _decoder.metadata!.frameDuration;
    _currentPosition = frameDuration * _currentFrameIndex;
    _safeNotifyListeners();
  }

  /// Seek to a specific time position
  void seekTo(Duration position) {
    if (_isDisposed || !isReady || _decoder.metadata == null) return;

    // Clamp position manually since Duration doesn't have clamp
    if (position < Duration.zero) {
      _currentPosition = Duration.zero;
    } else if (position > duration) {
      _currentPosition = duration;
    } else {
      _currentPosition = position;
    }
    final frameDuration = _decoder.metadata!.frameDuration;
    _currentFrameIndex =
        (_currentPosition.inMicroseconds / frameDuration.inMicroseconds)
            .floor()
            .clamp(0, frameCount - 1);
    _safeNotifyListeners();
  }

  /// Seek to a normalized position (0.0 to 1.0)
  void seekToNormalized(double normalized) {
    final targetPosition = Duration(
      microseconds: (normalized * duration.inMicroseconds).round(),
    );
    seekTo(targetPosition);
  }

  /// Get normalized position (0.0 to 1.0)
  double get normalizedPosition {
    if (duration.inMicroseconds == 0) return 0.0;
    return (_currentPosition.inMicroseconds / duration.inMicroseconds)
        .clamp(0.0, 1.0);
  }

  /// Ticker callback - advances frames based on elapsed time
  void _onTick(Duration elapsed) {
    if (_isDisposed || !isReady || _decoder.metadata == null) return;

    // Calculate delta time
    final delta = _lastTickTime == Duration.zero
        ? Duration.zero
        : elapsed - _lastTickTime;
    _lastTickTime = elapsed;

    // Advance position
    _currentPosition += delta;

    // Clamp position to duration
    if (_currentPosition > duration) {
      _currentPosition = duration;
    }

    // Find the correct frame index based on actual frame timestamps
    // This handles animations with varying frame durations correctly
    int newFrameIndex = 0;
    for (int i = 0; i < frameCount; i++) {
      final frame = _decoder.frames![i];
      if (_currentPosition >= frame.timestamp &&
          _currentPosition <= frame.timestamp + frame.duration) {
        newFrameIndex = i;
        break;
      }
    }

    // Check for end of animation
    if (_currentPosition >= duration) {
      if (_isLooping) {
        _currentPosition = Duration.zero;
        newFrameIndex = 0; // Reset to first frame
      } else {
        // Stay at last frame
        newFrameIndex = frameCount - 1;
        pause();
      }
    }

    // Only notify if frame changed
    if (newFrameIndex != _currentFrameIndex) {
      _currentFrameIndex = newFrameIndex;
      _safeNotifyListeners();
    }
  }

  /// Reset playback to beginning
  void reset() {
    if (_isDisposed) return;
    pause();
    _currentFrameIndex = 0;
    _currentPosition = Duration.zero;
    _lastTickTime = Duration.zero;
    _safeNotifyListeners();
  }

  /// Safe notify that checks if disposed
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Widget that displays frame-based animation with transparency support
class FramePlayerWidget extends StatefulWidget {
  final FramePlayerController controller;
  final BoxFit fit;
  final Color? backgroundColor;
  final Widget? placeholder;

  const FramePlayerWidget({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.backgroundColor,
    this.placeholder,
  });

  @override
  State<FramePlayerWidget> createState() => _FramePlayerWidgetState();
}

class _FramePlayerWidgetState extends State<FramePlayerWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(FramePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.controller.currentFrame;

    if (frame == null) {
      return widget.placeholder ??
          const Center(child: CircularProgressIndicator());
    }

    return CustomPaint(
      painter: _FramePainter(
        image: frame.image,
        fit: widget.fit,
        backgroundColor: widget.backgroundColor,
      ),
      size: Size.infinite,
    );
  }
}

/// Custom painter that renders a ui.Image with proper alpha handling
class _FramePainter extends CustomPainter {
  final ui.Image image;
  final BoxFit fit;
  final Color? backgroundColor;

  _FramePainter({
    required this.image,
    required this.fit,
    this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background if specified
    if (backgroundColor != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = backgroundColor!,
      );
    }

    // Calculate destination rect based on fit
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = _calculateDestRect(size, srcRect, fit);

    // Draw image with alpha preserved
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  Rect _calculateDestRect(Size canvasSize, Rect srcRect, BoxFit fit) {
    final srcSize = srcRect.size;
    Size dstSize;

    switch (fit) {
      case BoxFit.fill:
        dstSize = canvasSize;
        break;
      case BoxFit.contain:
        final scale = (canvasSize.width / srcSize.width)
            .clamp(0.0, canvasSize.height / srcSize.height);
        dstSize = srcSize * scale;
        break;
      case BoxFit.cover:
        final scale = (canvasSize.width / srcSize.width)
            .clamp(canvasSize.height / srcSize.height, double.infinity);
        dstSize = srcSize * scale;
        break;
      case BoxFit.fitWidth:
        dstSize = Size(
          canvasSize.width,
          srcSize.height * canvasSize.width / srcSize.width,
        );
        break;
      case BoxFit.fitHeight:
        dstSize = Size(
          srcSize.width * canvasSize.height / srcSize.height,
          canvasSize.height,
        );
        break;
      case BoxFit.none:
        dstSize = srcSize;
        break;
      case BoxFit.scaleDown:
        final scale = (canvasSize.width / srcSize.width)
            .clamp(0.0, canvasSize.height / srcSize.height)
            .clamp(0.0, 1.0);
        dstSize = srcSize * scale;
        break;
    }

    final dx = (canvasSize.width - dstSize.width) / 2;
    final dy = (canvasSize.height - dstSize.height) / 2;

    return Rect.fromLTWH(dx, dy, dstSize.width, dstSize.height);
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) {
    return image != oldDelegate.image ||
        fit != oldDelegate.fit ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

/// A stateful wrapper that manages its own TickerProvider
class FramePlayer extends StatefulWidget {
  final FrameDecoderService decoder;
  final bool autoPlay;
  final bool loop;
  final BoxFit fit;
  final Widget? placeholder;
  final void Function(FramePlayerController)? onControllerReady;

  const FramePlayer({
    super.key,
    required this.decoder,
    this.autoPlay = true,
    this.loop = true,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.onControllerReady,
  });

  @override
  State<FramePlayer> createState() => _FramePlayerState();
}

class _FramePlayerState extends State<FramePlayer>
    with SingleTickerProviderStateMixin {
  late FramePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FramePlayerController(widget.decoder);
    _controller.initialize(this);
    _controller.setLooping(widget.loop);

    if (widget.autoPlay && widget.decoder.isReady) {
      _controller.play();
    }

    widget.onControllerReady?.call(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FramePlayerWidget(
      controller: _controller,
      fit: widget.fit,
      placeholder: widget.placeholder,
    );
  }
}
