import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:whatsapp_stickers_plus/exceptions.dart';

int counter = 0;

/// Generates an UID based on current time.
/// Hacky but should work
String uid() {
  return sha256
      .convert(utf8.encode("${counter++}#${DateTime.timestamp().microsecondsSinceEpoch}"))
      .toString()
      .substring(0, 16);
}

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


extension DirectoryCopy on Directory {
  Future<void> copy(String targetPath) async {
    await Directory(targetPath).create(recursive: true);
    final String sourcePath = absolute.path;
    await for (final item in list(recursive: true)) {
      String relativePath = item.path.replaceFirst(sourcePath, '');
      if (relativePath.startsWith(Platform.pathSeparator)) {
        relativePath = relativePath.substring(1);
      }
      final String newPath = '$targetPath${Platform.pathSeparator}$relativePath';
      if (item is Directory) {
        await Directory(newPath).create(recursive: true);
      } else if (item is File) {
        await item.copy(newPath);
      }
    }
  }
}


Future<void> sendToWhatsappWithErrorHandling(StickerPack pack, BuildContext context) async {
  try {
    await pack.sendToWhatsapp();
  } on WhatsappStickersAlreadyAddedException catch (_) {
    // Not really an error
  } on WhatsappStickersCancelledException catch (_) {
    // The user decided to cancel - no need to inform
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
