import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
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

class _CropPageState extends State<CropPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: const Text("Crop your sticker"),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        //TODO  make loading less abrupt
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(color: Colors.black),
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
                    animationDuration: const Duration(milliseconds: 100),
                    maxScale: 8.0,
                    cropRectPadding: const EdgeInsets.all(40.0),
                    hitTestSize: 40.0,
                    cropAspectRatio: null,
                    cornerColor: Colors.black,
                    cornerSize: const Size(30, 4),
                  );
                },
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final state = widget.editorKey.currentState!;
              final cropped = await cropSticker(
                  state.getCropRect()!, state.rawImageData, widget.pack, widget.index);
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
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }
}

class EditArguments {
  StickerPack pack;
  int index;
  String imagePath;

  EditArguments({required this.pack, required this.index, required this.imagePath});
}
