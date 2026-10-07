import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/export_sticker_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/util.dart';

class EditStickerDialog extends StatefulWidget {
  final StickerPack pack;
  final int index;

  const EditStickerDialog(this.pack, this.index, {super.key});

  @override
  State<EditStickerDialog> createState() => _EditStickerDialogState();
}

class _EditStickerDialogState extends State<EditStickerDialog> {
  final formKey = GlobalKey<FormState>();
  final controller = TextEditingController();
  bool valid = true;

  @override
  void initState() {
    super.initState();
    controller.text = widget.pack.stickers[widget.index].emojis.join();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.editSticker,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.exportSticker,
                    icon: const Icon(Icons.share),
                    onPressed: _exportSticker,
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  CustomPaint(
                    painter: CheckerPainter(context),
                    child: Image.file(File(widget.pack.stickers[widget.index].source)),
                  ),
                  Positioned(
                    // FIXME this is ugly
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FilledButton(
                        onPressed: () {
                          final sticker = widget.pack.stickers[widget.index];
                          // The sticker image is the background when there is
                          // no editor data, or when it can't be loaded.
                          Navigator.of(context).pushNamed(
                            "/edit",
                            arguments: EditArguments(
                              pack: widget.pack,
                              index: widget.index,
                              type: widget.pack.animated ? .video : .picture,
                              mediaPath: sticker.source,
                              editorData: sticker.editorData,
                            ),
                          );
                        },
                        child: Text(AppLocalizations.of(context)!.edit),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: InputDecoration(label: Text(AppLocalizations.of(context)!.associatedEmojis)),
                    textAlign: TextAlign.center,
                    validator: validator,
                    controller: controller,
                    onChanged: (value) {
                      setState(() {
                        valid = validator(value) == null;
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await deleteSticker();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          child: Text(
                            AppLocalizations.of(context)!.deleteSticker,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                        FilledButton(
                          onPressed: valid
                              ? () {
                                  if (formKey.currentState?.validate() == false) return;
                                  widget.pack.stickers[widget.index].emojis = controller.value.text.characters.toList();
                                  widget.pack.onEdit();
                                  Navigator.of(context).pop();
                                }
                              : null,
                          child: Text(AppLocalizations.of(context)!.done),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSticker() async {
    final format = await showDialog<StickerFormat>(
      context: context,
      builder: (context) => const ExportStickerDialog(),
    );
    if (format == null || !mounted) return;
    await exportStickersWithProgress(
      context,
      [widget.pack.stickers[widget.index]],
      format,
      packTitle: widget.pack.title,
    );
  }

  Future<void> deleteSticker() async {
    await deleteStickerFiles(widget.pack.stickers[widget.index]);
    widget.pack.stickers.removeAt(widget.index);
    widget.pack.onEdit();
  }

  String? validator(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.pleaseProvideAtLeastOneEmoji;
    } else if (value.characters.length > 3) {
      return AppLocalizations.of(context)!.pleaseProvideAtmost3Emojis;
    }
    final emojiRegex = RegExp(
      r"(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])",
    );
    for (final char in value.characters) {
      if (emojiRegex.allMatches(char).isEmpty) {
        return AppLocalizations.of(context)!.pleaseEnterOnlyEmojis;
      }
    }
    return null;
  }
}
