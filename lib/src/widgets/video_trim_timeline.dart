import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/video/trim_range.dart';

String formatVideoTime(Duration time) {
  final milliseconds = time.inMilliseconds < 0 ? 0 : time.inMilliseconds;
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds ~/ 1000) % 60;
  final millis = milliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
}

enum _TimelineAction { start, end, seek }

class VideoTrimTimeline extends StatefulWidget {
  const VideoTrimTimeline({
    required this.duration,
    required this.range,
    required this.playhead,
    required this.thumbnails,
    required this.enabled,
    required this.onRangeChangeStart,
    required this.onRangeChanged,
    required this.onRangeChangeEnd,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onEdgeSelected,
    this.positionOverride,
    super.key,
  });

  final Duration duration;
  final RangeValues range;
  final ValueListenable<Duration> playhead;
  final Duration? positionOverride;
  final List<Uint8List?> thumbnails;
  final bool enabled;
  final VoidCallback onRangeChangeStart;
  final ValueChanged<RangeValues> onRangeChanged;
  final VoidCallback onRangeChangeEnd;
  final VoidCallback onSeekStart;
  final ValueChanged<Duration> onSeekChanged;
  final ValueChanged<Duration> onSeekEnd;
  final ValueChanged<TrimEdge> onEdgeSelected;

  @override
  State<VideoTrimTimeline> createState() => _VideoTrimTimelineState();
}

class _VideoTrimTimelineState extends State<VideoTrimTimeline> {
  static const _inset = 16.0;
  int? _pointer;
  Offset? _down;
  _TimelineAction? _action;
  bool _started = false;
  bool _vertical = false;

  double _fraction(double x, double width) =>
      width <= 2 * _inset ? 0 : ((x - _inset) / (width - 2 * _inset)).clamp(0.0, 1.0);

  _TimelineAction _actionAt(double x, double width) {
    final startX = _inset + (width - 2 * _inset) * widget.range.start;
    final endX = _inset + (width - 2 * _inset) * widget.range.end;
    final startDistance = (x - startX).abs();
    final endDistance = (x - endX).abs();
    if (startDistance <= 26 || endDistance <= 26) {
      return startDistance <= endDistance ? _TimelineAction.start : _TimelineAction.end;
    }
    return _TimelineAction.seek;
  }

  void _begin() {
    if (_started) return;
    _started = true;
    if (_action == _TimelineAction.seek) {
      widget.onSeekStart();
    } else {
      widget.onRangeChangeStart();
    }
  }

  void _update(double x, double width) {
    final fraction = _fraction(x, width);
    switch (_action) {
      case _TimelineAction.start:
        widget.onRangeChanged(RangeValues(fraction.clamp(0.0, widget.range.end), widget.range.end));
      case _TimelineAction.end:
        widget.onRangeChanged(RangeValues(widget.range.start, fraction.clamp(widget.range.start, 1.0)));
      case _TimelineAction.seek:
        final selected = fraction.clamp(widget.range.start, widget.range.end);
        widget.onSeekChanged(widget.duration * selected);
      case null:
        break;
    }
  }

  void _pointerDown(PointerDownEvent event, double width) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _down = event.localPosition;
    _action = _actionAt(event.localPosition.dx, width);
    if (_action == _TimelineAction.start) widget.onEdgeSelected(TrimEdge.start);
    if (_action == _TimelineAction.end) widget.onEdgeSelected(TrimEdge.end);
    _started = false;
    _vertical = false;
  }

  void _pointerMove(PointerMoveEvent event, double width) {
    if (event.pointer != _pointer || _vertical) return;
    final movement = event.localPosition - _down!;
    if (!_started) {
      if (movement.distance < 8) return;
      if (movement.dy.abs() > movement.dx.abs()) {
        _vertical = true;
        return;
      }
      _begin();
    }
    _update(event.localPosition.dx, width);
  }

  void _pointerUp(PointerUpEvent event, double width) {
    if (event.pointer != _pointer) return;
    if (!_vertical) {
      if (!_started && _action == _TimelineAction.seek) _begin();
      if (_started) {
        _update(event.localPosition.dx, width);
        if (_action == _TimelineAction.seek) {
          final selected = _fraction(event.localPosition.dx, width).clamp(widget.range.start, widget.range.end);
          widget.onSeekEnd(widget.duration * selected);
        } else {
          widget.onRangeChangeEnd();
        }
      }
    }
    _resetPointer();
  }

  void _resetPointer() {
    _pointer = null;
    _down = null;
    _action = null;
    _started = false;
    _vertical = false;
  }

  void _adjustRange(bool start, int direction) {
    widget.onEdgeSelected(start ? TrimEdge.start : TrimEdge.end);
    final step = (100000 / widget.duration.inMicroseconds).clamp(0.0, 1.0);
    final range = widget.range;
    final values = start
        ? RangeValues((range.start + direction * step).clamp(0.0, range.end - step), range.end)
        : RangeValues(range.start, (range.end + direction * step).clamp(range.start + step, 1.0));
    widget.onRangeChangeStart();
    widget.onRangeChanged(values);
    widget.onRangeChangeEnd();
  }

  void _adjustPlayhead(int direction) {
    final step = (100000 / widget.duration.inMicroseconds).clamp(0.0, 1.0);
    final current = widget.positionOverride ?? widget.playhead.value;
    final fraction = (current.inMicroseconds / widget.duration.inMicroseconds + direction * step).clamp(
      widget.range.start,
      widget.range.end,
    );
    final time = widget.duration * fraction;
    widget.onSeekStart();
    widget.onSeekChanged(time);
    widget.onSeekEnd(time);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final durationUs = widget.duration.inMicroseconds;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.trimVideo, style: Theme.of(context).textTheme.titleSmall)),
              ValueListenableBuilder<Duration>(
                valueListenable: widget.playhead,
                builder: (context, current, _) => Semantics(
                  label: '${l10n.previewPosition} ${formatVideoTime(widget.positionOverride ?? current)}',
                  enabled: widget.enabled,
                  onIncrease: widget.enabled ? () => _adjustPlayhead(1) : null,
                  onDecrease: widget.enabled ? () => _adjustPlayhead(-1) : null,
                  child: Text(
                    formatVideoTime(widget.positionOverride ?? current),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final trackWidth = width - 2 * _inset;
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _pointerDown(event, width),
                  onPointerMove: (event) => _pointerMove(event, width),
                  onPointerUp: (event) => _pointerUp(event, width),
                  onPointerCancel: (event) {
                    if (event.pointer == _pointer) {
                      if (_started) {
                        if (_action == _TimelineAction.seek) {
                          widget.onSeekEnd(widget.positionOverride ?? widget.playhead.value);
                        } else {
                          widget.onRangeChangeEnd();
                        }
                      }
                      _resetPointer();
                    }
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        left: _inset,
                        right: _inset,
                        top: 6,
                        bottom: 6,
                        child: RepaintBoundary(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: ColoredBox(
                              color: colors.surfaceContainerHighest,
                              child: widget.thumbnails.isEmpty
                                  ? const SizedBox.expand()
                                  : Row(
                                      children: [
                                        for (final frame in widget.thumbnails)
                                          Expanded(
                                            child: frame == null
                                                ? const SizedBox.expand()
                                                : Image.memory(
                                                    frame,
                                                    fit: BoxFit.cover,
                                                    height: 64,
                                                    gaplessPlayback: true,
                                                  ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      ValueListenableBuilder<Duration>(
                        valueListenable: widget.playhead,
                        builder: (context, current, _) {
                          final position = widget.positionOverride ?? current;
                          final fraction = durationUs == 0
                              ? 0.0
                              : (position.inMicroseconds / durationUs).clamp(0.0, 1.0);
                          return IgnorePointer(
                            child: CustomPaint(
                              painter: _PlayheadPainter(fraction, colors.onSurface),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _FilmstripPainter(widget.range, colors.primary, colors.onPrimary),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Positioned(
                        left: (_inset + trackWidth * widget.range.start - 22).clamp(0.0, width - 44),
                        child: Semantics(
                          container: true,
                          label: '${l10n.trimStart} ${formatVideoTime(widget.duration * widget.range.start)}',
                          enabled: widget.enabled,
                          onIncrease: widget.enabled ? () => _adjustRange(true, 1) : null,
                          onDecrease: widget.enabled ? () => _adjustRange(true, -1) : null,
                          child: const SizedBox(width: 44, height: 76),
                        ),
                      ),
                      Positioned(
                        left: (_inset + trackWidth * widget.range.end - 22).clamp(0.0, width - 44),
                        child: Semantics(
                          container: true,
                          label: '${l10n.trimEnd} ${formatVideoTime(widget.duration * widget.range.end)}',
                          enabled: widget.enabled,
                          onIncrease: widget.enabled ? () => _adjustRange(false, 1) : null,
                          onDecrease: widget.enabled ? () => _adjustRange(false, -1) : null,
                          child: const SizedBox(width: 44, height: 76),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          if (MediaQuery.textScalerOf(context).scale(12) > 18)
            Column(
              children: [
                _ExpandedTimeRow(label: l10n.trimStart, value: formatVideoTime(widget.duration * widget.range.start)),
                _ExpandedTimeRow(
                  label: l10n.clipLength,
                  value: formatVideoTime(widget.duration * (widget.range.end - widget.range.start)),
                ),
                _ExpandedTimeRow(label: l10n.trimEnd, value: formatVideoTime(widget.duration * widget.range.end)),
              ],
            )
          else
            Row(
              children: [
                _TimeLabel(
                  label: l10n.trimStart,
                  value: formatVideoTime(widget.duration * widget.range.start),
                  alignment: CrossAxisAlignment.start,
                ),
                _TimeLabel(
                  label: l10n.clipLength,
                  value: formatVideoTime(widget.duration * (widget.range.end - widget.range.start)),
                  alignment: CrossAxisAlignment.center,
                ),
                _TimeLabel(
                  label: l10n.trimEnd,
                  value: formatVideoTime(widget.duration * widget.range.end),
                  alignment: CrossAxisAlignment.end,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.label, required this.value, required this.alignment});
  final String label;
  final String value;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: alignment,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(value, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _ExpandedTimeRow extends StatelessWidget {
  const _ExpandedTimeRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _FilmstripPainter extends CustomPainter {
  const _FilmstripPainter(this.range, this.color, this.gripColor);
  final RangeValues range;
  final Color color;
  final Color gripColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 16.0;
    final left = inset + (size.width - 2 * inset) * range.start;
    final right = inset + (size.width - 2 * inset) * range.end;
    final top = (size.height - 64) / 2;
    final bottom = top + 64;
    final shade = Paint()..color = Colors.black.withValues(alpha: .64);
    canvas.drawRect(Rect.fromLTRB(inset, top, left, bottom), shade);
    canvas.drawRect(Rect.fromLTRB(right, top, size.width - inset, bottom), shade);
    canvas.drawRect(
      Rect.fromLTRB(left, top + 1.5, right, bottom - 1.5),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final fill = Paint()..color = color;
    final grip = Paint()
      ..color = gripColor
      ..strokeWidth = 2;
    for (final x in [left, right]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, size.height / 2), width: 18, height: 64),
          const Radius.circular(5),
        ),
        fill,
      );
      canvas.drawLine(Offset(x - 2, size.height / 2 - 8), Offset(x - 2, size.height / 2 + 8), grip);
      canvas.drawLine(Offset(x + 2, size.height / 2 - 8), Offset(x + 2, size.height / 2 + 8), grip);
    }
  }

  @override
  bool shouldRepaint(_FilmstripPainter oldDelegate) =>
      oldDelegate.range != range || oldDelegate.color != color || oldDelegate.gripColor != gripColor;
}

class _PlayheadPainter extends CustomPainter {
  const _PlayheadPainter(this.fraction, this.color);
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = 16 + (size.width - 32) * fraction;
    final center = Offset(x, size.height / 2);
    canvas.drawLine(
      Offset(x, 5),
      Offset(x, size.height - 5),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 5,
    );
    canvas.drawLine(
      Offset(x, 5),
      Offset(x, size.height - 5),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, 5, Paint()..color = Colors.black);
    canvas.drawCircle(center, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) => oldDelegate.fraction != fraction || oldDelegate.color != color;
}
