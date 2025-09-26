import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/dialogs/create_pack_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/widgets/sticker_pack_preview_card.dart';

class SelectPackPage extends StatefulWidget {
  final SharedMedia media;

  const SelectPackPage(this.media, {super.key});

  static const routeName = "/selectPack";

  @override
  State<SelectPackPage> createState() => _SelectPackPageState();
}

class _SelectPackPageState extends State<SelectPackPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
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
      title: AppLocalizations.of(context)!.selectStickerPack,
      child: ListView.separated(
        separatorBuilder: (context, index) => Container(),
        itemBuilder: (context, index) {
          bool disabled = packs[index].animated || packs[index].stickers.length >= 30;
          debugPrint("disabled: $disabled");
          return Stack(
            children: [
// dart format off
              ColorFiltered(
                colorFilter: disabled
                    ? ColorFilter.matrix(<double>[
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0
                      ])
                    : ColorFilter.matrix(<double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]),
                child: IgnorePointer(
                  child: StickerPackPreviewCard(packs[index], () {
                    setState(() {});
                  }),
                ),
              ),
// dart format on
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: disabled
                      ? null
                      : () {
                          Navigator.pushNamed(
                            context,
                            "/crop",
                            arguments: EditArguments(
                              pack: packs[index],
                              index: packs[index].stickers.length,
                              mediaPath: widget.media.attachments!.first!.path,
                            ),
                          ).then(
                            (value) => setState(
                              () {
                                Navigator.of(context).pop();
                                Navigator.of(context).pushNamed("/");
                                Navigator.of(context).pushNamed("/pack", arguments: packs[index]);
                              },
                            ),
                          );
                        },
                ),
              ),
            ],
          );
        },
        itemCount: packs.length,
      ),
    );
  }
}
