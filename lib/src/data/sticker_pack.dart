import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/storage.dart';
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

  /// Absolute path of the tray icon chosen by the user, if any.
  String? trayIcon;

  StickerPack(this.title, this.author, this.id, this.stickers, this.imageDataVersion, this.animated,
      {this.trayIcon, this.publisherWebsite, this.licenseAgreementWebsite, this.privacyPolicyWebsite});

  String get directory => "$packsDir/$id";

  /// The tray icon generated for WhatsApp, which requires a 96x96 PNG.
  String get whatsappTrayPath => "$directory/whatsapp_tray.png";

  Future<void> sendToWhatsapp() async {
    if (stickers.isEmpty) throw Exception("No stickers!");

    ImageEditorOption scale = ImageEditorOption();
    scale.addOption(const ScaleOption(96, 96));
    scale.outputFormat = const OutputFormat.png();
    final scaled = await ImageEditor.editFileImageAndGetFile(
      file: File(trayIcon ?? stickers.first.source),
      imageEditorOption: scale,
    );
    final File trayIconFile;
    try {
      trayIconFile = await scaled!.copy(whatsappTrayPath);
    } finally {
      await scaled?.delete();
    }

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

  /// Increments the version so WhatsApp picks up the changes, then saves the packs.
  Future<void> onEdit() {
    imageDataVersion = (int.parse(imageDataVersion) + 1).toString();
    return savePacks(packs);
  }

  /// Paths are stored relative to [packsDir].
  Map<String, Object?> toJson() {
    return {
      "id": id,
      "title": title,
      "author": author,
      "imageDataVersion": imageDataVersion,
      "animated": animated,
      "stickers": stickers.map((sticker) => sticker.toJson()).toList(),
      "trayIcon": trayIcon == null ? null : relativePath(trayIcon!, packsDir),
      "publisherWebsite": publisherWebsite,
      "privacyPolicyWebsite": privacyPolicyWebsite,
      "licenseAgreementWebsite": licenseAgreementWebsite,
    };
  }

  /// Resolves the stored paths against [root], [packsDir] by default.
  factory StickerPack.fromJson(Map<String, dynamic> json, {String? root}) {
    root ??= packsDir;
    final trayIcon = json["trayIcon"] as String?;
    return StickerPack(
      json["title"],
      json["author"],
      json["id"],
      (json["stickers"] as List).map((sticker) => Sticker.fromJson(sticker, root: root)).toList(),
      "${json["imageDataVersion"] ?? 1}",
      json["animated"] ?? false,
      trayIcon: trayIcon == null ? null : resolvePath(trayIcon, root),
      publisherWebsite: json["publisherWebsite"],
      privacyPolicyWebsite: json["privacyPolicyWebsite"],
      licenseAgreementWebsite: json["licenseAgreementWebsite"],
    );
  }

  /// Uses a copy of the sticker at [source] as tray icon, and saves the packs.
  Future<void> setTray(String source) async {
    await Directory(directory).create(recursive: true);
    final output = await File(source).copy("$directory/tray.${extensionOf(source)}");
    await FileImage(output).evict();
    await _replaceTray(output.path);
  }

  /// Saves the packs with [path] as tray icon, then deletes the previous one.
  Future<void> _replaceTray(String path) async {
    final previous = trayIcon;
    trayIcon = path;
    await onEdit();
    // Older versions used a sticker as tray icon, which must be kept.
    if (previous != null && previous != path && baseName(previous).startsWith("tray.")) {
      try {
        await File(previous).delete();
      } catch (_) {}
    }
  }

  /// Makes [data], a WebP image, the tray icon and saves the packs.
  Future<void> setTrayData(Uint8List data) async {
    await Directory(directory).create(recursive: true);
    final output = File("$directory/tray.webp");
    await output.writeAsBytes(data, flush: true);
    await FileImage(output).evict();
    await _replaceTray(output.path);
  }
}
