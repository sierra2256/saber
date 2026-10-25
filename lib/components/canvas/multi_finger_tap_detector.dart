import 'dart:math';

import 'package:flutter/gestures.dart';

/// Detects quick taps with two or more fingers,
/// e.g. a two-finger tap to undo and a three-finger tap to redo.
///
/// A gesture only counts as a tap if every finger lifts within
/// [maxDuration] of the first finger touching down, and no finger
/// moves more than [maxMovement]. This prevents it from firing
/// during a pinch-zoom or a pan.
///
/// Only [PointerDeviceKind.touch] pointers are considered.
class MultiFingerTapDetector {
  new({required this.onTap});

  /// Called with the number of fingers used for the tap.
  final void Function(int fingers) onTap;

  static const maxDuration = Duration(milliseconds: 300);
  static const maxMovement = kTouchSlop;

  final _downPositions = <int, Offset>{};
  var _firstDownTime = Duration.zero;
  var _maxFingers = 0;
  var _cancelled = false;

  void onPointerDown(PointerDownEvent event) {
    if (event.kind != .touch) return;

    if (_downPositions.isEmpty) {
      // start of a new gesture
      _firstDownTime = event.timeStamp;
      _maxFingers = 0;
      _cancelled = false;
    }

    _downPositions[event.pointer] = event.position;
    _maxFingers = max(_maxFingers, _downPositions.length);
    _checkDuration(event.timeStamp);
  }

  void onPointerMove(PointerMoveEvent event) {
    final downPosition = _downPositions[event.pointer];
    if (downPosition == null) return;

    if ((event.position - downPosition).distance > maxMovement) {
      _cancelled = true;
    }
    _checkDuration(event.timeStamp);
  }

  void onPointerUp(PointerUpEvent event) {
    if (_downPositions.remove(event.pointer) == null) return;
    _checkDuration(event.timeStamp);

    if (_downPositions.isNotEmpty) return;
    if (_cancelled) return;
    if (_maxFingers < 2) return;
    onTap(_maxFingers);
  }

  void onPointerCancel(PointerCancelEvent event) {
    if (_downPositions.remove(event.pointer) == null) return;
    _cancelled = true;
  }

  void _checkDuration(Duration timeStamp) {
    if (timeStamp - _firstDownTime > maxDuration) _cancelled = true;
  }
}
