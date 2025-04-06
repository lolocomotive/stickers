import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/dialogs/create_pack_dialog.dart';
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
          onPressed: () {
            Navigator.of(context).pushNamed("/settings");
          },
          icon: const Icon(Icons.settings),
        )
      ],
      fab: FloatingActionButton(
        onPressed: () {
          showDialog(context: context, builder: (_) => CreatePackDialog(packs))
              .then(
            (_) => setState(() {
              savePacks(packs);
            }),
          );
        },
        child: const Icon(Icons.add),
      ),
      title: AppLocalizations.of(context)?.pTitle ?? localizationUnavailable,
      child: packs.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(0, 36, 0, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    "No packs",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Opacity(
                    opacity: .8,
                    child: Text(
                      "Click on the bottom right to add a sticker pack",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              separatorBuilder: (context, index) => Container(),
              itemBuilder: (context, index) =>
                  StickerPackPreviewCard(packs[index], () {
                setState(() {});
              }),
              itemCount: packs.length,
            ),
    );
  }
}
