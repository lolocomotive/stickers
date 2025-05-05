import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/select_sticker_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/util.dart';

class EditPackDialog extends StatefulWidget {
  const EditPackDialog(this.pack, {super.key});

  final StickerPack pack;

  @override
  State<EditPackDialog> createState() => _EditPackDialogState();
}

class _EditPackDialogState extends State<EditPackDialog> {
  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherURLController = TextEditingController();
  final _privacyPolicyURLController = TextEditingController();
  final _licenseAgreementURLController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.pack.title;
    _authorController.text = widget.pack.author;
    _publisherURLController.text = widget.pack.publisherWebsite ?? "";
    _privacyPolicyURLController.text = widget.pack.privacyPolicyWebsite ?? "";
    _licenseAgreementURLController.text = widget.pack.licenseAgreementWebsite ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.editStickerPack),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              height: 150,
              width: 150,
              child: CustomPaint(
                painter: CheckerPainter(context),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _changeTrayIcon,
                  child: Stack(
                    children: [
                      Image.file(
                        File(widget.pack.trayIcon ?? widget.pack.stickers.first.source),
                      ),
                      Center(
                        child: Container(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withAlpha(130),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: OutlinedButton(
                            onPressed: _changeTrayIcon,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Icon(Icons.edit),
                                ),
                                Text(AppLocalizations.of(context)!.edit),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            Form(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      validator: titleValidator,
                      controller: _nameController,
                      decoration: InputDecoration(
                        label: Text(AppLocalizations.of(context)!.packTitle),
                      ),
                    ),
                    TextFormField(
                      validator: authorValidator,
                      controller: _authorController,
                      decoration: InputDecoration(
                        label: Text(AppLocalizations.of(context)!.author),
                      ),
                    ),
                    if (_showMore)
                      TextFormField(
                        keyboardType: TextInputType.url,
                        controller: _publisherURLController,
                        validator: _urlValidator,
                        decoration: InputDecoration(
                          label: Text(AppLocalizations.of(context)!.publisherWebsite),
                        ),
                      ),
                    if (_showMore)
                      TextFormField(
                        keyboardType: TextInputType.url,
                        controller: _privacyPolicyURLController,
                        validator: _urlValidator,
                        decoration: InputDecoration(
                          label: Text(AppLocalizations.of(context)!.privacyPolicyWebsite),
                        ),
                      ),
                    if (_showMore)
                      TextFormField(
                        keyboardType: TextInputType.url,
                        controller: _licenseAgreementURLController,
                        validator: _urlValidator,
                        decoration: InputDecoration(
                          label: Text(AppLocalizations.of(context)!.licenseAgreementWebsite),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_showMore)
          TextButton(
              onPressed: () => setState(() {
                    _showMore = true;
                  }),
              child: Text(AppLocalizations.of(context)!.more)),
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child:  Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            widget.pack.author = _authorController.text;
            widget.pack.title = _nameController.text;
            widget.pack.publisherWebsite = _publisherURLController.text;
            widget.pack.privacyPolicyWebsite = _privacyPolicyURLController.text;
            widget.pack.licenseAgreementWebsite = _licenseAgreementURLController.text;
            widget.pack.onEdit();
            Navigator.of(context).pop();
          },
          child:  Text(AppLocalizations.of(context)!.done),
        ),
      ],
    );
  }

  String? _urlValidator(String? value) {
    if (value == null) return null;
    if (value.isEmpty) return null;
    if (isValidURL(value)) return null;
    return AppLocalizations.of(context)!.pleaseEnterAValidUrl;
  }

  _changeTrayIcon() {
    showDialog(
      context: context,
      builder: (context) => TrayIconMethodSelector(
        pack: widget.pack,
      ),
    ).then((_) {
      setState(() {});
    });
  }
}

class TrayIconMethodSelector extends StatelessWidget {
  final StickerPack pack;

  const TrayIconMethodSelector({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.changePackIcon),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            onTap: () {
              showDialog(
                  context: context,
                  builder: (_) => SelectStickerDialog(callback: (sticker) {
                        pack.setTray(sticker.source);
                        Navigator.of(context).pop();
                      }));
            },
            leading: Icon(Icons.search),
            title: Text(AppLocalizations.of(context)!.chooseExistingSticker),
          ),
          ListTile(
            onTap: () async {
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(source: ImageSource.gallery);
              if (image == null) return; //TODO add Snackbar warning
              if (!context.mounted) return;
              Navigator.pushNamed(
                context,
                "/crop",
                arguments: EditArguments(
                  pack: pack,
                  index: 30,
                  imagePath: image.path,
                ),
              ).then((value) {
                if (!context.mounted) return;
                Navigator.of(context).pop();
              });
            },
            leading: Icon(Icons.add),
            title: Text(AppLocalizations.of(context)!.createNew),
          )
        ],
      ),
    );
  }
}
