import 'package:flutter/material.dart';

class ErrorDialog extends StatelessWidget {
  final String message;

  const ErrorDialog({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return
      Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Theme.of(context).brightness), brightness: Theme.of(context).brightness), child: AlertDialog(
        title: Text("Couldn't add sticker pack"),
        content: Text(message),
        actions: [ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text("Ok :("))],
      ))
      ;
  }
}
