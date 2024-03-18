import 'package:flutter/material.dart';
import 'package:stickers/src/data/sticker_pack.dart';

class EditPackDialog extends StatefulWidget {
  const EditPackDialog(this.pack, {super.key});

  final StickerPack pack;

  @override
  State<EditPackDialog> createState() => _EditPackDialogState();
}

class _EditPackDialogState extends State<EditPackDialog> {
  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.pack.title;
    _authorController.text = widget.pack.author;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Sticker pack"),
      content: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              autofocus: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
              controller: _nameController,
              decoration: const InputDecoration(
                label: Text("Pack name"),
              ),
            ),
            TextFormField(
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter an author';
                }
                return null;
              },
              controller: _authorController,
              decoration: const InputDecoration(
                label: Text("Author"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            widget.pack.author = _authorController.text;
            widget.pack.title = _nameController.text;
            widget.pack.onEdit();
            Navigator.of(context).pop();
          },
          child: const Text("Done"),
        ),
      ],
    );
  }
}
