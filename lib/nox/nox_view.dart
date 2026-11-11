import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../win/win_desktop.dart';
import 'brain.dart';
import 'owl_painter.dart';

/// Size of Nox's window and where his feet sit inside it (logical pixels).
const kNoxWindowSize = Size(200, 180);
const kNoxFeet = Offset(100, 170);

/// Runs Nox's brain every frame, moves his window and draws him.
class NoxView extends StatefulWidget {
  const NoxView({
    super.key,
    required this.brain,
    required this.desktop,
    required this.onMouseOver,
  });

  final NoxBrain brain;
  final WinDesktop desktop;

  /// Called when the cursor enters (true) or leaves (false) Nox's body, so
  /// the window only catches clicks on Nox and lets the rest through.
  final ValueChanged<bool> onMouseOver;

  @override
  State<NoxView> createState() => _NoxViewState();
}

class _NoxViewState extends State<NoxView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _lastX = -1 << 30;
  int _lastY = -1 << 30;
  // Start as "over" so the first frame turns click-through on.
  bool _over = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final brain = widget.brain;
    final desktop = widget.desktop;

    brain.scale = desktop.scale();
    brain.update(dt, desktop);

    final s = brain.scale;
    final x = (brain.pos.dx - kNoxFeet.dx * s).round();
    final y = (brain.pos.dy - kNoxFeet.dy * s).round();
    if (x != _lastX || y != _lastY) {
      _lastX = x;
      _lastY = y;
      desktop.moveWindow(x, y);
    }
    desktop.showFeather(brain.hidden ? null : brain.featherPos, brain.featherOpacity);

    final over = brain.state == NoxState.dragged || brain.hitTest(desktop.cursor());
    if (over != _over) {
      _over = over;
      widget.onMouseOver(over);
    }

    brain.pose.changed();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.brain.startDrag(widget.desktop.cursor()),
      child: CustomPaint(
        size: kNoxWindowSize,
        painter: OwlPainter(pose: widget.brain.pose, feet: kNoxFeet),
      ),
    );
  }
}
