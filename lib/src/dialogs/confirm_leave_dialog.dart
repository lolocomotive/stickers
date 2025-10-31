import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

class ConfirmLeaveDialog extends StatelessWidget {
  const ConfirmLeaveDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.leaveEditor),
      content: Text(AppLocalizations.of(context)!.editsNotSaved),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(AppLocalizations.of(context)!.stay)),
        ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(AppLocalizations.of(context)!.leave)),
      ],
    );
  }
}
