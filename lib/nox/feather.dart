import 'dart:math' as math;
import 'dart:typed_data';

/// Size of the feather Nox leaves behind, in logical pixels.
const kFeatherWidth = 44;
const kFeatherHeight = 20;

/// Draws the feather as premultiplied BGRA pixels (top row first), the format
/// a Windows layered window expects. Pure Dart: no engine, no async.
({Uint8List bgra, int width, int height}) renderFeather(double scale) {
  final w = math.max(1, (kFeatherWidth * scale).round());
  final h = math.max(1, (kFeatherHeight * scale).round());
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // u runs along the quill, v is the distance to it.
      final u = (x + 0.5) / w;
      final bend = math.sin(u * math.pi);
      final mid = h * 0.5 + bend * h * 0.12;
      final half = h * 0.38 * math.pow(bend, 0.7).toDouble();
      final v = (y + 0.5 - mid).abs();
      final a = ((half - v) / scale + 0.5).clamp(0.0, 1.0);
      if (a <= 0) continue;

      int r, g, b;
      if (v < 0.7 * scale) {
        // Cream shaft.
        r = 0xF3;
        g = 0xE3;
        b = 0xC3;
      } else {
        // Brown vane (Nox's plumage), darker towards the tip.
        final t = ((u - 0.6) / 0.4).clamp(0.0, 1.0);
        r = (0x8B + (0x6B - 0x8B) * t).round();
        g = (0x6B + (0x4F - 0x6B) * t).round();
        b = (0x4F + (0x38 - 0x4F) * t).round();
      }
      final i = (y * w + x) * 4;
      out[i] = (b * a).round();
      out[i + 1] = (g * a).round();
      out[i + 2] = (r * a).round();
      out[i + 3] = (255 * a).round();
    }
  }
  return (bgra: out, width: w, height: h);
}
