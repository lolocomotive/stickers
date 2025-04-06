import 'package:flutter/material.dart';
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

String? titleValidator(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter a title';
  }
  return null;
}

String? authorValidator(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter an author';
  }
  return null;
}

Future<void> sendToWhatsappWithErrorHandling(StickerPack pack) async {
  try {
    await pack.sendToWhatsapp();
  } on WhatsappStickersAlreadyAddedException catch (_) {
  } on WhatsappStickersException catch (e) {
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (_) => ErrorDialog(
        message: e.cause ?? e.runtimeType.toString(),
      ),
    );
  } on Exception catch (e) {
    showDialog(context: navigatorKey.currentContext!, builder: (_) => ErrorDialog(message: e.toString()));
  }
}
