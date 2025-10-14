import 'dart:io';
import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/default_page.dart';

class CropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey<ExtendedImageEditorState>();

  CropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/crop";

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> with TickerProviderStateMixin {
  late final AnimationController _maskColorController;
  final ImageEditorController _editorController = ImageEditorController();

  bool _previousPtrVal = false;

  @override
  void initState() {
    super.initState();
    _maskColorController = AnimationController(vsync: this);
    Tween<double> tween = Tween(begin: 0.0, end: 1.0);
    Animation anim = CurvedAnimation(parent: _maskColorController, curve: Curves.ease, reverseCurve: Curves.ease);
    anim.drive(tween);
    _maskColorController.addListener(_animationListener);
  }

  void _animationListener() {
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    _maskColorController.removeListener(_animationListener);
    _maskColorController.dispose();
  }

  double? _aspectRatio;

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.cropYourSticker),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        //TODO make loading less abrupt
        children: [
          Expanded(
            child: Container(
              // The clip and empty BoxDecoration is intentional, sometimes the done button doesn't appear otherwise
              // See: https://github.com/lolocomotive/stickers/issues/1
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              child: ExtendedImage.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
                beforePaintImage: (canvas, rect, image, paint) {
                  CheckerPainter.checkerPainter(canvas, rect, context);
                  return false;
                },
                mode: ExtendedImageMode.editor,
                extendedImageEditorKey: widget.editorKey,
                cacheRawData: true,
                initEditorConfigHandler: (state) {
                  return EditorConfig(
                    editorMaskColorHandler: (ctx, pointerDown) {
                      if (_previousPtrVal && !pointerDown) {
                        _maskColorController.animateTo(1, duration: Duration(milliseconds: 150));
                      }
                      if (!_previousPtrVal && pointerDown) {
                        _maskColorController.animateTo(0, duration: Duration(milliseconds: 150));
                      }
                      _previousPtrVal = pointerDown;
                      return Color.lerp(
                        Theme.of(context).colorScheme.surface.withAlpha(50),
                        Theme.of(context).colorScheme.surface.withAlpha(200),
                        _maskColorController.value,
                      )!;
                    },
                    animationCurve: Curves.ease,
                    tickerDuration: Duration(),
                    lineHeight: 3,
                    lineColor: Theme.of(context).colorScheme.primary.withAlpha(100),
                    animationDuration: const Duration(milliseconds: 400),
                    maxScale: double.infinity,
                    cropRectPadding: const EdgeInsets.all(40.0),
                    hitTestSize: 80.0,
                    cropAspectRatio: _aspectRatio,
                    cornerColor: Theme.of(context).colorScheme.primary,
                    cornerSize: const Size(30, 5),
                    controller: _editorController,
                  );
                },
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      _editorController.rotate(degree: -90, animation: true);
                    },
                    icon: Icon(Icons.rotate_left),
                  ),
                  IconButton(
                    onPressed: () {
                      _editorController.rotate(degree: 90, animation: true);
                    },
                    icon: Icon(Icons.rotate_right),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SegmentedButton<double>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  multiSelectionEnabled: false,
                  segments: [
                    ButtonSegment(
                        value: 16 / 9,
                        icon: Column(children: [
                          Icon(Icons.crop_16_9),
                          Text(
                            "16:9",
                            style: TextStyle(fontSize: 10),
                          )
                        ])),
                    ButtonSegment(
                        value: 3 / 2,
                        icon: Column(children: [
                          Icon(Icons.crop_3_2),
                          Text(
                            "3:2",
                            style: TextStyle(fontSize: 10),
                          )
                        ])),
                    ButtonSegment(
                        value: 1,
                        icon: Column(children: [
                          Icon(Icons.crop_din),
                          Text(
                            "1:1",
                            style: TextStyle(fontSize: 10),
                          )
                        ])),
                    ButtonSegment(
                        value: 2 / 3,
                        icon: Column(children: [
                          Transform.rotate(
                            angle: pi / 2,
                            child: Icon(Icons.crop_3_2),
                          ),
                          Text(
                            "2:3",
                            style: TextStyle(fontSize: 10),
                          )
                        ])),
                    ButtonSegment(
                        value: 9 / 16,
                        icon: Column(children: [
                          Transform.rotate(
                            angle: pi / 2,
                            child: Icon(Icons.crop_16_9),
                          ),
                          Text(
                            "9:16",
                            style: TextStyle(fontSize: 10),
                          )
                        ])),
                  ],
                  selected: {_aspectRatio == null ? 0 : _aspectRatio!},
                  onSelectionChanged: (v) {
                    setState(() {
                      _aspectRatio = v.firstOrNull;
                      HapticFeedback.lightImpact();
                    });
                  },
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: FilledButton(
                      onPressed: () async {
                        final state = widget.editorKey.currentState!;
                        if (state.getCropRect()!.height < .5 || state.getCropRect()!.width < .5) {
                          showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                    title: Text("Crop area too small"),
                                    content: Text("Must be at least 1x1 pixel"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Okay 💗")),
                                      FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text("Yay 💗")),
                                    ],
                                  ));
                          return;
                        }
                        final cropped = await cropSticker(state.getCropRect()!, state.rawImageData, widget.pack,
                            widget.index, _editorController.rotateDegrees);
                        final output = await saveTemp(cropped);
                        if (!context.mounted) return;
                        Navigator.of(context).pushNamed(
                          "/edit",
                          arguments: EditArguments(
                            pack: widget.pack,
                            index: widget.index,
                            mediaPath: output.path,
                          ),
                        );
                      },
                      child: Text(AppLocalizations.of(context)!.done),
                    ),
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }
}

enum MediaType {
  video,
  picture,
}

class EditArguments {
  StickerPack pack;

  // Index 30 is tray icon
  int index;
  String mediaPath;
  MediaType type;

  EditArguments({required this.pack, required this.index, required this.mediaPath, this.type = MediaType.picture});
}
