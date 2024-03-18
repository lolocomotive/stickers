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
          showDialog(context: context, builder: (_) => CreatePackDialog(packs)).then(
            (_) => setState(() {
              savePacks(packs);
            }),
          );
        },
        child: const Icon(Icons.add),
      ),
      title: AppLocalizations.of(context)?.pTitle ?? localizationUnavailable,
      child: ListView.separated(
        separatorBuilder: (context, index) => Container(),
        itemBuilder: (context, index) => StickerPackPreviewCard(packs[index], () {
          setState(() {});
        }),
        itemCount: packs.length,
      ),
    );
  }
}
