import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A custom video trim bar widget that solves the alignment mismatch between
/// range trim handles and the playback progress head.
///
/// Features:
/// - Start and end trim handles with clear grab bars and bounding borders.
/// - Unselected regions (before start and after end) dimmed out.
/// - Selected region framed with an accent border.
/// - Playhead indicator that precisely tracks playback position within [0.0, 1.0],
///   aligning perfectly with the handles at the edges.
/// - Can drag start handle, end handle, the middle region (to shift the whole trim window),
///   or scrub the playhead.
class VideoTrimBar extends StatefulWidget {
  const VideoTrimBar({
    super.key,
    required this.range,
    this.playbackPosition,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onSeek,
    this.minRangeDistance = 0.01,
    this.height = 44.0,
    this.handleWidth = 14.0,
    this.showPlayhead = true,
  });

  /// Range values between 0.0 and 1.0 representing start and end fractions.
  final RangeValues range;

  /// Current playback fraction between 0.0 and 1.0 (null if not available or gif).
  final double? playbackPosition;

  /// Called when the trim range is being changed by dragging.
  final ValueChanged<RangeValues> onChanged;

  /// Called when dragging handles or region begins.
  final ValueChanged<RangeValues>? onChangeStart;

  /// Called when dragging handles or region ends.
  final ValueChanged<RangeValues>? onChangeEnd;

  /// Called when scrubbing or tapping to seek position directly.
  final ValueChanged<double>? onSeek;

  /// Minimum fraction distance between start and end.
  final double minRangeDistance;

  /// Total height of the trim bar.
  final double height;

  /// Width of the start and end drag handles in logical pixels.
  final double handleWidth;

  /// Whether to render the playhead line/indicator.
  final bool showPlayhead;

  @override
  State<VideoTrimBar> createState() => _VideoTrimBarState();
}

enum _DragTarget {
  none,
  startHandle,
  endHandle,
  middleWindow,
  playhead,
}

class _VideoTrimBarState extends State<VideoTrimBar> {
  _DragTarget _dragTarget = _DragTarget.none;
  double _dragStartDx = 0.0;
  RangeValues _dragInitialRange = const RangeValues(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          // Available inner track width for the range [0.0, 1.0]
          // Handles sit on the edges. To allow the playhead and handles to reach
          // true 0.0 and 1.0, the inner track width is:
          final trackWidth = math.max(1.0, totalWidth - (widget.handleWidth * 2));

          double fractionToX(double fraction) {
            return widget.handleWidth + (fraction.clamp(0.0, 1.0) * trackWidth);
          }

          double xToFraction(double x) {
            return ((x - widget.handleWidth) / trackWidth).clamp(0.0, 1.0);
          }

          final startX = fractionToX(widget.range.start);
          final endX = fractionToX(widget.range.end);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragDown: (details) {
              final localX = details.localPosition.dx;
              final startHandleCenter = startX - (widget.handleWidth / 2);
              final endHandleCenter = endX + (widget.handleWidth / 2);

              // Generous touch hit targets (at least 28px wide)
              const hitPadding = 12.0;

              final nearStart = (localX - startHandleCenter).abs() <= (widget.handleWidth / 2 + hitPadding);
              final nearEnd = (localX - endHandleCenter).abs() <= (widget.handleWidth / 2 + hitPadding);

              _dragStartDx = localX;
              _dragInitialRange = widget.range;

              if (nearStart && nearEnd) {
                // When handles are very close together, pick based on which side touch is closer to
                if (localX < (startHandleCenter + endHandleCenter) / 2) {
                  _dragTarget = _DragTarget.startHandle;
                } else {
                  _dragTarget = _DragTarget.endHandle;
                }
              } else if (nearStart) {
                _dragTarget = _DragTarget.startHandle;
              } else if (nearEnd) {
                _dragTarget = _DragTarget.endHandle;
              } else if (localX >= startX && localX <= endX) {
                // Inside the trim window
                // Check if user tapped near playhead (if shown)
                final nearPlayhead =
                    widget.showPlayhead &&
                    widget.playbackPosition != null &&
                    (localX - fractionToX(widget.playbackPosition!)).abs() <= 16.0;
                _dragTarget = nearPlayhead ? _DragTarget.playhead : _DragTarget.middleWindow;
              } else {
                // Outside the trim window: tap outside adjusts the closest handle or seeks
                if (localX < startX) {
                  _dragTarget = _DragTarget.startHandle;
                } else {
                  _dragTarget = _DragTarget.endHandle;
                }
              }
            },
            onHorizontalDragStart: (details) {
              widget.onChangeStart?.call(widget.range);
              if (_dragTarget == _DragTarget.startHandle || _dragTarget == _DragTarget.endHandle) {
                // Update handle position immediately
                _updateHandlePosition(xToFraction(details.localPosition.dx));
              } else if (_dragTarget == _DragTarget.playhead && widget.onSeek != null) {
                final frac = xToFraction(details.localPosition.dx);
                widget.onSeek!(frac.clamp(widget.range.start, widget.range.end));
              }
            },
            onHorizontalDragUpdate: (details) {
              final localX = details.localPosition.dx;
              if (_dragTarget == _DragTarget.startHandle || _dragTarget == _DragTarget.endHandle) {
                _updateHandlePosition(xToFraction(localX));
              } else if (_dragTarget == _DragTarget.middleWindow) {
                final deltaPx = localX - _dragStartDx;
                final deltaFrac = deltaPx / trackWidth;
                final windowSpan = _dragInitialRange.end - _dragInitialRange.start;

                var newStart = _dragInitialRange.start + deltaFrac;
                var newEnd = _dragInitialRange.end + deltaFrac;

                if (newStart < 0.0) {
                  newStart = 0.0;
                  newEnd = windowSpan;
                } else if (newEnd > 1.0) {
                  newEnd = 1.0;
                  newStart = 1.0 - windowSpan;
                }

                widget.onChanged(RangeValues(newStart, newEnd));
              } else if (_dragTarget == _DragTarget.playhead && widget.onSeek != null) {
                final frac = xToFraction(localX);
                widget.onSeek!(frac.clamp(widget.range.start, widget.range.end));
              }
            },
            onHorizontalDragEnd: (details) {
              _finishDrag();
            },
            onHorizontalDragCancel: () {
              _finishDrag();
            },
            onTapUp: (details) {
              final localX = details.localPosition.dx;
              final tappedFrac = xToFraction(localX);
              if (tappedFrac >= widget.range.start && tappedFrac <= widget.range.end) {
                widget.onSeek?.call(tappedFrac);
              }
            },
            child: CustomPaint(
              size: Size(totalWidth, widget.height),
              painter: _TrimBarPainter(
                range: widget.range,
                playbackPosition: widget.playbackPosition,
                handleWidth: widget.handleWidth,
                showPlayhead: widget.showPlayhead,
                primaryColor: colorScheme.primary,
                onPrimaryColor: colorScheme.onPrimary,
                trackColor: colorScheme.surfaceContainerHighest,
                scrimColor: Colors.black.withValues(alpha: 0.55),
                playheadColor: colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }

  void _updateHandlePosition(double frac) {
    if (_dragTarget == _DragTarget.startHandle) {
      final maxStart = math.max(0.0, widget.range.end - widget.minRangeDistance);
      final newStart = math.min(frac, maxStart);
      widget.onChanged(RangeValues(newStart, widget.range.end));
    } else if (_dragTarget == _DragTarget.endHandle) {
      final minEnd = math.min(1.0, widget.range.start + widget.minRangeDistance);
      final newEnd = math.max(frac, minEnd);
      widget.onChanged(RangeValues(widget.range.start, newEnd));
    }
  }

  void _finishDrag() {
    if (_dragTarget != _DragTarget.none) {
      widget.onChangeEnd?.call(widget.range);
      _dragTarget = _DragTarget.none;
    }
  }
}

class _TrimBarPainter extends CustomPainter {
  const _TrimBarPainter({
    required this.range,
    required this.playbackPosition,
    required this.handleWidth,
    required this.showPlayhead,
    required this.primaryColor,
    required this.onPrimaryColor,
    required this.trackColor,
    required this.scrimColor,
    required this.playheadColor,
  });

  final RangeValues range;
  final double? playbackPosition;
  final double handleWidth;
  final bool showPlayhead;
  final Color primaryColor;
  final Color onPrimaryColor;
  final Color trackColor;
  final Color scrimColor;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    final trackWidth = math.max(1.0, size.width - (handleWidth * 2));
    final startHandleRight = handleWidth + (range.start.clamp(0.0, 1.0) * trackWidth);
    final startHandleLeft = startHandleRight - handleWidth;

    final endHandleLeft = handleWidth + (range.end.clamp(0.0, 1.0) * trackWidth);
    final endHandleRight = endHandleLeft + handleWidth;

    const cornerRadius = 8.0;
    final fullRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(cornerRadius),
    );

    // 1. Draw base track background
    final bgPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(fullRect, bgPaint);

    // 2. Dimmed unselected regions (left of start handle, right of end handle)
    final scrimPaint = Paint()
      ..color = scrimColor
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipRRect(fullRect);

    if (startHandleLeft > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, startHandleLeft, size.height), scrimPaint);
    }
    if (endHandleRight < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(endHandleRight, 0, size.width - endHandleRight, size.height),
        scrimPaint,
      );
    }

    // 3. Middle active border (top and bottom rails)
    const borderWidth = 3.0;
    final borderPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final middleLeft = startHandleRight;
    final middleWidth = math.max(0.0, endHandleLeft - middleLeft);

    // Top rail
    canvas.drawRect(
      Rect.fromLTWH(middleLeft, 0, middleWidth, borderWidth),
      borderPaint,
    );
    // Bottom rail
    canvas.drawRect(
      Rect.fromLTWH(middleLeft, size.height - borderWidth, middleWidth, borderWidth),
      borderPaint,
    );

    // 4. Draw Start Handle
    final startHandleRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(startHandleLeft, 0, startHandleRight, size.height),
      topLeft: Radius.circular(startHandleLeft <= 1 ? cornerRadius : 4),
      bottomLeft: Radius.circular(startHandleLeft <= 1 ? cornerRadius : 4),
      topRight: const Radius.circular(2),
      bottomRight: const Radius.circular(2),
    );
    final handlePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(startHandleRRect, handlePaint);

    // Grip lines on start handle
    _drawGrip(
      canvas,
      Rect.fromLTRB(startHandleLeft, 0, startHandleRight, size.height),
      onPrimaryColor,
    );

    // 5. Draw End Handle
    final endHandleRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(endHandleLeft, 0, endHandleRight, size.height),
      topRight: Radius.circular(endHandleRight >= size.width - 1 ? cornerRadius : 4),
      bottomRight: Radius.circular(endHandleRight >= size.width - 1 ? cornerRadius : 4),
      topLeft: const Radius.circular(2),
      bottomLeft: const Radius.circular(2),
    );
    canvas.drawRRect(endHandleRRect, handlePaint);

    // Grip lines on end handle
    _drawGrip(
      canvas,
      Rect.fromLTRB(endHandleLeft, 0, endHandleRight, size.height),
      onPrimaryColor,
    );

    // 6. Draw Playhead
    if (showPlayhead && playbackPosition != null) {
      final posFrac = playbackPosition!.clamp(0.0, 1.0);
      final playheadX = handleWidth + (posFrac * trackWidth);

      // Playhead vertical line
      const playheadWidth = 3.0;
      final playheadPaint = Paint()
        ..color = playheadColor
        ..style = PaintingStyle.fill;

      // Playhead shadow for high visibility against any video content
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            playheadX - (playheadWidth / 2) - 0.5,
            1.0,
            playheadWidth + 1.0,
            size.height - 2.0,
          ),
          const Radius.circular(1.5),
        ),
        shadowPaint,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            playheadX - (playheadWidth / 2),
            2.0,
            playheadWidth,
            size.height - 4.0,
          ),
          const Radius.circular(1.5),
        ),
        playheadPaint,
      );

      // Small circular / rounded cap on top & bottom for polished look
      canvas.drawCircle(Offset(playheadX, 4.0), 3.0, playheadPaint);
      canvas.drawCircle(Offset(playheadX, size.height - 4.0), 3.0, playheadPaint);
    }

    canvas.restore();
  }

  void _drawGrip(Canvas canvas, Rect handleRect, Color gripColor) {
    final gripPaint = Paint()
      ..color = gripColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final centerY = handleRect.center.dy;
    final centerX = handleRect.center.dx;
    const gripHeight = 12.0;

    canvas.drawLine(
      Offset(centerX - 1.5, centerY - gripHeight / 2),
      Offset(centerX - 1.5, centerY + gripHeight / 2),
      gripPaint,
    );
    canvas.drawLine(
      Offset(centerX + 1.5, centerY - gripHeight / 2),
      Offset(centerX + 1.5, centerY + gripHeight / 2),
      gripPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TrimBarPainter oldDelegate) {
    return oldDelegate.range != range ||
        oldDelegate.playbackPosition != playbackPosition ||
        oldDelegate.handleWidth != handleWidth ||
        oldDelegate.showPlayhead != showPlayhead ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.onPrimaryColor != onPrimaryColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.playheadColor != playheadColor;
  }
}
