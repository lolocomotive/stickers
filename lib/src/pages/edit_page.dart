import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_editor/image_editor.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/confirm_leave_dialog.dart';
import 'package:stickers/src/dialogs/edit_text_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/dialogs/eyedropper_dialog.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/overlay_encode.dart';
import 'package:stickers/src/widgets/draw_layer.dart';
import 'package:stickers/src/widgets/text_layer.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:video_player/video_player.dart';

class EditPage extends StatefulWidget {
  /// Path of the temporary image to edit
  final String imagePath;
  final StickerPack pack;
  final int index;

  const EditPage(this.pack, this.index, this.imagePath, this.mediaType, {super.key});

  static const routeName = "/edit";

  final MediaType mediaType;

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
  Color? _pickedColor;
  final Curve _curve = Curves.ease;
  final List<UndoEntry> _undo = [];
  final double maxWidth = 200;
  String? _message;
  double? _exportProgress;

  /// The sticker is 512x512 as opposed to the canvas, which is why we need a scale factor
  double scaleFactor = 0;
  final List<EditorText> _texts = [];
  final List<EditorLayer> _layers = [];

  TextLayer? _currentTextLayer;

  @override
  void initState() {
    super.initState();
    _source = File(widget.imagePath);
    if (widget.mediaType == MediaType.video) {
      _controller = VideoPlayerController.file(
        _source,
        viewType: VideoViewType.textureView,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller.setLooping(true);
      _controller.setVolume(0);
      _controller.initialize().then((_) {
        _controller.play();
        setState(() {});
      });
    }
    //_sticker = _pack.stickers[widget.index];
  }

  final GlobalKey _rbKey = GlobalKey();
  bool _exporting = false;
  late VideoPlayerController _controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        bool shouldPop = await showDialog<bool>(
              context: context,
              builder: (builderContext) => ConfirmLeaveDialog(),
            ) ??
            false;
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: DefaultActivity(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.editYourSticker),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final isHorizontal = constraints.maxWidth > constraints.maxHeight;
            final double buttonSize = isHorizontal
                ? (min(constraints.maxHeight - 48, 500 - 12)) / (colors.length / 2)
                : min(constraints.maxWidth - 48, 500) / (colors.length / 2);
                
            final colorButtons = AnimatedCrossFade(
                sizeCurve: _curve,
                firstCurve: _curve,
                secondCurve: _curve,
                firstChild: Container(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: colors.getRange(0, (colors.length / 2).floor()).map((c) {
                        return ColorButton(
                          c,
                          size: buttonSize,
                          onTap: () => _setColor(c),
                          active: c == _brushColor,
                        );
                      }).toList(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: colors
                          .getRange((colors.length / 2).floor() + 1, colors.length)
                          .map((c) => ColorButton(
                                c,
                                size: buttonSize,
                                onTap: () => _setColor(c),
                                active: c == _brushColor,
                              ))
                          .toList(),
                    ),
                    SizedBox(
                      height: 10,
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
                duration: Duration(milliseconds: 200));
                
            final drawButton = AnimatedCrossFade(
                firstChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() {
                          _drawing = true;
                        });
                      },
                      label: Text(AppLocalizations.of(context)!.draw),
                      icon: Icon(Icons.draw),
                    ),
                  ],
                ),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Theme(
                      data: ThemeData(
                        colorScheme:
                            ColorScheme.fromSeed(seedColor: Colors.green, brightness: Theme.of(context).brightness),
                      ),
                      child: FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _drawing = false;
                          });
                        },
                        label: Text(AppLocalizations.of(context)!.done),
                        icon: Icon(Icons.check),
                      ),
                    ),
                  ],
                ),
                crossFadeState: _drawing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200));
                
            var editButtons = Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        _drawing = false;
                        EditorText text = EditorText(
                          outlineWidth: 10,
                          outlineColor: Colors.transparent,
                          text: "",
                          transform: Matrix4.identity(),
                          fontSize: 40,
                          textColor: Colors.white,
                        );
                        _texts.add(text);
                        _layers.add(TextLayer(
                          text,
                          rbKey: _rbKey,
                          onDelete: (layer) {
                            _layers.remove(layer);
                            if (_currentTextLayer == layer) _currentTextLayer = null;
                            setState(() {});
                          },
                        ));
                
                        setState(() {});
                      },
                      label: Text(AppLocalizations.of(context)!.addText),
                      icon: Icon(Icons.format_size),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: drawButton,
                  ),
                ],
              ),
            );
                
            final imageDisplay = Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: RepaintBoundary(
                key: _rbKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: Colors.black,
                      child: AspectRatio(
                        aspectRatio: 1,
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
                            onGestureStart: onGestureStart,
                            onMatrixUpdate: (_, translationDeltaMatrix, scaleDeltaMatrix, rotationDeltaMatrix) =>
                                onMatrixUpdate(translationDeltaMatrix, scaleDeltaMatrix, rotationDeltaMatrix),
                            child: Stack(children: [
                              if (widget.mediaType == MediaType.picture)
                                Image.file(_source)
                              else
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: _controller.value.aspectRatio,
                                    child: VideoPlayer(_controller),
                                  ),
                                ),
                              ..._layers.map(
                                (e) => Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: e,
                                ),
                              ),
                              if (_message != null)
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    color: Theme.of(context).colorScheme.surface.withAlpha(200),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          "Exporting",
                                          style: Theme.of(context).textTheme.displaySmall,
                                        ),
                                        SizedBox(
                                          height: 12,
                                        ),
                                        SizedBox(
                                          height: 64,
                                          width: 64,
                                          child: CircularProgressIndicator(
                                            year2023: false,
                                            value: _exportProgress,
                                          ),
                                        ),
                                        Text(_message ?? ""),
                                      ],
                                    ),
                                  ),
                                )
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
                
            final undoButtons = AnimatedCrossFade(
              sizeCurve: _curve,
              firstCurve: _curve,
              secondCurve: _curve,
              firstChild: Container(),
              secondChild: Padding(
                padding: isHorizontal ? EdgeInsets.zero : EdgeInsets.only(top: 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _layers.whereType<DrawLayer>().where((layer) => layer.painter.strokes.isNotEmpty).isEmpty
                          ? null
                          : () {
                              final layer =
                                  _layers.whereType<DrawLayer>().lastWhere((layer) => layer.painter.strokes.isNotEmpty);
                              _undo.add(UndoEntry(layer.painter.strokes.removeLast(), layer.painter));
                              setState(() {});
                            },
                      label: Text(AppLocalizations.of(context)!.undo),
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
                      label: Text(AppLocalizations.of(context)!.redo),
                      icon: Icon(Icons.redo),
                    ),
                  ),
                ]),
              ),
              crossFadeState: _drawing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: Duration(milliseconds: 200),
            );
                
            var doneButton = FilledButton.icon(
              icon: Icon(Icons.done),
              onPressed: _exporting
                  ? null
                  : () async {
                      await onDone(context);
                    },
              label: Text(AppLocalizations.of(context)!.addToPack),
            );
            if (isHorizontal) {
              final double halfWidth = min(constraints.maxHeight - 16, min(500, constraints.maxWidth / 2 - 16));
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 1024),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: halfWidth),
                          child: imageDisplay,
                        ),
                        SizedBox(
                          width: 12,
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: halfWidth),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  editButtons,
                                  colorButtons,
                                  undoButtons,
                                  if (_drawing) SizedBox(height: 12),
                                  doneButton,
                                ],
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 512),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        editButtons,
                        colorButtons,
                        imageDisplay,
                        undoButtons,
                        SizedBox(height: 12),
                        doneButton,
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Future<void> onDone(BuildContext context) async {
    setState(() {
      _exporting = true;
    });
    try {
      final option = ImageEditorOption();
      for (EditorLayer layer in _layers) {
        final Option layerOption;
        if (layer is TextLayer) {
          layerOption = AddTextOption();
          final transform = layer.text.transform.storage;
          transform[12] = transform[12] / scaleFactor;
          transform[13] = transform[13] / scaleFactor;
          layer.text.fontSize /= scaleFactor;
          layer.text.outlineWidth /= scaleFactor;
          layer.text.fontSize *= FontsRegistry.sizeMultiplier(layer.text.fontName) ?? 1;
          (layerOption as AddTextOption).addText(layer.text);
        } else if (layer is DrawLayer) {
          layerOption = layer.drawOption;
        } else {
          throw UnimplementedError();
        }
        option.addOption(layerOption);
      }

      option.outputFormat = const OutputFormat.webp_lossy();

      final Uint8List data;
      if (widget.mediaType == MediaType.picture) {
        data = (await ImageEditor.editFileImage(file: _source, imageEditorOption: option))!;
      } else {
        data = await exportAnimatedSticker(option, context);
      }
      addToPack(widget.pack, widget.index, data);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (mounted) {
        showDialog(
            context: context,
            builder: (context) {
              return ErrorDialog(
                title: "Couldn't export sticker",
                message: "Error message: $e",
              );
            });
      }
    } finally {
      //This is useless if the screen goes away but useful for debugging
      for (EditorText text in _texts) {
        final transform = text.transform.storage;
        transform[12] = transform[12] * scaleFactor;
        transform[13] = transform[13] * scaleFactor;
        text.fontSize *= scaleFactor;
        text.outlineWidth *= scaleFactor;
        text.fontSize /= FontsRegistry.sizeMultiplier(text.fontName) ?? 1;
      }
      setState(() {
        _exporting = false;
      });
    }
    return;
  }

  Future<Uint8List> exportAnimatedSticker(ImageEditorOption option, BuildContext context) async {
    final transparent = await rootBundle.load("assets/transparent.webp");
    final out =
        await ImageEditor.editImageAndGetFile(image: transparent.buffer.asUint8List(), imageEditorOption: option);
    final service = OverlayAndEncodeService();
    final output =
        File("$mediaCacheDir/exported_${DateTime.now().millisecondsSinceEpoch}.webp");
    Stopwatch sw = Stopwatch()..start();
    Uint8List? data;
    double quality = 60;
    int fps = 24;

    for (int attempt = 0; attempt < 3; attempt++) {
      switch (attempt) {
        case 0:
          _message = "First attempt";
        case 1:
          _message = "Result too big, re-encoding with lower quality";
        case 2:
          _message = "Last attempt";
      }
      setState(() {});
      var config = WebPConfig(
        lossless: false,
        quality: quality,
        alphaCompression: 1,
        method: 4,
      );
      await service.start(
          videoFile: _source.path, overlayFile: out.path, outputFile: output.path, config: config, fps: fps);
      await for (final update in service.progressStream) {
        if (update.status == Status.SUCCESS) {
          break;
        } else if (update.status == Status.RUNNING) {
          _exportProgress = update.progress;
          setState(() {});
        } else if (update.status == Status.FAILED) {
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (context) {
                return ErrorDialog(
                  title: "Exporting to WebP failed",
                  message: "Try again, or with another sticker. If the issue persists, submit an issue on GitHub.",
                );
              },
            );
          }
        }
      }
      print("Exported WebP in ${sw.elapsedMilliseconds}ms");
      data = await output.readAsBytes();
      print("Output size: ${data.lengthInBytes / 1024}kiB");
      if (data.lengthInBytes / 1024 < 500) {
        break;
      } else {
        print("Result is ${data.lengthInBytes / 500 / 1024} times too big");
        if (data.lengthInBytes / 1024 > 550) {
          // If the sticker is really too large, the only solution is to drop frames
          fps = (fps / (data.lengthInBytes / 1024) * 550).round();
        }
        quality -= 20;
        print("New configuration: q=$quality fps=$fps");
      }
    }
    if (data!.lengthInBytes / 1024 > 500) {
      if (!context.mounted) throw Exception();
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Sticker too large"),
          content: Text(
              "Even when encoding at very low quality settings, the sticker still exceeds the maximum size requirement of 512kB. Please use a shorter video."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                "Okay",
              ),
            )
          ],
        ),
      );
      throw Exception("Sticker too large");
    }
    return data;
  }

  void onMatrixUpdate(Matrix4 translationDeltaMatrix, Matrix4 scaleDeltaMatrix, Matrix4 rotationDeltaMatrix) {
    if (_drawing) {
      _brushPos = Offset(_brushPos.dx + translationDeltaMatrix.row0.w, _brushPos.dy + translationDeltaMatrix.row1.w);
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
    return;
  }

  void onGestureStart(Offset focalPoint) {
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
    return;
  }

  void _setColor(Color c) async {
    if (c == Colors.transparent) {
      _pickedColor = await showDialog(
          context: context,
          builder: (context) => EyedropperDialog(_rbKey.currentContext!.findRenderObject() as RenderRepaintBoundary));
      c = _pickedColor!;
    }
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

abstract class EditorLayer extends Widget {
  const EditorLayer({super.key});
}
