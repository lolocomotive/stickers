import 'package:flutter/material.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/util.dart';

class EditPackDialog extends StatefulWidget {
  const EditPackDialog(this.pack, {super.key});

  final StickerPack pack;

  @override
  State<EditPackDialog> createState() => _EditPackDialogState();
}

class _EditPackDialogState extends State<EditPackDialog> {
  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherURLController = TextEditingController();
  final _privacyPolicyURLController = TextEditingController();
  final _licenseAgreementURLController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.pack.title;
    _authorController.text = widget.pack.author;
    _publisherURLController.text = widget.pack.publisherWebsite ?? "";
    _privacyPolicyURLController.text = widget.pack.privacyPolicyWebsite ?? "";
    _licenseAgreementURLController.text = widget.pack.licenseAgreementWebsite ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Sticker pack"),
      content: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: _formKey,
        child: SingleChildScrollView(
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
              if (_showMore)
                TextFormField(
                  keyboardType: TextInputType.url,
                  controller: _publisherURLController,
                  validator: _urlValidator,
                  decoration: const InputDecoration(
                    label: Text("Publisher Website"),
                  ),
                ),
              if (_showMore)
                TextFormField(
                  keyboardType: TextInputType.url,
                  controller: _privacyPolicyURLController,
                  validator: _urlValidator,
                  decoration: const InputDecoration(
                    label: Text("Privacy policy website"),
                  ),
                ),
              if (_showMore)
                TextFormField(
                  keyboardType: TextInputType.url,
                  controller: _licenseAgreementURLController,
                  validator: _urlValidator,
                  decoration: const InputDecoration(
                    label: Text("License agreement website"),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_showMore)
          TextButton(
              onPressed: () => setState(() {
                    _showMore = true;
                  }),
              child: Text("More")),
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
            widget.pack.publisherWebsite = _publisherURLController.text;
            widget.pack.privacyPolicyWebsite = _privacyPolicyURLController.text;
            widget.pack.licenseAgreementWebsite = _licenseAgreementURLController.text;
            widget.pack.onEdit();
            Navigator.of(context).pop();
          },
          child: const Text("Done"),
        ),
      ],
    );
  }

  String? _urlValidator(String? value) {
    if (value == null) return null;
    if (value.isEmpty) return null;
    if (isValidURL(value)) return null;
    return "Please enter a valid URL";
  }
}
