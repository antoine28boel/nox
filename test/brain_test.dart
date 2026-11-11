import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox/nox/brain.dart';
import 'package:nox/nox/desktop.dart';

/// A fake 1920x1080 screen with a 40 px taskbar and a few windows.
class FakeDesktop implements Desktop {
  Offset cursorPos = const Offset(1500, 900);
  int idle = 0;
  bool button = false;
  bool fullscreen = false;
  int? foreground;
  final windows = <int, Rect>{};
  final hidden = <int>{};

  /// Window covering the others (z-order top), if any.
  int? onTop;

  static const screen = Rect.fromLTWH(0, 0, 1920, 1080);
  static const work = Rect.fromLTWH(0, 0, 1920, 1040);

  @override
  Offset cursor() => cursorPos;
  @override
  int idleMillis() => idle;
  @override
  bool leftButtonDown() => button;
  @override
  Rect workArea(Offset at) => work;
  @override
  Rect monitorBounds(Offset at) => screen;
  @override
  int? foregroundWindow() => foreground;
  @override
  Rect? windowRect(int handle) => hidden.contains(handle) ? null : windows[handle];
  @override
  bool isPerchable(int handle) => windowRect(handle) != null;
  @override
  bool isTopAt(int handle, Offset point) {
    final top = onTop;
    if (top != null && top != handle && (windows[top]?.contains(point) ?? false)) {
      return false;
    }
    return windows[handle]?.contains(point) ?? false;
  }

  @override
  bool foregroundIsFullscreen() => fullscreen;
}

void run(NoxBrain b, Desktop d, double seconds) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds; t += dt) {
    b.update(dt, d);
  }
}

void main() {
  late FakeDesktop d;
  late NoxBrain b;

  setUp(() {
    d = FakeDesktop();
    d.windows[1] = const Rect.fromLTWH(400, 300, 900, 600);
    d.foreground = 1;
    b = NoxBrain(random: math.Random(1));
  });

  test('lands on the title bar of the foreground window', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    expect(b.state, NoxState.perched);
    expect(b.perch?.handle, 1);
    expect(b.pos.dy, 300);
    expect(b.pos.dx, inInclusiveRange(400, 1300));
  });

  test('is carried along when the window moves slowly', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    final before = b.pos;
    for (var i = 0; i < 30; i++) {
      d.windows[1] = d.windows[1]!.shift(const Offset(2, 1));
      b.update(1 / 60, d);
    }
    expect(b.state, NoxState.perched);
    expect(b.pos, before + const Offset(60, 30));
  });

  test('takes off when the window is shaken', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.windows[1] = d.windows[1]!.shift(const Offset(200, 0));
    b.update(1 / 60, d);
    expect(b.state, NoxState.flying);
  });

  test('falls then flies away when the window is minimized', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.hidden.add(1);
    b.update(1 / 60, d);
    expect(b.state, NoxState.falling);
    run(b, d, 8);
    expect(b.state, NoxState.perched);
    expect(b.perch?.isFloor, isTrue);
    expect(b.pos.dy, FakeDesktop.work.bottom);
  });

  test('leaves when another window covers his spot', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    final x = b.pos.dx;
    d.windows[2] = Rect.fromLTWH(x - 100, 200, 400, 400);
    d.onTop = 2;
    d.foreground = 2;
    run(b, d, 0.6);
    expect(b.perch?.handle, isNot(1));
  });

  test('can be dragged and thrown, then lands', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.cursorPos = b.pos + const Offset(0, -50);
    b.startDrag(d.cursorPos);
    d.button = true;
    for (var i = 0; i < 10; i++) {
      d.cursorPos += const Offset(20, -5);
      b.update(1 / 60, d);
    }
    expect(b.state, NoxState.dragged);
    expect(b.pos, d.cursorPos + const Offset(0, 50));
    d.button = false;
    b.update(1 / 60, d);
    expect(b.state, NoxState.falling);
    expect(b.vel.dx, greaterThan(0));
    run(b, d, 10);
    expect(b.state, NoxState.perched);
  });

  test('falls asleep when the user is idle and wakes up on input', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.idle = 10 * 60 * 1000;
    b.update(1 / 60, d);
    expect(b.sleeping, isTrue);
    expect(b.pose.sleeping, isTrue);
    d.idle = 0;
    b.update(1 / 60, d);
    expect(b.sleeping, isFalse);
  });

  test('hides during fullscreen apps', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.fullscreen = true;
    b.update(1 / 60, d);
    expect(b.pose.hidden, isTrue);
    expect(b.hitTest(b.pos + const Offset(0, -50)), isFalse);
  });

  test('espiègle follows the window you switch to', () {
    b.mode = NoxMode.espiegle;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.windows[3] = const Rect.fromLTWH(100, 500, 600, 400);
    var followed = false;
    // Random: try a few switches.
    for (var i = 0; i < 6 && !followed; i++) {
      d.foreground = i.isEven ? 3 : 1;
      run(b, d, 6);
      followed = b.perch?.handle == 3;
    }
    expect(followed, isTrue);
  });

  test('scales with Windows display scaling', () {
    b.scale = 2;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 8);
    expect(b.state, NoxState.perched);
    expect(b.hitTest(b.pos + const Offset(0, -100)), isTrue);
    expect(b.hitTest(b.pos + const Offset(0, -260)), isFalse);
  });
}
