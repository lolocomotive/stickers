import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/gif/gif_info.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';

class GifCropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;

  const GifCropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/crop_gif";

  @override
  State<GifCropPage> createState() => _GifCropPageState();
}

class _GifCropPageState extends State<GifCropPage> {
  GifInfo? _info;
  RangeValues _range = const RangeValues(0, 1);
  Duration _position = Duration.zero;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGif();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadGif() async {
    try {
      final info = await readGifInfo(File(widget.imagePath));
      if (!mounted) return;
      setState(() {
        _info = info;
        _range = _initialRange(info.duration);
        _position = Duration.zero;
        _loading = false;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      showDialog(
        context: context,
        builder: (context) => ErrorDialog(
          title: AppLocalizations.of(context)!.couldntLoadGif,
          message: e.toString(),
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return DefaultActivity(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.trimGif),
      ),
      child: SafeArea(
        child: _loading || info == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(),
                      child: Center(
                        child: Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (info.duration > maxAnimatedStickerDuration)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Opacity(
                            opacity: .8,
                            child: Text(
                              AppLocalizations.of(context)!.animatedDurationLimit,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Stack(
                          children: [
                            RangeSlider(
                              year2023: false,
                              values: _range,
                              onChanged: (values) {
                                final movedStart = values.start != _range.start;
                                final next = _clampRange(values, movedStart: movedStart);
                                setState(() {
                                  _range = next;
                                  _position = _durationFromFraction(next.start);
                                });
                              },
                            ),
                            IgnorePointer(
                              child: Slider(
                                thumbColor: Theme.of(context).colorScheme.onSurface,
                                activeColor: Colors.transparent,
                                inactiveColor: Colors.transparent,
                                value: _position.inMilliseconds / info.duration.inMilliseconds,
                                onChanged: (_) {},
                                year2023: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(_durationFromFraction(_range.start))),
                            Text(_formatDuration(_durationFromFraction(_range.end))),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                        child: FilledButton(
                          onPressed: _continueToEditor,
                          child: Text(AppLocalizations.of(context)!.done),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  RangeValues _initialRange(Duration duration) {
    if (duration <= maxAnimatedStickerDuration) return const RangeValues(0, 1);
    return RangeValues(0, maxAnimatedStickerDuration.inMilliseconds / duration.inMilliseconds);
  }

  RangeValues _clampRange(RangeValues values, {required bool movedStart}) {
    final duration = _info!.duration;
    final maxSpan = min(1.0, maxAnimatedStickerDuration.inMilliseconds / duration.inMilliseconds);
    var start = values.start.clamp(0.0, 1.0).toDouble();
    var end = values.end.clamp(0.0, 1.0).toDouble();

    if (end - start > maxSpan) {
      if (movedStart) {
        end = min(1.0, start + maxSpan);
      } else {
        start = max(0.0, end - maxSpan);
      }
    }
    if (end <= start) {
      end = min(1.0, start + .001);
    }
    return RangeValues(start, end);
  }

  void _tick() {
    final info = _info;
    if (!mounted || info == null) return;
    final start = _durationFromFraction(_range.start);
    final end = _durationFromFraction(_range.end);
    var next = _position + const Duration(milliseconds: 100);
    if (next >= end) next = start;
    setState(() {
      _position = next;
    });
  }

  Duration _durationFromFraction(double value) {
    return Duration(milliseconds: (_info!.duration.inMilliseconds * value).round());
  }

  void _continueToEditor() {
    final start = _durationFromFraction(_range.start);
    final end = _durationFromFraction(_range.end);
    final selected = end - start;
    if (selected <= Duration.zero || selected > maxAnimatedStickerDuration) {
      showDialog(
        context: context,
        builder: (context) => ErrorDialog(
          title: AppLocalizations.of(context)!.animatedDurationLimitTitle,
          message: AppLocalizations.of(context)!.animatedDurationLimitMessage,
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed(
      "/edit",
      arguments: EditArguments(
        pack: widget.pack,
        index: widget.index,
        mediaPath: widget.imagePath,
        type: MediaType.gif,
        trimStart: start,
        trimEnd: end,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inMilliseconds / 1000;
    return "${totalSeconds.toStringAsFixed(1)}s";
  }
}
