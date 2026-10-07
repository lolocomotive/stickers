import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/src/checker_painter.dart';

/// A performance-optimized thumbnail widget for stickers.
///
/// Automatically calculates target decode dimensions in physical display
/// pixels (`cacheWidth` / `cacheHeight`) using [MediaQueryData.devicePixelRatio]
/// so that Skia/Impeller decodes an appropriately sized bitmap in memory rather
/// than the full 512x512 image.
///
/// Also encapsulates [CheckerPainter] for transparency visualization and isolates
/// rasterization using [RepaintBoundary].
class StickerThumbnail extends StatelessWidget {
  final File file;

  /// Displayed width and height. When null, the incoming constraints are used.
  final double? targetSize;

  const StickerThumbnail({
    super.key,
    required this.file,
    this.targetSize,
  });

  @override
  Widget build(BuildContext context) {
    if (targetSize != null) {
      return _buildImage(context, targetSize, targetSize);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final h = constraints.hasBoundedHeight ? constraints.maxHeight : null;
        return _buildImage(context, w, h);
      },
    );
  }

  Widget _buildImage(BuildContext context, double? w, double? h) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // WhatsApp stickers are standard 512x512.
    // Calculate decode size based on physical display pixels.
    // Setting only cacheWidth preserves the image's aspect ratio.
    int? cacheW;
    int? cacheH;
    if (w != null && w.isFinite && w > 0) {
      cacheW = (w * dpr).round().clamp(1, 512);
    } else if (h != null && h.isFinite && h > 0) {
      cacheH = (h * dpr).round().clamp(1, 512);
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: CheckerPainter(context),
        child: Image.file(
          file,
          width: w,
          height: h,
          fit: BoxFit.contain,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
