import 'dart:typed_data';
import 'dart:ui' as ui;

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
    print(_samplePosition);
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
              body: Column(
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
                          _samplePosition = details.localPosition;
                          print(_samplePosition);

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
    }
  }
}
