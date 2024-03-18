import 'package:flutter/material.dart';
import 'package:stickers/src/data/sticker_pack.dart';

class CreatePackDialog extends StatelessWidget {
  CreatePackDialog(this.packs, {super.key});

  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<StickerPack> packs;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create Sticker pack"),
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
            packs.add(StickerPack(
              _nameController.text,
              _authorController.text,
              "pack_${DateTime.now().millisecondsSinceEpoch}",
              [],
              "0",
            ));
            Navigator.of(context).pop();
          },
          child: const Text("Add"),
        ),
      ],
    );
  }
}
