import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class Sticker {
  String source;

  List<String> emojis;

  Sticker(this.source, this.emojis);

  Map<String, dynamic> toJson() {
    return {"source": source, "emojis": emojis};
  }

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(json["source"], (json["emojis"] as List<dynamic>).map<String>((e) => e as String).toList());
  }

  WhatsappStickerImage getWhatsappStickerImage() {
    return WhatsappStickerImage.fromFile(source);
  }
}
