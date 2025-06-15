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
  final double sizeMultiplier;

  /// Font name used by image editor plug-in
  String? fontName;

  PreviewFont(this.family, {this.fontName, this.display, this.sizeMultiplier = 1});
}

/// The fonts have different names depending on where they're loaded from
/// This map helps going between those without having to iterate through the fonts list
/// Initialized in loadFonts()
final Map<String, PreviewFont> fontsMap = <String, PreviewFont>{};

final List<PreviewFont> fonts = [
  PreviewFont("sans-serif", display: "Classic"),
  PreviewFont("SairaStencilOne", display: "Stencil"),
  PreviewFont("Lobster"),
  PreviewFont("PressStart2P", display: "Game", sizeMultiplier: .7),
  PreviewFont("RacingSansOne", display: "Racing"),
  PreviewFont("PirataOne", display: "Pirata"),
  PreviewFont("RobotoMono", display: "type", sizeMultiplier: .8),
  PreviewFont("DMSerifText", display: "Serif"),
  PreviewFont("Pacifico"),
  PreviewFont("Sacramento"),
  PreviewFont("PassionsConflict", display: "Passion", sizeMultiplier: 1.4),
  PreviewFont("IslandMoments", display: "Island", sizeMultiplier: 1.3),
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
