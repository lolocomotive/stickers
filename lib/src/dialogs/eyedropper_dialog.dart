import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class EyedropperDialog extends StatefulWidget {
  final RenderRepaintBoundary boundary;

  const EyedropperDialog(this.boundary, {super.key});

  @override
  State<EyedropperDialog> createState() => _EyedropperDialogState();
}

class _EyedropperDialogState extends State<EyedropperDialog> {
  final double size = 150;
  Future? _future;
  Color _color = Colors.black;
  HSLColor _hslColor = HSLColor.fromColor(Colors.black);
  Offset _samplePosition = Offset(0, 0);
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
  }

  Future<ui.Image> _getImage() async {
    final image = await widget.boundary.toImage(pixelRatio: MediaQuery.of(context).devicePixelRatio);
    if (mounted) {
      _samplePosition = Offset(image.width / 2 / MediaQuery.of(context).devicePixelRatio,
          image.height / 2 / MediaQuery.of(context).devicePixelRatio);
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

  @override
  Widget build(BuildContext context) {
    _future ??= _getImage();
    return FutureBuilder(
        future: _future,
        builder: (context, asyncSnapshot) {
          if (asyncSnapshot.hasData) {
            ui.Image img = asyncSnapshot.data!;
            return Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        "Pick a color",
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    Center(
                      child: Container(
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(), // For the clip to work
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            _samplePosition += details.delta;
                            _sampleColor(img);
                            setState(() {});
                          },
                          child: Stack(
                            children: [
                              RawImage(
                                width: img.width / MediaQuery.of(context).devicePixelRatio,
                                height: img.height / MediaQuery.of(context).devicePixelRatio,
                                image: asyncSnapshot.data,
                              ),
                              Positioned(
                                top: _samplePosition.dy,
                                left: _samplePosition.dx,
                                child: Transform.translate(
                                  offset: Offset(-size / 2, -size / 2),
                                  child: Stack(
                                    children: [
                                      Transform.translate(
                                        offset: Offset(0, size / 2),
                                        child: Container(
                                          height: 2,
                                          color: Colors.black,
                                          width: size,
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: Offset(size / 2, 0),
                                        child: Container(
                                          height: size,
                                          color: Colors.black,
                                          width: 2,
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: Offset(-2, -2),
                                        child: Container(
                                          height: size + 4,
                                          width: size + 4,
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.black, width: 24),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      // Color circle
                                      Container(
                                        height: size,
                                        width: size,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: _color, width: 20),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 16,
                    ),
                    Text(
                      "Adjust",
                      style: TextTheme.of(context).bodyLarge,
                    ),
                    HSLPicker(
                      onUpdate: (color) {
                        _hslColor = color;
                        _color = color.toColor();
                        setState(() {});
                      },
                      color: _hslColor,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Flexible(
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text("New color:"),
                              SizedBox(
                                width: 10,
                              ),
                              Container(
                                height: 30,
                                width: 60,
                                decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(8)),
                              ),
                            ]),
                          ),
                          Expanded(
                              child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(_color);
                                  },
                                  child: Text("Done")))
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            if (asyncSnapshot.hasError) {
              return Column(
                children: [
                  Text("Error"),
                  Text(asyncSnapshot.error!.toString()),
                ],
              );
            } else {
              return Center(
                child: CircularProgressIndicator(),
              );
            }
          }
        });
  }

  void _sampleColor(ui.Image image) {
    double px = _samplePosition.dx * MediaQuery.of(context).devicePixelRatio;
    double py = _samplePosition.dy * MediaQuery.of(context).devicePixelRatio;
    if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
      int index = (py.floor() * image.width + px.floor()) * 4;
      _color =
          Color.fromARGB(_imageData![index + 3], _imageData![index], _imageData![index + 1], _imageData![index + 2]);
      _hslColor = HSLColor.fromColor(_color);
    }
  }
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

  void _updateColor() {
    setState(() {});
    final _color = HSLColor.fromAHSL(1, _h, _s, _l);
    widget.onUpdate?.call(_color);
  }

  @override
  void initState() {
    super.initState();
    _updateFromWidgetColor();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackShape: GradientSliderTrackShape(null, _s, _l)),
          child: Slider(
              thumbColor: _color.toColor(),
              min: 0,
              max: 360,
              value: _h,
              onChanged: (v) {
                _h = v;
                _updateColor();
              }),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackShape: GradientSliderTrackShape(_h, null, _l)),
          child: Slider(
              thumbColor: _color.toColor(),
              min: 0,
              max: 1,
              value: _s,
              onChanged: (v) {
                _s = v;
                _updateColor();
              }),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackShape: GradientSliderTrackShape(_h, _s, null)),
          child: Slider(
              thumbColor: _color.toColor(),
              min: 0,
              max: 1,
              value: _l,
              onChanged: (v) {
                _l = v;
                _updateColor();
              }),
        ),
      ],
    );
  }
}

FragmentProgram? _hueGradientProgram;
FragmentProgram? _saturationGradientProgram;
FragmentProgram? _lightnessGradientProgram;

class GradientSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
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
  void paint(PaintingContext context, ui.Offset offset,
      {required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required Animation<double> enableAnimation,
      required ui.Offset thumbCenter,
      ui.Offset? secondaryOffset,
      bool? isEnabled,
      bool? isDiscrete,
      required ui.TextDirection textDirection}) {
    var barRect =
        Rect.fromCenter(center: parentBox.paintBounds.center, width: parentBox.paintBounds.width - 48, height: 10);
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
    context.canvas.drawRRect(RRect.fromRectAndRadius(barRect, Radius.circular(10)), _paint);
  }
}
