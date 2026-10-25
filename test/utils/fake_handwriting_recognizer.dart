import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';

/// A [HandwritingRecognizer] for tests, since ML Kit only runs on devices.
///
/// Each line is "recognized" as the text in [textForLine],
/// or as "line N" (with N counting from 1) if [textForLine] is null.
class FakeHandwritingRecognizer extends HandwritingRecognizer {
  new({this.textForLine, this.modelDownloaded = true});

  String? Function(List<Stroke> line)? textForLine;
  bool modelDownloaded;

  /// The lines passed to [recognizeLine], with their pre-contexts.
  final recognizedLines = <({List<Stroke> strokes, String? preContext})>[];

  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelDownloaded() async => modelDownloaded;

  @override
  Future<bool> downloadModel() async => modelDownloaded = true;

  @override
  Future<String?> recognizeLine(
    List<Stroke> strokes, {
    String? preContext,
  }) async {
    recognizedLines.add((strokes: strokes, preContext: preContext));
    return textForLine?.call(strokes) ?? 'line ${recognizedLines.length}';
  }
}
