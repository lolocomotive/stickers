import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:stickers/src/pages/edit_page.dart';

class ImageLayer extends StatelessWidget implements EditorLayer {
  String source;

  ImageLayer({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: Image.file(File(source)));
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'source': source,
    };
  }

  factory ImageLayer.fromJson(Map<String, dynamic> json) {
    return ImageLayer(
      source: json['source'] as String,
    );
  }
}
