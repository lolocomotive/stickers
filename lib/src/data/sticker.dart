import 'package:stickers/src/data/storage.dart';
import 'package:stickers/src/globals.dart';
import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class Sticker {
  /// Absolute path of the source file
  String source;

  /// Absolute path of the editor data file, holding the original media and
  /// layers of the sticker. Used to allow editing
  String? editorData;
  List<String> emojis;

  Sticker(this.source, this.emojis, this.editorData);

  /// Paths are stored relative to [packsDir].
  Map<String, dynamic> toJson() {
    return {
      "source": relativePath(source, packsDir),
      "emojis": emojis,
      "editorData": editorData == null ? null : relativePath(editorData!, packsDir),
    };
  }

  /// Resolves the stored paths against [root], [packsDir] by default.
  factory Sticker.fromJson(Map<String, dynamic> json, {String? root}) {
    root ??= packsDir;
    final editorData = json["editorData"] as String?;
    return Sticker(
      resolvePath(json["source"], root),
      (json["emojis"] as List<dynamic>? ?? []).map<String>((e) => e as String).toList(),
      editorData == null ? null : resolvePath(editorData, root),
    );
  }

  WhatsappStickerImage getWhatsappStickerImage() {
    return WhatsappStickerImage.fromFile(source);
  }
}
