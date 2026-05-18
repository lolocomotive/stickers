import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/batch/batch_import_queue.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/pages/gif_crop_page.dart';
import 'package:stickers/src/pages/video_crop_page.dart';
import 'package:stickers/src/util.dart';

class StickerPackPage extends StatefulWidget {
  final StickerPack pack;
  final Function deleteCallback;

  const StickerPackPage(this.pack, this.deleteCallback, {super.key});

  static const routeName = "/pack";

  @override
  State<StickerPackPage> createState() => StickerPackPageState();
}

class StickerPackPageState extends State<StickerPackPage> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: DefaultSliverActivity(
              actions: [
                IconButton(
                  tooltip: AppLocalizations.of(context)!.edit,
                  onPressed: () {
                    showDialog(
                            context: context,
                            builder: (context) => EditPackDialog(widget.pack))
                        .then((value) => setState(() {}));
                  },
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: () {
                    showDialog<bool>(
                        context: context,
                        builder: (context) =>
                            DeleteConfirmDialog(widget.pack.title)).then(
                      (value) async {
                        if (value == true) {
                          packs.remove(widget.pack);
                          widget.deleteCallback();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          final dir = Directory("$packsDir/${widget.pack.id}");
                          if (await dir.exists()) {
                            await dir.delete(recursive: true);
                          }
                          await savePacks(packs);
                        }
                      },
                    );
                  },
                  icon: const Icon(Icons.delete),
                ),
              ],
              title: widget.pack.title,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: GridView.builder(
                    itemCount: widget.pack.stickers.length + 1,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          colCount(MediaQuery.of(context).size.width),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      if (index == widget.pack.stickers.length) {
                        bool disabled = widget.pack.stickers.length >= 30;
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: disabled
                                  ? Colors.grey
                                  : Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap:
                                disabled ? null : () => _createSticker(index),
                            child: Icon(
                              Icons.add,
                              size: 40,
                              color: disabled
                                  ? Colors.grey
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Color.lerp(
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.surface,
                              .7),
                          boxShadow: [
                            BoxShadow(
                              offset: Offset(1, 1),
                              blurRadius: 3,
                              color: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Colors.black26
                                  : Colors.black12,
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: index >= widget.pack.stickers.length
                            ? null
                            : CustomPaint(
                                painter: CheckerPainter(context),
                                child: GestureDetector(
                                  child: Image.file(
                                    File(widget.pack.stickers[index].source),
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.broken_image),
                                  ),
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: ((context) => EditStickerDialog(
                                          widget.pack, index)),
                                    ).then(
                                      (_) => setState(() {}),
                                    );
                                  },
                                ),
                              ),
                      );
                    }),
              ),
            ),
          ),
          Material(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.pack.stickers.length < 3)
                    Opacity(
                      opacity: .7,
                      child: Text(
                        AppLocalizations.of(context)!.youNeedAtLeast3Stickers,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (widget.pack.stickers.length >= 30)
                    Opacity(
                      opacity: .7,
                      child: Text(
                        AppLocalizations.of(context)!
                            .youCanTHaveMoreThan30Stickers,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.share),
                        onPressed: () {
                          exportPack(widget.pack);
                        },
                        label: Text(AppLocalizations.of(context)!.export),
                      ),
                      SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: widget.pack.stickers.length < 3
                              ? null
                              : () => sendToWhatsappWithErrorHandling(
                                  widget.pack, context),
                          child:
                              Text(AppLocalizations.of(context)!.addToWhatsapp),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _createSticker(int index) async {
    try {
      if (widget.pack.animated) {
        await _createAnimatedSticker(index);
      } else {
        await _createStaticSticker(index);
      }
    } on Exception catch (e) {
      if (mounted) {
        showDialog(
            context: context,
            builder: (context) {
              return ErrorDialog(
                title: AppLocalizations.of(context)!.couldntLoadMedia,
                message: e.toString(),
              );
            });
      }
    }
  }

  Future<void> _createStaticSticker(int index) async {
    final localizations = AppLocalizations.of(context)!;
    final chooseImageTitle = localizations.chooseImage;
    final chooseMultipleImagesTitle = localizations.chooseMultipleImages;
    final result = await showModalBottomSheet<_StaticMediaType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: Text(chooseImageTitle),
              onTap: () => Navigator.of(context).pop(_StaticMediaType.image),
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: Text(chooseMultipleImagesTitle),
              onTap: () => Navigator.of(context).pop(_StaticMediaType.batch),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result == _StaticMediaType.batch) {
      await _pickStaticBatch();
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return; //TODO add Snackbar warning
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      CropPage.routeName,
      arguments: EditArguments(
        pack: widget.pack,
        index: index,
        mediaPath: image.path,
      ),
    ).then((value) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _createAnimatedSticker(int index) async {
    final localizations = AppLocalizations.of(context)!;
    final chooseVideoTitle = localizations.chooseVideo;
    final chooseGifTitle = localizations.chooseGif;
    final chooseMultipleAnimatedMediaTitle =
        localizations.chooseMultipleAnimatedMedia;
    final result = await showModalBottomSheet<_AnimatedMediaType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library),
              title: Text(chooseVideoTitle),
              onTap: () => Navigator.of(context).pop(_AnimatedMediaType.video),
            ),
            ListTile(
              leading: const Icon(Icons.gif),
              title: Text(chooseGifTitle),
              onTap: () => Navigator.of(context).pop(_AnimatedMediaType.gif),
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: Text(chooseMultipleAnimatedMediaTitle),
              onTap: () => Navigator.of(context).pop(_AnimatedMediaType.batch),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result == _AnimatedMediaType.batch) {
      await _pickAnimatedBatch();
      return;
    }
    if (result == _AnimatedMediaType.video) {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        VideoCropPage.routeName,
        arguments: EditArguments(
          pack: widget.pack,
          index: index,
          mediaPath: video.path,
        ),
      ).then((value) => setState(() {}));
    } else {
      final FilePickerResult? gif = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["gif"],
        allowMultiple: false,
        dialogTitle: chooseGifTitle,
      );
      final path = gif?.files.single.path;
      if (path == null) return;
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        GifCropPage.routeName,
        arguments: EditArguments(
          pack: widget.pack,
          index: index,
          mediaPath: path,
          type: MediaType.gif,
        ),
      ).then((value) => setState(() {}));
    }
  }

  Future<void> _pickStaticBatch() async {
    final localizations = AppLocalizations.of(context)!;
    final dialogTitle = localizations.chooseMultipleImages;
    final limitMessage = localizations.batchImportLimit;
    final emptyMessage = localizations.noSupportedBatchMedia;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["png", "jpg", "jpeg", "webp", "bmp", "heic", "heif"],
      allowMultiple: true,
      dialogTitle: dialogTitle,
    );
    final items = result?.files
            .map((file) => file.path)
            .whereType<String>()
            .map((path) =>
                BatchImportItem(path: path, kind: BatchImportMediaKind.picture))
            .toList() ??
        [];
    _startBatchImport(items,
        limitMessage: limitMessage, emptyMessage: emptyMessage);
  }

  Future<void> _pickAnimatedBatch() async {
    final localizations = AppLocalizations.of(context)!;
    final dialogTitle = localizations.chooseMultipleAnimatedMedia;
    final limitMessage = localizations.batchImportLimit;
    final emptyMessage = localizations.noSupportedBatchMedia;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["gif", "mp4", "mov", "m4v", "3gp", "3gpp", "webm"],
      allowMultiple: true,
      dialogTitle: dialogTitle,
    );
    final items = result?.files
            .map((file) => file.path)
            .whereType<String>()
            .map(_animatedBatchItemForPath)
            .whereType<BatchImportItem>()
            .toList() ??
        [];
    _startBatchImport(items,
        limitMessage: limitMessage, emptyMessage: emptyMessage);
  }

  BatchImportItem? _animatedBatchItemForPath(String path) {
    final extension = path.split(".").last.toLowerCase();
    if (extension == "gif") {
      return BatchImportItem(path: path, kind: BatchImportMediaKind.gif);
    }
    if (["mp4", "mov", "m4v", "3gp", "3gpp", "webm"].contains(extension)) {
      return BatchImportItem(path: path, kind: BatchImportMediaKind.video);
    }
    return null;
  }

  void _startBatchImport(
    List<BatchImportItem> items, {
    required String limitMessage,
    required String emptyMessage,
  }) {
    if (!mounted) return;
    final remainingSlots = 30 - widget.pack.stickers.length;
    final queued = items.take(remainingSlots).toList();
    if (queued.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(emptyMessage)));
      return;
    }
    if (items.length > queued.length) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(limitMessage)));
    }

    final queue = BatchImportQueue(queued, onChanged: () {
      if (mounted) setState(() {});
    });
    final firstItem = queue.next()!;
    Navigator.pushNamed(
      context,
      _routeForBatchItem(firstItem),
      arguments: EditArguments(
        pack: widget.pack,
        index: widget.pack.stickers.length,
        mediaPath: firstItem.path,
        type: _mediaTypeForBatchItem(firstItem),
        batchQueue: queue,
      ),
    ).then((value) {
      if (mounted) setState(() {});
    });
  }

  String _routeForBatchItem(BatchImportItem item) {
    switch (item.kind) {
      case BatchImportMediaKind.picture:
        return CropPage.routeName;
      case BatchImportMediaKind.video:
        return VideoCropPage.routeName;
      case BatchImportMediaKind.gif:
        return GifCropPage.routeName;
    }
  }

  MediaType _mediaTypeForBatchItem(BatchImportItem item) {
    switch (item.kind) {
      case BatchImportMediaKind.picture:
        return MediaType.picture;
      case BatchImportMediaKind.video:
        return MediaType.video;
      case BatchImportMediaKind.gif:
        return MediaType.gif;
    }
  }
}

enum _StaticMediaType { image, batch }

enum _AnimatedMediaType { video, gif, batch }
