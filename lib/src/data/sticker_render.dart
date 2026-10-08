import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:stickers/src/video/common.dart';

/// Side length of a sticker in pixels.
const int stickerSize = 512;

const _methodChannel = MethodChannel('de.loicezt.stickers/methods');

/// Renders the editor layers in [layers] at sticker resolution, over [background] if given.
///
/// The layers are captured from the editor canvas itself, so the sticker matches what the user sees.
Future<ui.Image> renderSticker(RenderRepaintBoundary layers, {File? background}) async {
  final canvasSize = layers.size.width;
  final scale = stickerSize / canvasSize;
  final overlay = await layers.toImage(pixelRatio: scale);
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (background != null) {
      final image = await _decode(background);
      try {
        // The editor shows the background at its own size, shrunk to fit the canvas, in the top left corner.
        final fit = min(1.0, canvasSize / max(image.width, image.height)) * scale;
        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(0, 0, image.width * fit, image.height * fit),
          image: image,
          filterQuality: FilterQuality.medium,
        );
      } finally {
        image.dispose();
      }
    }
    // Rounding can make the overlay a pixel larger than the sticker, which gets cut off here.
    canvas.drawImage(overlay, Offset.zero, Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(stickerSize, stickerSize);
    } finally {
      picture.dispose();
    }
  } finally {
    overlay.dispose();
  }
}

/// Encodes [image] as a still WebP using the bundled libwebp.
Future<Uint8List> encodeWebp(ui.Image image, WebPConfig config) async {
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final data = await _methodChannel.invokeMethod<Uint8List>('encodeWebp', {
    'rgba': rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
    'width': image.width,
    'height': image.height,
    'config': config.toMap(),
  });
  return data!;
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
