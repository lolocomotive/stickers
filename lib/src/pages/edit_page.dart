import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' hide log;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_editor/image_editor.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/editor_data.dart';
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
import 'package:stickers/src/video/gif_transcoder.dart';
import 'package:stickers/src/video/overlay_encode.dart';
import 'package:stickers/src/widgets/draw_layer.dart';
import 'package:stickers/src/widgets/text_layer.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:video_player/video_player.dart';

import '../util.dart';

class EditPage extends StatefulWidget {
  /// Path of the temporary image to edit
  final String? mediaPath;
  final StickerPack pack;
  final int index;
  final String? editorData;
  final bool returnResult;

  const EditPage(this.pack, this.index, this.mediaType, {super.key, this.mediaPath, this.editorData, this.returnResult = false});

  static const routeName = "/edit";

  final StickerMediaType mediaType;

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
  bool _isWebpVideo = false;

  /// The sticker is 512x512 as opposed to the canvas, which is why we need a scale factor
  double scaleFactor = 0;
  final List<EditorLayer> _layers = [];

  Iterable<EditorText> get _texts => _layers.whereType<TextLayer>().map((layer) => layer.text);

  TextLayer? _currentTextLayer;

  @override
  void initState() {
    super.initState();
    final data = widget.editorData == null ? null : _loadEditorData(widget.editorData!);
    if (data != null) {
      _source = File(data.background);
      for (final layer in data.layers) {
        _layers.add(layer is TextLayer ? _createTextLayer(layer.text, openEditor: false) : layer);
      }
    } else {
      // Without usable editor data, the sticker itself is the background.
      _source = File(widget.mediaPath ?? widget.pack.stickers[widget.index].source);
    }
    _isWebpVideo = widget.mediaType == StickerMediaType.video &&
        _source.path.toLowerCase().endsWith('.webp');
    if (widget.mediaType == StickerMediaType.video && !_isWebpVideo) {
      final controller = VideoPlayerController.file(
        _source,
        viewType: VideoViewType.textureView,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      controller.setLooping(true);
      controller.setVolume(0);
      controller.initialize().then((_) {
        if (!mounted) return;
        controller.play();
        setState(() {});
      });
    }
  }

  /// Returns null when the saved data can't be used.
  EditorData? _loadEditorData(String path) {
    try {
      final data = EditorData.fromJson(jsonDecode(File(path).readAsStringSync()), _rbKey);
      if (!File(data.background).existsSync()) {
        throw FileSystemException("Background not found", data.background);
      }
      return data;
    } catch (e) {
      debugPrint("Couldn't load editor data $path: $e");
      return null;
    }
  }

  TextLayer _createTextLayer(EditorText text, {bool openEditor = true}) {
    return TextLayer(
      text,
      rbKey: _rbKey,
      openNextFrame: openEditor,
      onDelete: (layer) {
        _layers.remove(layer);
        if (_currentTextLayer == layer) _currentTextLayer = null;
        setState(() {});
      },
    );
  }

  /// Whether this edits a sticker already in the pack, which can be replaced.
  bool get _editsExistingSticker => !widget.returnResult && widget.index < widget.pack.stickers.length;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  final GlobalKey _rbKey = GlobalKey();
  bool _exporting = false;
  VideoPlayerController? _controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        if (_exporting || _message != null) {
          return;
        }
        bool shouldPop = await showDialog<bool>(
              context: context,
              builder: (builderContext) => ConfirmLeaveDialog(),
            ) ??
            false;
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Stack(
        children: [
          DefaultActivity(
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
                      onPressed: _addText,
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

            final imageDisplay = LayoutBuilder(builder: (context, constraints) {
              final newScaleFactor = constraints.biggest.width / 512;
              if (scaleFactor != newScaleFactor) {
                if (scaleFactor == 0) {
                  scaleFactor = newScaleFactor;
                  // We have to do this after loading from json
                  // We cannot do this in initState because scaleFactor cannot be defined there.
                  denormalizeTexts();
                } else {
                  // The canvas was resized, e.g. on rotation; texts are in canvas coordinates.
                  _scaleTexts(newScaleFactor / scaleFactor);
                  scaleFactor = newScaleFactor;
                }
                for (final layer in _layers) {
                  if (layer is DrawLayer) {
                    layer.painter.scaleFactor = scaleFactor;
                  }
                }
              }
              return Container(
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
                                if (widget.mediaType == StickerMediaType.picture || _isWebpVideo)
                                  Image.file(_source)
                                else if (_controller != null && _controller!.value.isInitialized)
                                  Center(
                                    child: AspectRatio(
                                      aspectRatio: _controller!.value.aspectRatio,
                                      child: VideoPlayer(_controller!),
                                    ),
                                  )
                                else
                                  const SizedBox.expand(),
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
                      ),
                    ],
                  ),
                ),
              );
            });

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
                      onPressed: _layers
                              .whereType<DrawLayer>()
                              .where((layer) => layer.painter.strokes.isNotEmpty)
                              .isEmpty
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
                    width: 8,
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
                  SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: Tooltip(
                      message: AppLocalizations.of(context)!.clearDrawings,
                      child: FilledButton.tonalIcon(
                        onPressed: _hasDrawings ? _clearDrawings : null,
                        label: Text(AppLocalizations.of(context)!.clear),
                        icon: Icon(Icons.delete),
                      ),
                    ),
                  ),
                ]),
              ),
              crossFadeState: _drawing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: Duration(milliseconds: 200),
            );

            var doneButton = Row(
              children: [
                if (_editsExistingSticker)
                  FilledButton.tonal(
                    onPressed: _exporting
                        ? null
                        : () async {
                            await addSticker(context, replace: true);
                          },
                    child: Text(AppLocalizations.of(context)!.replace),
                  ),
                if (_editsExistingSticker)
                  SizedBox(
                    width: 16,
                  ),
                Expanded(
                  child: FilledButton.icon(
                    icon: Icon(Icons.done),
                    onPressed: _exporting
                        ? null
                        : () async {
                            await addSticker(context);
                          },
                    label: Text(AppLocalizations.of(context)!.addToPack),
                  ),
                ),
              ],
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
      if (_message != null) ...[
        Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Theme.of(context).colorScheme.surface.withAlpha(200),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            // Outside the Scaffold, so it needs its own Material for text styling
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.exporting,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(
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
                    const SizedBox(
                      height: 12,
                    ),
                    Text(
                      _message ?? "",
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  ),
);
  }

  void _addText() {
    _drawing = false;
    EditorText text = EditorText(
      outlineWidth: 10,
      outlineColor: Colors.transparent,
      text: "",
      transform: Matrix4.identity(),
      fontSize: 40,
      textColor: Colors.white,
    );
    _layers.add(_createTextLayer(text));

    setState(() {});
  }

  Future<void> addSticker(BuildContext context, {bool replace = false}) async {
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
      if (widget.mediaType == StickerMediaType.picture) {
        data = (await ImageEditor.editFileImage(file: _source, imageEditorOption: option))!;
      } else {
        data = await exportAnimatedSticker(option, context);
      }
      final editorData = EditorData(background: _source.path, layers: _layers);
      if (widget.returnResult) {
        if (!context.mounted) return;
        Navigator.of(context).pop(data);
        return;
      }
      if (replace) {
        await addToPack(widget.pack, widget.index, data, editorData, replace);
      } else {
        await addToPack(widget.pack, widget.pack.stickers.length, data, editorData);
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (mounted) {
        showDialog(
            context: context,
            builder: (context) {
              return ErrorDialog(
                title: AppLocalizations.of(context)!.couldntExportSticker,
                message: AppLocalizations.of(context)!.errorMessage + e.toString(),
              );
            });
      }
    } finally {
      //This is useless if the screen goes away but useful for debugging
      denormalizeTexts();
      if (mounted) {
        setState(() {
          _exporting = false;
          _message = null;
          _exportProgress = null;
        });
      }
    }
    return;
  }

  void _scaleTexts(double ratio) {
    for (EditorText text in _texts) {
      final transform = text.transform.storage;
      transform[12] *= ratio;
      transform[13] *= ratio;
      text.fontSize *= ratio;
      text.outlineWidth *= ratio;
    }
  }

  void denormalizeTexts() {
    for (EditorText text in _texts) {
      final transform = text.transform.storage;
      transform[12] = transform[12] * scaleFactor;
      transform[13] = transform[13] * scaleFactor;
      text.fontSize *= scaleFactor;
      text.outlineWidth *= scaleFactor;
      text.fontSize /= FontsRegistry.sizeMultiplier(text.fontName) ?? 1;
    }
  }

  Future<Uint8List> exportAnimatedSticker(ImageEditorOption option, BuildContext context) async {
    if (_isWebpVideo && _layers.isEmpty && _texts.isEmpty) {
      return await _source.readAsBytes();
    }
    final transparent = await rootBundle.load("assets/transparent.webp");
    final out =
        await ImageEditor.editImageAndGetFile(image: transparent.buffer.asUint8List(), imageEditorOption: option);
    if (_isWebpVideo) {
      if (context.mounted) {
        _message = AppLocalizations.of(context)!.firstAttempt;
        setState(() {});
      }
      final result = await GifTranscoder.transcodeWebpWithOverlay(
        webpPath: _source.path,
        overlayBytes: await out.readAsBytes(),
      );
      if (result.lengthInBytes / 1024 > 500) {
        if (!context.mounted) throw Exception();
        showDialog(
          context: context,
          builder: (context) {
            return ErrorDialog(
              title: AppLocalizations.of(context)!.exportWebpFailed,
              message: AppLocalizations.of(context)!.stickerTooLargeMsg,
            );
          },
        );
        throw Exception("WebP file too big");
      }
      return result;
    }
    final service = OverlayAndEncodeService();
    final output = File("$mediaCacheDir/exported_${uid()}.webp");
    Stopwatch sw = Stopwatch()..start();
    Uint8List? data;
    double quality = 60;
    int fps = 24;

    for (int attempt = 0; attempt < 3; attempt++) {
      if (context.mounted) {
        switch (attempt) {
          case 0:
            _message = AppLocalizations.of(context)!.firstAttempt;
          case 1:
            _message = AppLocalizations.of(context)!.secondAttempt;
          case 2:
            _message = AppLocalizations.of(context)!.thirdAttempt;
        }
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
                  title: AppLocalizations.of(context)!.exportWebpFailed,
                  message: AppLocalizations.of(context)!.exportWebpFailedMsg,
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
          title: Text(AppLocalizations.of(context)!.stickerTooLarge),
          content: Text(AppLocalizations.of(context)!.stickerTooLargeMsg),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                AppLocalizations.of(context)!.ok,
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

  bool get _hasDrawings =>
      _layers.whereType<DrawLayer>().any((layer) => layer.painter.strokes.isNotEmpty);

  void _clearDrawings() {
    _layers.removeWhere((layer) => layer is DrawLayer);
    _undo.clear();
    setState(() {});
  }

  Map<String, dynamic> toJson() {
    return {
      "layers": _layers.map((layer) => layer.toJson()).toList(),
    };
  }

  void _dumpLayers() {
    print("Layers:");
    for (final layer in _layers) {
      log(layer.toJson().toString());
    }
  }
}

class UndoEntry {
  final Stroke stroke;
  final DrawingPainter painter;

  UndoEntry(this.stroke, this.painter);
}

abstract class EditorLayer extends Widget {
  const EditorLayer({super.key});

  Map<String, dynamic> toJson();

  static EditorLayer fromJson(Map<String, dynamic> json, GlobalKey rbKey) {
    switch (json["type"]) {
      case "draw":
        return DrawLayer.fromJson(json);
      case "text":
        return TextLayer.fromJson(json, rbKey);
      case "image":
        throw Exception("Not supported yet");
      default:
        throw Exception("Unsupported layer type");
    }
  }
}
