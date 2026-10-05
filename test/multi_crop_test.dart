import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_editor/image_editor.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/data/batch_import.dart';
import 'package:stickers/src/data/sticker.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/globals.dart' as globals;
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/multi_crop_page.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';
import 'fake_picker.dart';

class FakeImageEditor extends UnsupportedImageEditor {
  FakeImageEditor(this.output);
  final Uint8List output;
  final edits = <ImageEditorOption>[];
  int merges = 0;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<Uint8List?> editImage({required Uint8List image, required ImageEditorOption imageEditorOption}) async {
    edits.add(imageEditorOption);
    if (pending != null) await pending!.future;
    if (fail) throw PlatformException(code: 'bad_image');
    return output;
  }

  @override
  Future<Uint8List?> mergeToMemory({required ImageMergeOption option}) async {
    merges++;
    return output;
  }
}

Future<Uint8List> imageBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.amber, BlendMode.src);
  canvas.drawRect(Rect.fromLTWH(0, 0, width / 2, height.toDouble()), Paint()..color = Colors.teal);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FakePicker picker;
  late FakeImageEditor editor;
  late ImagePickerPlatform oldPicker;
  late ImageEditorPlatform oldEditor;
  late StickerPack pack;
  late Uint8List originalBytes, croppedBytes;
  late String first, second;
  setUpAll(() async {
    final fonts = Platform.environment['STICKERS_TEST_FONTS'];
    if (fonts != null) {
      for (final font in {'Roboto': 'roboto-regular.ttf', 'MaterialIcons': 'materialicons-regular.otf'}.entries) {
        final loader = FontLoader(font.key);
        loader.addFont(File('$fonts/${font.value}').readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    }
    originalBytes = await imageBytes(320, 160);
    croppedBytes = await imageBytes(512, 512);
  });
  setUp(() {
    Directory('build/test-work').createSync(recursive: true);
    directory = Directory('build/test-work').createTempSync('batch_');
    first = File('${directory.path}/first.png').absolute.path;
    second = File('${directory.path}/second.png').absolute.path;
    File(first).writeAsBytesSync(originalBytes);
    File(second).writeAsBytesSync(originalBytes);
    packsDir = '${directory.path}/packs';
    Directory(packsDir).createSync();
    pack = StickerPack('Test pack', 'Author', 'test', [], '1', false);
    globals.packs = [pack];
    File('$packsDir/packs.json').writeAsStringSync(jsonEncode([pack.toJson()]));
    oldPicker = ImagePickerPlatform.instance;
    oldEditor = ImageEditorPlatform.instance;
    picker = FakePicker()..images = [XFile(first), XFile(second)];
    editor = FakeImageEditor(croppedBytes);
    ImagePickerPlatform.instance = picker;
    ImageEditorPlatform.instance = editor;
  });
  tearDown(() {
    ImagePickerPlatform.instance = oldPicker;
    ImageEditorPlatform.instance = oldEditor;
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      // Windows image codecs may keep fixtures mapped until the test process
      // exits. They live under build/ and can be cleaned with other build files.
      if (error.osError?.errorCode != 32) rethrow;
    }
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await settle(tester);
    }
    expect(ready(), isTrue);
  }

  Future<void> showPack(WidgetTester tester, {int count = 0, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    });
    pack.stickers.addAll(List.generate(count, (_) => Sticker(first, [], null)));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StickerPackPage(pack, () {})),
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Video crop'))),
      ),
    );
    await settle(tester);
    await tester.scrollUntilVisible(find.byIcon(Icons.add), 300, scrollable: find.byType(Scrollable).last);
  }

  Future<void> select(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester, int count) async {
    await tester.tap(find.text('Save all ($count)'));
    await until(tester, () => find.byType(MultiCropPage).evaluate().isEmpty);
    await settle(tester);
  }

  testWidgets('gallery imports all images as-is without opening crop and preserves existing stickers', (tester) async {
    await showPack(tester, count: 1);
    final existing = pack.stickers.first;
    await select(tester);
    expect(find.byType(MultiCropPage), findsOneWidget);
    expect(find.byType(CropPage), findsNothing);
    expect(find.text('first.png'), findsOneWidget);
    expect(find.text('second.png'), findsOneWidget);
    expect(pack.stickers, [existing]);
    await save(tester, 2);
    expect(pack.stickers.length, 3);
    expect(pack.stickers.first, same(existing));
    expect(pack.imageDataVersion, '2');
    for (final edit in editor.edits) {
      final clip = edit.options.whereType<ClipOption>().single;
      expect([clip.x, clip.y, clip.width, clip.height], [0, 0, 320, 160]);
      final scale = edit.options.whereType<ScaleOption>().single;
      expect([scale.width, scale.height], [512, 256]);
    }
    expect(editor.merges, 2);
    expect(jsonDecode(File('$packsDir/packs.json').readAsStringSync()).single['stickers'].length, 3);
  });
  testWidgets('gallery decodes thumbnails to physical tile bounds without changing import resolution', (tester) async {
    await tester.runAsync(() async {
      File(first).writeAsBytesSync(await imageBytes(1600, 800));
      File(second).writeAsBytesSync(await imageBytes(800, 1600));
    });
    await showPack(tester);
    await select(tester);
    for (final ratio in [1.0, 3.0]) {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(390 * ratio, 844 * ratio);
      await settle(tester);
      for (final entry in {'first.png': 2.0, 'second.png': .5}.entries) {
        final tile = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Crop ${entry.key}');
        final raw = find.descendant(of: tile, matching: find.byType(RawImage));
        await until(tester, () => raw.evaluate().isNotEmpty && tester.widget<RawImage>(raw).image != null);
        final decoded = tester.widget<RawImage>(raw).image!;
        final bounds = tester.getSize(raw);
        expect(decoded.width, lessThanOrEqualTo((bounds.width * ratio).ceil()));
        expect(decoded.height, lessThanOrEqualTo((bounds.height * ratio).ceil()));
        expect(decoded.width / decoded.height, closeTo(entry.value, .03));
        expect(decoded.width, greaterThan(50 * ratio));
      }
    }
    await save(tester, 2);
    final clips = editor.edits.map((edit) => edit.options.whereType<ClipOption>().single).toList();
    expect([clips[0].width, clips[0].height], [1600, 800]);
    expect([clips[1].width, clips[1].height], [800, 1600]);
  });
  testWidgets('real crop screen returns a preview without saving; bulk save uses that crop', (tester) async {
    await showPack(tester);
    await select(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Crop first.png'));
    await until(tester, () {
      final pages = find.byType(CropPage).evaluate();
      return pages.isNotEmpty && (pages.single.widget as CropPage).editorKey.currentState?.getCropRect() != null;
    });
    await tester.tap(find.text('1:1'));
    await settle(tester);
    await tester.tap(find.text('Save crop'));
    await until(tester, () => find.byType(CropPage).evaluate().isEmpty);
    expect(find.byType(MultiCropPage), findsOneWidget);
    expect(find.byTooltip('Reset crop'), findsOneWidget);
    expect(pack.stickers, isEmpty);
    final clip = editor.edits.single.options.whereType<ClipOption>().single;
    expect(clip.width, clip.height);
    await save(tester, 2);
    expect(pack.stickers.length, 2);
    expect(editor.merges, 2);
    expect(File(pack.stickers.first.source).readAsBytesSync(), croppedBytes);
  });
  testWidgets('crop preview preserves the dev branch stretch option', (tester) async {
    await showPack(tester);
    await select(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Crop first.png'));
    await until(tester, () {
      final pages = find.byType(CropPage).evaluate();
      return pages.isNotEmpty && (pages.single.widget as CropPage).editorKey.currentState?.getCropRect() != null;
    });
    await tester.tap(find.text('Stretch'));
    await settle(tester);
    await tester.tap(find.text('Save crop'));
    await until(tester, () => find.byType(CropPage).evaluate().isEmpty);
    final edit = editor.edits.single;
    final clip = edit.options.whereType<ClipOption>().single;
    expect(clip.width, isNot(clip.height));
    final scale = edit.options.whereType<ScaleOption>().single;
    expect([scale.width, scale.height], [512, 512]);
    expect(pack.stickers, isEmpty);
    await save(tester, 2);
    expect(pack.stickers.length, 2);
    expect(pack.stickers.every((sticker) => sticker.editorData == null), isTrue);
  });
  testWidgets('back from crop keeps selection; back from gallery saves nothing', (tester) async {
    await showPack(tester);
    await select(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Crop first.png'));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Save all (2)'), findsOneWidget);
    expect(pack.stickers, isEmpty);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(MultiCropPage), findsNothing);
    expect(pack.stickers, isEmpty);
  });
  testWidgets('saving blocks duplicate submissions and back navigation until the batch is committed', (tester) async {
    editor.pending = Completer<void>();
    await showPack(tester);
    await select(tester);
    final submit = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save all (2)')).onPressed!;
    submit();
    submit();
    await until(tester, () => editor.edits.isNotEmpty);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(MultiCropPage), findsOneWidget);
    expect(pack.stickers, isEmpty);
    editor.pending!.complete();
    await until(tester, () => find.byType(MultiCropPage).evaluate().isEmpty);
    expect(pack.stickers.length, 2);
    expect(editor.merges, 2);
  });

  testWidgets('bad image is identified without a partial save; removing it allows retry', (tester) async {
    File(second).writeAsStringSync('not an image');
    await showPack(tester);
    await select(tester);
    await tester.tap(find.text('Save all (2)'));
    await until(tester, () => find.textContaining('Nothing was saved.').evaluate().isNotEmpty);
    expect(find.text('second.png'), findsOneWidget);
    expect(pack.stickers, isEmpty);
    expect(jsonDecode(File('$packsDir/packs.json').readAsStringSync()).single['stickers'], isEmpty);
    await tester.tap(find.byTooltip('Remove second.png'));
    await settle(tester);
    await save(tester, 1);
    expect(pack.stickers.length, 1);
  });
  testWidgets('removing all selections disables save', (tester) async {
    await showPack(tester);
    await select(tester);
    await tester.tap(find.byTooltip('Remove first.png'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove second.png'));
    await tester.pump();
    expect(find.text('No images selected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save all (0)')).onPressed, isNull);
  });
  testWidgets('last slot uses single picker', (tester) async {
    await showPack(tester, count: 29);
    await select(tester);
    expect(picker.singleCalls, 1);
    await save(tester, 1);
    expect(pack.stickers.length, 30);
  });
  testWidgets('provider ignoring limit cannot overfill pack', (tester) async {
    picker.images.add(XFile(first));
    await showPack(tester, count: 28);
    await select(tester);
    expect(picker.limit, 2);
    expect(find.text('Save all (2)'), findsOneWidget);
    await save(tester, 2);
    expect(pack.stickers.length, 30);
  });
  testWidgets('full pack cannot open picker', (tester) async {
    await showPack(tester, count: 30);
    await select(tester);
    expect(picker.multiCalls + picker.singleCalls, 0);
  });
  testWidgets('cancelled picker, repeated tap, and disposed page do not start an import', (tester) async {
    picker.images = [];
    await showPack(tester);
    await select(tester);
    expect(find.byType(MultiCropPage), findsNothing);
    picker.pending = Completer<List<XFile>>();
    await select(tester);
    await tester.tap(find.byIcon(Icons.add));
    expect(picker.multiCalls, 2);
    await tester.pumpWidget(const SizedBox());
    picker.pending!.complete([XFile(first)]);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('animated packs retain video flow', (tester) async {
    pack.animated = true;
    await showPack(tester);
    await select(tester);
    expect(picker.videoCalls, 1);
    expect(find.text('Video crop'), findsOneWidget);
  });
  test('failed manifest commit rolls back batch and permits retry', () async {
    final manifest = File('$packsDir/packs.json');
    manifest.deleteSync();
    Directory(manifest.path).createSync();
    await expectLater(saveStickerBatch(pack, [croppedBytes, croppedBytes]), throwsA(isA<FileSystemException>()));
    expect(pack.stickers, isEmpty);
    expect(pack.imageDataVersion, '1');
    expect(Directory('$packsDir/${pack.id}').listSync(), isEmpty);
    Directory(manifest.path).deleteSync();
    await saveStickerBatch(pack, [croppedBytes, croppedBytes]);
    expect(pack.stickers.length, 2);
  });
  test('bulk persistence enforces capacity', () async {
    pack.stickers.addAll(List.generate(29, (_) => Sticker(first, [], null)));
    await expectLater(saveStickerBatch(pack, [croppedBytes, croppedBytes]), throwsStateError);
    expect(pack.stickers.length, 29);
  });
  testWidgets('gallery fits small phone and wide window', (tester) async {
    await showPack(tester, size: const Size(360, 640));
    await select(tester);
    expect(tester.takeException(), isNull);
    if (Platform.environment['STICKERS_TEST_FONTS'] != null) {
      await until(tester, () => tester.widgetList<RawImage>(find.byType(RawImage)).every((w) => w.image != null));
      await tester.runAsync(() async {
        final boundary = tester.firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('../multi-crop-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    tester.view.physicalSize = const Size(900, 600);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
