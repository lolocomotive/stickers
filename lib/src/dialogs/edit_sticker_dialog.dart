import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/video/frame_decoder.dart';

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
  int _fileSize = 0;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    controller.text = widget.pack.stickers[widget.index].emojis.join();
    try {
      _fileSize = File(widget.pack.stickers[widget.index].source).lengthSync();
    } catch (e) {
      print("Error getting file size: $e");
    }
    _loadDuration();
  }

  void _loadDuration() async {
    try {
      final decoder = FrameDecoderService();
      final success = await decoder.decode(widget.pack.stickers[widget.index].source);
      if (success) {
        setState(() {
          _duration = decoder.metadata?.totalDuration;
        });
      } else {
        setState(() {
          _duration = null;
        });
      }
    } catch (e) {
      setState(() {
        _duration = null;
      });
    }
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
              child: Text(
                AppLocalizations.of(context)!.editSticker,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  CustomPaint(
                    painter: CheckerPainter(context),
                    child: Image.file(
                      File(widget.pack.stickers[widget.index].source),
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                  if (!widget.pack.animated || widget.pack.stickers[widget.index].editorData != null || widget.pack.animated)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: FilledButton.icon(
                        onPressed: () async {
                          if (widget.pack.stickers[widget.index].editorData != null) {
                            Navigator.of(context).pushNamed(
                              "/edit",
                              arguments: EditArguments(
                                pack: widget.pack,
                                index: widget.index,
                                mediaPath: widget.pack.stickers[widget.index].source,
                                type: widget.pack.animated ? MediaType.animatedWebp : MediaType.picture,
                                editorData: widget.pack.stickers[widget.index].editorData!,
                              ),
                            );
                          } else {
                            Navigator.of(context).pushNamed(
                              "/edit",
                              arguments: EditArguments(
                                pack: widget.pack,
                                index: widget.index,
                                mediaPath: widget.pack.stickers[widget.index].source,
                                type: widget.pack.animated ? MediaType.animatedWebp : MediaType.picture,
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.edit),
                        label: Text("Edit"),
                      ),
                    ),
                ],
              ),
            ),
            if (_fileSize > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${getFileSizeString(_fileSize, widget.pack.stickers[widget.index].source)}${_duration != null ? ' ${getDurationString(_duration!)}' : ''}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
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

  Future<void> deleteSticker() async {
    final file = File(widget.pack.stickers[widget.index].source);
    if (await file.exists()) {
      await file.delete();
    }
    if (widget.pack.stickers[widget.index].editorData != null) {
      final editorDataFile = File(widget.pack.stickers[widget.index].editorData!);
      if (await editorDataFile.exists()) {
        await editorDataFile.delete();
      }
      final editorDataDir = Directory(
        widget.pack.stickers[widget.index].editorData!.replaceAll(RegExp("\\.json\$"), ""),
      );
      if (await editorDataDir.exists()) {
        await editorDataDir.delete(recursive: true);
      }
    }
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
