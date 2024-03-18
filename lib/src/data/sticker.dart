import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';

class Sticker {
  String source;

  List<String> emojis;
  Sticker(this.source, [this.emojis = const ["😍"]]);

  Map<String, dynamic> toJson() {
    return {"source": source};
  }

  static Sticker fromJson(Map<String, dynamic> json) {
    return Sticker(json["source"]);
  }

  WhatsappStickerImage getWhatsappStickerImage() {
    return WhatsappStickerImage.fromFile(source);
  }
}
