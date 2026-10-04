import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight, move }

/// Keeps the crop in normalized video coordinates so it is independent of the preview size.
class VideoCropOverlay extends StatefulWidget {
  const VideoCropOverlay({
    required this.crop,
    required this.onChanged,
    this.aspectRatio,
    super.key,
  });

  final Rect crop;
  final double? aspectRatio;
  final ValueChanged<Rect> onChanged;

  @override
  State<VideoCropOverlay> createState() => _VideoCropOverlayState();
}

class _VideoCropOverlayState extends State<VideoCropOverlay> {
  _CropHandle? _handle;
  int? _pointer;
  Offset? _dragOrigin;
  Rect? _initialCrop;
  bool _focused = false;

  void _startDrag(PointerDownEvent event, Rect selection) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _dragOrigin = event.localPosition;
    _initialCrop = widget.crop;

    final corners = <_CropHandle, Offset>{
      _CropHandle.topLeft: selection.topLeft,
      _CropHandle.topRight: selection.topRight,
      _CropHandle.bottomLeft: selection.bottomLeft,
      _CropHandle.bottomRight: selection.bottomRight,
    };
    for (final entry in corners.entries) {
      if ((entry.value - event.localPosition).distance <= 32) {
        _handle = entry.key;
        return;
      }
    }
    _handle = selection.contains(event.localPosition) ? _CropHandle.move : null;
  }

  void _moveDrag(PointerMoveEvent event, Size size) {
    final handle = _handle;
    final crop = _initialCrop;
    if (event.pointer != _pointer ||
        handle == null ||
        crop == null ||
        _dragOrigin == null ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final movement = event.localPosition - _dragOrigin!;
    final delta = Offset(movement.dx / size.width, movement.dy / size.height);
    if (handle == _CropHandle.move) {
      final left = (crop.left + delta.dx).clamp(0.0, 1.0 - crop.width);
      final top = (crop.top + delta.dy).clamp(0.0, 1.0 - crop.height);
      widget.onChanged(Rect.fromLTWH(left, top, crop.width, crop.height));
      return;
    }

    final leftHandle = handle == _CropHandle.topLeft || handle == _CropHandle.bottomLeft;
    final topHandle = handle == _CropHandle.topLeft || handle == _CropHandle.topRight;
    final anchor = Offset(leftHandle ? crop.right : crop.left, topHandle ? crop.bottom : crop.top);
    final corner = Offset(leftHandle ? crop.left : crop.right, topHandle ? crop.top : crop.bottom) + delta;
    final maxWidth = leftHandle ? anchor.dx : 1 - anchor.dx;
    final maxHeight = topHandle ? anchor.dy : 1 - anchor.dy;
    final ratio = widget.aspectRatio == null ? null : widget.aspectRatio! * size.height / size.width;
    double width = leftHandle ? anchor.dx - corner.dx : corner.dx - anchor.dx;
    double height = topHandle ? anchor.dy - corner.dy : corner.dy - anchor.dy;
    if (ratio != null) {
      if ((width - crop.width).abs() > (height - crop.height).abs() * ratio) {
        height = width / ratio;
      } else {
        width = height * ratio;
      }
      final limit = math.min(maxWidth, maxHeight * ratio);
      width = width.clamp(math.min(limit, math.max(48 / size.width, ratio * 48 / size.height)), limit);
      height = width / ratio;
    } else {
      width = width.clamp(math.min(48 / size.width, maxWidth), maxWidth);
      height = height.clamp(math.min(48 / size.height, maxHeight), maxHeight);
    }
    widget.onChanged(
      Rect.fromLTRB(
        leftHandle ? anchor.dx - width : anchor.dx,
        topHandle ? anchor.dy - height : anchor.dy,
        leftHandle ? anchor.dx : anchor.dx + width,
        topHandle ? anchor.dy : anchor.dy + height,
      ),
    );
  }

  void _endDrag(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _handle = null;
    _dragOrigin = null;
    _initialCrop = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selection = Rect.fromLTRB(
          widget.crop.left * size.width,
          widget.crop.top * size.height,
          widget.crop.right * size.width,
          widget.crop.bottom * size.height,
        );
        return Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            const step = .02;
            final double dx;
            final double dy;
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              dx = -step;
              dy = 0;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              dx = step;
              dy = 0;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              dx = 0;
              dy = -step;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              dx = 0;
              dy = step;
            } else {
              return KeyEventResult.ignored;
            }
            final crop = widget.crop;
            widget.onChanged(
              Rect.fromLTWH(
                (crop.left + dx).clamp(0.0, 1.0 - crop.width),
                (crop.top + dy).clamp(0.0, 1.0 - crop.height),
                crop.width,
                crop.height,
              ),
            );
            return KeyEventResult.handled;
          },
          child: Semantics(
            label: AppLocalizations.of(context)!.cropSelectionInstructions,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _startDrag(event, selection),
              onPointerMove: (event) => _moveDrag(event, size),
              onPointerUp: (event) => _endDrag(event.pointer),
              onPointerCancel: (event) => _endDrag(event.pointer),
              child: CustomPaint(
                painter: _VideoCropPainter(selection, Theme.of(context).colorScheme.primary, _focused),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoCropPainter extends CustomPainter {
  const _VideoCropPainter(this.selection, this.color, this.focused);

  final Rect selection;
  final Color color;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, selection.top), mask);
    canvas.drawRect(Rect.fromLTRB(0, selection.top, selection.left, selection.bottom), mask);
    canvas.drawRect(Rect.fromLTRB(selection.right, selection.top, size.width, selection.bottom), mask);
    canvas.drawRect(Rect.fromLTRB(0, selection.bottom, size.width, size.height), mask);
    final outline = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final stroke = Paint()
      ..color = (focused ? Colors.white : color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(selection, outline);
    canvas.drawRect(selection, stroke);
    for (final corner in [selection.topLeft, selection.topRight, selection.bottomLeft, selection.bottomRight]) {
      canvas.drawCircle(corner, 9, Paint()..color = Colors.black);
      canvas.drawCircle(corner, 6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_VideoCropPainter oldDelegate) =>
      oldDelegate.selection != selection || oldDelegate.color != color || oldDelegate.focused != focused;
}
