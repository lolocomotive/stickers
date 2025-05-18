import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

class ErrorDialog extends StatelessWidget {
  final String message;
  final String title;

  const ErrorDialog({super.key, required this.message, required this.title});

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Theme.of(context).brightness),
            brightness: Theme.of(context).brightness),
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context)!.ok))
          ],
        ));
  }
}
