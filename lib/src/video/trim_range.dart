import 'package:flutter/material.dart';

enum TrimEdge { start, end }

const minimumTrimLength = Duration(milliseconds: 100);

/// Seeks to the clip start after trimming or when too little selected video remains.
Duration? playbackRestartPosition({
  required Duration duration,
  required RangeValues range,
  required Duration position,
  required bool selectionChanged,
  required bool completed,
}) {
  final start = duration * range.start;
  final end = duration * range.end;
  if (selectionChanged || completed || position < start || position >= end - const Duration(milliseconds: 80)) {
    return start;
  }
  return null;
}

/// Returns a frame-aligned trim range, or null when the requested frame is outside it.
RangeValues? moveTrimBoundary({
  required Duration duration,
  required RangeValues range,
  required TrimEdge edge,
  required Duration frame,
}) {
  final totalUs = duration.inMicroseconds;
  final frameUs = frame.inMicroseconds;
  if (totalUs < minimumTrimLength.inMicroseconds || frameUs < 0 || frameUs > totalUs) return null;

  final startUs = (duration * range.start).inMicroseconds;
  final endUs = (duration * range.end).inMicroseconds;
  if (edge == TrimEdge.start) {
    if (frameUs == startUs || frameUs > endUs - minimumTrimLength.inMicroseconds) return null;
    return RangeValues(frameUs / totalUs, range.end);
  }
  if (frameUs == endUs || frameUs < startUs + minimumTrimLength.inMicroseconds) return null;
  return RangeValues(range.start, frameUs / totalUs);
}
