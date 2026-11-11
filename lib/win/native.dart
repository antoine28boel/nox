import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';

// Win32 bindings for Nox's pranks (desktop icons, feather window), declared
// here so they do not depend on the exact signatures of the win32 package.

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');

final class NPoint extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class BlendFunction extends Struct {
  @Uint8()
  external int op;
  @Uint8()
  external int flags;
  @Uint8()
  external int alpha;
  @Uint8()
  external int format;
}

final class BitmapInfoHeader extends Struct {
  @Uint32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Uint16()
  external int planes;
  @Uint16()
  external int bitCount;
  @Uint32()
  external int compression;
  @Uint32()
  external int sizeImage;
  @Int32()
  external int xPelsPerMeter;
  @Int32()
  external int yPelsPerMeter;
  @Uint32()
  external int clrUsed;
  @Uint32()
  external int clrImportant;
}

final _findWindowEx = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
    int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');

final _sendMessageTimeout = _user32.lookupFunction<
    IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr, Uint32, Uint32, Pointer<IntPtr>),
    int Function(int, int, int, int, int, int, Pointer<IntPtr>)>('SendMessageTimeoutW');

final _getWindowThreadProcessId = _user32.lookupFunction<
    Uint32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');

final _clientToScreen = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<NPoint>),
    int Function(int, Pointer<NPoint>)>('ClientToScreen');

final _createWindowEx = _user32.lookupFunction<
    IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32, Int32, Int32,
        Int32, IntPtr, IntPtr, IntPtr, Pointer<Void>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int, int, int,
        int, Pointer<Void>)>('CreateWindowExW');

final _showWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');

final _updateLayeredWindow = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Pointer<NPoint>, Pointer<NPoint>, IntPtr,
        Pointer<NPoint>, Uint32, Pointer<BlendFunction>, Uint32),
    int Function(int, int, Pointer<NPoint>, Pointer<NPoint>, int, Pointer<NPoint>, int,
        Pointer<BlendFunction>, int)>('UpdateLayeredWindow');

final _openProcess = _kernel32.lookupFunction<IntPtr Function(Uint32, Int32, Uint32),
    int Function(int, int, int)>('OpenProcess');

final _closeHandle =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final _virtualAllocEx = _kernel32.lookupFunction<
    Pointer<Void> Function(IntPtr, Pointer<Void>, IntPtr, Uint32, Uint32),
    Pointer<Void> Function(int, Pointer<Void>, int, int, int)>('VirtualAllocEx');

final _virtualFreeEx = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Void>, IntPtr, Uint32),
    int Function(int, Pointer<Void>, int, int)>('VirtualFreeEx');

final _readProcessMemory = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Void>, Pointer<Void>, IntPtr, Pointer<IntPtr>),
    int Function(int, Pointer<Void>, Pointer<Void>, int, Pointer<IntPtr>)>(
    'ReadProcessMemory');

final _getModuleHandle = _kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>),
    int Function(Pointer<Utf16>)>('GetModuleHandleW');

final _createCompatibleDC =
    _gdi32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');

final _createDIBSection = _gdi32.lookupFunction<
    IntPtr Function(IntPtr, Pointer<BitmapInfoHeader>, Uint32, Pointer<Pointer<Void>>,
        IntPtr, Uint32),
    int Function(int, Pointer<BitmapInfoHeader>, int, Pointer<Pointer<Void>>, int,
        int)>('CreateDIBSection');

final _selectObject = _gdi32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SelectObject');

const _lvmGetItemCount = 0x1004;
const _lvmGetItemPosition = 0x1010;
const _lvmGetItemSpacing = 0x1033;
const _smtoAbortIfHung = 0x0002;

int _send(int hwnd, int msg, int wParam, int lParam, Pointer<IntPtr> result) {
  result.value = 0;
  final ok = _sendMessageTimeout(hwnd, msg, wParam, lParam, _smtoAbortIfHung, 200, result);
  return ok == 0 ? -1 : result.value;
}

/// The list view that holds the desktop icons, or 0.
int _desktopListView() {
  final progman = 'Progman'.toNativeUtf16();
  final workerW = 'WorkerW'.toNativeUtf16();
  final defView = 'SHELLDLL_DefView'.toNativeUtf16();
  final listView = 'SysListView32'.toNativeUtf16();
  try {
    var view = _findWindowEx(_findWindowEx(0, 0, progman, nullptr), 0, defView, nullptr);
    var worker = 0;
    for (var i = 0; view == 0 && i < 50; i++) {
      worker = _findWindowEx(0, worker, workerW, nullptr);
      if (worker == 0) break;
      view = _findWindowEx(worker, 0, defView, nullptr);
    }
    return view == 0 ? 0 : _findWindowEx(view, 0, listView, nullptr);
  } finally {
    calloc.free(progman);
    calloc.free(workerW);
    calloc.free(defView);
    calloc.free(listView);
  }
}

/// Approximate centers of the desktop icons, in physical screen pixels.
///
/// The positions live in Explorer's memory, so they are read through a small
/// buffer allocated there. Returns an empty list on any failure.
List<Offset> readDesktopIcons({int max = 200}) {
  final icons = <Offset>[];
  final lv = _desktopListView();
  if (lv == 0) return icons;

  final result = calloc<IntPtr>();
  final pid = calloc<Uint32>();
  final local = calloc<NPoint>();
  var process = 0;
  Pointer<Void> remote = nullptr;
  try {
    final count = _send(lv, _lvmGetItemCount, 0, 0, result);
    if (count <= 0) return icons;
    final spacing = _send(lv, _lvmGetItemSpacing, 0, 0, result);
    final cellW = spacing <= 0 ? 0 : spacing & 0xFFFF;
    final cellH = spacing <= 0 ? 0 : (spacing >> 16) & 0xFFFF;

    _getWindowThreadProcessId(lv, pid);
    // PROCESS_VM_OPERATION | PROCESS_VM_READ
    process = _openProcess(0x0008 | 0x0010, 0, pid.value);
    if (process == 0) return icons;
    // MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE
    remote = _virtualAllocEx(process, nullptr, sizeOf<NPoint>(), 0x3000, 0x04);
    if (remote == nullptr) return icons;

    for (var i = 0; i < count && i < max; i++) {
      if (_send(lv, _lvmGetItemPosition, i, remote.address, result) <= 0) continue;
      if (_readProcessMemory(process, remote, local.cast(), sizeOf<NPoint>(), nullptr) == 0) {
        continue;
      }
      // The position is the icon's top-left corner; the icon is centered in
      // its grid cell and takes roughly the top half of it.
      final left = local.ref.x;
      final top = local.ref.y;
      final cx = cellW > 0 ? (left ~/ cellW) * cellW + cellW ~/ 2 : left + 24;
      final cy = cellH > 0 ? top + cellH ~/ 4 : top + 24;
      local.ref
        ..x = cx
        ..y = cy;
      _clientToScreen(lv, local);
      icons.add(Offset(local.ref.x.toDouble(), local.ref.y.toDouble()));
    }
    return icons;
  } finally {
    // MEM_RELEASE
    if (remote != nullptr) _virtualFreeEx(process, remote, 0, 0x8000);
    if (process != 0) _closeHandle(process);
    calloc.free(result);
    calloc.free(pid);
    calloc.free(local);
  }
}

/// A tiny click-through, always-on-top window that shows the feather Nox
/// leaves behind. It is a per-pixel-alpha layered window, so it needs no
/// window procedure of its own.
class FeatherWindow {
  /// [bgra] is premultiplied BGRA, [width] x [height] pixels, top row first.
  FeatherWindow(Uint8List bgra, this.width, this.height) {
    final cls = 'Static'.toNativeUtf16();
    final title = ''.toNativeUtf16();
    // WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
    // | WS_EX_TOPMOST, WS_POPUP
    hwnd = _createWindowEx(0x00080000 | 0x20 | 0x80 | 0x08000000 | 0x8, cls, title,
        0x80000000, 0, 0, width, height, 0, 0, _getModuleHandle(nullptr), nullptr);
    calloc.free(cls);
    calloc.free(title);
    if (hwnd == 0) return;

    final header = calloc<BitmapInfoHeader>()
      ..ref.size = sizeOf<BitmapInfoHeader>()
      ..ref.width = width
      ..ref.height = -height
      ..ref.planes = 1
      ..ref.bitCount = 32;
    final bits = calloc<Pointer<Void>>();
    _dc = _createCompatibleDC(0);
    final bitmap = _createDIBSection(_dc, header, 0, bits, 0, 0);
    if (bitmap != 0 && bits.value != nullptr && bgra.length == width * height * 4) {
      bits.value.cast<Uint8>().asTypedList(bgra.length).setAll(0, bgra);
      _selectObject(_dc, bitmap);
      _ready = true;
    }
    calloc.free(header);
    calloc.free(bits);

    _size.ref
      ..x = width
      ..y = height;
  }

  final int width;
  final int height;

  /// Window handle, or 0 if it could not be created.
  int hwnd = 0;

  int _dc = 0;
  bool _ready = false;
  bool _visible = false;
  int _x = -1 << 30;
  int _y = -1 << 30;
  int _alpha = -1;

  final _pos = calloc<NPoint>();
  final _size = calloc<NPoint>();
  final _src = calloc<NPoint>();
  final _blend = calloc<BlendFunction>();

  /// Shows the feather centered on ([x], [y]) with [alpha] in 0..255.
  void show(int x, int y, int alpha) {
    if (!_ready) return;
    x -= width ~/ 2;
    y -= height ~/ 2;
    if (_visible && x == _x && y == _y && alpha == _alpha) return;
    _x = x;
    _y = y;
    _alpha = alpha;
    _pos.ref
      ..x = x
      ..y = y;
    _blend.ref
      ..op = 0 // AC_SRC_OVER
      ..flags = 0
      ..alpha = alpha
      ..format = 1; // AC_SRC_ALPHA
    // ULW_ALPHA
    _updateLayeredWindow(hwnd, 0, _pos, _size, _dc, _src, 0, _blend, 0x2);
    if (!_visible) {
      _showWindow(hwnd, 4); // SW_SHOWNOACTIVATE
      _visible = true;
    }
  }

  void hide() {
    if (!_visible) return;
    _showWindow(hwnd, 0); // SW_HIDE
    _visible = false;
  }
}
