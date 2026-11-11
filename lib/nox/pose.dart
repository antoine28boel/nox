import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Everything the painter needs to draw Nox for one frame.
class NoxPose extends ChangeNotifier {
  bool hidden = false;
  double time = 0;
  bool sleeping = false;
  bool happy = false;
  bool surprised = false;

  /// Holds an envelope in his beak: he has news waiting for an answer.
  bool carrying = false;

  /// 0 = closed, 1 = open.
  double eyeOpen = 1;

  /// Where the pupils look, each axis in -1..1.
  Offset look = Offset.zero;

  /// -1 (left) .. 1 (right).
  double headTurn = 0;

  /// 0 = folded, 1 = wide open.
  double wingSpread = 0;

  /// Extra wing angle (radians) for flapping.
  double wingFlap = 0;
  bool feetTucked = false;

  /// Body rotation in radians.
  double tilt = 0;

  /// Asks the painter to redraw.
  void changed() => notifyListeners();
}
