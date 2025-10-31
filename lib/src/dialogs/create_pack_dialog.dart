import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/util.dart';

class CreatePackDialog extends StatefulWidget {
  CreatePackDialog(this.packs, {super.key});

  final List<StickerPack> packs;

  @override
  State<CreatePackDialog> createState() => _CreatePackDialogState();
}

class _CreatePackDialogState extends State<CreatePackDialog> {
  final _nameController = TextEditingController();

  final _authorController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _animated = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      title: Text(AppLocalizations.of(context)!.createStickerPack),
      content: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton(
                emptySelectionAllowed: false,
                multiSelectionEnabled: false,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(AppLocalizations.of(context)!.staticPack),
                    icon: Icon(Icons.photo),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(AppLocalizations.of(context)!.animatedPack),
                    icon: Icon(Icons.animation),
                  ),
                ],
                selected: {_animated},
                onSelectionChanged: (set) {
                  setState(() {
                    _animated = set.first;
                    HapticFeedback.lightImpact();
                  });
                },
              ),
              SizedBox(
                height: 8,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextFormField(
                  autofocus: true,
                  validator: (v) => titleValidator(v, context),
                  controller: _nameController,
                  decoration: InputDecoration(
                    label: Text(AppLocalizations.of(context)!.packTitle),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextFormField(
                  validator: (v) => authorValidator(v, context),
                  controller: _authorController,
                  decoration: InputDecoration(
                    label: Text(AppLocalizations.of(context)!.author),
                  ),
                ),
              ),
            ],
          ),
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
            widget.packs.add(StickerPack(
              _nameController.text,
              _authorController.text,
              "pack_${DateTime.now().millisecondsSinceEpoch}",
              [],
              "0",
              _animated,
            ));
            Navigator.of(context).pop();
          },
          child: Text(AppLocalizations.of(context)!.add),
        ),
      ],
    );
  }
}
