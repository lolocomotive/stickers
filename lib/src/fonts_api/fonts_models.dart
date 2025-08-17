class GoogleFontsReply {
  final String kind;
  final List<WebFont> items;

  GoogleFontsReply({
    required this.kind,
    required this.items,
  });

  factory GoogleFontsReply.fromJson(Map<String, dynamic> json) {
    return GoogleFontsReply(
      kind: json['kind'],
      items: (json['items'] as List)
          .map((item) => WebFont.fromJson(item))
          .toList(),
    );
  }
}
class WebFont {
  final String family;
  final List<String> variants;
  final List<String> subsets;
  final String version;
  final String lastModified;
  final Map<String, String> files;
  final String category;
  final String kind;
  final String menu;

  WebFont({
    required this.family,
    required this.variants,
    required this.subsets,
    required this.version,
    required this.lastModified,
    required this.files,
    required this.category,
    required this.kind,
    required this.menu,
  });

  factory WebFont.fromJson(Map<String, dynamic> json) {
    return WebFont(
      family: json['family'],
      variants: List<String>.from(json['variants']),
      subsets: List<String>.from(json['subsets']),
      version: json['version'],
      lastModified: json['lastModified'],
      files: Map<String, String>.from(json['files']),
      category: json['category'],
      kind: json['kind'],
      menu: json['menu'],
    );
  }
}