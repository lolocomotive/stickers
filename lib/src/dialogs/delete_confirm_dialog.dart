import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

class DeleteConfirmDialog extends StatefulWidget {
  /// Asks to confirm deleting the sticker pack named [target].
  const DeleteConfirmDialog(String this.target, {super.key}) : title = null;

  const DeleteConfirmDialog.titled(String this.title, {super.key}) : target = null;

  final String? target;
  final String? title;

  @override
  State<DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<DeleteConfirmDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? AppLocalizations.of(context)!.deletePack(widget.target!)),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(AppLocalizations.of(context)!.cancel)),
        Theme(
          data: ThemeData.from(
              colorScheme: ColorScheme.fromSeed(
            seedColor: Theme.of(context).colorScheme.error,
            brightness: Theme.of(context).brightness,
          )),
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        )
      ],
    );
  }
}
