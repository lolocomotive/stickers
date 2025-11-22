import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class Sticker {
  String source;

  /// Source file of the original media of the sticker
  /// Used to allow editing
  String? layers;
  List<String> emojis;

  Sticker(this.source, this.emojis, this.layers);

  Map<String, dynamic> toJson() {
    return {"source": source, "emojis": emojis};
  }

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      json["source"],
      (json["emojis"] as List<dynamic>).map<String>((e) => e as String).toList(),
      json["layers"],
    );
  }

  WhatsappStickerImage getWhatsappStickerImage() {
    return WhatsappStickerImage.fromFile(source);
  }
}
