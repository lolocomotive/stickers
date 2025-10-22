import 'package:flutter/material.dart';
import 'package:stickers/src/fonts_api/fonts_models.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/fonts_api/google_fonts.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/pages/fonts_search_delegate.dart';

class FontsSearchPage extends StatefulWidget {
  const FontsSearchPage({super.key});

  @override
  State<FontsSearchPage> createState() => _FontsSearchPageState();
}

class _FontsSearchPageState extends State<FontsSearchPage> {
  Future<GoogleFontsReply>? _future;

  @override
  void initState() {
    _future = getFonts();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
      title: "Search for fonts",
      actions: [
        FutureBuilder(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                    onPressed: () {
                      showSearch(context: context, delegate: GoogleFontsSearchDelegate(snapshot.data!.items));
                    },
                    icon: Icon(Icons.search));
              }
              return SizedBox();
            })
      ],
      child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final result = snapshot.data!;
              return ListView.separated(
                separatorBuilder: (ctx, idx) {
                  return SizedBox(
                    height: 8,
                  );
                },
                itemBuilder: (ctx, idx) {
                  return GoogleFontPreview(result.items[idx]);
                },
                itemCount: result.items.length,
              );
            }
            if (snapshot.hasError) {
              print(snapshot.error);
              print(snapshot.stackTrace);
              return Column(
                children: [
                  Text("Error"),
                ],
              );
            }
            return Center(child: CircularProgressIndicator());
          }),
    );
  }
}

class GoogleFontPreview extends StatefulWidget {
  final WebFont font;

  const GoogleFontPreview(this.font, {super.key});

  @override
  State<GoogleFontPreview> createState() => _GoogleFontPreviewState();
}

class _GoogleFontPreviewState extends State<GoogleFontPreview> {
  Future? _future;
  bool _delayOver = false;

  @override
  void initState() {
    Future.delayed(Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _delayOver = true;
      });
    });
    if (!FontsRegistry.contains(widget.font.family)) {
      _future = downloadAndRegisterFontPreview(widget.font).then((_) {
        // We have to return something here or the FutureBuilder doesn't work as it should
        if (!mounted) return 1;
        setState(() {});
        return 0;
      });
    } else {
      _future = Future.value(0);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    bool inRegistry = FontsRegistry.get(widget.font.family)?.fontFile != null;
    return Opacity(
      opacity: inRegistry ? .7 : 1,
      child: Card(
        child: FutureBuilder(
            future: _future,
            builder: (context, asyncSnapshot) {
              return Stack(
                children: [
                  ListTile(
                    subtitle: inRegistry
                        ? Center(child: Text("Already downloaded"))
                        : (asyncSnapshot.hasError ? Center(child: Text("Error downloading font preview")) : null),
                    onTap: inRegistry
                        ? null
                        : () async {
                            await showDialog(
                              context: context,
                              builder: (context) => DownloadFontDialog(widget: widget),
                            );
                          },
                    title: Text(
                      widget.font.family,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: inRegistry ? widget.font.family : "${widget.font.family}-PREVIEW",
                        fontSize: 25,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity:
                        (!asyncSnapshot.hasData && _future != null && _delayOver && !asyncSnapshot.hasError) ? .7 : 0,
                    duration: Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.onSurface,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                ],
              );
            }),
      ),
    );
  }
}

class DownloadFontDialog extends StatefulWidget {
  const DownloadFontDialog({
    super.key,
    required this.widget,
  });

  final GoogleFontPreview widget;

  @override
  State<DownloadFontDialog> createState() => _DownloadFontDialogState();
}

class _DownloadFontDialogState extends State<DownloadFontDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Download ${widget.widget.font.family}?"),
      actions: [
        TextButton(
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            child: Text("Cancel")),
        ElevatedButton(
            onPressed: _loading
                ? null
                : () async {
                    setState(() {
                      _loading = true;
                    });
                    await downloadAndRegisterFont(widget.widget.font);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
            child: _loading ? Text("Downloading...") : Text("Download")),
      ],
    );
  }
}
