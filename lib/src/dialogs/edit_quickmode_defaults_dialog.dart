import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/settings/settings_controller.dart';
import 'package:stickers/src/util.dart';

class EditQuickmodeDefaultsDialog extends StatelessWidget {
  EditQuickmodeDefaultsDialog({super.key, required this.settingsController});

  final SettingsController settingsController;
  final _authorController = TextEditingController();
  final _titleController = TextEditingController();
  final _formkey = GlobalKey<FormState>();
  @override
  StatelessElement createElement() {
    _authorController.text = settingsController.defaultAuthor;
    _titleController.text = settingsController.defaultTitle;
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
              validator: titleValidator,
              controller: _titleController,
              decoration: InputDecoration(label: Text(AppLocalizations.of(context)!.defaultTitle)),
            ),
            TextFormField(
              validator: authorValidator,
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
              settingsController.updateDefaultTitle(_titleController.text);
              settingsController.updateDefaultAuthor(_authorController.text);
              Navigator.of(context).pop();
            },
            child: Text(AppLocalizations.of(context)!.confirm)),
      ],
    );
  }
}
