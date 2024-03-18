import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/globals.dart';
import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class StickerPack {
  String title;
  String author;
  String id;
  String imageDataVersion;
  List<Sticker> stickers;

  StickerPack(this.title, this.author, this.id, this.stickers, this.imageDataVersion);

  sendToWhatsapp() async {
    if (stickers.isEmpty) throw Exception("No stickers!");

    ImageEditorOption scale = ImageEditorOption();
    scale.addOption(const ScaleOption(96, 96));
    scale.outputFormat = const OutputFormat.png();
    File? trayIcon = await ImageEditor.editFileImageAndGetFile(
      file: File(stickers.first.source),
      imageEditorOption: scale,
    );
    trayIcon = await trayIcon!.rename("$packsDir/$id/tray.png");

    var stickerPack = WhatsappStickers(
      identifier: id,
      name: title,
      publisher: author,
      trayImageFileName: WhatsappStickerImage.fromFile(trayIcon.path),
      imageDataVersion: imageDataVersion,
      //publisherWebsite: '', //TODO allow to edit
      //privacyPolicyWebsite: '',
      //licenseAgreementWebsite: '',
    );

    for (var sticker in stickers) {
      stickerPack.addSticker(sticker.getWhatsappStickerImage(), ["😀"]);
    }

    debugPrint("Adding $title ($id)  v=$imageDataVersion to Whatsapp");
    await stickerPack.sendToWhatsApp();
  }

  onEdit() {
    savePacks(packs);
    imageDataVersion = (int.parse(imageDataVersion) + 1).toString();
  }

  toJson() {
    return {
      "id": id,
      "title": title,
      "author": author,
      "imageDataVersion": imageDataVersion,
      "stickers": stickers.map((sticker) => sticker.toJson()).toList(),
    };
  }

  static StickerPack fromJson(Map<String, dynamic> json) {
    return StickerPack(
      json["title"],
      json["author"],
      json["id"],
      (json["stickers"] as List).map((sticker) => Sticker.fromJson(sticker)).toList(),
      json["imageDataVersion"],
    );
  }
}
