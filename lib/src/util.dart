import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:whatsapp_stickers_plus/exceptions.dart';

bool isValidURL(String input) {
  final url = Uri.tryParse(input);
  if (url == null) return false;
  if (url.scheme != "http" && url.scheme != "https") return false;
  if (url.host.isEmpty) return false;
  return url.isAbsolute;
}

String? titleValidator(String? value, BuildContext context) {
  if (value == null || value.isEmpty) {
    return AppLocalizations.of(context)!.pleaseEnterTitle;
  }
  return null;
}

String? authorValidator(String? value, BuildContext context) {
  if (value == null || value.isEmpty) {
    return AppLocalizations.of(context)!.pleaseEnterAuthor;
  }
  return null;
}

Future<void> sendToWhatsappWithErrorHandling(StickerPack pack, BuildContext context) async {
  try {
    await pack.sendToWhatsapp();
  } on WhatsappStickersAlreadyAddedException catch (_) {
  } on WhatsappStickersException catch (e) {
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (_) => ErrorDialog(
        title: AppLocalizations.of(context)!.couldnTAddStickerPack,
        message: e.cause ?? e.runtimeType.toString(),
      ),
    );
  } on PlatformException catch (e) {
    if (e.message == "WhatsApp is not installed on target device!") {
      showDialog(
          context: navigatorKey.currentContext!,
          builder: (_) => ErrorDialog(
              title: AppLocalizations.of(context)!.couldnTAddStickerPack,
              message: AppLocalizations.of(context)!.whatsappNotInstalled));
    } else {
      showDialog(
          context: navigatorKey.currentContext!,
          builder: (_) =>
              ErrorDialog(title: AppLocalizations.of(context)!.couldnTAddStickerPack, message: e.message ?? ""));
    }
  } on Exception catch (e) {
    showDialog(
        context: navigatorKey.currentContext!,
        builder: (_) => ErrorDialog(title: AppLocalizations.of(context)!.couldnTAddStickerPack, message: e.toString()));
  }
}

int colCount(double width) {
  if (width < 500) {
    return 3;
  } else if (width < 800) {
    return 6;
  } else {
    return 9;
  }
}

Future<void> loadFonts() async {
  debugPrint("Registering fonts...");
  Stopwatch sw = Stopwatch()..start();
  Directory fontsDir = Directory("${(await getTemporaryDirectory()).path}/fonts/");
  if (!await fontsDir.exists()) await fontsDir.create(recursive: true);
  for (final font in fonts) {
    if (font.family == "sans-serif" || font.family == "monospace") continue;
    File fontFile = File("${fontsDir.path}${font.family}.ttf");
    if (!await fontFile.exists()) {
      debugPrint("Copying file to ${fontFile.path}");
      await fontFile.create();
      await fontFile.writeAsBytes((await rootBundle
              .load("assets/fonts/${font.family}-${font.family == "RobotoMono" ? "SemiBold" : "Regular"}.ttf"))
          .buffer
          .asInt8List());
    }
    font.fontName = await FontManager.registerFont(fontFile);
    debugPrint("Registered font ${font.family} with name ${font.fontName}");
  }
  debugPrint("${fonts.length} fonts registered in ${sw.elapsedMilliseconds}ms");
}
