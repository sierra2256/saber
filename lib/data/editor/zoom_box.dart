import 'dart:math';
import 'dart:ui';

/// The state of the zoom writing box: a magnified strip where you write
/// large, and the strokes appear small in the [target] area of the page.
///
/// The target area moves forward automatically as you write,
/// and wraps to the next line at the end of the page.
class ZoomBox {
  new({
    required this.pageIndex,
    required this.pageSize,
    required this.position,
    required this.height,
  });

  /// The page that is being written on.
  int pageIndex;

  /// The size of the page that is being written on.
  Size pageSize;

  /// The top-left of the target area, in page coordinates.
  Offset position;

  /// The height of the target area, in page coordinates.
  ///
  /// The width depends on the aspect ratio of the writing box.
  double height;

  /// When writing past this fraction of the target width,
  /// the target moves forward.
  static const advanceThreshold = 0.75;

  /// After moving forward, the latest writing ends up
  /// at this fraction of the target width.
  static const advanceTo = 0.25;

  /// The left and right margin of the page, as a fraction of its width.
  static const marginFraction = 0.05;

  double get margin => pageSize.width * marginFraction;

  /// The magnification for a writing box of size [boxSize].
  double scaleFor(Size boxSize) => boxSize.height / height;

  /// The target area on the page for a writing box of size [boxSize].
  Rect targetFor(Size boxSize) =>
      position & Size(boxSize.width / scaleFor(boxSize), height);

  /// Converts a position in the writing box to page coordinates.
  Offset toPage(Offset boxPosition, Size boxSize) =>
      position + boxPosition / scaleFor(boxSize);

  /// Moves the target forward if a stroke ending at [strokeRight]
  /// (in page coordinates) is near the end of the target area.
  ///
  /// Returns whether the target moved.
  bool advanceAfterStroke(double strokeRight, Size boxSize) {
    final target = targetFor(boxSize);
    if (strokeRight < target.left + target.width * advanceThreshold) {
      return false;
    }
    _moveTo(strokeRight - target.width * advanceTo, target.width);
    return true;
  }

  /// Moves the target forward by half its width.
  void forward(Size boxSize) {
    final width = targetFor(boxSize).width;
    _moveTo(position.dx + width / 2, width);
  }

  /// Moves the target back by half its width.
  void back(Size boxSize) {
    final width = targetFor(boxSize).width;
    final dx = position.dx - width / 2;
    position = Offset(max(0, dx), position.dy);
  }

  /// Moves the target to the start of the next line.
  void newLine() {
    position = Offset(
      margin,
      min(position.dy + height, max(0, pageSize.height - height)),
    );
  }

  /// Moves the target up a line.
  void lineUp() {
    position = Offset(position.dx, max(0, position.dy - height));
  }

  void _moveTo(double dx, double targetWidth) {
    // Writing continues at [advanceTo] of the target,
    // so wrap if that's past the right margin.
    if (dx + targetWidth * advanceTo > pageSize.width - margin) {
      newLine();
    } else {
      position = Offset(max(0, dx), position.dy);
    }
  }
}
