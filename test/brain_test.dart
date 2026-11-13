import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox/nox/brain.dart';
import 'package:nox/nox/desktop.dart';
import 'package:nox/nox/feather.dart';

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

  final icons = <Offset>[];
  int nudges = 0;

  @override
  void nudgeWindow(int handle, int dx) {
    nudges++;
    windows[handle] = windows[handle]!.shift(Offset(dx.toDouble(), 0));
  }

  @override
  List<Offset> desktopIcons() => icons;
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

  test('a plain click leaves him on his perch', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    final before = b.pos;
    d.cursorPos = b.pos + const Offset(0, -50);
    b.startDrag(d.cursorPos);
    d.button = true;
    run(b, d, 0.1);
    expect(b.state, NoxState.dragged);
    d.button = false;
    b.update(1 / 60, d);
    expect(b.state, NoxState.perched);
    expect(b.perch?.handle, 1);
    expect(b.pos, before);
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
    b.pranks.clear();
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

  group('pranks', () {
    NoxBrain prankster(NoxPrank prank) =>
        NoxBrain(random: math.Random(1), mode: NoxMode.espiegle, pranks: {prank});

    test('chases and catches the cursor', () {
      b = prankster(NoxPrank.chase);
      b.spawn(d, const Offset(800, 500));
      run(b, d, 600);
      expect(b.catches, greaterThan(0));
      expect(b.pecks, 0);
      expect(d.nudges, 0);
      expect(b.featherPos, isNull);
    });

    test('lets clicks through while hunting', () {
      b = prankster(NoxPrank.chase);
      b.spawn(d, const Offset(800, 500));
      var hunted = false;
      for (var i = 0; i < 600 * 60 && !hunted; i++) {
        b.update(1 / 60, d);
        hunted = b.hunting;
      }
      expect(hunted, isTrue);
      expect(b.state, NoxState.flying);
      expect(b.hitTest(b.pos + const Offset(0, -50)), isFalse);
    });

    test('pushes the window he is perched on, a little', () {
      b = prankster(NoxPrank.push);
      b.spawn(d, const Offset(800, 500));
      final before = d.windows[1]!;
      run(b, d, 600);
      expect(d.nudges, greaterThan(0));
      expect(d.windows[1]!.top, before.top);
      expect(d.windows[1]!.size, before.size);
      expect(b.catches, 0);
    });

    test('pecks at a desktop icon then leaves', () {
      b = prankster(NoxPrank.peck);
      d.icons.add(const Offset(100, 100));
      b.spawn(d, const Offset(800, 500));
      var pecking = false;
      for (var i = 0; i < 600 * 60 && !pecking; i++) {
        b.update(1 / 60, d);
        pecking = b.perch?.spot != null;
      }
      expect(pecking, isTrue);
      expect(b.pecks, 1);
      expect(b.pos, const Offset(148, 144));
      run(b, d, 4);
      expect(b.perch?.spot, isNull);
    });

    test('does not peck when no icon is visible', () {
      b = prankster(NoxPrank.peck);
      b.spawn(d, const Offset(800, 500));
      run(b, d, 300);
      expect(b.pecks, 0);
    });

    test('drops a feather when shaken off, and it fades away', () {
      b = prankster(NoxPrank.feather);
      b.spawn(d, const Offset(800, 500));
      run(b, d, 6);
      expect(b.perch?.handle, 1);
      d.windows[1] = d.windows[1]!.shift(const Offset(200, 0));
      b.update(1 / 60, d);
      expect(b.featherPos, isNotNull);
      expect(b.featherOpacity, 1);
      run(b, d, 14);
      expect(b.featherPos!.dy, FakeDesktop.work.bottom - 6);
      for (var i = 0; i < 15 * 60 && b.featherPos != null; i++) {
        b.update(1 / 60, d);
      }
      expect(b.featherPos, isNull);
    });

    test('plays no prank in sage mode or when all are turned off', () {
      d.icons.add(const Offset(100, 100));
      b.spawn(d, const Offset(800, 500));
      run(b, d, 300);
      final off = NoxBrain(random: math.Random(2), mode: NoxMode.espiegle, pranks: {});
      off.spawn(d, const Offset(800, 500));
      run(off, d, 300);
      for (final brain in [b, off]) {
        expect(brain.catches, 0);
        expect(brain.pecks, 0);
        expect(brain.featherPos, isNull);
      }
      expect(d.nudges, 0);
    });

    test('feather image is premultiplied BGRA of the right size', () {
      final f = renderFeather(1.5);
      expect(f.width, 66);
      expect(f.height, 30);
      expect(f.bgra.length, 66 * 30 * 4);
      var opaque = 0;
      for (var i = 0; i < f.bgra.length; i += 4) {
        final a = f.bgra[i + 3];
        expect(f.bgra[i], lessThanOrEqualTo(a));
        expect(f.bgra[i + 1], lessThanOrEqualTo(a));
        expect(f.bgra[i + 2], lessThanOrEqualTo(a));
        if (a == 255) opaque++;
      }
      expect(opaque, greaterThan(100));
      expect(f.bgra[3], 0); // corners are transparent
    });
  });

  test('scales with Windows display scaling', () {
    b.scale = 2;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 8);
    expect(b.state, NoxState.perched);
    expect(b.hitTest(b.pos + const Offset(0, -100)), isTrue);
    expect(b.hitTest(b.pos + const Offset(0, -260)), isFalse);
  });

  test('work mode: flies into the island at the top center', () {
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    b.setWorkMode(true, d);
    run(b, d, 6);
    expect(b.state, NoxState.docked);
    expect(b.pos.dx, FakeDesktop.screen.center.dx);
    expect(b.pose.island, 1);
    final island = b.islandRect();
    expect(island.top, greaterThanOrEqualTo(0));
    expect(island.bottom, lessThan(60));
    expect(b.hitTest(island.center), isTrue);
    // Stays put when windows change.
    d.foreground = null;
    run(b, d, 30);
    expect(b.state, NoxState.docked);
  });

  test('work mode: a click calls Nox, a second one sends him back', () {
    b.workMode = true;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    expect(b.state, NoxState.docked);
    final small = b.islandRect();
    b.press(small.center);
    run(b, d, 0.5);
    expect(b.listening, isTrue);
    expect(b.islandRect().width, greaterThan(small.width));
    b.press(b.islandRect().center);
    run(b, d, 0.5);
    expect(b.listening, isFalse);
    expect(b.state, NoxState.docked);
  });

  test('leaving work mode sends Nox back to perching', () {
    b.workMode = true;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    b.setWorkMode(false, d);
    run(b, d, 8);
    expect(b.state, NoxState.perched);
    expect(b.pose.island, 0);
  });

  test('nest: dragging the island moves it, even to the bottom edge', () {
    b.workMode = true;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    expect(b.state, NoxState.docked);
    d.cursorPos = b.islandRect().center;
    b.press(d.cursorPos);
    d.button = true;
    for (var i = 0; i < 30; i++) {
      d.cursorPos += const Offset(25, 33);
      b.update(1 / 60, d);
    }
    d.button = false;
    b.update(1 / 60, d);
    expect(b.takeNestMoved(), isTrue);
    expect(b.takeCall(), isFalse);
    expect(b.nestBottom, isTrue);
    expect(b.nestX, closeTo(d.cursorPos.dx / 1920, 0.01));
    expect(b.islandRect().bottom, closeTo(FakeDesktop.work.bottom - 6, 1));
    expect(b.state, NoxState.docked);
  });

  test('nest: a click without moving calls Nox', () {
    b.workMode = true;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    d.cursorPos = b.islandRect().center;
    b.press(d.cursorPos);
    d.button = true;
    b.update(1 / 60, d);
    d.button = false;
    b.update(1 / 60, d);
    expect(b.takeCall(), isTrue);
    expect(b.listening, isTrue);
  });

  test('nest: pulls back when the cursor comes near, comes out on hover', () {
    b.workMode = true;
    b.spawn(d, const Offset(800, 500));
    run(b, d, 6);
    final full = b.islandRect();
    d.cursorPos = full.bottomCenter + const Offset(40, 15);
    run(b, d, 0.5);
    expect(b.pose.retract, 1);
    expect(b.hitTest(full.center), isFalse);
    // Hovering the thin line brings the island back.
    d.cursorPos = b.islandRect().center;
    run(b, d, 0.9);
    expect(b.pose.retract, 0);
    expect(b.hitTest(b.islandRect().center), isTrue);
    // Moving away and back pulls it back again.
    d.cursorPos = const Offset(1500, 900);
    run(b, d, 0.3);
    d.cursorPos = full.bottomCenter + const Offset(40, 15);
    run(b, d, 0.5);
    expect(b.pose.retract, 1);
  });
}
