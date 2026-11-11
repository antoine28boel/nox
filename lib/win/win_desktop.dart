import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../nox/desktop.dart';
import 'native.dart';

/// [Desktop] backed by the Win32 API.
class WinDesktop implements Desktop {
  WinDesktop(this.ownWindow);

  /// Nox's own window: never a perch, never counted as foreground app.
  final int ownWindow;

  final _point = calloc<POINT>();
  final _rect = calloc<RECT>();
  final _lastInput = calloc<LASTINPUTINFO>()..ref.cbSize = sizeOf<LASTINPUTINFO>();
  final _monitor = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
  final _cloaked = calloc<Uint32>();
  final _className = wsalloc(64);

  static const _shellClasses = {
    'Progman',
    'WorkerW',
    'Shell_TrayWnd',
    'Shell_SecondaryTrayWnd',
    'Windows.UI.Core.CoreWindow',
  };

  /// Finds the window created by `windows/runner/main.cpp`.
  static int findOwnWindow() {
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final title = 'Nox'.toNativeUtf16();
    try {
      return FindWindow(cls, title);
    } finally {
      calloc.free(cls);
      calloc.free(title);
    }
  }

  /// Physical pixels per logical pixel for Nox's window.
  double scale() {
    final dpi = GetDpiForWindow(ownWindow);
    return dpi == 0 ? 1 : dpi / 96;
  }

  /// Moves Nox's window without activating it or blocking the UI thread.
  void moveWindow(int x, int y) {
    SetWindowPos(ownWindow, HWND_TOPMOST, x, y, 0, 0,
        SWP_NOSIZE | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
  }

  /// Makes Nox's window a fully opaque layered window, once at startup.
  ///
  /// A layered window is not drawn at all until it has layered attributes, so
  /// the style stays on for good and [setClickThrough] only toggles
  /// `WS_EX_TRANSPARENT`.
  void makeLayered() {
    final ex = GetWindowLongPtr(ownWindow, GWL_EXSTYLE);
    SetWindowLongPtr(ownWindow, GWL_EXSTYLE, ex | WS_EX_LAYERED);
    SetLayeredWindowAttributes(ownWindow, 0, 255, _lwaAlpha);
  }

  static const _lwaAlpha = 0x2;

  /// Lets mouse clicks pass through Nox's window (true) or catches them.
  void setClickThrough(bool on) {
    final ex = GetWindowLongPtr(ownWindow, GWL_EXSTYLE);
    final want = on ? ex | WS_EX_TRANSPARENT : ex & ~WS_EX_TRANSPARENT;
    if (want != ex) SetWindowLongPtr(ownWindow, GWL_EXSTYLE, want);
  }

  /// Turns Nox's window into a normal, focusable window of [logical] size
  /// placed above [feet], for the "Aujourd'hui" panel.
  void enterPanel(Offset feet, Size logical) {
    final s = scale();
    final w = (logical.width * s).round();
    final h = (logical.height * s).round();
    final work = workArea(feet);
    final margin = 8 * s;
    final x = (feet.dx - w / 2)
        .clamp(work.left + margin, math.max(work.left + margin, work.right - w - margin));
    final y = (feet.dy - h)
        .clamp(work.top + margin, math.max(work.top + margin, work.bottom - h - margin));
    final ex = GetWindowLongPtr(ownWindow, GWL_EXSTYLE);
    SetWindowLongPtr(ownWindow, GWL_EXSTYLE, ex & ~(WS_EX_NOACTIVATE | WS_EX_TRANSPARENT));
    SetWindowPos(ownWindow, HWND_TOPMOST, x.round(), y.round(), w, h, SWP_SHOWWINDOW);
    SetForegroundWindow(ownWindow);
  }

  /// Back to the small window that never takes the focus.
  void leavePanel(Size logical) {
    final s = scale();
    final ex = GetWindowLongPtr(ownWindow, GWL_EXSTYLE);
    SetWindowLongPtr(ownWindow, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE);
    SetWindowPos(ownWindow, HWND_TOPMOST, 0, 0, (logical.width * s).round(),
        (logical.height * s).round(), SWP_NOMOVE | SWP_NOACTIVATE);
  }

  FeatherWindow? _feather;

  /// Prepares the feather Nox can leave behind ([bgra]: premultiplied BGRA).
  void setFeatherImage(Uint8List bgra, int width, int height) {
    _feather ??= FeatherWindow(bgra, width, height);
  }

  /// Shows the feather centered on [at] (physical pixels), or hides it.
  void showFeather(Offset? at, double opacity) {
    final feather = _feather;
    if (feather == null) return;
    if (at == null || opacity <= 0) {
      feather.hide();
    } else {
      feather.show(at.dx.round(), at.dy.round(), (opacity.clamp(0.0, 1.0) * 255).round());
    }
  }

  @override
  void nudgeWindow(int handle, int dx) {
    if (handle == ownWindow || IsWindow(handle) == 0 || IsZoomed(handle) != 0) return;
    if (GetWindowRect(handle, _rect) == 0) return;
    SetWindowPos(handle, 0, _rect.ref.left + dx, _rect.ref.top, 0, 0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
  }

  @override
  List<Offset> desktopIcons() {
    final visible = <Offset>[];
    final pt = calloc<POINT>();
    try {
      for (final icon in readDesktopIcons()) {
        pt.ref
          ..x = icon.dx.round()
          ..y = icon.dy.round();
        final hit = WindowFromPoint(pt.ref);
        if (hit == 0) continue;
        final root = GetAncestor(hit, GA_ROOT);
        // Only icons that no window covers.
        if (root == ownWindow || const {'Progman', 'WorkerW'}.contains(_classOf(root))) {
          visible.add(icon);
        }
      }
    } finally {
      calloc.free(pt);
    }
    return visible;
  }

  @override
  Offset cursor() {
    GetCursorPos(_point);
    return Offset(_point.ref.x.toDouble(), _point.ref.y.toDouble());
  }

  @override
  int idleMillis() {
    if (GetLastInputInfo(_lastInput) == 0) return 0;
    return (GetTickCount() - _lastInput.ref.dwTime) & 0xFFFFFFFF;
  }

  @override
  bool leftButtonDown() => (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;

  bool _monitorInfo(Offset at) {
    final pt = calloc<POINT>()
      ..ref.x = at.dx.round()
      ..ref.y = at.dy.round();
    try {
      final monitor = MonitorFromPoint(pt.ref, MONITOR_DEFAULTTONEAREST);
      return GetMonitorInfo(monitor, _monitor) != 0;
    } finally {
      calloc.free(pt);
    }
  }

  Rect _toRect(RECT r) => Rect.fromLTRB(
      r.left.toDouble(), r.top.toDouble(), r.right.toDouble(), r.bottom.toDouble());

  @override
  Rect workArea(Offset at) =>
      _monitorInfo(at) ? _toRect(_monitor.ref.rcWork) : const Rect.fromLTWH(0, 0, 1920, 1040);

  @override
  Rect monitorBounds(Offset at) =>
      _monitorInfo(at) ? _toRect(_monitor.ref.rcMonitor) : const Rect.fromLTWH(0, 0, 1920, 1080);

  @override
  int? foregroundWindow() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0 || hwnd == ownWindow) return null;
    return hwnd;
  }

  @override
  Rect? windowRect(int handle) {
    if (IsWindow(handle) == 0 || IsWindowVisible(handle) == 0 || IsIconic(handle) != 0) {
      return null;
    }
    final ok = DwmGetWindowAttribute(
            handle, DWMWA_EXTENDED_FRAME_BOUNDS, _rect, sizeOf<RECT>()) ==
        S_OK;
    if (!ok && GetWindowRect(handle, _rect) == 0) return null;
    return _toRect(_rect.ref);
  }

  String _classOf(int handle) {
    final n = GetClassName(handle, _className, 64);
    return n > 0 ? _className.toDartString(length: n) : '';
  }

  bool _isCloaked(int handle) {
    _cloaked.value = 0;
    DwmGetWindowAttribute(handle, DWMWA_CLOAKED, _cloaked, sizeOf<Uint32>());
    return _cloaked.value != 0;
  }

  @override
  bool isPerchable(int handle) {
    if (handle == 0 || handle == ownWindow) return false;
    if (IsWindowVisible(handle) == 0 || IsIconic(handle) != 0 || IsZoomed(handle) != 0) {
      return false;
    }
    if ((GetWindowLongPtr(handle, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return false;
    if (GetWindowTextLength(handle) == 0) return false;
    if (_shellClasses.contains(_classOf(handle))) return false;
    if (_isCloaked(handle)) return false;
    final r = windowRect(handle);
    return r != null && r.width >= 200 && r.height >= 100;
  }

  @override
  bool isTopAt(int handle, Offset point) {
    final pt = calloc<POINT>()
      ..ref.x = point.dx.round()
      ..ref.y = point.dy.round();
    try {
      final hit = WindowFromPoint(pt.ref);
      if (hit == 0) return false;
      final root = GetAncestor(hit, GA_ROOT);
      // Nox himself never counts as covering a window.
      return root == handle || hit == handle || root == ownWindow;
    } finally {
      calloc.free(pt);
    }
  }

  @override
  bool foregroundIsFullscreen() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0 || hwnd == ownWindow || hwnd == GetShellWindow()) return false;
    if (_shellClasses.contains(_classOf(hwnd))) return false;
    if (GetWindowRect(hwnd, _rect) == 0) return false;
    final r = _toRect(_rect.ref);
    final m = monitorBounds(r.center);
    return r.left <= m.left && r.top <= m.top && r.right >= m.right && r.bottom >= m.bottom;
  }

  void dispose() {
    calloc.free(_point);
    calloc.free(_rect);
    calloc.free(_lastInput);
    calloc.free(_monitor);
    calloc.free(_cloaked);
    free(_className);
  }
}
