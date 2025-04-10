import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/globals.dart';

class SelectStickerDialog extends StatelessWidget {
  const SelectStickerDialog({super.key, required this.callback});

  final void Function(Sticker) callback;

  @override
  Widget build(BuildContext context) {
    var stickers = packs.expand((p) => p.stickers).toList();
    return AlertDialog(
      title: Text("Choose a sticker"),
      content: SizedBox(
        width: 10000, //FIXME make this dynamic
        height: 10000,
        child: GridView.builder(
            itemCount: stickers.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      offset: Offset(1, 1),
                      blurRadius: 3,
                      color: Theme.of(context).brightness == Brightness.light ? Colors.black26 : Colors.black12,
                    )
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: CheckerPainter(context),
                  child: InkWell(
                    onTap: () {
                      callback(stickers[index]);
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(stickers[index].source),
                    ),
                  ),
                ),
              );
            }),
      ),
    );
  }
}
