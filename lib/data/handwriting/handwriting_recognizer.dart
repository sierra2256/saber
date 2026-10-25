import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/handwriting/handwriting_lines.dart';
import 'package:sbn/tool_id.dart';

/// Recognizes handwriting on the device.
///
/// The handwriting never leaves the device. The only network connection
/// is a one-time download of the language model, see [downloadModel].
abstract class HandwritingRecognizer {
  /// The recognizer used by the app. Tests can replace this with a fake.
  static HandwritingRecognizer instance = MlKitHandwritingRecognizer();

  /// The language of the handwriting.
  static const languageCode = 'en';

  /// Whether handwriting recognition is supported on this platform.
  bool get isSupported;

  Future<bool> isModelDownloaded();

  /// Downloads the language model. Returns whether it succeeded.
  Future<bool> downloadModel();

  /// Recognizes a single line of handwriting,
  /// returning null if nothing was recognized.
  ///
  /// [preContext] is the text written just before this line, if any,
  /// which helps with recognition.
  Future<String?> recognizeLine(List<Stroke> strokes, {String? preContext});

  /// Whether [stroke] is handwriting that should be recognized,
  /// e.g. not a highlighter, tape or a shape.
  static bool isHandwriting(Stroke stroke) {
    if (stroke is CircleStroke || stroke is RectangleStroke) return false;
    if (stroke.isEmpty) return false;
    return switch (stroke.toolId) {
      ToolId.fountainPen || ToolId.ballpointPen || ToolId.pencil => true,
      _ => false,
    };
  }

  /// Recognizes [strokes], which may span multiple lines.
  /// Returns the recognized text, with one line per line of handwriting.
  Future<String> recognize(Iterable<Stroke> strokes) async {
    final lines = HandwritingLines.group(strokes.where(isHandwriting));
    final recognizedLines = <String>[];
    for (final line in lines) {
      final text = await recognizeLine(
        line,
        preContext: recognizedLines.lastOrNull,
      );
      if (text != null && text.isNotEmpty) recognizedLines.add(text);
    }
    return recognizedLines.join('\n');
  }
}

/// A [HandwritingRecognizer] that uses ML Kit's Digital Ink Recognition,
/// which runs on the device (Android and iOS only).
class MlKitHandwritingRecognizer extends HandwritingRecognizer {
  static final log = Logger('MlKitHandwritingRecognizer');

  final _modelManager = mlkit.DigitalInkRecognizerModelManager();
  late final _recognizer = mlkit.DigitalInkRecognizer(
    languageCode: HandwritingRecognizer.languageCode,
  );

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<bool> isModelDownloaded() async {
    if (!isSupported) return false;
    try {
      return await _modelManager.isModelDownloaded(
        HandwritingRecognizer.languageCode,
      );
    } catch (e) {
      log.warning('Failed to check if model is downloaded: $e', e);
      return false;
    }
  }

  @override
  Future<bool> downloadModel() async {
    if (!isSupported) return false;
    try {
      return await _modelManager.downloadModel(
        HandwritingRecognizer.languageCode,
        isWifiRequired: false,
      );
    } catch (e) {
      log.warning('Failed to download model: $e', e);
      return false;
    }
  }

  @override
  Future<String?> recognizeLine(
    List<Stroke> strokes, {
    String? preContext,
  }) async {
    if (!isSupported || strokes.isEmpty) return null;

    // Saber doesn't record when each point was drawn,
    // so make up increasing timestamps in drawing order.
    var t = 0;
    final ink = mlkit.Ink()
      ..strokes = [
        for (final stroke in strokes)
          mlkit.Stroke()
            ..points = [
              for (final point in stroke.centerline)
                mlkit.StrokePoint(x: point.dx, y: point.dy, t: t += 10),
            ],
      ];

    final bounds = HandwritingLines.boundsOf(strokes);
    try {
      final candidates = await _recognizer.recognize(
        ink,
        context: mlkit.DigitalInkRecognitionContext(
          preContext: preContext,
          writingArea: mlkit.WritingArea(
            width: bounds.width,
            height: bounds.height,
          ),
        ),
      );
      return candidates.firstOrNull?.text;
    } catch (e) {
      log.warning('Failed to recognize handwriting: $e', e);
      return null;
    }
  }
}
