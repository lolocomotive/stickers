import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class Sticker {
  String source;

  /// Source file of the original media and layers of the sticker
  /// Used to allow editing
  String? editorData;
  List<String> emojis;

  Sticker(this.source, this.emojis, this.editorData);

  Map<String, dynamic> toJson() {
    return {
      "source": source,
      "emojis": emojis,
      "editorData": editorData,
    };
  }

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      json["source"],
      (json["emojis"] as List<dynamic>).map<String>((e) => e as String).toList(),
      json["editorData"],
    );
  }

  WhatsappStickerImage getWhatsappStickerImage() {
    return WhatsappStickerImage.fromFile(source);
  }
}
