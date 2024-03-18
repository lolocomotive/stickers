import 'dart:io';
import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/default_page.dart';

class EditPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey<ExtendedImageEditorState>();

  EditPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/edit";

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: const Text("Edit your sticker"),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        /*  TODO Add more editing options
           *  Text would probably the most useful one
           *  Drawing could be interesting too
           */
        //TODO  make loading less abrupt
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            height: MediaQuery.of(context).size.height / 2,
            decoration: const BoxDecoration(color: Colors.black),
            child: ExtendedImage.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
              beforePaintImage: (canvas, rect, image, paint) {
                // Paint a checkerboard below the image to indicate transparency

                double size = 10;
                final checkerPaint = Paint();
                checkerPaint.blendMode = BlendMode.srcOver;
                checkerPaint.style = PaintingStyle.fill;
                checkerPaint.color = Theme.of(context).brightness == Brightness.light
                    ? Colors.white
                    : Colors.grey.shade900.withAlpha(150);
                canvas.drawRect(rect, checkerPaint);
                checkerPaint.color = Theme.of(context).brightness == Brightness.light
                    ? Colors.grey.shade300
                    : Colors.grey.shade900;
                canvas.clipRect(rect);

                // Clamp to screen area for performance reasons.
                // Not optimal since canvas is still bigger than display area
                // Not something I can fix here tho

                final maxX = min(MediaQuery.of(context).size.width, rect.right);
                final maxY = min(MediaQuery.of(context).size.height, rect.bottom);

                int row = 0;
                for (double y = max(rect.top, 0); y < maxY; y += size) {
                  for (double x = max(rect.left, 0) + row * size; x < maxX; x += size * 2) {
                    Rect r = Rect.fromLTWH(x, y, size, size);
                    canvas.drawRect(r, checkerPaint);
                  }
                  row++;
                  row &= 1;
                }
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
          TextButton(
            onPressed: () async {
              final state = widget.editorKey.currentState!;
              await saveSticker(
                  state.getCropRect()!, state.rawImageData, widget.pack, widget.index);
              if (!context.mounted) return;
              Navigator.of(context).pop();
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
