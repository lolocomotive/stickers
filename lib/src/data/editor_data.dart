import 'package:flutter/cupertino.dart';
import 'package:stickers/src/pages/edit_page.dart';

class EditorData {
  String background;
  List<EditorLayer> layers;

  EditorData({required this.background, required this.layers});

  Map<String, dynamic> toJson() {
    return {
      'background': background,
      'layers': layers.map((layer) => layer.toJson()).toList(),
    };
  }

  factory EditorData.fromJson(Map<String, dynamic> map, GlobalKey rbKey) {
    return EditorData(
      background: map['background'] as String,
      layers: map['layers'].map<EditorLayer>((layer) => EditorLayer.fromJson(layer, rbKey)).toList(),
    );
  }
}
