import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/sticker_packs_page.dart';
import 'package:stickers/src/settings/settings.dart';

const String localizationUnavailable = "Localization unavailable";
const double defaultBorderRadius = 10;
late String dataDir;
late String tempDir;
late String packsDir;
late String cacheDir;
late String fontsCacheDir;
late String exportCacheDir;
late String mediaCacheDir;
late String bundledFontsDir;
late String googleFontsDir;
late String customFontsDir;

/// Index passed to the crop and edit pages to make a pack's tray icon instead of a sticker.
const int trayIndex = 30;

late List<StickerPack> packs;
final navigatorKey = GlobalKey<NavigatorState>();
late Settings settings;

StickerPacksPageState? homeState;
PackageInfo? info;

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
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.brown,
  Colors.black,
  Colors.transparent,
];
