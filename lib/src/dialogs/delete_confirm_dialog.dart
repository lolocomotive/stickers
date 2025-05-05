import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

class DeleteConfirmDialog extends StatefulWidget {
  const DeleteConfirmDialog(this.target, {super.key});
  final String target;

  @override
  State<DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<DeleteConfirmDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Delete ${widget.target}?"),
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
