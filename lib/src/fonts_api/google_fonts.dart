import 'dart:convert';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickers/src/api_keys.dart';
import 'package:stickers/src/fonts_api/fonts_models.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';

String apiURL = "https://www.googleapis.com/webfonts/v1/webfonts";
/*
 * https://developers.google.com/fonts/docs/developer_api/?apix=true
 * webfonts?key=<your_key>[&family=<family>][&subset=<subset>][&capability=<capability>...][&sort=<sort>]
 *    your_key: Your developer API Key.
 *    family: Name of a font family.
 *    subset: Name of a font subset.
 *    category: serif | sans-serif | monospace | display | handwriting
 *    capability: VF | WOFF2.
 *    sort: alpha | date | popularity | style | trending.
 */
Future<GoogleFontsReply> getFonts({String? family, String? category}) async {
  File fontsListCache = File("${(await getTemporaryDirectory()).path}/google_fonts.json");
  if (await fontsListCache.exists()) {
    try {
      return GoogleFontsReply.fromJson(jsonDecode(await fontsListCache.readAsString()));
    } on Exception catch (e, st) {
      debugPrint("Couldn't read font list from cache");
      debugPrint(e.toString());
      debugPrintStack(stackTrace: st);
    }
  }
  Uri uri = Uri.parse(apiURL).replace(queryParameters: {
    "key": fontsKey,
    if (family != null) "family": family,
    if (category != null) "category": category,
  });
  final response = await get(uri);
  await fontsListCache.create(recursive: true);
  await fontsListCache.writeAsString(response.body);
  return GoogleFontsReply.fromJson(jsonDecode(response.body));
}

double totalDownload = 0;

Future<void> downloadAndRegisterFont(WebFont font) async {
  final entry = FontsRegistry.get(font.family) ?? FontsRegistryEntry(font.family, FontType.googleFont);
  final tmp = await getApplicationDocumentsDirectory();
  await Directory("${tmp.path}/googleFonts").create(recursive: true);
  File dest = File("${tmp.path}/googleFonts/${font.family}.ttf");
  final result = await get(Uri.parse(font.files["regular"]!));
  await dest.writeAsBytes(result.bodyBytes);
  final loader = FontLoader(font.family);
  loader.addFont(Future.value(ByteData.view(result.bodyBytes.buffer)));
  await loader.load();
  entry.fontFile = dest.path;
  FontsRegistry.put(font.family, entry);
  await registerFont(entry);
}

Future<void> downloadAndRegisterFontPreview(WebFont font) async {
  print("Downloading font ${font.family}");
  if (FontsRegistry.contains(font.family)) {
    if (FontsRegistry.get(font.family)?.previewFile != null) {
      return;
    }
  }
  FontsRegistry.put(font.family, FontsRegistryEntry(font.family, FontType.googleFont));

  // Downloading font files for all of these fonts would use up almost 1GB of data, which is why we only download
  // a preview version of the font, capable of displaying only the font name, cutting the total download down to ~35MB
  // This unfortunately means we have to parse CSS as the official API does not provide this feature.
  // In the flutter engine, this preview font is registered as $family-PREVIEW.
  // In the editor plugin, this preview font is not registered at all.
  var result = await get(
      Uri.parse("https://fonts.googleapis.com/css2?family=${font.family}&sort=popularity&text=${font.family}"));
  totalDownload += (result.contentLength ?? 0) / 1000.0;

  final regex = RegExp(r"url\((.*?)\)", dotAll: true);
  final match = regex.firstMatch(result.body);
  final fontUrl = match?.group(1)?.trim();

  result = await get(Uri.parse(fontUrl!));
  totalDownload += (result.contentLength ?? 0) / 1000.0;
  debugPrint("Total: $totalDownload kB");

  debugPrint("Downloaded preview font ${font.family}");
  final tmp = await getTemporaryDirectory();
  await Directory("${tmp.path}/googleFonts").create(recursive: true);
  File dest = File("${tmp.path}/googleFonts/${font.family}.ttf");
  FontsRegistry.get(font.family)!.previewFile = dest.path;
  await dest.writeAsBytes(result.bodyBytes);
  final loader = FontLoader("${font.family}-PREVIEW");
  loader.addFont(Future.value(ByteData.view(result.bodyBytes.buffer)));
  await loader.load();
  FontsRegistry.get(font.family)!.isLoaded = true;
}
