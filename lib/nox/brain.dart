import 'dart:math' as math;
import 'dart:ui';

import 'desktop.dart';
import 'pose.dart';

/// How lively Nox is. Set from the tray menu.
enum NoxMode { sage, espiegle }

enum NoxState { perched, flying, falling, dragged }

/// Where Nox wants to sit: on a window's title bar, or on the taskbar edge.
class Perch {
  const Perch.window(this.handle, this.offsetX);
  const Perch.floor(this.offsetX) : handle = null;

  /// Window handle, or null for the "floor" (top of the taskbar).
  final int? handle;

  /// For a window: distance from its left edge. For the floor: absolute x.
  final double offsetX;

  bool get isFloor => handle == null;
}

/// Geometry of Nox in logical pixels, relative to his feet.
class NoxGeometry {
  static const bodyCenter = Offset(0, -51);
  static const bodyRadiusX = 46.0;
  static const bodyRadiusY = 52.0;
  static const headCenter = Offset(0, -70);
  static const height = 120.0;

  /// Area kept free on the right of a title bar (minimize/maximize/close).
  static const captionButtons = 150.0;
}

/// Nox's behaviour: where he is, what he does, how he looks.
///
/// Pure Dart: everything it knows about the desktop comes from [Desktop],
/// so it can be tested without Windows.
class NoxBrain {
  NoxBrain({math.Random? random, this.mode = NoxMode.sage})
      : _rng = random ?? math.Random();

  final math.Random _rng;
  NoxMode mode;

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

  /// Whether [point] (physical) is on Nox's body.
  bool hitTest(Offset point) {
    if (hidden) return false;
    final c = pos + NoxGeometry.bodyCenter * _px;
    final dx = (point.dx - c.dx) / (NoxGeometry.bodyRadiusX * _px);
    final dy = (point.dy - c.dy) / (NoxGeometry.bodyRadiusY * _px);
    return dx * dx + dy * dy <= 1;
  }

  /// Called when the user presses the mouse on Nox.
  void startDrag(Offset cursor) {
    _grabOffset = pos - cursor;
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
    }

    _updatePetting(dt, cursor);
    _updateLook(dt, cursor);
    _updatePose(dt);
    _lastCursor = cursor;
  }

  // ---------------------------------------------------------------- states

  void _setState(NoxState s) {
    state = s;
    _stateTime = 0;
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
    } else if (state == NoxState.perched && idle > _sleepAfterMs) {
      sleeping = true;
    }
  }

  int get _sleepAfterMs => mode == NoxMode.sage ? 120000 : 240000;

  void _updatePerched(double dt, Desktop d) {
    final p = perch;
    if (p == null) {
      _fall();
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
        _takeOff(d);
        return;
      }
      pos = next;

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
      final roll = _rng.nextDouble();
      if (roll < 0.5) {
        _takeOff(d);
      } else if (roll < 0.8 && !p.isFloor) {
        _hopAlong(d);
      }
      // else: stays put, just looks around.
    }
  }

  double _decisionInterval() => mode == NoxMode.sage
      ? 45 + _rng.nextDouble() * 75
      : 8 + _rng.nextDouble() * 17;

  void _hopAlong(Desktop d) {
    final p = perch;
    if (p == null || p.isFloor) return;
    final r = d.windowRect(p.handle!);
    if (r == null) return;
    final maxX = math.max(40 * _px, r.width - NoxGeometry.captionButtons * _px);
    final x = 40 * _px + _rng.nextDouble() * (maxX - 40 * _px);
    target = Perch.window(p.handle!, x);
    vel = Offset(0, -200 * _px);
    _setState(NoxState.flying);
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
    if (p.isFloor) {
      final work = d.workArea(Offset(p.offsetX, pos.dy));
      return Offset(p.offsetX, work.bottom);
    }
    final r = d.windowRect(p.handle!);
    if (r == null || !d.isPerchable(p.handle!)) return null;
    return Offset(r.left + p.offsetX, r.top);
  }

  void _updateFlying(double dt, Desktop d) {
    var t = target;
    var goal = t == null ? null : _targetPoint(d, t);
    if (t == null || goal == null) {
      t = target = _chooseTarget(d);
      goal = _targetPoint(d, t) ?? pos;
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
      if (!t.isFloor &&
          !d.isTopAt(t.handle!, Offset(goal.dx, goal.dy + 14 * _px))) {
        target = _chooseTarget(d);
        return;
      }
      pos = goal;
      vel = Offset.zero;
      perch = t;
      target = null;
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

    _flapPhase += dt * (flying ? 22 : (falling ? 30 : 0));

    pose
      ..hidden = hidden
      ..time = _t
      ..sleeping = sleeping
      ..happy = _t < _happyUntil
      ..surprised = falling || dragged
      ..eyeOpen = sleeping ? 0 : (_t < _blinkUntil ? 0.05 : 1)
      ..look = (sleeping || falling) ? Offset.zero : _look
      ..headTurn = sleeping ? 0 : _headTurn
      ..wingSpread = flying ? 0.9 : (falling ? 1.0 : (dragged ? 0.35 : 0))
      ..wingFlap = (flying || falling) ? math.sin(_flapPhase) * 0.55 : 0
      ..feetTucked = flying
      ..tilt = flying
          ? (vel.dx / (900 * _px)).clamp(-0.35, 0.35)
          : (dragged ? math.sin(_t * 6) * 0.12 : 0);
  }
}
