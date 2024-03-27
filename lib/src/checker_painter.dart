import 'dart:math';

import 'package:flutter/material.dart' hide Image;

class CheckerPainter extends CustomPainter {
  BuildContext context;
  Function(Size)? sizeCallback;
  CheckerPainter(this.context, [this.sizeCallback]);
  @override
  void paint(Canvas canvas, Size size) {
    if (sizeCallback != null) sizeCallback!(size);
    checkerPainter(canvas, Rect.fromLTWH(0, 0, size.width, size.height), context);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }

  static void checkerPainter(Canvas canvas, Rect rect, BuildContext context) {
    // Paint a checkerboard below the image to indicate transparency

    double size = 10;
    final checkerPaint = Paint();
    checkerPaint.blendMode = BlendMode.srcOver;
    checkerPaint.style = PaintingStyle.fill;
    checkerPaint.color = Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : Colors.grey.shade900.withAlpha(150);
    canvas.drawRect(rect, checkerPaint);
    checkerPaint.color = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade900;
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
