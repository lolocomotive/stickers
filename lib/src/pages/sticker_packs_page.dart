import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/dialogs/create_pack_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/widgets/sticker_pack_preview_card.dart';

class StickerPacksPage extends StatefulWidget {
  const StickerPacksPage({super.key});

  static const routeName = "/";

  @override
  State<StickerPacksPage> createState() => StickerPacksPageState();
}

class StickerPacksPageState extends State<StickerPacksPage> {
  @override
  initState() {
    super.initState();
    homeState = this;
  }

  update() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context)!.settings,
          onPressed: () {
            Navigator.of(context).pushNamed("/settings");
          },
          icon: const Icon(Icons.settings),
        )
      ],
      fab: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            tooltip: "Import",
            onPressed: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                  allowedExtensions: ["zip"],
                  type: FileType.custom,
                  allowMultiple: false,
                  dialogTitle: "Select a sticker pack");
              if (result == null) return;
              try {
                await importPack(File(result.files.single.path!));
              } on Exception catch (_) {
                if (!context.mounted) return;
                showDialog(
                    context: context,
                    builder: (context) => ErrorDialog(
                        title: "Couldn't import sticker pack",
                        message: "Check if the file is a valid sticker pack ZIP file"));
              }
              setState(() {});
            },
            mini: true,
            child: const Icon(Icons.upload_file),
          ),
          SizedBox(
            width: 8,
          ),
          FloatingActionButton.extended(
            backgroundColor: Theme.of(context).colorScheme.primary,
            onPressed: () {
              showDialog(context: context, builder: (_) => CreatePackDialog(packs)).then(
                (_) => setState(() {
                  savePacks(packs);
                }),
              );
            },
            icon: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(
              "Create Pack",
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
        ],
      ),
      title: AppLocalizations.of(context)?.pTitle ?? localizationUnavailable,
      child: packs.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(0, 36, 0, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.noPacks,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Opacity(
                    opacity: .8,
                    child: Text(
                      AppLocalizations.of(context)!.clickOnTheBottomRightToAddAStickerPack,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              separatorBuilder: (context, index) => Container(),
              itemBuilder: (context, index) => StickerPackPreviewCard(packs[index], () {
                setState(() {});
              }),
              itemCount: packs.length,
            ),
    );
  }
}
