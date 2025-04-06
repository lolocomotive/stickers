import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_handler/share_handler.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/edit_page.dart';
import 'package:stickers/src/pages/select_pack_page.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';
import 'package:stickers/src/pages/sticker_packs_page.dart';
import 'package:stickers/src/util.dart';

import 'settings/settings_controller.dart';
import 'settings/settings_page.dart';

/// The Widget that configures your application.
class StickersApp extends StatefulWidget {
  const StickersApp({
    super.key,
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  State<StickersApp> createState() => StickersAppState();
}

class StickersAppState extends State<StickersApp> {
  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  SharedMedia? media;

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    final handler = ShareHandlerPlatform.instance;
    media = await handler.getInitialSharedMedia();
    if (media != null) {
      debugPrint("Initial Media received");
      if (widget.settingsController.quickMode) {
        _quickAdd(media!, widget.settingsController.defaultTitle, widget.settingsController.defaultAuthor);
        media = null;
      }
    }
    handler.sharedMediaStream.listen((SharedMedia media) {
      navigatorKey.currentState!.pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
      if (!mounted) return;
      debugPrint("Media Stream received");
      if (widget.settingsController.quickMode) {
        _quickAdd(media, widget.settingsController.defaultTitle, widget.settingsController.defaultAuthor);
      } else {
        this.media = media;
      }
      setState(() {});
    });
    if (!mounted) return;

    setState(() {
      // _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Glue the SettingsController to the MaterialApp.
    //
    // The ListenableBuilder Widget listens to the SettingsController for changes.
    // Whenever the user updates their settings, the MaterialApp is rebuilt.
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          // Providing a restorationScopeId allows the Navigator built by the
          // MaterialApp to restore the navigation stack when a user leaves and
          // returns to the app after it has been killed while running in the
          // background.
          restorationScopeId: 'app',

          // Provide the generated AppLocalizations to the MaterialApp. This
          // allows descendant Widgets to display the correct translations
          // depending on the user's locale.
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''), // English, no country code
          ],

          // Use AppLocalizations to configure the correct application title
          // depending on the user's locale.
          //
          // The appTitle is defined in .arb files found in the localization
          // directory.
          onGenerateTitle: (BuildContext context) => AppLocalizations.of(context)!.appTitle,

          // Define a light and dark color theme. Then, read the user's
          // preferred ThemeMode (light, dark, or system default) from the
          // SettingsController to display the correct theme.
          theme: ThemeData(),
          darkTheme: ThemeData.dark(),
          themeMode: widget.settingsController.themeMode,
          navigatorKey: navigatorKey,

          // Define a function to handle named routes in order to support
          // Flutter web url navigation and deep linking.
          onGenerateRoute: (RouteSettings routeSettings) {
            return MaterialPageRoute<void>(
              settings: routeSettings,
              builder: (BuildContext context) {
                if (media != null) {
                  final page = SelectPackPage(media!);
                  media = null;
                  return page;
                }
                switch (routeSettings.name) {
                  case SettingsPage.routeName:
                    return SettingsPage(controller: widget.settingsController);
                  case CropPage.routeName:
                    final args = routeSettings.arguments as EditArguments;
                    return CropPage(
                      pack: args.pack,
                      index: args.index,
                      imagePath: args.imagePath,
                    );
                  case EditPage.routeName:
                    final args = routeSettings.arguments as EditArguments;
                    return EditPage(args.pack, args.index, args.imagePath);
                  case StickerPackPage.routeName:
                    return StickerPackPage(routeSettings.arguments as StickerPack, () {
                      setState(() {});
                    });
                  case StickerPacksPage.routeName:
                  default:
                    return const StickerPacksPage();
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> _quickAdd(SharedMedia media, String defaultTitle, String defaultAuthor) async {
    final rawImageData = File(media.attachments!.first!.path).readAsBytesSync();
    final pack = packs.firstWhere((pack) => pack.stickers.length < 30, orElse: () {
      final pack = StickerPack(
        defaultTitle,
        defaultAuthor,
        "pack_${DateTime.now().millisecondsSinceEpoch}",
        [],
        "0",
      );
      packs.add(pack);
      savePacks(packs);
      return pack;
    });
    final index = pack.stickers.length;
    final img = await decodeImageFromList(rawImageData);
    final cropRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final cropped = await cropSticker(cropRect, rawImageData, pack, index);
    addToPack(pack, index, cropped);

    navigatorKey.currentState!.pushNamed("/pack", arguments: pack).then((value) {
      if (homeState != null) {
        homeState!.update();
      }
    });
    await sendToWhatsappWithErrorHandling(pack);
  }
}
