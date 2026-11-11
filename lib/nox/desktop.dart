import 'dart:ui';

/// What Nox can see of the Windows desktop.
///
/// All coordinates are physical screen pixels. The real implementation lives
/// in `lib/win/win_desktop.dart`; tests use a fake.
abstract class Desktop {
  /// Current mouse cursor position.
  Offset cursor();

  /// Milliseconds since the last keyboard or mouse input.
  int idleMillis();

  /// Whether the left mouse button is currently held down.
  bool leftButtonDown();

  /// Usable area (excluding the taskbar) of the monitor nearest to [at].
  Rect workArea(Offset at);

  /// Full bounds of the monitor nearest to [at].
  Rect monitorBounds(Offset at);

  /// Handle of the foreground window, or null if none.
  int? foregroundWindow();

  /// Visible bounds of [handle], or null if it is gone, hidden or minimized.
  Rect? windowRect(int handle);

  /// Whether Nox may perch on [handle]: a normal, visible, non-maximized
  /// application window that is not Nox itself.
  bool isPerchable(int handle);

  /// Whether [handle] is the top-most window at [point] (nothing covers it).
  bool isTopAt(int handle, Offset point);

  /// Whether the foreground window covers its whole monitor (game, video…).
  bool foregroundIsFullscreen();
}
