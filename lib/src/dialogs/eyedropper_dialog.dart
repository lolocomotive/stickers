import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

class EyedropperDialog extends StatefulWidget {
  final RenderRepaintBoundary boundary;

  const EyedropperDialog(this.boundary, {super.key});

  @override
  State<EyedropperDialog> createState() => _EyedropperDialogState();
}

class _EyedropperDialogState extends State<EyedropperDialog> {
  static const double _loupeSize = 152;
  Future<ui.Image>? _future;
  Color _color = Colors.black;
  HSLColor _hslColor = HSLColor.fromColor(Colors.black);

  /// Sampled point, in logical pixels of the captured image (not of its on-screen display).
  Offset _samplePosition = Offset(0, 0);
  Uint8List? _imageData;

  Future<ui.Image> _getImage() async {
    final image = await widget.boundary.toImage(pixelRatio: MediaQuery.of(context).devicePixelRatio);
    if (mounted) {
      _samplePosition = Offset(
        image.width / 2 / MediaQuery.of(context).devicePixelRatio,
        image.height / 2 / MediaQuery.of(context).devicePixelRatio,
      );
    }
    _decodeImage(image);
    return image;
  }

  void _decodeImage(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    _imageData = byteData!.buffer.asUint8List();
    _sampleColor(image);
    setState(() {});
  }

  void _moveSampleTo(Offset position, ui.Image image) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final maxX = (image.width - 1) / dpr;
    final maxY = (image.height - 1) / dpr;
    _samplePosition = Offset(position.dx.clamp(0, maxX), position.dy.clamp(0, maxY));
    _sampleColor(image);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _future ??= _getImage();
    return FutureBuilder(
      future: _future,
      builder: (context, asyncSnapshot) {
        final appBar = AppBar(title: Text(AppLocalizations.of(context)!.pickAColor));
        if (asyncSnapshot.hasData) {
          return Scaffold(
            appBar: appBar,
            body: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildImage(asyncSnapshot.data!),
                  ),
                ),
                _buildControls(context),
              ],
            ),
          );
        } else if (asyncSnapshot.hasError) {
          return Scaffold(
            appBar: appBar,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(context)!.error),
                  Text(asyncSnapshot.error!.toString()),
                ],
              ),
            ),
          );
        } else {
          return Scaffold(
            appBar: appBar,
            body: Center(child: CircularProgressIndicator()),
          );
        }
      },
    );
  }

  /// The captured image, scaled to fit the available space, with the loupe over the sampled point.
  /// Tapping jumps the loupe to the finger; dragging moves it relatively, for precision.
  Widget _buildImage(ui.Image img) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final imageSize = Size(img.width / dpr, img.height / dpr);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(constraints.maxWidth / imageSize.width, constraints.maxHeight / imageSize.height);
        final displaySize = imageSize * scale;
        return Center(
          child: SizedBox.fromSize(
            size: displaySize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _moveSampleTo(details.localPosition / scale, img),
              onPanUpdate: (details) => _moveSampleTo(_samplePosition + details.delta / scale, img),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RawImage(
                      image: img,
                      width: displaySize.width,
                      height: displaySize.height,
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned(
                    left: _samplePosition.dx * scale - _loupeSize / 2,
                    top: _samplePosition.dy * scale - _loupeSize / 2,
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.square(_loupeSize),
                        painter: _LoupePainter(
                          img,
                          Offset(
                            (_samplePosition.dx * dpr).floorToDouble(),
                            (_samplePosition.dy * dpr).floorToDouble(),
                          ),
                          _color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hex = (_color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  AppLocalizations.of(context)!.adjust,
                  style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              HSLPicker(
                onUpdate: (color) {
                  _hslColor = color;
                  _color = color.toColor();
                  setState(() {});
                },
                color: _hslColor,
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.outlineVariant, width: 2),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.newColor,
                          style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          '#$hex',
                          style: textTheme.titleMedium?.copyWith(fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_color);
                    },
                    icon: Icon(Icons.check),
                    label: Text(AppLocalizations.of(context)!.done),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sampleColor(ui.Image image) {
    if (_imageData == null) return;
    double px = _samplePosition.dx * MediaQuery.of(context).devicePixelRatio;
    double py = _samplePosition.dy * MediaQuery.of(context).devicePixelRatio;
    if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
      int index = (py.floor() * image.width + px.floor()) * 4;
      _color = Color.fromARGB(
        _imageData![index + 3],
        _imageData![index],
        _imageData![index + 1],
        _imageData![index + 2],
      );
      _hslColor = HSLColor.fromColor(_color);
    }
  }
}

/// A magnifier showing the pixels around the sampled one, enlarged with no smoothing, inside a
/// thick ring of the picked color. The sampled pixel is outlined in the middle.
class _LoupePainter extends CustomPainter {
  /// How many image pixels fit across the magnified area. Odd so the sampled pixel is centered.
  static const int _pixelsAcross = 15;
  static const double _ringWidth = 22;

  final ui.Image image;

  /// Sampled pixel, in physical pixels of [image].
  final Offset pixel;
  final Color color;

  _LoupePainter(this.image, this.pixel, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius - _ringWidth;
    final pixelSize = innerRadius * 2 / _pixelsAcross;
    final hairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black26;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)));
    // Shown where the magnified area extends past the image's edges
    canvas.drawColor(Colors.grey.shade800, BlendMode.src);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        pixel.dx - _pixelsAcross ~/ 2,
        pixel.dy - _pixelsAcross ~/ 2,
        _pixelsAcross.toDouble(),
        _pixelsAcross.toDouble(),
      ),
      Rect.fromCircle(center: center, radius: innerRadius),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      outerRadius - _ringWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth
        ..color = color.withAlpha(255),
    );
    // Hairlines keep the ring distinct when the image around it has the same color
    canvas.drawCircle(center, outerRadius - 0.5, hairline);
    canvas.drawCircle(center, innerRadius, hairline);

    final reticle = Rect.fromCenter(center: center, width: pixelSize, height: pixelSize);
    canvas.drawRect(
      reticle.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black54,
    );
    canvas.drawRect(
      reticle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_LoupePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.pixel != pixel || oldDelegate.color != color;
}

class HSLPicker extends StatefulWidget {
  final Function(HSLColor)? onUpdate;
  final HSLColor color;

  const HSLPicker({super.key, this.onUpdate, required this.color});

  @override
  State<HSLPicker> createState() => _HSLPickerState();
}

class _HSLPickerState extends State<HSLPicker> {
  late double _h;
  late double _s;
  late double _l;
  late HSLColor _color;

  @override
  void initState() {
    super.initState();
    _updateFromWidgetColor();
  }

  void _updateColor() {
    _color = HSLColor.fromAHSL(1, _h, _s, _l);
    widget.onUpdate?.call(_color);
    setState(() {});
  }

  void _updateFromWidgetColor() {
    _color = widget.color;
    _h = _color.hue;
    _s = _color.saturation;
    _l = _color.lightness;
  }

  @override
  void didUpdateWidget(covariant HSLPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFromWidgetColor();
  }

  Widget _buildSlider(
    String label,
    GradientSliderTrackShape trackShape,
    double max,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: trackShape,
              trackHeight: GradientSliderTrackShape.barHeight,
              thumbShape: const ColorSliderThumbShape(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
            ),
            child: Slider(
              thumbColor: _color.toColor().withAlpha(255),
              min: 0,
              max: max,
              value: value,
              onChanged: (v) {
                onChanged(v);
                _updateColor();
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSlider('H', GradientSliderTrackShape(null, _s, _l), 360, _h, (v) => _h = v),
        _buildSlider('S', GradientSliderTrackShape(_h, null, _l), 1, _s, (v) => _s = v),
        _buildSlider('L', GradientSliderTrackShape(_h, _s, null), 1, _l, (v) => _l = v),
      ],
    );
  }
}

FragmentProgram? _hueGradientProgram;
FragmentProgram? _saturationGradientProgram;
FragmentProgram? _lightnessGradientProgram;

class GradientSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  static const double barHeight = 16;

  double? h;
  double? s;
  double? l;
  final Paint _paint = Paint();

  GradientSliderTrackShape(this.h, this.s, this.l) {
    loadShaders();
  }

  void loadShaders() async {
    _hueGradientProgram ??= await FragmentProgram.fromAsset('assets/shaders/hue_gradient.frag');
    _saturationGradientProgram ??= await FragmentProgram.fromAsset('assets/shaders/saturation_gradient.frag');
    _lightnessGradientProgram ??= await FragmentProgram.fromAsset('assets/shaders/lightness_gradient.frag');
  }

  @override
  void paint(
    PaintingContext context,
    ui.Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required ui.Offset thumbCenter,
    ui.Offset? secondaryOffset,
    bool? isEnabled,
    bool? isDiscrete,
    required ui.TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme);
    // Extend the bar past the thumb's travel so its rounded ends sit under the knob at the extremes
    final barRect = Rect.fromCenter(center: trackRect.center, width: trackRect.width + barHeight, height: barHeight);
    final ui.FragmentProgram? program;
    if (h == null) {
      program = _hueGradientProgram;
    } else if (s == null) {
      program = _saturationGradientProgram;
    } else if (l == null) {
      program = _lightnessGradientProgram;
    } else {
      throw Exception("Exactly one of the HSL components should be null");
    }

    if (program != null) {
      final shader = program.fragmentShader();
      shader.setFloat(0, barRect.width);
      shader.setFloat(1, barRect.height);
      shader.setFloat(2, barRect.left);
      shader.setFloat(3, barRect.top);

      try {
        if (h == null) {
          shader.setFloat(4, s!);
          shader.setFloat(5, l!);
        } else if (s == null) {
          shader.setFloat(4, h!);
          shader.setFloat(5, l!);
        } else if (l == null) {
          shader.setFloat(4, h!);
          shader.setFloat(5, s!);
        }
      } on Exception catch (_) {
        throw Exception("Exactly one of the HSL components should be null");
      }

      _paint.shader = shader;
    }
    context.canvas.drawRRect(RRect.fromRectAndRadius(barRect, Radius.circular(barHeight / 2)), _paint);
  }
}

/// A round knob filled with the slider's current color, ringed in white so it stays visible on
/// any part of the gradient. It grows slightly while dragged.
class ColorSliderThumbShape extends SliderComponentShape {
  const ColorSliderThumbShape({this.radius = 13});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required ui.TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final r = radius * (1 + 0.15 * activationAnimation.value);
    canvas.drawShadow(Path()..addOval(Rect.fromCircle(center: center, radius: r)), Colors.black, 3, true);
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(center, r - 3, Paint()..color = sliderTheme.thumbColor ?? Colors.white);
  }
}
