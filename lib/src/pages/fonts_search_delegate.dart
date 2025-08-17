import 'package:flutter/material.dart';
import 'package:stickers/src/fonts_api/fonts_models.dart';
import 'package:stickers/src/pages/fonts_search_page.dart';

class GoogleFontsSearchDelegate extends SearchDelegate<WebFont> {
  final List<WebFont> fonts;

  GoogleFontsSearchDelegate(this.fonts);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pop(),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final searchResults = fonts.where((font) => font.family.toLowerCase().contains(query.toLowerCase())).toList();
    return ListView.separated(
      padding: EdgeInsets.only(top: 12),
      itemCount: searchResults.length,
      separatorBuilder: (ctx, idx) {
        return SizedBox(
          height: 8,
        );
      },
      itemBuilder: (context, index) {
        return GoogleFontPreview(
          searchResults[index],
          key: ValueKey(searchResults[index].family),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
  }
}
