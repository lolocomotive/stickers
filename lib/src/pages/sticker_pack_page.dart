import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/dialogs/edit_sticker_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';

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
    return Column(
      children: [
        Expanded(
          child: DefaultSliverActivity(
            actions: [
              IconButton(
                onPressed: () {
                  showDialog(context: context, builder: (context) => EditPackDialog(widget.pack))
                      .then((value) => setState(() {}));
                },
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                onPressed: () {
                  showDialog<bool>(
                      context: context,
                      builder: (context) => DeleteConfirmDialog(widget.pack.title)).then(
                    (value) async {
                      if (value == true) {
                        packs.remove(widget.pack);
                        widget.deleteCallback();
                        Navigator.of(context).pop();
                        Directory("$packsDir/${widget.pack.id}").delete(recursive: true);
                        savePacks(packs);
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    if (index == widget.pack.stickers.length) {
                      bool disabled = widget.pack.stickers.length >= 30;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: disabled
                              ? null
                              : () async {
                                  final ImagePicker picker = ImagePicker();
                                  final XFile? image =
                                      await picker.pickImage(source: ImageSource.gallery);
                                  if (image == null) return; //TODO add Snackbar warning
                                  if (!context.mounted) return;

                                  Navigator.pushNamed(
                                    context,
                                    "/crop",
                                    arguments: EditArguments(
                                      pack: widget.pack,
                                      index: index,
                                      imagePath: image.path,
                                    ),
                                  ).then((value) => setState(() {}));
                                },
                          child: Icon(
                            Icons.add,
                            size: 40,
                            color: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(widget.pack.stickers[index].source)),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: ((context) => EditStickerDialog(widget.pack, index)),
                          ).then((_) => setState(() {}));
                        },
                      ),
                    );
                  }),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.pack.stickers.length < 3)
                const Opacity(
                  opacity: .7,
                  child: Text(
                    "You need at least 3 stickers",
                    textAlign: TextAlign.center,
                  ),
                ),
              if (widget.pack.stickers.length >= 30)
                const Opacity(
                  opacity: .7,
                  child: Text(
                    "You can't have more than 30 stickers",
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: widget.pack.stickers.length >= 3 ? widget.pack.sendToWhatsapp : null,
                child: const Text("Add to WhatsApp"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
