import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
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
                    maxScale: 8.0,
                    cropRectPadding: const EdgeInsets.all(40.0),
                    hitTestSize: 80.0,
                    cropAspectRatio: null,
                    cornerColor: Theme.of(context).colorScheme.primary,
                    cornerSize: const Size(30, 5),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: FilledButton(
              onPressed: () async {
                final state = widget.editorKey.currentState!;
                final cropped = await cropSticker(state.getCropRect()!, state.rawImageData, widget.pack, widget.index);
                final output = await saveTemp(cropped);
                if (!context.mounted) return;
                Navigator.of(context).pushNamed(
                  "/edit",
                  arguments: EditArguments(
                    pack: widget.pack,
                    index: widget.index,
                    imagePath: output.path,
                  ),
                );
              },
              child: Text(AppLocalizations.of(context)!.done),
            ),
          ),
        ],
      ),
    );
  }
}

class EditArguments {
  StickerPack pack;

  // Index 30 is tray icon
  int index;
  String imagePath;

  EditArguments({required this.pack, required this.index, required this.imagePath});
}
