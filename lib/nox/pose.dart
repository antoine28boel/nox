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

  /// 0 = full owl, 1 = tucked into the "island" at the top of the screen.
  double island = 0;

  /// 0 = island with just the eyes, 1 = island opened (Nox listens).
  double expand = 0;

  /// 0 = island shown, 1 = pulled back to a thin line (cursor nearby).
  double retract = 0;

  /// Whether the nest is on the bottom edge (above the taskbar) instead of
  /// the top of the screen.
  bool nestBottom = false;

  /// Asks the painter to redraw.
  void changed() => notifyListeners();
}

/// Phases of the trip into the nest, on the `island` 0..1 scale:
/// a slot opens (0 → [kSlotOpen]), Nox plunges into it ([kSlotOpen] →
/// [kPlungeEnd]), then the slot widens into the island and his eyes light up.
const kSlotOpen = 0.25;
const kPlungeEnd = 0.7;

double _ease(double t) => t * t * (3 - 2 * t);

/// How far Nox has plunged into the slot (0 = not yet, 1 = gone inside).
double plungeProgress(double island) =>
    _ease(((island - kSlotOpen) / (kPlungeEnd - kSlotOpen)).clamp(0.0, 1.0));

/// How far the slot has widened into the island after the plunge.
double widenProgress(double island) =>
    _ease(((island - kPlungeEnd) / (1 - kPlungeEnd)).clamp(0.0, 1.0));

/// Size of the island pill (logical px) for a given [island]/[expand].
Size islandSize(double island, double expand) {
  final open = _ease((island / kSlotOpen).clamp(0.0, 1.0));
  final widen = widenProgress(island);
  return Size(40 * open + 76 * widen + 60 * expand, 10 * open + 20 * widen + 34 * expand);
}

/// Gap between the top of the screen and the island (logical px).
const kIslandTop = 6.0;

/// The island inside Nox's window (logical px). Anchored to the top or the
/// bottom of the window depending on the screen edge it sits on; [retract]
/// pulls it back to a thin line against that edge.
Rect islandBox({
  required Size window,
  required double centerX,
  required double island,
  required double expand,
  required double retract,
  required bool bottom,
}) {
  final size = islandSize(island, expand);
  final w = size.width + (60 - size.width) * retract * (size.width > 0 ? 1 : 0);
  final h = size.height + (4 - size.height) * retract * (size.height > 0 ? 1 : 0);
  final gap = kIslandTop * (1 - retract);
  final top = bottom ? window.height - gap - h : gap;
  return Rect.fromLTWH(centerX - w / 2, top, w, h);
}
