import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

enum StickerFormat {
  png('png', 'PNG'),
  webp('webp', 'WebP'),
  jpeg('jpg', 'JPEG'),
  gif('gif', 'GIF');

  final String extension;
  final String label;

  const StickerFormat(this.extension, this.label);
}

/// Receives the converted fraction (0 to 1) of the current sticker.
typedef ConversionProgress = void Function(double progress);

/// How many decoded frames may wait for the encoder, which bounds memory use
/// for long animations.
const _framesInFlight = 2;

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

/// Converts the sticker at [path] to [format], keeping animation for every
/// format that supports it (GIF, animated PNG and WebP).
///
/// Frames are decoded by the engine's native codecs and encoded one at a time
/// in a background isolate.
Future<Uint8List> convertSticker(String path, StickerFormat format, {ConversionProgress? onProgress}) async {
  final bytes = await File(path).readAsBytes();
  if (format == StickerFormat.webp && _isWebp(bytes)) {
    // Stickers are already WebP; copying the file keeps animated ones animated.
    onProgress?.call(1);
    return bytes;
  }

  final codec = await ui.instantiateImageCodec(bytes);
  final frameCount = format == StickerFormat.jpeg ? 1 : codec.frameCount;
  final replies = ReceivePort();
  final messages = StreamIterator(replies);
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      _encodeWorker,
      _EncodeJob(replies.sendPort, format, frameCount),
      onError: replies.sendPort,
      onExit: replies.sendPort,
    );

    Future<Object> next() async {
      if (!await messages.moveNext()) throw StateError('Encoder closed');
      final message = messages.current;
      if (message == null) throw StateError('Encoder stopped unexpectedly');
      if (message is List) throw Exception('Encoding failed: ${message.first}');
      if (message is _EncodeError) throw Exception('Encoding failed: ${message.message}');
      return message as Object;
    }

    final toWorker = await next() as SendPort;
    var encoded = 0;
    Future<void> waitForEncoder() async {
      encoded = await next() as int;
      onProgress?.call(encoded / frameCount);
    }

    for (var sent = 0; sent < frameCount;) {
      final frame = await codec.getNextFrame();
      final ByteData? rgba;
      try {
        rgba = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        toWorker.send(_Frame(
          TransferableTypedData.fromList([rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes)]),
          frame.image.width,
          frame.image.height,
          frame.duration.inMilliseconds,
        ));
      } finally {
        frame.image.dispose();
      }
      sent++;
      while (sent - encoded > _framesInFlight) {
        await waitForEncoder();
      }
    }
    while (encoded < frameCount) {
      await waitForEncoder();
    }
    return (await next() as TransferableTypedData).materialize().asUint8List();
  } finally {
    codec.dispose();
    isolate?.kill(priority: Isolate.immediate);
    await messages.cancel();
    replies.close();
  }
}

class _EncodeJob {
  final SendPort replies;
  final StickerFormat format;
  final int frameCount;

  _EncodeJob(this.replies, this.format, this.frameCount);
}

class _Frame {
  final TransferableTypedData rgba;
  final int width;
  final int height;
  final int durationMs;

  _Frame(this.rgba, this.width, this.height, this.durationMs);
}

class _EncodeError {
  final String message;

  _EncodeError(this.message);
}

/// Replies with its frame port, then the number of frames encoded after each
/// frame, then the encoded file.
void _encodeWorker(_EncodeJob job) {
  final frames = ReceivePort();
  job.replies.send(frames.sendPort);
  final encoder = switch (job.format) {
    StickerFormat.gif => _GifFrameEncoder(),
    StickerFormat.png => _PngFrameEncoder(job.frameCount),
    StickerFormat.jpeg => _JpegFrameEncoder(),
    StickerFormat.webp => _WebpFrameEncoder(),
  };
  var encoded = 0;
  frames.listen((message) {
    try {
      final frame = message as _Frame;
      final image = img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.rgba.materialize(),
        numChannels: 4,
        frameDuration: frame.durationMs,
      );
      encoder.add(image);
      job.replies.send(++encoded);
      if (encoded == job.frameCount) {
        job.replies.send(TransferableTypedData.fromList([encoder.finish()]));
        frames.close();
      }
    } catch (e) {
      job.replies.send(_EncodeError(e.toString()));
      frames.close();
    }
  });
}

abstract class _FrameEncoder {
  /// Adds an RGBA frame whose [img.Image.frameDuration] is in milliseconds.
  void add(img.Image frame);

  Uint8List finish();
}

class _GifFrameEncoder implements _FrameEncoder {
  final _encoder = img.GifEncoder(repeat: 0);

  @override
  void add(img.Image frame) {
    // GIF delays are in hundredths of a second, and most viewers treat delays
    // under 2 as 10, which would slow the animation down.
    final delay = (frame.frameDuration / 10).round();
    _encoder.addFrame(_quantize(frame), duration: delay < 2 ? 2 : delay);
  }

  @override
  Uint8List finish() => _encoder.finish()!;
}

class _PngFrameEncoder implements _FrameEncoder {
  final _encoder = img.PngEncoder();

  _PngFrameEncoder(int frameCount) {
    // More than one frame produces an animated PNG.
    _encoder.start(frameCount);
  }

  @override
  void add(img.Image frame) => _encoder.addFrame(frame);

  @override
  Uint8List finish() => _encoder.finish()!;
}

class _JpegFrameEncoder implements _FrameEncoder {
  img.Image? _frame;

  @override
  void add(img.Image frame) {
    // JPEG has no transparency, so the sticker goes on a white background.
    final canvas = img.Image(width: frame.width, height: frame.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    _frame = img.compositeImage(canvas, frame);
  }

  @override
  Uint8List finish() => img.encodeJpg(_frame!, quality: 90);
}

/// Only used for stickers that are not WebP already, which is rare, so frames
/// are simply collected into one animation.
class _WebpFrameEncoder implements _FrameEncoder {
  img.Image? _animation;

  @override
  void add(img.Image frame) {
    if (_animation == null) {
      _animation = frame;
    } else {
      _animation!.addFrame(frame);
    }
  }

  @override
  Uint8List finish() => img.encodeWebP(_animation!);
}

/// Reduces [frame] to a 256 color palette whose first entry is transparent.
///
/// Uses a median cut over a 15-bit color histogram. This is much faster than
/// the image package's neural quantizer and dithering, and looks the same on
/// the flat colors stickers are usually made of.
img.Image _quantize(img.Image frame) {
  const bins = 1 << 15;
  const transparent = 0xFFFF;
  final rgba = frame.toUint8List();
  final pixelCount = frame.width * frame.height;
  final counts = Int32List(bins);
  final sumR = Int32List(bins);
  final sumG = Int32List(bins);
  final sumB = Int32List(bins);
  final pixelBins = Uint16List(pixelCount);

  for (var p = 0, i = 0; p < pixelCount; p++, i += 4) {
    // GIF transparency is on or off.
    if (rgba[i + 3] < 128) {
      pixelBins[p] = transparent;
      continue;
    }
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final bin = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    pixelBins[p] = bin;
    counts[bin]++;
    sumR[bin] += r;
    sumG[bin] += g;
    sumB[bin] += b;
  }

  final used = Int32List.fromList([
    for (var bin = 0; bin < bins; bin++)
      if (counts[bin] > 0) bin,
  ]);
  final boxes = <_Box>[if (used.isNotEmpty) _Box(used, counts, 0, used.length)];
  // Index 0 is reserved for transparent pixels.
  while (boxes.length < 255) {
    var best = -1;
    var bestScore = 0;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].score > bestScore) {
        bestScore = boxes[i].score;
        best = i;
      }
    }
    if (best == -1) break;
    boxes.addAll(boxes.removeAt(best).split(used, counts));
  }

  final palette = img.PaletteUint8(256, 4);
  final lookup = Uint8List(bins);
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i];
    var r = 0, g = 0, b = 0;
    for (var j = box.start; j < box.end; j++) {
      final bin = used[j];
      r += sumR[bin];
      g += sumG[bin];
      b += sumB[bin];
      lookup[bin] = i + 1;
    }
    palette.setRgba(i + 1, r ~/ box.count, g ~/ box.count, b ~/ box.count, 255);
  }

  final indices = Uint8List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final bin = pixelBins[p];
    if (bin != transparent) indices[p] = lookup[bin];
  }
  return img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: indices.buffer,
    numChannels: 1,
    palette: palette,
  );
}

/// A range of histogram bins in the median cut.
class _Box {
  final int start;
  final int end;
  int count = 0;

  /// Channel with the widest range, as the shift of its 5 bits in a bin.
  int _axisShift = 0;

  /// Splitting priority; zero when the box cannot be split.
  int score = 0;

  _Box(Int32List used, Int32List counts, this.start, this.end) {
    final min = [31, 31, 31], max = [0, 0, 0];
    for (var i = start; i < end; i++) {
      final bin = used[i];
      count += counts[bin];
      for (var c = 0; c < 3; c++) {
        final value = (bin >> (10 - 5 * c)) & 31;
        if (value < min[c]) min[c] = value;
        if (value > max[c]) max[c] = value;
      }
    }
    var widest = 0;
    for (var c = 0; c < 3; c++) {
      final range = max[c] - min[c];
      if (range > widest) {
        widest = range;
        _axisShift = 10 - 5 * c;
      }
    }
    if (end - start > 1) score = count * widest;
  }

  /// Splits at the median pixel along the widest channel.
  List<_Box> split(Int32List used, Int32List counts) {
    final shift = _axisShift;
    final sorted = used.sublist(start, end)..sort((a, b) => ((a >> shift) & 31) - ((b >> shift) & 31));
    used.setRange(start, end, sorted);
    var middle = start + 1;
    for (var i = start, seen = 0; i < end - 1; i++) {
      seen += counts[used[i]];
      middle = i + 1;
      if (seen * 2 >= count) break;
    }
    return [_Box(used, counts, start, middle), _Box(used, counts, middle, end)];
  }
}
