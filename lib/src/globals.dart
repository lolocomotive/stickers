import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/sticker_packs_page.dart';

late List<StickerPack> packs;
final navigatorKey = GlobalKey<NavigatorState>();

StickerPacksPageState? homeState;
PackageInfo? info;