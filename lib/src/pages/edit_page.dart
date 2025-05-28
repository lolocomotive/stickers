import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/default_page.dart';
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

  /// The sticker is 512x512 as opposed to the canvas, which is why we need a scale factor
  double scaleFactor = 0;
  final List<EditorText> _texts = [];
  final List<TextLayer> _layers = [];
  TextLayer? _currentLayer;

  @override
  void initState() {
    super.initState();
    _source = File(widget.imagePath);
    //_sticker = _pack.stickers[widget.index];
  }

  @override
  Widget build(BuildContext context) {
    //TODO add support for drawing
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
                    child: FilledButton.tonalIcon(
                      onPressed: () {},
                      label: Text("Draw"),
                      icon: Icon(Icons.draw),
                    ),
                  ),
                ],
              ),
            ),
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
                          double minDistance = double.infinity;
                          for (final layer in _layers) {
                            Vector4 center = Vector4(scaleFactor * 256, scaleFactor * 256, 1, 1);
                            center.applyMatrix4(layer.text.transform);
                            Offset position = Offset(center.x, center.y);
                            Offset delta = position - focalPoint;
                            if (minDistance > delta.distanceSquared) {
                              minDistance = delta.distanceSquared;
                              _currentLayer = layer;
                            }
                          }
                        },
                        onMatrixUpdate: (matrix, translationDeltaMatrix, scaleDeltaMatrix, rotationDeltaMatrix) {
                          if (_currentLayer == null) return;
                          // If we just use matrix here it breaks when switching between layers
                          var newTransform = _currentLayer!.text.transform;
                          newTransform = translationDeltaMatrix * newTransform;
                          newTransform = scaleDeltaMatrix * newTransform;
                          newTransform = rotationDeltaMatrix * newTransform;
                          _currentLayer!.update(newTransform);
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
            SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final option = ImageEditorOption();
                final textOption = AddTextOption();

                for (EditorText text in _texts) {
                  final transform = text.transform.storage;
                  transform[12] = transform[12] / scaleFactor;
                  transform[13] = transform[13] / scaleFactor;
                  text.fontSize /= scaleFactor;

                  textOption.addText(text);
                }

                option.addOption(textOption);
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
}
