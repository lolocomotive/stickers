import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/video/frame_decoder.dart';

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
  void initState() {
    super.initState();
    _removeBrokenStickers();
  }

  Future<void> _removeBrokenStickers() async {
    final stickersToCheck = widget.pack.stickers.toList();
    final brokenStickers = [];

    for (final sticker in stickersToCheck) {
      if (!await File(sticker.source).exists()) {
        brokenStickers.add(sticker);
      }
    }

    if (brokenStickers.isNotEmpty && mounted) {
      setState(() {
        for (final sticker in brokenStickers) {
          widget.pack.stickers.remove(sticker);
        }
      });
      widget.pack.onEdit();
      await savePacks(packs);
    }
  }

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
                    showDialog(context: context, builder: (context) => EditPackDialog(widget.pack))
                        .then((value) => setState(() {}));
                  },
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: () {
                    showDialog<bool>(
                        context: context,
                        builder: (context) => DeleteConfirmDialog(widget.pack.title)).then(
                      (value) async {
                        if (value == true) {
                          packs.remove(widget.pack);
                          widget.deleteCallback();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          Directory("$packsDir/${widget.pack.id}").delete(recursive: true);
                          savePacks(packs);
                        }
                      },
                    );
                  },
                  icon: const Icon(Icons.delete),
                ),
              ],
              titleWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.pack.title),
                  Opacity(
                    opacity: 0.8,
                    child: Row(
                      children: [
                        Text(widget.pack.author, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 4),
                        Icon(widget.pack.animated ? Icons.animation : Icons.collections, size: 16),
                        const SizedBox(width: 2),
                        Text(widget.pack.stickers.length.toString(), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: GridView.builder(
                    itemCount: widget.pack.stickers.length + 1,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: colCount(MediaQuery.of(context).size.width),
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
                              color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: disabled ? null : () => _createSticker(index),
                            child: Icon(
                              Icons.add,
                              size: 40,
                              color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Color.lerp(Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.surface, .7),
                          boxShadow: [
                            BoxShadow(
                              offset: Offset(1, 1),
                              blurRadius: 3,
                              color: Theme.of(context).brightness == Brightness.light
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
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Center(child: Icon(Icons.broken_image)),
                                  ),
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: ((context) => EditStickerDialog(widget.pack, index)),
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
                        AppLocalizations.of(context)!.youCanTHaveMoreThan30Stickers,
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
                              : () => sendToWhatsappWithErrorHandling(widget.pack, context),
                          child: Text(AppLocalizations.of(context)!.addToWhatsapp),
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
      final ImagePicker picker = ImagePicker();
      if (widget.pack.animated) {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'webp',
            'mp4',
            'avi',
            'mov',
            'mkv',
            'webm',
            'gif',
            'flv',
            'wmv',
            'mpeg',
            'mpg',
            'm4v',
            '3gp',
            'ts'
          ],
        );

        if (result == null || result.files.single.path == null) return;
        final String mediaPath = result.files.single.path!;

        if (!mounted) return;
        
        // Use frame-based pipeline for WebP and GIF to preserve alpha
        final extension = mediaPath.toLowerCase().split('.').last;
        final useFramePipeline = ['webp', 'gif'].contains(extension);
        
        if (useFramePipeline) {
          // Check frame count for animated WebP/GIF
          final frameInfo = await MediaValidator.getQuickFrameInfo(mediaPath);
          if (!frameInfo.hasEnoughFrames) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => ErrorDialog(
                  title: AppLocalizations.of(context)!.couldntExportSticker,
                  message: AppLocalizations.of(context)!.animatedStickersMustHaveAtLeast2Frames,
                ),
              );
            }
            return;
          }
        }
        
        if (!mounted) return;
        
        Navigator.pushNamed(
          context,
          useFramePipeline ? "/trim_animated" : "/crop_video",
          arguments: EditArguments(
            pack: widget.pack,
            index: index,
            mediaPath: mediaPath,
          ),
        ).then((value) => setState(() {}));
      } else {
        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
        if (image == null) return; //TODO add Snackbar warning
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          "/crop",
          arguments: EditArguments(
            pack: widget.pack,
            index: index,
            mediaPath: image.path,
          ),
        ).then((value) => setState(() {}));
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
}
