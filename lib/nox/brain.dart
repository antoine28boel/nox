import 'dart:math' as math;
import 'dart:ui';

import 'desktop.dart';
import 'pose.dart';

/// How lively Nox is. Set from the tray menu.
enum NoxMode { sage, espiegle }

enum NoxState { perched, flying, falling, dragged, docked }

/// Mischief Nox gets up to in espiègle mode. Each can be turned off.
enum NoxPrank {
  /// Swoops on the mouse cursor.
  chase,

  /// Leaves a feather behind when he takes off.
  feather,

  /// Lands next to a desktop icon and pecks at it.
  peck,

  /// Shoves the window he is perched on a little.
  push,
}

/// Where Nox wants to sit: on a window's title bar, or on the taskbar edge.
class Perch {
  const Perch.window(this.handle, this.offsetX) : spot = null;
  const Perch.floor(this.offsetX)
      : handle = null,
        spot = null;
  const Perch.spot(Offset at)
      : handle = null,
        offsetX = 0,
        spot = at;

  /// Window handle, or null for the "floor" (top of the taskbar) or a spot.
  final int? handle;

  /// A fixed point on the desktop (next to an icon), in physical pixels.
  final Offset? spot;

  /// For a window: distance from its left edge. For the floor: absolute x.
  final double offsetX;

  bool get isFloor => handle == null && spot == null;
}

/// Geometry of Nox in logical pixels, relative to his feet.
class NoxGeometry {
  static const bodyCenter = Offset(0, -51);
  static const bodyRadiusX = 46.0;
  static const bodyRadiusY = 52.0;
  static const headCenter = Offset(0, -70);
  static const height = 120.0;

  /// Nox's window (logical px) and where his feet sit inside it.
  static const windowSize = Size(200, 180);
  static const windowFeet = Offset(100, 170);

  /// Area kept free on the right of a title bar (minimize/maximize/close).
  static const captionButtons = 150.0;
}

/// Nox's behaviour: where he is, what he does, how he looks.
///
/// Pure Dart: everything it knows about the desktop comes from [Desktop],
/// so it can be tested without Windows.
class NoxBrain {
  NoxBrain({math.Random? random, this.mode = NoxMode.sage, Set<NoxPrank>? pranks})
      : _rng = random ?? math.Random(),
        pranks = pranks ?? NoxPrank.values.toSet();

  final math.Random _rng;
  NoxMode mode;

  /// Pranks Nox is allowed to play (only in espiègle mode).
  final Set<NoxPrank> pranks;

  /// Nox holds an envelope: he has news waiting for your answer.
  bool carrying = false;

  /// True while Nox swoops on the cursor.
  bool hunting = false;

  /// How many times Nox caught the cursor / pecked at an icon.
  int catches = 0;
  int pecks = 0;

  /// The feather Nox left behind (physical pixels), or null.
  Offset? featherPos;
  double featherOpacity = 0;
  double _featherAge = 0;

  // Where Nox was when the mouse went down on him: a plain click (no drag)
  // puts him back there instead of making him fall.
  Perch? _clickPerch;
  Offset _clickPos = Offset.zero;

  double _peckUntil = 0;
  double _pushLeft = 0;
  double _pushDir = 1;
  double _pushCarry = 0;

  bool get _pecking => state == NoxState.perched && perch?.spot != null;
  bool get _pushing => state == NoxState.perched && _pushLeft > 0;

  NoxState state = NoxState.falling;

  /// Position of Nox's feet, in physical pixels.
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;

  /// Physical pixels per logical pixel (1.0 at 100 % Windows scaling).
  double scale = 1;

  Perch? perch;
  Perch? target;

  bool hidden = false;
  bool sleeping = false;

  /// Work mode: Nox stays in the island at the top of the screen.
  bool workMode = false;

  double _t = 0;
  double _stateTime = 0;
  double _nextDecision = 5;
  double _nextBlink = 3;
  double _blinkUntil = 0;
  double _happyUntil = 0;
  double _coveredFor = 0;
  double _flapPhase = 0;
  double _recoverAt = 0.35;
  int? _lastForeground;
  double? _followAt;
  Offset _grabOffset = Offset.zero;
  Offset _lastCursor = Offset.zero;
  double _petAmount = 0;
  Offset _look = Offset.zero;
  double _headTurn = 0;
  double _island = 0;
  double _expand = 0;
  bool _hover = false;
  double _retract = 0;
  bool _summoned = false;
  double _lineHover = 0;
  Offset? _nestPress;
  bool _nestDragging = false;
  bool _nestMoved = false;
  bool _callRequested = false;

  /// Where the nest sits: fraction of the screen width, and which edge.
  double nestX = 0.5;
  bool nestBottom = false;

  final NoxPose pose = NoxPose();

  double get _px => scale;

  /// Places Nox somewhere sensible at startup.
  void spawn(Desktop d, Offset at) {
    final work = d.workArea(at);
    pos = Offset(work.center.dx, work.top + 80 * _px);
    vel = Offset.zero;
    _setState(NoxState.falling);
    _recoverAt = 0.25;
  }

  /// Whether [point] (physical) is on Nox's body (or on his island).
  bool hitTest(Offset point) {
    // While he hunts the cursor, clicks must still reach what is under him.
    if (hidden || hunting) return false;
    if (state == NoxState.docked) {
      if (_nestPress != null) return true;
      if (_retract > 0.5) return false;
      return islandRect().inflate(4 * _px).contains(point);
    }
    final c = pos + NoxGeometry.bodyCenter * _px;
    final dx = (point.dx - c.dx) / (NoxGeometry.bodyRadiusX * _px);
    final dy = (point.dy - c.dy) / (NoxGeometry.bodyRadiusY * _px);
    return dx * dx + dy * dy <= 1;
  }

  /// Island bounds on screen (physical px).
  Rect islandRect({double? retract}) {
    final box = islandBox(
      window: NoxGeometry.windowSize,
      centerX: NoxGeometry.windowFeet.dx,
      island: _island,
      expand: _expand,
      retract: retract ?? _retract,
      bottom: nestBottom,
    );
    final topLeft = pos - NoxGeometry.windowFeet * _px;
    return Rect.fromLTWH(topLeft.dx + box.left * _px, topLeft.dy + box.top * _px,
        box.width * _px, box.height * _px);
  }

  /// Where Nox's feet are when he sits in his nest: window glued to the top
  /// of the screen, or to the top of the taskbar, at [nestX].
  Offset dockPoint(Desktop d, {Offset? at}) {
    final m = d.monitorBounds(at ?? pos);
    final half = NoxGeometry.windowSize.width / 2 * _px;
    final x = (m.left + nestX * m.width)
        .clamp(m.left + half, math.max(m.left + half, m.right - half))
        .toDouble();
    if (nestBottom) {
      final work = d.workArea(at ?? pos);
      final below = NoxGeometry.windowSize.height - NoxGeometry.windowFeet.dy;
      return Offset(x, work.bottom - below * _px);
    }
    return Offset(x, m.top + NoxGeometry.windowFeet.dy * _px);
  }

  /// True once after a click on the island called Nox (opens the assistant).
  bool takeCall() {
    final c = _callRequested;
    _callRequested = false;
    return c;
  }

  /// True once after the island was dragged to a new place (to save it).
  bool takeNestMoved() {
    final m = _nestMoved;
    _nestMoved = false;
    return m;
  }

  /// In the nest: click (call Nox) or drag (move the nest), pull the island
  /// back when the cursor comes near, bring it out on a short hover.
  void _updateNest(double dt, Desktop d, Offset cursor) {
    final press = _nestPress;
    if (press != null) {
      if (d.leftButtonDown()) {
        if (!_nestDragging && (cursor - press).distance > 6 * _px) _nestDragging = true;
        if (_nestDragging) {
          final m = d.monitorBounds(cursor);
          nestX = ((cursor.dx - m.left) / m.width).clamp(0.0, 1.0);
          nestBottom = cursor.dy > m.center.dy;
          pos = dockPoint(d, at: cursor);
          return;
        }
      } else {
        _nestPress = null;
        if (_nestDragging) {
          _nestDragging = false;
          _nestMoved = true;
        } else {
          _callRequested = true;
        }
      }
    }
    pos = dockPoint(d);

    final near = workMode &&
        _island >= 1 &&
        islandRect(retract: 0).inflate(30 * _px).contains(cursor);
    if (!near) {
      _summoned = false;
      _lineHover = 0;
    } else if (_retract > 0.9) {
      if (islandRect().inflate(8 * _px).contains(cursor)) {
        _lineHover += dt;
        if (_lineHover > 0.5) _summoned = true;
      } else {
        _lineHover = 0;
      }
    }
    final pull = near && !_summoned && !listening && _nestPress == null;
    _retract = (_retract + (pull ? dt : -dt) * 6).clamp(0.0, 1.0);
    // Opened (eyes and beak) only while the cursor is on the island.
    _hover = workMode &&
        _island >= 1 &&
        _retract < 0.1 &&
        islandRect().inflate(4 * _px).contains(cursor);

    if (!workMode && _island <= 0) {
      vel = Offset(0, 300 * _px);
      _recoverAt = 0.3;
      _setState(NoxState.falling);
    }
  }

  /// Turns work mode on or off (tray menu).
  void setWorkMode(bool on, Desktop d) {
    workMode = on;
    sleeping = false;
    hunting = false;
    _hover = false;
    if (on && state == NoxState.perched) {
      _takeOff(d);
    }
    // Leaving the nest: Nox first drops out of the island (see docked
    // update), then falls and flies away.
  }

  /// Mouse pressed on Nox: in the island it calls him, elsewhere it grabs him.
  void press(Offset cursor) {
    if (state == NoxState.docked) {
      // Decided on release: a click calls Nox, a drag moves the nest.
      sleeping = false;
      _nestPress = cursor;
      _nestDragging = false;
      return;
    }
    startDrag(cursor);
  }

  /// Whether Nox is opened in the island (the cursor is on it).
  bool get listening => state == NoxState.docked && _hover;

  /// Called when the user presses the mouse on Nox.
  void startDrag(Offset cursor) {
    _grabOffset = pos - cursor;
    _clickPerch = state == NoxState.perched ? perch : null;
    _clickPos = pos;
    vel = Offset.zero;
    sleeping = false;
    perch = null;
    _setState(NoxState.dragged);
  }

  /// Brings Nox back near [at] (tray menu "Rappeler Nox").
  void recall(Desktop d, Offset at) {
    sleeping = false;
    final work = d.workArea(at);
    pos = Offset(at.dx.clamp(work.left + 60 * _px, work.right - 60 * _px),
        work.top + 60 * _px);
    vel = Offset.zero;
    perch = null;
    _setState(NoxState.falling);
    _recoverAt = 0.2;
  }

  void update(double dt, Desktop d) {
    dt = dt.clamp(0.0, 0.1);
    _t += dt;
    _stateTime += dt;

    final cursor = d.cursor();
    hidden = state != NoxState.dragged && d.foregroundIsFullscreen();

    _trackForeground(d);
    _updateSleep(d);

    switch (state) {
      case NoxState.perched:
        _updatePerched(dt, d);
      case NoxState.flying:
        _updateFlying(dt, d);
      case NoxState.falling:
        _updateFalling(dt, d);
      case NoxState.dragged:
        _updateDragged(dt, d, cursor);
      case NoxState.docked:
        _updateNest(dt, d, cursor);
    }

    _updateFeather(dt, d);
    _updatePetting(dt, cursor);
    _updateLook(dt, cursor);
    _updatePose(dt);
    _lastCursor = cursor;
  }

  // ---------------------------------------------------------------- states

  void _setState(NoxState s) {
    state = s;
    _stateTime = 0;
    hunting = false;
    if (s != NoxState.perched) _pushLeft = 0;
  }

  void _trackForeground(Desktop d) {
    final fg = d.foregroundWindow();
    if (fg != _lastForeground) {
      _lastForeground = fg;
      _followAt = _t + 0.8;
    }
  }

  void _updateSleep(Desktop d) {
    final idle = d.idleMillis();
    if (sleeping) {
      if (idle < 1000) {
        sleeping = false;
        _nextDecision = _t + 2;
      }
    } else if ((state == NoxState.perched || state == NoxState.docked) &&
        !listening &&
        idle > _sleepAfterMs) {
      sleeping = true;
    }
  }

  int get _sleepAfterMs => mode == NoxMode.sage ? 120000 : 240000;

  void _updatePerched(double dt, Desktop d) {
    if (workMode) {
      _takeOff(d);
      return;
    }
    final p = perch;
    if (p == null) {
      _fall();
      return;
    }

    final spot = p.spot;
    if (spot != null) {
      // Pecking at an icon, then off again.
      pos = spot;
      if (_t >= _peckUntil) _takeOff(d);
      return;
    }

    if (p.isFloor) {
      final work = d.workArea(pos);
      pos = Offset(p.offsetX.clamp(work.left + 40 * _px, work.right - 40 * _px),
          work.bottom);
    } else {
      final handle = p.handle!;
      final r = d.windowRect(handle);
      if (r == null || !d.isPerchable(handle)) {
        _fall();
        return;
      }
      final offsetX = p.offsetX.clamp(30 * _px, math.max(30 * _px, r.width - 30 * _px));
      final next = Offset(r.left + offsetX, r.top);
      final moved = next - pos;
      final speed = moved.distance / math.max(dt, 1 / 240);
      if (speed > 3000 * _px && moved.distance > 25 * _px) {
        // The window was shaken: take off.
        pos = next;
        vel = Offset(-moved.dx.sign * 250 * _px, -350 * _px);
        _maybeFeather(1);
        _takeOff(d);
        return;
      }
      pos = next;

      if (_pushLeft > 0 && !sleeping) {
        final step = math.min(_pushLeft, 60 * _px * dt);
        _pushLeft -= step;
        _pushCarry += step * _pushDir;
        final whole = _pushCarry.truncate();
        if (whole != 0) {
          _pushCarry -= whole;
          d.nudgeWindow(handle, whole);
        }
      }

      // Another window now covers the title bar where Nox sits.
      final below = Offset(pos.dx, pos.dy + 14 * _px);
      if (!d.isTopAt(handle, below)) {
        _coveredFor += dt;
        if (_coveredFor > 0.4) {
          _coveredFor = 0;
          _takeOff(d);
          return;
        }
      } else {
        _coveredFor = 0;
      }
    }

    if (sleeping) return;

    // Espiègle: follows the window you switch to.
    final followAt = _followAt;
    if (followAt != null && _t >= followAt) {
      _followAt = null;
      final fg = _lastForeground;
      if (mode == NoxMode.espiegle &&
          fg != null &&
          fg != p.handle &&
          d.isPerchable(fg) &&
          _rng.nextDouble() < 0.7) {
        _takeOff(d);
        return;
      }
    }

    if (_t >= _nextDecision) {
      _nextDecision = _t + _decisionInterval();
      if (mode == NoxMode.espiegle &&
          pranks.isNotEmpty &&
          _rng.nextDouble() < 0.4 &&
          _startPrank(d)) {
        return;
      }
      final roll = _rng.nextDouble();
      if (roll < 0.5) {
        _maybeFeather(0.3);
        _takeOff(d);
      } else if (roll < 0.8 && p.handle != null) {
        _hopAlong(d);
      }
      // else: stays put, just looks around.
    }
  }

  double _decisionInterval() => mode == NoxMode.sage
      ? 45 + _rng.nextDouble() * 75
      : 8 + _rng.nextDouble() * 17;

  void _hopAlong(Desktop d) {
    final handle = perch?.handle;
    if (handle == null) return;
    final r = d.windowRect(handle);
    if (r == null) return;
    final maxX = math.max(40 * _px, r.width - NoxGeometry.captionButtons * _px);
    final x = 40 * _px + _rng.nextDouble() * (maxX - 40 * _px);
    target = Perch.window(handle, x);
    vel = Offset(0, -200 * _px);
    _setState(NoxState.flying);
  }

  // ---------------------------------------------------------------- pranks

  bool _startPrank(Desktop d) {
    final options = <NoxPrank>[
      if (pranks.contains(NoxPrank.chase) && d.idleMillis() < 3000) NoxPrank.chase,
      if (pranks.contains(NoxPrank.push) && perch?.handle != null) NoxPrank.push,
      if (pranks.contains(NoxPrank.peck)) NoxPrank.peck,
    ];
    if (options.isEmpty) return false;
    switch (options[_rng.nextInt(options.length)]) {
      case NoxPrank.chase:
        perch = null;
        target = null;
        vel = Offset(0, -250 * _px);
        _setState(NoxState.flying);
        hunting = true;
        return true;
      case NoxPrank.push:
        return _startPush(d);
      case NoxPrank.peck:
        return _startPeck(d);
      case NoxPrank.feather:
        return false;
    }
  }

  bool _startPush(Desktop d) {
    final handle = perch?.handle;
    if (handle == null) return false;
    final r = d.windowRect(handle);
    if (r == null) return false;
    final work = d.workArea(pos);
    final dir = _rng.nextBool() ? 1.0 : -1.0;
    final dist = 24 * _px;
    if (r.left + dir * dist < work.left || r.right + dir * dist > work.right) return false;
    _pushDir = dir;
    _pushLeft = dist;
    _pushCarry = 0;
    return true;
  }

  bool _startPeck(Desktop d) {
    final icons = d.desktopIcons();
    if (icons.isEmpty) return false;
    final icon = icons[_rng.nextInt(icons.length)];
    // Stands just to the right of the icon and leans over it.
    target = Perch.spot(icon + Offset(48 * _px, 44 * _px));
    perch = null;
    vel = Offset(0, -250 * _px);
    _setState(NoxState.flying);
    return true;
  }

  void _updateHunting(double dt, Desktop d) {
    final goal = d.cursor() - NoxGeometry.bodyCenter * _px;
    final dir = goal - pos;
    final dist = dir.distance;
    final speed = math.min(950 * _px, dist * 4 + 80 * _px);
    final desired = dist < 0.001 ? Offset.zero : dir / dist * speed;
    vel = vel + (desired - vel) * (1 - math.exp(-dt * 6));
    pos += vel * dt;

    final caught = dist < 18 * _px;
    if (caught || _stateTime > 5) {
      hunting = false;
      if (caught) {
        catches++;
        _happyUntil = _t + 1.5;
      }
      vel = Offset(vel.dx * 0.3, -300 * _px);
      target = _chooseTarget(d);
      _stateTime = 0;
    }
  }

  void _maybeFeather(double chance) {
    if (mode != NoxMode.espiegle || !pranks.contains(NoxPrank.feather)) return;
    if (featherPos != null || _rng.nextDouble() >= chance) return;
    featherPos = pos - Offset(0, 40 * _px);
    featherOpacity = 1;
    _featherAge = 0;
  }

  /// The feather drifts down to the taskbar, lies there, then fades away.
  void _updateFeather(double dt, Desktop d) {
    final f = featherPos;
    if (f == null) return;
    _featherAge += dt;
    const life = 25.0;
    if (_featherAge >= life) {
      featherPos = null;
      featherOpacity = 0;
      return;
    }
    final floor = d.workArea(f).bottom - 6 * _px;
    if (f.dy < floor) {
      featherPos = Offset(f.dx + math.cos(_featherAge * 3) * 40 * _px * dt,
          math.min(floor, f.dy + 70 * _px * dt));
    }
    featherOpacity = ((life - _featherAge) / 2).clamp(0.0, 1.0);
  }

  void _takeOff(Desktop d) {
    target = _chooseTarget(d);
    perch = null;
    if (vel.dy > -150 * _px) vel = Offset(vel.dx, -250 * _px);
    _setState(NoxState.flying);
  }

  void _fall() {
    perch = null;
    _recoverAt = 0.35;
    _setState(NoxState.falling);
  }

  Perch _chooseTarget(Desktop d) {
    final fg = d.foregroundWindow();
    if (fg != null && d.isPerchable(fg)) {
      final r = d.windowRect(fg);
      if (r != null && r.width > 220 * _px) {
        final work = d.workArea(r.topCenter);
        final roomAbove = r.top - work.top;
        if (roomAbove > NoxGeometry.height * _px) {
          final minX = 40 * _px;
          final maxX = math.max(minX, r.width - NoxGeometry.captionButtons * _px);
          for (var i = 0; i < 4; i++) {
            final x = minX + _rng.nextDouble() * (maxX - minX);
            if (d.isTopAt(fg, Offset(r.left + x, r.top + 14 * _px))) {
              return Perch.window(fg, x);
            }
          }
        }
      }
    }
    final work = d.workArea(pos);
    final x = (pos.dx + (_rng.nextDouble() * 2 - 1) * 400 * _px)
        .clamp(work.left + 60 * _px, work.right - 60 * _px);
    return Perch.floor(x);
  }

  Offset? _targetPoint(Desktop d, Perch p) {
    final spot = p.spot;
    if (spot != null) return spot;
    if (p.isFloor) {
      final work = d.workArea(Offset(p.offsetX, pos.dy));
      return Offset(p.offsetX, work.bottom);
    }
    final r = d.windowRect(p.handle!);
    if (r == null || !d.isPerchable(p.handle!)) return null;
    return Offset(r.left + p.offsetX, r.top);
  }

  void _updateFlying(double dt, Desktop d) {
    if (hunting) {
      _updateHunting(dt, d);
      return;
    }
    Perch? t;
    Offset? goal;
    if (workMode) {
      goal = dockPoint(d);
    } else {
      t = target;
      goal = t == null ? null : _targetPoint(d, t);
      if (t == null || goal == null) {
        t = target = _chooseTarget(d);
        goal = _targetPoint(d, t) ?? pos;
      }
    }

    final toGoal = goal - pos;
    final dist = toGoal.distance;

    // Arc: aim above the goal while far away.
    final lift = math.min(dist * 0.35, 140 * _px);
    final aim = goal - Offset(0, dist > 40 * _px ? lift : 0);
    final dir = aim - pos;
    final maxSpeed = (mode == NoxMode.sage ? 520 : 700) * _px;
    final speed = math.min(maxSpeed, dir.distance * 3.2 + 40 * _px);
    final desired = dir.distance < 0.001 ? Offset.zero : dir / dir.distance * speed;
    final k = 1 - math.exp(-dt * 5);
    vel = vel + (desired - vel) * k;
    pos += vel * dt;

    if (dist < 4 * _px || (dist < 12 * _px && vel.distance < 120 * _px)) {
      if (t == null) {
        pos = goal;
        vel = Offset.zero;
        perch = null;
        target = null;
        _setState(NoxState.docked);
        return;
      }
      final handle = t.handle;
      if (handle != null && !d.isTopAt(handle, Offset(goal.dx, goal.dy + 14 * _px))) {
        target = _chooseTarget(d);
        return;
      }
      pos = goal;
      vel = Offset.zero;
      perch = t;
      target = null;
      if (t.spot != null) {
        pecks++;
        _peckUntil = _t + 2.4;
      }
      _nextDecision = _t + _decisionInterval();
      _setState(NoxState.perched);
    } else if (_stateTime > 12) {
      // Never fly forever.
      target = _chooseTarget(d);
      _stateTime = 0;
    }
  }

  void _updateFalling(double dt, Desktop d) {
    vel = vel + Offset(0, 2200 * _px * dt);
    pos += vel * dt;

    final bounds = d.monitorBounds(pos);
    if (pos.dx < bounds.left + 30 * _px || pos.dx > bounds.right - 30 * _px) {
      pos = Offset(pos.dx.clamp(bounds.left + 30 * _px, bounds.right - 30 * _px), pos.dy);
      vel = Offset(-vel.dx * 0.5, vel.dy);
    }
    if (pos.dy < bounds.top + NoxGeometry.height * _px) {
      pos = Offset(pos.dx, bounds.top + NoxGeometry.height * _px);
      vel = Offset(vel.dx, vel.dy.abs() * 0.4);
    }

    final work = d.workArea(pos);
    if (pos.dy >= work.bottom) {
      pos = Offset(pos.dx, work.bottom);
      vel = Offset.zero;
      perch = Perch.floor(pos.dx);
      _nextDecision = _t + 3 + _rng.nextDouble() * 4;
      _setState(NoxState.perched);
      return;
    }
    if (_stateTime > _recoverAt) _takeOff(d);
  }

  void _updateDragged(double dt, Desktop d, Offset cursor) {
    final next = cursor + _grabOffset;
    if (dt > 0) {
      final instant = (next - pos) / dt;
      vel = vel + (instant - vel) * 0.35;
    }
    pos = next;
    if (!d.leftButtonDown()) {
      final from = _clickPerch;
      if (from != null &&
          from.spot == null &&
          _stateTime < 0.4 &&
          (pos - _clickPos).distance < 6 * _px) {
        pos = _clickPos;
        vel = Offset.zero;
        perch = from;
        _setState(NoxState.perched);
        return;
      }
      final max = 2500 * _px;
      if (vel.distance > max) vel = vel / vel.distance * max;
      _recoverAt = 0.6;
      _setState(NoxState.falling);
    }
  }

  // ------------------------------------------------------------ expression

  void _updatePetting(double dt, Offset cursor) {
    final moved = (cursor - _lastCursor).distance;
    final onHead = state == NoxState.perched &&
        !hidden &&
        (cursor - (pos + NoxGeometry.headCenter * _px)).distance < 45 * _px;
    if (onHead && moved > 0) {
      _petAmount += moved / _px;
    } else {
      _petAmount = math.max(0, _petAmount - 200 * dt);
    }
    if (_petAmount > 120) {
      _happyUntil = _t + 1.5;
      sleeping = false;
    }
  }

  void _updateLook(double dt, Offset cursor) {
    Offset look;
    double turn;
    if (state == NoxState.flying && vel.distance > 30 * _px) {
      look = vel / vel.distance * 0.6;
      turn = (vel.dx / (400 * _px)).clamp(-1.0, 1.0);
    } else {
      final eye = pos + NoxGeometry.headCenter * _px;
      final v = cursor - eye;
      final dist = v.distance;
      final strength = math.min(1.0, dist / (220 * _px));
      look = dist < 0.001 ? Offset.zero : v / dist * strength;
      turn = (v.dx / (500 * _px)).clamp(-1.0, 1.0);
    }
    final k = 1 - math.exp(-dt * 10);
    _look = _look + (look - _look) * k;
    _headTurn += (turn - _headTurn) * (1 - math.exp(-dt * 4));
  }

  void _updatePose(double dt) {
    if (_t >= _nextBlink) {
      _blinkUntil = _t + 0.13;
      _nextBlink = _t + 2.5 + _rng.nextDouble() * 4;
    }

    final flying = state == NoxState.flying;
    final falling = state == NoxState.falling;
    final dragged = state == NoxState.dragged;
    final docked = state == NoxState.docked;
    // Into the nest in 0.9 s, out of it in 0.7 s.
    _island = (_island + (docked && workMode ? dt / 0.9 : -dt / 0.7)).clamp(0.0, 1.0);
    final leavingNest = docked && !workMode;
    _expand = (_expand + (listening ? dt : -dt) * 6).clamp(0.0, 1.0);

    _flapPhase += dt * (flying || leavingNest ? 22 : (falling ? 30 : 0));

    pose
      ..hidden = hidden
      ..time = _t
      ..sleeping = sleeping
      ..island = _island
      ..expand = _expand
      ..retract = _retract
      ..nestBottom = nestBottom
      ..happy = _t < _happyUntil
      ..carrying = carrying
      ..surprised = falling || dragged
      ..eyeOpen = sleeping ? 0 : (_t < _blinkUntil ? 0.05 : 1)
      ..look = (sleeping || falling)
          ? Offset.zero
          : (_pecking ? const Offset(-0.8, 0.7) : _look)
      ..headTurn = sleeping ? 0 : _headTurn
      ..wingSpread = flying || leavingNest ? 0.9 : (falling ? 1.0 : (dragged ? 0.35 : 0))
      ..wingFlap = (flying || falling || leavingNest) ? math.sin(_flapPhase) * 0.55 : 0
      ..feetTucked = flying
      ..tilt = flying
          ? (vel.dx / (900 * _px)).clamp(-0.35, 0.35)
          : dragged
              ? math.sin(_t * 6) * 0.12
              : _pecking
                  ? -0.5 * math.max(0.0, math.sin(_stateTime * 11))
                  : (_pushing ? _pushDir * 0.2 : 0.0);
  }
}
