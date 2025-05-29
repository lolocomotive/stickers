import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/edit_text_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/widgets/draw_layer.dart';
import 'package:stickers/src/widgets/text_layer.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class EditPage extends StatefulWidget {
  /// Path of the temporary image to edit
  final String imagePath;
  final StickerPack pack;
  final int index;

  const EditPage(this.pack, this.index, this.imagePath, {super.key});

  static const routeName = "/edit";

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final File _source;
  Size imageSize = const Size(0, 0);
  bool _drawing = false;
  Color _brushColor = Colors.white;
  double _brushSize = 15;
  Offset _brushPos = Offset(0, 0);
  final Curve _curve = Curves.ease;
  final List<UndoEntry> _undo = [];

  /// The sticker is 512x512 as opposed to the canvas, which is why we need a scale factor
  double scaleFactor = 0;
  final List<EditorText> _texts = [];
  final List<EditorLayer> _layers = [];

  TextLayer? _currentTextLayer;

  @override
  void initState() {
    super.initState();
    _source = File(widget.imagePath);
    //_sticker = _pack.stickers[widget.index];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.editYourSticker),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        _drawing = false;
                        EditorText text = EditorText(
                          text: "",
                          transform: Matrix4.identity(),
                          fontSize: 40 * scaleFactor,
                          textColor: Colors.white,
                        );
                        _texts.add(text);
                        _layers.add(TextLayer(text));

                        setState(() {});
                      },
                      label: Text("Add Text"),
                      icon: Icon(Icons.format_size),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: AnimatedCrossFade(
                        firstChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () {
                                setState(() {
                                  _drawing = true;
                                });
                              },
                              label: Text("Draw"),
                              icon: Icon(Icons.draw),
                            ),
                          ],
                        ),
                        secondChild: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Theme(
                              data: ThemeData(
                                colorScheme: ColorScheme.fromSeed(
                                    seedColor: Colors.green, brightness: Theme.of(context).brightness),
                              ),
                              child: FilledButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _drawing = false;
                                  });
                                },
                                label: Text("Done"),
                                icon: Icon(Icons.check),
                              ),
                            ),
                          ],
                        ),
                        crossFadeState: _drawing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        duration: Duration(milliseconds: 200)),
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
                sizeCurve: _curve,
                firstCurve: _curve,
                secondCurve: _curve,
                firstChild: Container(),
                secondChild: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: colors
                          .getRange(0, (colors.length / 2).floor())
                          .map((c) => ColorButton(
                                c,
                                size: (MediaQuery.of(context).size.width - 48) / (colors.length / 2),
                                onTap: () => _setColor(c),
                                active: c == _brushColor,
                              ))
                          .toList(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: colors
                          .getRange((colors.length / 2).floor() + 1, colors.length)
                          .map((c) => ColorButton(
                                c,
                                size: (MediaQuery.of(context).size.width - 48) / (colors.length / 2),
                                onTap: () => _setColor(c),
                                active: c == _brushColor,
                              ))
                          .toList(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(color: _brushColor, borderRadius: BorderRadius.circular(10)),
                            height: 7,
                            width: 7,
                          ),
                          Expanded(
                            child: Slider(
                                activeColor: _brushColor,
                                min: 7,
                                max: 150,
                                value: _brushSize,
                                onChanged: (value) {
                                  setState(() {
                                    _brushSize = value;
                                  });
                                }),
                          ),
                          Container(
                            decoration: BoxDecoration(color: _brushColor, borderRadius: BorderRadius.circular(25)),
                            height: 25,
                            width: 25,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                crossFadeState: _drawing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200)),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    color: Colors.black,
                    child: CustomPaint(
                      painter: CheckerPainter(context, sizeCallback: (size) {
                        if (imageSize != size) {
                          imageSize = size;
                          scaleFactor = size.width / 512;
                          if (size.aspectRatio != 1) {
                            // That should never happen
                            print("Aspect ratio of sticker should be 1");
                          }
                          WidgetsBinding.instance.addPostFrameCallback(
                            (timeStamp) => setState(() {}),
                          );
                        }
                      }),
                      child: MatrixGestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onGestureStart: (Offset focalPoint) {
                          if (_drawing) {
                            _undo.clear();
                            _brushPos = focalPoint;
                            if (_layers.lastOrNull is! DrawLayer) {
                              _layers.add(DrawLayer()..painter.scaleFactor = scaleFactor);
                            }
                            final painter = (_layers.last as DrawLayer).painter;

                            painter.strokes.add(Stroke(_brushColor, _brushSize));
                            setState(() {});
                            return;
                          }
                          double minDistance = double.infinity;
                          for (final TextLayer layer in _layers.whereType<TextLayer>()) {
                            Vector4 center = Vector4(scaleFactor * 256, scaleFactor * 256, 1, 1);
                            center.applyMatrix4(layer.text.transform);
                            Offset position = Offset(center.x, center.y);
                            Offset delta = position - focalPoint;
                            if (minDistance > delta.distanceSquared) {
                              minDistance = delta.distanceSquared;
                              _currentTextLayer = layer;
                            }
                          }
                        },
                        onMatrixUpdate: (matrix, translationDeltaMatrix, scaleDeltaMatrix, rotationDeltaMatrix) {
                          if (_drawing) {
                            _brushPos = Offset(_brushPos.dx + translationDeltaMatrix.row0.w,
                                _brushPos.dy + translationDeltaMatrix.row1.w);
                            (_layers.last as DrawLayer).painter.strokes.last.points.add(_brushPos / scaleFactor);
                            setState(() {});
                            return;
                          }

                          if (_currentTextLayer == null) return;
                          // If we just use matrix here it breaks when switching between layers
                          var newTransform = _currentTextLayer!.text.transform;
                          newTransform = translationDeltaMatrix * newTransform;
                          newTransform = scaleDeltaMatrix * newTransform;
                          newTransform = rotationDeltaMatrix * newTransform;
                          _currentTextLayer!.update(newTransform);
                        },
                        child: Stack(children: [
                          Image.file(_source),
                          ..._layers.map(
                            (e) => Positioned(
                              top: 0,
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: e,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
                sizeCurve: _curve,
                firstCurve: _curve,
                secondCurve: _curve,
                firstChild: Container(),
                secondChild: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed:
                            _layers.whereType<DrawLayer>().where((layer) => layer.painter.strokes.isNotEmpty).isEmpty
                                ? null
                                : () {
                                    final layer = _layers
                                        .whereType<DrawLayer>()
                                        .lastWhere((layer) => layer.painter.strokes.isNotEmpty);
                                    _undo.add(UndoEntry(layer.painter.strokes.removeLast(), layer.painter));
                                    setState(() {});
                                  },
                        label: Text("Undo"),
                        icon: Icon(Icons.undo),
                      ),
                    ),
                    SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _undo.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  final entry = _undo.removeLast();
                                  entry.painter.strokes.add(entry.stroke);
                                });
                              },
                        label: Text("Redo"),
                        icon: Icon(Icons.redo),
                      ),
                    ),
                  ]),
                ),
                crossFadeState: _drawing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200)),
            SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final option = ImageEditorOption();

                // for (EditorText text in _texts) {
                //   final transform = text.transform.storage;
                //   transform[12] = transform[12] / scaleFactor;
                //   transform[13] = transform[13] / scaleFactor;
                //   text.fontSize /= scaleFactor;
                //
                //   textOption.addText(text);
                // }

                for (EditorLayer layer in _layers) {
                  final Option layerOption;
                  if (layer is TextLayer) {
                    layerOption = AddTextOption();
                    final transform = layer.text.transform.storage;
                    transform[12] = transform[12] / scaleFactor;
                    transform[13] = transform[13] / scaleFactor;
                    layer.text.fontSize /= scaleFactor;
                    (layerOption as AddTextOption).addText(layer.text);
                  } else if (layer is DrawLayer) {
                    layerOption = layer.drawOption;
                  } else {
                    throw UnimplementedError();
                  }
                  option.addOption(layerOption);
                }

                option.outputFormat = const OutputFormat.webp_lossy();

                final data = await ImageEditor.editFileImage(file: _source, imageEditorOption: option);
                addToPack(widget.pack, widget.index, data!);
                if (!context.mounted) return;
                Navigator.of(context).pop();
                Navigator.of(context).pop();

                //This is useless if the screen goes away but useful for debugging
                for (EditorText text in _texts) {
                  final transform = text.transform.storage;
                  transform[12] = transform[12] * scaleFactor;
                  transform[13] = transform[13] * scaleFactor;
                  text.fontSize *= scaleFactor;
                }
              },
              child: Text(AppLocalizations.of(context)!.done),
            )
          ],
        ),
      ),
    );
  }

  _setColor(Color c) {
    setState(() {
      _brushColor = c;
    });
  }
}

class UndoEntry {
  final Stroke stroke;
  final DrawingPainter painter;

  UndoEntry(this.stroke, this.painter);
}

abstract class EditorLayer extends Widget {}
