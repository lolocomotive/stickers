import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';

void savePacks(List<StickerPack> packs) async {
  File output = File("$packsDir/packs.json");
  output.writeAsString(jsonEncode(packs.map((pack) => pack.toJson()).toList()));
}

Future<List<StickerPack>> getPacks() async {
  File input = File("$packsDir/packs.json");
  if (await input.exists()) {
    return (jsonDecode(await input.readAsString()) as List)
        .map((json) => StickerPack.fromJson(json))
        .toList();
  }
  return List.empty(growable: true);
}

saveSticker(Rect cropRect, Uint8List rawImageData, StickerPack pack, int index) async {
  Stopwatch sw = Stopwatch()..start();
  // Apply crop then scale then put on 512x512 transparent image in center

  final crop = ImageEditorOption();
  Size oldSize = cropRect.size;
  crop.addOption(ClipOption.fromRect(cropRect));
  Size newSize;
  //Make the longest border exactly 512 pixels wide, preseving aspect ratio
  if (oldSize.height > oldSize.width) {
    newSize = Size(oldSize.width * 512 / oldSize.height, 512);
  } else {
    newSize = Size(512, oldSize.height * 512 / oldSize.width);
  }
  crop.addOption(
    ScaleOption(
      newSize.width.toInt(),
      newSize.height.toInt(),
    ),
  );
  crop.outputFormat = const OutputFormat.png(); // Ensure the format supports transparency
  final intermediate = (await ImageEditor.editImage(image: rawImageData, imageEditorOption: crop))!;

  final option = ImageMergeOption(
    canvasSize: const Size.square(512),
    format: const OutputFormat.webp_lossy(50),
  );

  option.addImage(
    MergeImageConfig(
      image: MemoryImageSource(intermediate),
      position: ImagePosition(
        Offset((512 - newSize.width) / 2, (512 - newSize.height) / 2),
        newSize,
      ),
    ),
  );
  final result = await ImageMerger.mergeToMemory(option: option);

  Directory("$packsDir/${pack.id}").createSync(recursive: true);
  File output =
      File("$packsDir/${pack.id}/sticker_${index}_${DateTime.now().millisecondsSinceEpoch}.webp");
  output.writeAsBytesSync(result!);

  pack.stickers.add(Sticker(output.path));
  pack.onEdit();
  savePacks(packs);

  debugPrint("Saved to ${output.path} in ${sw.elapsedMilliseconds}ms");
}
