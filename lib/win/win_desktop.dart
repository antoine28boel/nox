import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../nox/desktop.dart';

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
