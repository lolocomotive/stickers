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
import 'dart:math';
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

String getFileSizeString(int bytes, String filePath) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (log(bytes) / log(1000)).floor();
  final sizeStr = '${(bytes / pow(1000, i)).toStringAsFixed(2)} ${suffixes[i]}';
  final extension = filePath.split('.').last.toUpperCase();
  return '$sizeStr ($extension)';
}

String getDurationString(Duration duration) {
  int min = duration.inMinutes;
  int sec = duration.inSeconds % 60;
  int ms = duration.inMilliseconds % 1000;

  String formatFractional(int ms) {
    if (ms == 0) return '';
    String frac = (ms / 1000.0).toStringAsFixed(2);
    if (frac == '0.00') return '';
    frac = frac.substring(2);
    frac = frac.replaceAll(RegExp(r'0+$'), '');
    if (frac.isEmpty) frac = '0';
    return '.$frac';
  }

  if (min > 0) {
    return '$min:${sec.toString().padLeft(2, '0')}${formatFractional(ms)} s';
  } else if (sec == 0) {
    return '${ms}ms';
  } else {
    return '$sec${formatFractional(ms)}s';
  }
}

String? urlValidator(String? value, BuildContext context) {
  if (value == null) return null;
  if (value.isEmpty) return null;
  if (isValidURL(value)) return null;
  return AppLocalizations.of(context)!.pleaseEnterAValidUrl;
}

String? emojiValidator(String? value, BuildContext context) {
  if (value == null || value.isEmpty) {
    return AppLocalizations.of(context)!.pleaseProvideAtLeastOneEmoji;
  } else if (value.characters.length > 3) {
    return AppLocalizations.of(context)!.pleaseProvideAtmost3Emojis;
  }
  final emojiRegex = RegExp(
      r"(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])");
  for (final char in value.characters) {
    if (emojiRegex.allMatches(char).isEmpty) {
      return AppLocalizations.of(context)!.pleaseEnterOnlyEmojis;
    }
  }
  return null;
}

