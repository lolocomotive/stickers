import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/util.dart';

class CreatePackDialog extends StatelessWidget {
  CreatePackDialog(this.packs, {super.key});

  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<StickerPack> packs;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.createStickerPack),
      content: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              autofocus: true,
              validator: (v) => titleValidator(v, context),
              controller: _nameController,
              decoration: InputDecoration(
                label: Text(AppLocalizations.of(context)!.packTitle),
              ),
            ),
            TextFormField(
              validator: (v) => authorValidator(v, context),
              controller: _authorController,
              decoration: InputDecoration(
                label: Text(AppLocalizations.of(context)!.author),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            packs.add(StickerPack(
              _nameController.text,
              _authorController.text,
              "pack_${DateTime.now().millisecondsSinceEpoch}",
              [],
              "0",
            ));
            Navigator.of(context).pop();
          },
          child: Text(AppLocalizations.of(context)!.add),
        ),
      ],
    );
  }
}
