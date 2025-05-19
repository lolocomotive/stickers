# Stickers

Simple android sticker maker for WhatsApp without ads.

[![](https://upload.wikimedia.org/wikipedia/commons/7/78/Google_Play_Store_badge_EN.svg)](https://play.google.com/store/apps/details?id=de.loicezt.stickers)

Or download from the latest [GitHub Release](https://github.com/lolocomotive/stickers/releases)

## Features

Best feature imo:

-   Sharing an image to the app directly adds it as a sticker to Whatsapp

Other basic features:

-   Creating and deleting sticker packs and stickers
-   Cropping stickers
-   Renaming sticker packs/author
-   Updating the sticker pack once it's already been added to whatsapp

## Building

Should be pretty straightforward since no special setup is required. Refer to the flutter documentation.

## Contributing

Any contributions (Pull requests, feature requests and bug reports) are very welcome!
Be aware that I set my line width to 100 instead of 80, so be careful before reformatting entire files. If you're using vscode put the following in `.vscode/settings.json` .

```json
{
    "dart.lineLength": 100,
    "[dart]": {
        "editor.rulers": [100]
    }
}
```

Also the code is not very well documented yet so sorry in advance to anyone trying to read it :3

## TODO

The app is far from finished and there's a few key points I want to work on:

-   [x] Better error reporting across the entire app
-   [ ] Image editor features
    -   [x] Text
    -   [ ] Drawing
-   [x] Allow setting a cusom Tray icon
-   [x] Allow editing more of the sticker pack metadata
-   [x] Find a name and logo
-   [x] Translate the App (Localization is setup, I just didn't use it)
-   [ ] Maybe improve the performance of cropping (It has to do 2 Image operations right now due to the way `image_editor` is made)

(also refer to the TODO comments in the code)

## iOS Support

I don't own any Apple devices, therefore I can't build for iOS nor test the iOS app. It's a flutter app so it should more or less work.
If you want to add iOS support, you're welcome! Here's some things to look out for:

-   `image_editor` would have to be modified to support WEBP on iOS (I only added support for WEBP on Android)
-   `whatsapp_stickers_plus` package might not work (it didn't on Android).
-   Many widgets would have to be replaced with their `.adaptive` equivalent if you want it to look like an iOS app
