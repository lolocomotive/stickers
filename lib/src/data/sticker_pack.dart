import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/globals.dart';
import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class StickerPack {
  String title;
  String author;
  String id;
  String imageDataVersion;
  bool animated;
  String? publisherWebsite;
  String? privacyPolicyWebsite;
  String? licenseAgreementWebsite;
  List<Sticker> stickers;
  String? trayIcon;

  StickerPack(this.title, this.author, this.id, this.stickers, this.imageDataVersion, this.animated,
      {this.trayIcon, this.publisherWebsite, this.licenseAgreementWebsite, this.privacyPolicyWebsite});

  Future<void> sendToWhatsapp() async {
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
      animatedStickerPack: animated,
    );

    for (final sticker in stickers) {
      stickerPack.addSticker(sticker.getWhatsappStickerImage(), sticker.emojis);
    }

    debugPrint("Adding $title ($id)  v=$imageDataVersion to Whatsapp");
    await stickerPack.sendToWhatsApp();
  }

  void onEdit() {
    savePacks(packs);
    imageDataVersion = (int.parse(imageDataVersion) + 1).toString();
  }

  Map<String, Object?> toJson() {
    return {
      "id": id,
      "title": title,
      "author": author,
      "imageDataVersion": imageDataVersion,
      "animated": animated,
      "stickers": stickers.map((sticker) => sticker.toJson()).toList(),
      "trayIcon": trayIcon,
      "publisherWebsite": publisherWebsite,
      "privacyPolicyWebsite": privacyPolicyWebsite,
      "licenseAgreementWebsite": licenseAgreementWebsite,
    };
  }

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      json["title"],
      json["author"],
      json["id"],
      (json["stickers"] as List).map((sticker) => Sticker.fromJson(sticker)).toList(),
      json["imageDataVersion"],
      json["animated"] ?? false,
      trayIcon: json["trayIcon"],
      publisherWebsite: json["publisherWebsite"],
      privacyPolicyWebsite: json["privacyPolicyWebsite"],
      licenseAgreementWebsite: json["licenseAgreementWebsite"],
    );
  }

  void setTray(String source) {
    Directory parent = Directory("$packsDir/$id/");
    File output = File("$packsDir/$id/tray.webp");
    FileImage(output).evict();
    if (!parent.existsSync()) parent.createSync(recursive: true);
    File(source).copySync(output.path);
    trayIcon = output.path;
  }
}
