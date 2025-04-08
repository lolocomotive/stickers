import 'dart:math';

import 'package:flutter/material.dart' hide Image;

class CheckerPainter extends CustomPainter {
  BuildContext context;
  Function(Size)? sizeCallback;

  CheckerPainter(this.context, {this.sizeCallback, this.fg, this.bg});

  final Color? fg;
  final Color? bg;

  @override
  void paint(Canvas canvas, Size size) {
    if (sizeCallback != null) sizeCallback!(size);
    checkerPainter(canvas, Rect.fromLTWH(0, 0, size.width, size.height), context, fg, bg);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

  static void checkerPainter(Canvas canvas, Rect rect, BuildContext context, [Color? bg, Color? fg]) {
    // Paint a checkerboard below the image to indicate transparency
    fg = fg ?? (Theme.of(context).brightness == Brightness.light
        ? Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .8)
        : Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .9));
    bg = bg ?? (Theme.of(context).brightness == Brightness.light
            ? Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .9)
            : Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .95));

    double size = 10;
    final checkerPaint = Paint();
    checkerPaint.blendMode = BlendMode.srcOver;
    checkerPaint.style = PaintingStyle.fill;

    // It's ok to null check like this since lerp only returns null only if both arguments are null,
    // Which isn't the case here
    checkerPaint.color = bg!;
    canvas.drawRect(rect, checkerPaint);
    checkerPaint.color = fg!;
    canvas.clipRect(rect);

    // Clamp to screen area for performance reasons.
    // Not optimal since canvas is still bigger than display area
    // Not something I can fix here tho

    final maxX = min(MediaQuery.of(context).size.width, rect.right);
    final maxY = min(MediaQuery.of(context).size.height, rect.bottom);

    int row = 0;
    for (double y = max(rect.top, 0); y < maxY; y += size) {
      for (double x = max(rect.left, 0) + row * size; x < maxX; x += size * 2) {
        Rect r = Rect.fromLTWH(x, y, size, size);
        canvas.drawRect(r, checkerPaint);
      }
      row++;
      row &= 1;
    }
  }
}
