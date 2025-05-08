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
  String? publisherWebsite;
  String? privacyPolicyWebsite;
  String? licenseAgreementWebsite;
  List<Sticker> stickers;
  String? trayIcon;

  StickerPack(this.title, this.author, this.id, this.stickers, this.imageDataVersion,
      {this.trayIcon, this.publisherWebsite, this.licenseAgreementWebsite, this.privacyPolicyWebsite});

  sendToWhatsapp() async {
    if (stickers.isEmpty) throw Exception("No stickers!");

    ImageEditorOption scale = ImageEditorOption();
    scale.addOption(const ScaleOption(96, 96));
    scale.outputFormat = const OutputFormat.png();
    File? trayIconFile = await ImageEditor.editFileImageAndGetFile(
      file: File(trayIcon ?? stickers.first.source),
      imageEditorOption: scale,
    );
    trayIconFile = await trayIconFile!.rename("$packsDir/$id/tray.png");

    var stickerPack = WhatsappStickers(
      identifier: id,
      name: title,
      publisher: author,
      trayImageFileName: WhatsappStickerImage.fromFile(trayIconFile.path),
      imageDataVersion: imageDataVersion,
      publisherWebsite: publisherWebsite,
      privacyPolicyWebsite: privacyPolicyWebsite,
      licenseAgreementWebsite: licenseAgreementWebsite,
    );

    for (var sticker in stickers) {
      stickerPack.addSticker(sticker.getWhatsappStickerImage(), sticker.emojis);
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
      "trayIcon": trayIcon,
      "publisherWebsite": publisherWebsite,
      "privacyPolicyWebsite": privacyPolicyWebsite,
      "licenseAgreementWebsite": licenseAgreementWebsite,
    };
  }

  static StickerPack fromJson(Map<String, dynamic> json) {
    return StickerPack(
      json["title"],
      json["author"],
      json["id"],
      (json["stickers"] as List).map((sticker) => Sticker.fromJson(sticker)).toList(),
      json["imageDataVersion"],
      trayIcon: json["trayIcon"],
      publisherWebsite: json["publisherWebsite"],
      privacyPolicyWebsite: json["privacyPolicyWebsite"],
      licenseAgreementWebsite: json["licenseAgreementWebsite"],
    );
  }

  setTray(String source) {
    Directory parent = Directory("$packsDir/$id/");
    File output = File("$packsDir/$id/tray_${DateTime.now().millisecondsSinceEpoch}.webp");
    if (!parent.existsSync()) parent.createSync(recursive: true);
    File(source).copySync(output.path);
    trayIcon = output.path;
  }
}
