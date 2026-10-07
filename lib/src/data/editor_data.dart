import 'package:flutter/cupertino.dart';
import 'package:stickers/src/data/storage.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/edit_page.dart';

class EditorData {
  /// Absolute path of the background image or video.
  String background;
  List<EditorLayer> layers;

  EditorData({required this.background, required this.layers});

  /// The background is stored relative to [packsDir].
  Map<String, dynamic> toJson() {
    return {
      'background': relativePath(background, packsDir),
      'layers': layers.map((layer) => layer.toJson()).toList(),
    };
  }

  factory EditorData.fromJson(Map<String, dynamic> map, GlobalKey rbKey) {
    return EditorData(
      background: resolvePath(map['background'] as String, packsDir),
      layers: (map['layers'] as List? ?? []).map((layer) => EditorLayer.fromJson(layer, rbKey)).toList(),
    );
  }
}
