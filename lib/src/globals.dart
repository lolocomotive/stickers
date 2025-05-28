import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/sticker_packs_page.dart';

late List<StickerPack> packs;
final navigatorKey = GlobalKey<NavigatorState>();

StickerPacksPageState? homeState;
PackageInfo? info;

class PreviewFont {
  final String? display;
  final String family;

  /// Font name used by image editor plug-in
  String? fontName;

  PreviewFont(this.family, {this.fontName, this.display});
}

final List<PreviewFont> fonts = [
  PreviewFont("sans-serif", display: "Classic"),
  PreviewFont("Coiny"),
  PreviewFont("Lobster"),
  PreviewFont("Pacifico"),
  PreviewFont("PressStart2P", display: "Game"),
  PreviewFont("RacingSansOne", display: "Racing"),
  PreviewFont("RobotoMono", display: "type"),
  PreviewFont("DMSerifText", display: "Serif"),
];

final List<Color> colors = [
  Colors.pink,
  Colors.red,
  Colors.deepOrange,
  Colors.amber,
  Colors.yellow,
  Colors.lime,
  Colors.lightGreen,
  Colors.blueGrey,
  Colors.white,
  Colors.purple,
  Colors.deepPurple,
  Colors.indigo,
  Colors.blue,
  Colors.lightBlue,
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.brown,
  Colors.black,
];