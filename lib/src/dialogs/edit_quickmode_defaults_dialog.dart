import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/util.dart';

class EditQuickmodeDefaultsDialog extends StatelessWidget {
  EditQuickmodeDefaultsDialog({super.key});

  final _authorController = TextEditingController();
  final _titleController = TextEditingController();
  final _formkey = GlobalKey<FormState>();
  @override
  StatelessElement createElement() {
    _authorController.text = settings.defaultAuthor.value;
    _titleController.text = settings.defaultTitle.value;
    return super.createElement();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.editDefaults),
      content: Form(
        key: _formkey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              autofocus: true,
              validator: (v) => titleValidator(v, context),
              controller: _titleController,
              decoration: InputDecoration(label: Text(AppLocalizations.of(context)!.defaultTitle)),
            ),
            TextFormField(
              validator: (v) => authorValidator(v, context),
              controller: _authorController,
              decoration: InputDecoration(label: Text(AppLocalizations.of(context)!.defaultAuthor)),
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
              if (!_formkey.currentState!.validate()) return;
              settings.defaultTitle.value = _titleController.text;
              settings.defaultAuthor.value = _authorController.text;
              Navigator.of(context).pop();
            },
            child: Text(AppLocalizations.of(context)!.confirm)),
      ],
    );
  }
}
