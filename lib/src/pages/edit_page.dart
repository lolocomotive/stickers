import 'dart:convert';
import 'dart:io';
import 'dart:math' hide log;
import 'dart:ui' as ui;

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
import 'package:stickers/src/app.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/frame_decoder.dart';
import 'package:stickers/src/video/frame_export.dart';
import 'package:stickers/src/video/overlay_encode.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/draw_layer.dart';
import 'package:stickers/src/widgets/text_layer.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:video_player/video_player.dart';

class EditPage extends StatefulWidget {
  /// Path of the temporary image to edit
  final String? mediaPath;
  final StickerPack pack;
  final int index;
  final String? editorData;

  /// If true, use frames from FrameCache instead of decoding mediaPath
  final bool useFrameCache;

  const EditPage(
    this.pack,
    this.index,
    this.mediaPath,
    this.editorData,
    this.mediaType, {
    this.useFrameCache = false,
    super.key,
  });

  static const routeName = "/edit";

  final MediaType mediaType;

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> with TickerProviderStateMixin {
  late final File _source;
  Size imageSize = const Size(0, 0);
  int _fileSize = 0;
  Duration? _duration;
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

  // Frame-based player for animated WebP (preserves alpha)
  FrameDecoderService? _frameDecoder;

  @override
  void initState() {
    super.initState();
    if (widget.mediaPath == null) {
      EditorData data = EditorData.fromJson(
        jsonDecode(File(widget.editorData!).readAsStringSync()),
        _rbKey,
      );
      _source = File(data.background);
      for (final layer in data.layers) {
        if (layer is TextLayer) {
          final newLayer = TextLayer(
            layer.text,
            key: GlobalKey<TextLayerState>(),
            onDelete: layer.onDelete,
            rbKey: layer.rbKey,
            openNextFrame: false,
          );
          _layers.add(newLayer);
          _texts.add(layer.text);
        } else {
          _layers.add(layer);
        }
      }
    } else {
      _source = File(widget.mediaPath!);
    }
    try {
      _fileSize = _source.lengthSync();
    } catch (e) {
      print("Error getting file size: $e");
    }
    if (widget.mediaType == MediaType.animatedWebp) {
      // Initialize frame decoder for export functionality
      _frameDecoder = FrameDecoderService();
      _loadFrameDecoder();
    } else if (widget.mediaType == MediaType.video) {
      _controller = VideoPlayerController.file(
        _source,
        viewType: VideoViewType.textureView,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller.setLooping(true);
      _controller.setVolume(0);
      _controller.initialize().then((_) {
        _controller.play();
        _duration = _controller.value.duration;
        setState(() {});
      });
    }
    //_sticker = _pack.stickers[widget.index];
  }

  Future<void> _loadFrameDecoder() async {
    if (_frameDecoder == null) return;

    final success = await _frameDecoder!.decode(widget.mediaPath!);
    if (success && mounted) {
      _duration = _frameDecoder!.metadata!.totalDuration;
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (widget.mediaType == MediaType.video) {
      _controller.dispose();
    }
    _frameDecoder?.dispose();
    super.dispose();
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
        bool shouldPop =
            await showDialog<bool>(
              context: context,
              builder: (builderContext) => ConfirmLeaveDialog(),
            ) ??
            false;
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: DefaultActivity(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(
            _duration != null
                ? '${AppLocalizations.of(context)!.editYourSticker} (${getDurationString(_duration!)})'
                : AppLocalizations.of(context)!.editYourSticker,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isHorizontal = constraints.maxWidth > constraints.maxHeight;
              final double buttonSize = isHorizontal
                  ? (min(constraints.maxHeight - 48, 500 - 12)) /
                        (colors.length / 2)
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
                      children: colors
                          .getRange(0, (colors.length / 2).floor())
                          .map((c) {
                            return ColorButton(
                              c,
                              size: buttonSize,
                              onTap: () => _setColor(c),
                              active: c == _brushColor,
                            );
                          })
                          .toList(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: colors
                          .getRange(
                            (colors.length / 2).floor() + 1,
                            colors.length,
                          )
                          .map(
                            (c) => ColorButton(
                              c,
                              size: buttonSize,
                              onTap: () => _setColor(c),
                              active: c == _brushColor,
                            ),
                          )
                          .toList(),
                    ),
                    SizedBox(
                      height: 10,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: _brushColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                              },
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: _brushColor,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            height: 25,
                            width: 25,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                crossFadeState: _drawing
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200),
              );

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
                        colorScheme: ColorScheme.fromSeed(
                          seedColor: Colors.green,
                          brightness: Theme.of(context).brightness,
                        ),
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
                crossFadeState: _drawing
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200),
              );

              var editButtons = Padding(
                padding: const EdgeInsets.only(bottom: 6),
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

              final imageDisplay = LayoutBuilder(
                builder: (context, constraints) {
                  if (scaleFactor != constraints.biggest.width / 512) {
                    //FIXME this probably breaks when the screen size changes
                    scaleFactor = constraints.biggest.width / 512;

                    // We have to do this after loading from json
                    // We cannot do this in initState because scaleFactor cannot be defined there.
                    denormalizeTexts();
                    for (final layer in _layers) {
                      if (layer is DrawLayer) {
                        layer.painter.scaleFactor = scaleFactor;
                      }
                    }
                  }
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                    ),
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
                                painter: CheckerPainter(
                                  context,
                                  sizeCallback: (size) {
                                    if (imageSize != size) {
                                      imageSize = size;

                                      if (size.aspectRatio != 1) {
                                        // That should never happen
                                        print(
                                          "Aspect ratio of sticker should be 1",
                                        );
                                      }
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (timeStamp) => setState(() {}),
                                          );
                                    }
                                  },
                                ),
                                child: MatrixGestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onGestureStart: onGestureStart,
                                  onMatrixUpdate:
                                      (
                                        _,
                                        translationDeltaMatrix,
                                        scaleDeltaMatrix,
                                        rotationDeltaMatrix,
                                      ) => onMatrixUpdate(
                                        translationDeltaMatrix,
                                        scaleDeltaMatrix,
                                        rotationDeltaMatrix,
                                      ),
                                  child: Stack(
                                    children: [
                                      if (widget.mediaType == MediaType.picture)
                                        Image.file(
                                          _source,
                                          fit: BoxFit.fill,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Center(
                                                    child: Icon(
                                                      Icons.broken_image,
                                                      size: 64,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                        )
                                      else if (widget.mediaType ==
                                          MediaType.animatedWebp)
                                        Image.file(
                                          _source,
                                          fit: BoxFit.fill,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Center(
                                                    child: Icon(
                                                      Icons.broken_image,
                                                      size: 64,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                        )
                                      else
                                        Center(
                                          child: AspectRatio(
                                            aspectRatio:
                                                _controller.value.aspectRatio,
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
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withAlpha(200),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  AppLocalizations.of(
                                                    context,
                                                  )!.exporting,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.displaySmall,
                                                ),
                                                SizedBox(
                                                  height: 12,
                                                ),
                                                SizedBox(
                                                  height: 64,
                                                  width: 64,
                                                  child:
                                                      CircularProgressIndicator(
                                                        year2023: false,
                                                        value: _exportProgress,
                                                      ),
                                                ),
                                                Text(
                                                  _message ?? "",
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

              final undoButtons = AnimatedCrossFade(
                sizeCurve: _curve,
                firstCurve: _curve,
                secondCurve: _curve,
                firstChild: Container(),
                secondChild: Padding(
                  padding: isHorizontal
                      ? EdgeInsets.zero
                      : EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              _layers
                                  .whereType<DrawLayer>()
                                  .where(
                                    (layer) => layer.painter.strokes.isNotEmpty,
                                  )
                                  .isEmpty
                              ? null
                              : () {
                                  final layer = _layers
                                      .whereType<DrawLayer>()
                                      .lastWhere(
                                        (layer) =>
                                            layer.painter.strokes.isNotEmpty,
                                      );
                                  _undo.add(
                                    UndoEntry(
                                      layer.painter.strokes.removeLast(),
                                      layer.painter,
                                    ),
                                  );
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
                    ],
                  ),
                ),
                crossFadeState: _drawing
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 200),
              );

              // Declare compressionOption before the Row to avoid syntax error
              Widget compressionOption = SizedBox();
              if (!_drawing &&
                  (widget.mediaType == MediaType.video ||
                      widget.mediaType == MediaType.animatedWebp)) {
                compressionOption = ListenableBuilder(
                  listenable: settingsController,
                  builder: (context, _) {
                    return ListTile(
                      onTap: () async {
                        settingsController.updateCompressionMethod(
                          (settingsController.compressionMethod + 1) % 2,
                        );
                      },
                      leading: const Icon(Icons.compress),
                      title: Text(
                        AppLocalizations.of(context)!.compressionMethod,
                      ),
                      trailing: Text(
                        settingsController.compressionMethod == 0
                            ? AppLocalizations.of(context)!.reduceQuality
                            : AppLocalizations.of(context)!.reduceFPS,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    );
                  },
                );
              }

              var doneButton = _drawing
                  ? SizedBox()
                  : Row(
                      children: [
                        if (widget.editorData != null)
                          FilledButton.tonalIcon(
                            onPressed: _exporting
                                ? null
                                : () async {
                                    await addSticker(context, replace: true);
                                  },
                            icon: Icon(Icons.refresh),
                            label: Text("Replace"),
                          ),
                        if (widget.editorData != null)
                          SizedBox(
                            width: 12,
                          ),
                        Expanded(
                          child: FilledButton.icon(
                            icon: Icon(Icons.done),
                            onPressed: _exporting
                                ? null
                                : () async {
                                    await addSticker(context);
                                  },
                            label: Text(
                              AppLocalizations.of(context)!.addToPack,
                            ),
                          ),
                        ),
                      ],
                    );
              if (isHorizontal) {
                final double halfWidth = min(
                  constraints.maxHeight - 16,
                  min(500, constraints.maxWidth / 2 - 16),
                );
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    editButtons,
                                    colorButtons,
                                    undoButtons,
                                    if (_drawing) SizedBox(height: 12),
                                    compressionOption,
                                    doneButton,
                                  ],
                                ),
                              ),
                            ),
                          ),
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
                          imageDisplay,
                          if (_fileSize > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '${getFileSizeString(_fileSize, _source.path)}${_duration != null ? ' ${getDurationString(_duration!)}' : ''}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          colorButtons,
                          editButtons,
                          undoButtons,
                          SizedBox(height: 12),
                          compressionOption,
                          doneButton,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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
    _texts.add(text);
    _layers.add(
      TextLayer(
        text,
        key: GlobalKey<TextLayerState>(),
        rbKey: _rbKey,
        onDelete: (layer) {
          _layers.remove(layer);
          if (_currentTextLayer == layer) _currentTextLayer = null;
          setState(() {});
        },
      ),
    );

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
          layer.text.fontSize *=
              FontsRegistry.sizeMultiplier(layer.text.fontName) ?? 1;
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
        data = (await ImageEditor.editFileImage(
          file: _source,
          imageEditorOption: option,
        ))!;
      } else if (widget.mediaType == MediaType.animatedWebp) {
        data = await exportAnimatedWebpSticker(option, context);
      } else {
        data = await exportAnimatedSticker(option, context);
      }

      // Validate frame count for animated stickers before adding to pack
      // Skip validation for video type - video pipeline already validates
      // Only validate animatedWebp, and use native decoder (FFprobe doesn't work for WebP)
      if (widget.mediaType == MediaType.animatedWebp) {
        // Write the data to a temporary file to validate frame count
        final tempValidationPath = "$mediaCacheDir/validate_${uid()}.webp";
        final tempFile = File(tempValidationPath);
        await tempFile.writeAsBytes(data);

        try {
          // Use Flutter's native image codec to count frames (FFprobe can't handle WebP animations)
          final bytes = await tempFile.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frameCount = codec.frameCount;
          codec.dispose();

          if (frameCount < 2) {
            // Clean up temp file
            await tempFile.delete();

            // Reset state before showing error
            _message = null;
            setState(() {
              _exporting = false;
            });

            if (mounted) {
              String errorMessage;
              if (frameCount == 0) {
                errorMessage = AppLocalizations.of(
                  context,
                )!.trimResultedInZeroFrames;
              } else {
                errorMessage = AppLocalizations.of(
                  context,
                )!.trimResultedInSingleFrame;
              }
              showDialog(
                context: context,
                builder: (context) {
                  return ErrorDialog(
                    title: AppLocalizations.of(context)!.couldntExportSticker,
                    message: errorMessage,
                  );
                },
              );
            }
            return;
          }

          // Clean up validation file (we'll use the in-memory data)
          await tempFile.delete();
        } catch (e) {
          // Clean up on error
          try {
            await tempFile.delete();
          } catch (_) {}
          // Continue - if validation fails, still try to add the sticker
          print("Frame validation error (continuing): $e");
        }
      }

      final editorData = EditorData(background: _source.path, layers: _layers);
      if (replace) {
        await addToPack(widget.pack, widget.index, data, editorData, replace);
      } else {
        await addToPack(
          widget.pack,
          widget.pack.stickers.length,
          data,
          editorData,
        );
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
              message:
                  AppLocalizations.of(context)!.errorMessage + e.toString(),
            );
          },
        );
      }
    } finally {
      //This is useless if the screen goes away but useful for debugging
      denormalizeTexts();
      setState(() {
        _exporting = false;
      });
    }
    return;
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

  Future<Uint8List> exportAnimatedSticker(
    ImageEditorOption option,
    BuildContext context,
  ) async {
    final transparent = await rootBundle.load("assets/transparent.webp");
    final out = await ImageEditor.editImageAndGetFile(
      image: transparent.buffer.asUint8List(),
      imageEditorOption: option,
    );
    final service = OverlayAndEncodeService();
    final output = File("$mediaCacheDir/exported_${uid()}.webp");

    Uint8List? data;
    double quality = 80;
    double speed = 1.0;

    // Check duration limit
    final totalDuration = _controller.value.duration;
    if (totalDuration > const Duration(seconds: 10)) {
      speed =
          totalDuration.inMilliseconds /
          10000.0; // Adjusted to use milliseconds for precision
    }

    const int fps = 24;
    const int maxAttempts = 5;
    const double targetKB = 500;
    const double minQuality = 10;
    const double maxSpeed = 5.0;
    double? previousSize;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (context.mounted) {
        _message = attempt == 0
            ? AppLocalizations.of(context)!.firstAttempt
            : "${AppLocalizations.of(context)!.secondAttempt} (${attempt + 1}/$maxAttempts)";
        setState(() {});
      }

      final config = WebPConfig(
        lossless: false,
        quality: quality,
        alphaCompression: 1,
        method: 4,
      );

      await service.start(
        videoFile: _source.path,
        overlayFile: out.path,
        outputFile: output.path,
        config: config,
        fps: fps,
        speed: speed,
      );

      await for (final update in service.progressStream) {
        if (update.status == Status.success) break;
        if (update.status == Status.running) {
          _exportProgress = update.progress;
          setState(() {});
        } else if (update.status == Status.failed && context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ErrorDialog(
              title: AppLocalizations.of(ctx)!.exportWebpFailed,
              message: AppLocalizations.of(ctx)!.exportWebpFailedMsg,
            ),
          );
        }
      }

      data = await output.readAsBytes();
      final sizeKB = data.lengthInBytes / 1000;
      print(
        "Attempt ${attempt + 1}: ${sizeKB.toStringAsFixed(1)}KB (q=${quality.toStringAsFixed(1)}, speed=${speed.toStringAsFixed(2)}x)",
      );

      if (previousSize != null && sizeKB >= previousSize - 0.1) {
        quality = max(quality * 0.8, minQuality);
      }
      previousSize = sizeKB;

      // Stop as soon as we're under the max size.
      // We never try to "increase size" via reprocessing.
      if (sizeKB <= targetKB) break;

      final ratio = sizeKB / targetKB;

      final method = context.mounted
          ? (StickersApp.of(
                  context,
                )?.widget.settingsController.compressionMethod ??
                0)
          : 0;

      if (method == 0) {
        // MODE: Reduce Quality — preserve FPS and duration if possible
        // WebP quality-size relationship is roughly quadratic: size ∝ sqrt(quality)
        // So to achieve target size: new_quality = old_quality * (target/current)^2
        final sizeRatio = targetKB / sizeKB; // < 1 when over target
        final targetQuality = quality * pow(sizeRatio, 2.0) * 0.85;
        quality = max(targetQuality, minQuality);

        // If quality hits floor, use speed as fallback
        if (quality <= minQuality + 0.1) {
          speed = min(speed * ratio, maxSpeed);
        }
      } else {
        // MODE: Fasten — reduce duration (speed up), preserve quality
        // Speed-size relationship is linear: size ∝ 1/speed
        // So to achieve target size: new_speed = old_speed * (current/target)
        final sizeRatio = targetKB / sizeKB; // < 1 when over target
        final targetSpeed = speed / sizeRatio;

        if (targetSpeed <= maxSpeed) {
          speed = targetSpeed;
        } else {
          // If we hit the speed cap, use quality as a secondary lever
          speed = maxSpeed;
          final remainingRatio =
              targetSpeed / maxSpeed; // how much more we needed
          if (quality > minQuality + 0.1) {
            // Use quadratic quality formula for the remainder
            final targetQuality =
                quality * pow(1.0 / remainingRatio, 2.0) * 0.85;
            quality = max(targetQuality, minQuality);
          }
        }
      }
    }

    if (data!.lengthInBytes / 1000 > targetKB) {
      if (context.mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx)!.stickerTooLarge),
            content: Text(AppLocalizations.of(ctx)!.stickerTooLargeMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(ctx)!.ok),
              ),
            ],
          ),
        );
      }
      throw Exception("Sticker too large");
    }

    return data;
  }

  /// Export animated WebP sticker using frame-based pipeline (preserves alpha)
  Future<Uint8List> exportAnimatedWebpSticker(
    ImageEditorOption option,
    BuildContext context,
  ) async {
    if (_frameDecoder == null || !_frameDecoder!.isReady) {
      throw Exception("Frame decoder not ready");
    }

    final transparent = await rootBundle.load("assets/transparent.webp");
    final out = await ImageEditor.editImageAndGetFile(
      image: transparent.buffer.asUint8List(),
      imageEditorOption: option,
    );

    final exportService = FrameExportService();
    final output = File("$mediaCacheDir/exported_${uid()}.webp");

    Uint8List? data;

    // Check if source file is already small enough
    double sourceSize = 0;
    try {
      if (_source.existsSync()) {
        sourceSize = _source.lengthSync() / 1000; // KB
      }
    } catch (e) {
      debugPrint("Error getting source size: $e");
    }

    // Start with higher quality if source is already small
    double quality = sourceSize <= 400 ? 90 : 80;
    double speed = 1.0;

    // Check duration limit
    final totalDuration = _frameDecoder!.metadata!.totalDuration;
    if (totalDuration > const Duration(seconds: 10)) {
      speed =
          totalDuration.inMilliseconds /
          10000.0; // Adjusted to use milliseconds for precision
    }

    const int maxAttempts = 5;
    const double targetKB = 500;
    const double minQuality = 10;
    const double maxSpeed = 5.0;
    double? previousSize;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (context.mounted) {
        _message = attempt == 0
            ? AppLocalizations.of(context)!.firstAttempt
            : "${AppLocalizations.of(context)!.secondAttempt} (${attempt + 1}/$maxAttempts)";
        setState(() {});
      }

      // Calculate which frames to use based on speed
      final allFrames = _frameDecoder!.frames!;
      final List<DecodedFrame> framesToExport;
      final double fps;

      if (speed > 1.0) {
        // Skip frames to speed up (reduce duration)
        final skipInterval = speed.round().clamp(1, allFrames.length);
        framesToExport = [];
        for (int i = 0; i < allFrames.length; i += skipInterval) {
          framesToExport.add(allFrames[i]);
        }
        // FPS must match the target duration: frames / (original_duration / speed)
        final targetDurationSeconds = totalDuration.inSeconds / speed;
        fps = framesToExport.length / targetDurationSeconds;
      } else {
        framesToExport = allFrames;
        fps = _frameDecoder!.metadata!.fps;
      }

      final success = await exportService.exportFramesWithOverlay(
        frames: framesToExport,
        overlayPath: out.path,
        outputPath: output.path,
        fps: fps,
        quality: quality.round(),
      );

      if (!success) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ErrorDialog(
              title: AppLocalizations.of(ctx)!.exportWebpFailed,
              message: AppLocalizations.of(ctx)!.exportWebpFailedMsg,
            ),
          );
        }
        throw Exception("Export failed");
      }

      data = await output.readAsBytes();
      final sizeKB = data.lengthInBytes / 1000;
      print(
        "Attempt ${attempt + 1}: ${sizeKB.toStringAsFixed(1)}KB (q=${quality.toStringAsFixed(1)}, speed=${speed.toStringAsFixed(2)}x)",
      );

      if (previousSize != null && sizeKB >= previousSize - 0.1) {
        quality = max(quality * 0.8, minQuality);
      }
      previousSize = sizeKB;

      if (sizeKB <= targetKB) break;

      final ratio = sizeKB / targetKB;

      final method = context.mounted
          ? (StickersApp.of(
                  context,
                )?.widget.settingsController.compressionMethod ??
                0)
          : 0;

      if (method == 0) {
        // MODE: Reduce Quality — preserve frame count if possible
        // WebP quality-size relationship is roughly quadratic: size ∝ sqrt(quality)
        final sizeRatio = targetKB / sizeKB;
        final targetQuality = quality * pow(sizeRatio, 2.0) * 0.85;
        quality = max(targetQuality, minQuality);

        if (quality <= minQuality + 0.1) {
          speed = min(speed * ratio, maxSpeed);
        }
      } else {
        // MODE: Reduce Frames — skip frames to reduce file size, preserve quality
        // Speed-size relationship is linear: size ∝ 1/speed
        final sizeRatio = targetKB / sizeKB;
        final targetSpeed = speed / sizeRatio;

        if (targetSpeed <= maxSpeed) {
          speed = targetSpeed;
        } else {
          speed = maxSpeed;
          final remainingRatio = targetSpeed / maxSpeed;
          if (quality > minQuality + 0.1) {
            final targetQuality =
                quality * pow(1.0 / remainingRatio, 2.0) * 0.85;
            quality = max(targetQuality, minQuality);
          }
        }
      }
    }

    if (data!.lengthInBytes / 1000 > targetKB) {
      if (context.mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx)!.stickerTooLarge),
            content: Text(AppLocalizations.of(ctx)!.stickerTooLargeMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(ctx)!.ok),
              ),
            ],
          ),
        );
      }
      throw Exception("Sticker too large");
    }

    return data;
  }

  void onMatrixUpdate(
    Matrix4 translationDeltaMatrix,
    Matrix4 scaleDeltaMatrix,
    Matrix4 rotationDeltaMatrix,
  ) {
    if (_drawing) {
      _brushPos = Offset(
        _brushPos.dx + translationDeltaMatrix.row0.w,
        _brushPos.dy + translationDeltaMatrix.row1.w,
      );
      (_layers.last as DrawLayer).painter.strokes.last.points.add(
        _brushPos / scaleFactor,
      );
      setState(() {});
      return;
    }

    if (_currentTextLayer == null) return;
    // If we just use matrix here it breaks when switching between layers
    var newTransform = _currentTextLayer!.text.transform;
    newTransform = translationDeltaMatrix * newTransform;
    newTransform = scaleDeltaMatrix * newTransform;
    newTransform = rotationDeltaMatrix * newTransform;
    (_currentTextLayer!.key as GlobalKey<TextLayerState>).currentState!.update(newTransform);
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
        builder: (context) => EyedropperDialog(
          _rbKey.currentContext!.findRenderObject() as RenderRepaintBoundary,
        ),
      );
      c = _pickedColor!;
    }
    setState(() {
      _brushColor = c;
    });
  }

  Map<String, dynamic> toJson() {
    return {
      "layers": _layers.map((layer) => layer.toJson()).toList(),
    };
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
