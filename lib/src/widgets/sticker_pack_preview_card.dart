import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/dialogs/edit_pack_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';

class StickerPackPreviewCard extends StatefulWidget {
  final StickerPack pack;
  final Function deleteCallback;
  const StickerPackPreviewCard(this.pack, this.deleteCallback, {super.key});

  @override
  State<StickerPackPreviewCard> createState() => _StickerPackPreviewCardState();
}

class _StickerPackPreviewCardState extends State<StickerPackPreviewCard> {
  @override
  Widget build(BuildContext context) {
    final Color surface = ElevationOverlay.applySurfaceTint(
      Theme.of(context).colorScheme.surface,
      Theme.of(context).colorScheme.primary,
      2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OpenContainer(
        closedColor: surface,
        openColor: Theme.of(context).colorScheme.background,
        middleColor: surface,
        closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        closedBuilder: (context, action) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(widget.pack.title),
              subtitle: Opacity(
                opacity: .8,
                child: Text(widget.pack.author),
              ),
              leading: widget.pack.stickers.isEmpty
                  ? null
                  : Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(
                        File(widget.pack.stickers.first.source),
                      ),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        showDialog(
                            context: context,
                            builder: (context) => EditPackDialog(widget.pack)).then(
                          (_) => setState(() {}),
                        );
                      }),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      showDialog<bool>(
                          context: context,
                          builder: (context) => DeleteConfirmDialog(widget.pack.title)).then(
                        (value) async {
                          if (value == true) {
                            packs.remove(widget.pack);
                            widget.deleteCallback();
                            Directory("$packsDir/${widget.pack.id}").delete(recursive: true);
                            savePacks(packs);
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            Container(
              height: 100,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ListView(
                shrinkWrap: true,
                scrollDirection: Axis.horizontal,
                children: widget.pack.stickers
                    .map((e) => Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(defaultBorderRadius),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.file(File(e.source)),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        openBuilder: (BuildContext context, void Function({Object? returnValue}) action) =>
            StickerPackPage(widget.pack, widget.deleteCallback),
      ),
    );
  }
}
