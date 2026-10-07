import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker.dart';
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
  } on PlatformException catch (e, st) {
    print(e);
    print(st);
    if (e.message == "WhatsApp is not installed on target device!") {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (_) => ErrorDialog(
          title: AppLocalizations.of(context)!.couldnTAddStickerPack,
          message: AppLocalizations.of(context)!.whatsappNotInstalled,
        ),
      );
    } else {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (_) =>
            ErrorDialog(title: AppLocalizations.of(context)!.couldnTAddStickerPack, message: e.message ?? ""),
      );
    }
  } on Exception catch (e, st) {
    print(e);
    print(st);
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (_) => ErrorDialog(title: AppLocalizations.of(context)!.couldnTAddStickerPack, message: e.toString()),
    );
  }
}

/// Runs [export] and reports the outcome with a snackbar, or an error dialog if it throws.
Future<void> exportWithFeedback(BuildContext context, Future<bool> Function() export) async {
  try {
    final success = await export();
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.exportComplete),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: AppLocalizations.of(context)!.couldntExportSticker,
        message: e.toString(),
      ),
    );
  }
}

/// Converts [stickers] to [format] behind a progress dialog, then opens the share sheet.
Future<void> exportStickersWithProgress(
  BuildContext context,
  List<Sticker> stickers,
  StickerFormat format, {
  String? packTitle,
}) async {
  final progress = ValueNotifier<(double, int)>((0, 1));
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(AppLocalizations.of(context)!.exporting),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, _) {
            final (fraction, current) = value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: fraction),
                if (stickers.length > 1) ...[
                  const SizedBox(height: 12),
                  Text("$current/${stickers.length}", textAlign: TextAlign.center),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );

  final List<XFile> files;
  try {
    files = await convertStickers(
      stickers,
      format: format,
      packTitle: packTitle,
      onProgress: (fraction, current) => progress.value = (fraction, current),
    );
  } catch (e, st) {
    debugPrint("Sticker export failed: $e");
    debugPrintStack(stackTrace: st);
    navigator.pop();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: AppLocalizations.of(context)!.couldntExportSticker,
        message: e.toString(),
      ),
    );
    return;
  }
  navigator.pop();
  if (files.isEmpty || !context.mounted) return;
  await exportWithFeedback(context, () async {
    await SharePlus.instance.share(ShareParams(files: files));
    return true;
  });
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

const Set<String> supportedVideoExtensions = {
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'webm',
  '3gp',
  'avi',
};

const Set<String> supportedImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
  'gif',
};

const Set<String> supportedPackExtensions = {
  'zip',
  'wastickers',
  'stickify',
};

bool _hasExtension(String filePath, Set<String> extensions) {
  final parts = filePath.toLowerCase().split('.');
  return parts.length >= 2 && extensions.contains(parts.last);
}

bool isSupportedVideo(String filePath) => _hasExtension(filePath, supportedVideoExtensions);

bool isSupportedImage(String filePath) => _hasExtension(filePath, supportedImageExtensions);

bool isSupportedPack(String filePath) => _hasExtension(filePath, supportedPackExtensions);

Future<void> showUnsupportedFormatDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => ErrorDialog(
      title: AppLocalizations.of(context)!.unrecognizedFormat,
      message: AppLocalizations.of(context)!.checkIfFileValid,
    ),
  );
}
