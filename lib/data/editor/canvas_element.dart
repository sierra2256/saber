import 'dart:convert';
import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:sbn/has_size.dart';

/// A saved group of strokes (like a sticker) that can be
/// inserted into any note, see [stows.savedElements].
///
/// The strokes are stored relative to the top-left of their bounds.
class CanvasElement {
  new _(this.strokes, this.bounds);

  /// Creates an element from copies of [strokes],
  /// e.g. the strokes in a lasso selection.
  factory fromStrokes(Iterable<Stroke> strokes) {
    final bounds = boundsOf(strokes);
    return CanvasElement._([
      for (final stroke in strokes)
        stroke.copy()
          ..shift(-bounds.topLeft)
          ..pageIndex = 0
          ..page = _page,
    ], bounds.shift(-bounds.topLeft));
  }

  /// Decodes an element encoded with [encode].
  factory decode(String encoded) {
    final json = BsonCodec.deserialize(BsonBinary.from(base64Decode(encoded)));
    final strokes = [
      for (final strokeJson in json['s'] as List)
        Stroke.fromJson(
          Map<String, dynamic>.from(strokeJson as Map),
          fileVersion: json['v'] as int,
          pageIndex: 0,
          page: _page,
        ),
    ];
    return CanvasElement._(strokes, boundsOf(strokes));
  }

  final List<Stroke> strokes;
  final Rect bounds;

  /// A placeholder page size for the strokes until they are inserted.
  static const _page = HasSize(EditorPage.defaultSize);

  /// Encodes this element as a string to store in prefs.
  String encode() {
    final bson = BsonCodec.serialize({
      'v': EditorCoreInfo.sbnVersion,
      's': [for (final stroke in strokes) stroke.toJson()],
    });
    return base64Encode(Uint8List.fromList(bson.byteList));
  }

  /// Returns copies of the strokes for [page], centered at [center].
  List<Stroke> instantiate({
    required EditorPage page,
    required int pageIndex,
    required Offset center,
  }) {
    final offset = center - bounds.center;
    return [
      for (final stroke in strokes)
        stroke.copy()
          ..shift(offset)
          ..pageIndex = pageIndex
          ..page = page,
    ];
  }

  static Rect boundsOf(Iterable<Stroke> strokes) {
    Rect? bounds;
    for (final stroke in strokes) {
      final strokeBounds = stroke.lowQualityPath.getBounds();
      bounds = bounds?.expandToInclude(strokeBounds) ?? strokeBounds;
    }
    return bounds ?? Rect.zero;
  }
}
