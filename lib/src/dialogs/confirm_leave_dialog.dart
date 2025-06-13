import 'package:flutter/material.dart';

class ConfirmLeaveDialog extends StatelessWidget {


  const ConfirmLeaveDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Leave editor?"),
      content: Text("Your edits won't be saved"),
      actions: [
        TextButton(onPressed: () {
          Navigator.of(context).pop(false);
        }, child: Text("Stay")),
        ElevatedButton(onPressed: () {
          Navigator.of(context).pop(true);
        }, child: Text("Leave")),
      ],
    );
  }
}
