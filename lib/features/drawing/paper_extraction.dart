import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Estimate local page color and photographic noise separately. Flat test
/// images need a narrow cutoff; photographed paper needs a measured noise band.
int removeDrawingPaper(image.Image source, double strength, Uint8List? mask) {
  const tile = 32;
  final columns = (source.width / tile).ceil(),
      rows = (source.height / tile).ceil();
  final samples = List<List<double>?>.filled(columns * rows, null);
  final noise = List<double>.filled(columns * rows, 0);
  final all = <List<double>>[];
  for (var gy = 0; gy < rows; gy++) {
    for (var gx = 0; gx < columns; gx++) {
      final candidates = <List<double>>[];
      final residuals = <double>[];
      for (var y = gy * tile;
          y < math.min((gy + 1) * tile, source.height);
          y += 2) {
        for (var x = gx * tile;
            x < math.min((gx + 1) * tile, source.width);
            x += 2) {
          final p = source.getPixel(x, y);
          final low = math.min(p.r, math.min(p.g, p.b));
          final high = math.max(p.r, math.max(p.g, p.b));
          if (p.a > 240 && low >= 130 && high - low <= 65) {
            candidates.add([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
            // A second difference ignores gradual lighting. Its median rejects
            // sparse pencil/ink edges instead of treating them as page noise.
            if (x >= 4 &&
                y >= 4 &&
                x + 4 < source.width &&
                y + 4 < source.height) {
              final neighbors = [
                source.getPixel(x - 4, y),
                source.getPixel(x + 4, y),
                source.getPixel(x, y - 4),
                source.getPixel(x, y + 4)
              ];
              // A tile may contain only a thin strip of page beside a large
              // colored shape. Sampling across that edge inflated its noise
              // and erased blocks of artwork. Measure within the page only.
              if (neighbors.any((c) =>
                  c.a < 240 ||
                  (c.r - p.r).abs() > 24 ||
                  (c.g - p.g).abs() > 24 ||
                  (c.b - p.b).abs() > 24)) continue;
              final around = neighbors.fold<double>(
                      0, (sum, c) => sum + (c.r + c.g + c.b) / 3) /
                  4;
              residuals.add(((p.r + p.g + p.b) / 3 - around).abs());
            }
          }
        }
      }
      if (candidates.isEmpty) continue;
      candidates
          .sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
      // The previous 94th percentile biased noisy paper toward its brightest
      // speckles, leaving most real page pixels opaque. Use a robust midpoint.
      final value = candidates[((candidates.length - 1) * .60).round()];
      samples[gy * columns + gx] = value;
      residuals.sort();
      if (residuals.isNotEmpty)
        noise[gy * columns + gx] =
            residuals[residuals.length ~/ 2].clamp(0, 12);
      all.add(value);
    }
  }
  if (all.isEmpty) return 0;
  all.sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
  final fallback = all[((all.length - 1) * .85).round()];
  // Avoid mistaking a tile filled with faint pencil shading for the page.
  final background = List<List<double>?>.from(samples);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      final nearby = <List<double>>[];
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < columns && ny < rows) {
            final value = samples[ny * columns + nx];
            if (value != null) nearby.add(value);
          }
        }
      }
      nearby.sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
      // Only use brighter neighbors within a modest lighting difference.
      final current = samples[y * columns + x];
      final bright = nearby.isEmpty ? fallback : nearby.last;
      background[y * columns + x] = current == null ||
              bright[0] +
                      bright[1] +
                      bright[2] -
                      current[0] -
                      current[1] -
                      current[2] <
                  48
          ? bright
          : current;
    }
  }
  final amount = strength.clamp(0, 100);
  final originalAlpha = Uint8List(source.width * source.height);
  var cleared = 0;
  for (final p in source) {
    originalAlpha[p.y * source.width + p.x] = p.a.toInt();
  }
  for (final p in source) {
    if (p.a == 0 || (mask != null && mask[p.y * source.width + p.x] == 0))
      continue;
    final index = (p.y ~/ tile) * columns + p.x ~/ tile;
    var paper = background[index] ?? fallback;
    // Opposite samples follow gradual page lighting without treating a thin
    // darker line as paper. Keep the coarse estimate for ambiguous shading.
    List<double>? local;
    for (final direction in const [
      [8, 0],
      [0, 8]
    ]) {
      final ax = (p.x - direction[0]).clamp(0, source.width - 1);
      final ay = (p.y - direction[1]).clamp(0, source.height - 1);
      final bx = (p.x + direction[0]).clamp(0, source.width - 1);
      final by = (p.y + direction[1]).clamp(0, source.height - 1);
      final a = source.getPixel(ax, ay), b = source.getPixel(bx, by);
      if (originalAlpha[ay * source.width + ax] < 240 ||
          originalAlpha[by * source.width + bx] < 240) continue;
      final candidate = [(a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2];
      if (candidate.reduce(math.min) < 130 ||
          candidate.reduce(math.max) - candidate.reduce(math.min) > 65)
        continue;
      if (local == null ||
          candidate[0] + candidate[1] + candidate[2] >
              local[0] + local[1] + local[2]) local = candidate;
    }
    if (local != null &&
        math.max(
                (local[0] - paper[0]).abs(),
                math.max(
                    (local[1] - paper[1]).abs(), (local[2] - paper[2]).abs())) <
            10 + noise[index] * 2) paper = local;
    final difference = math.max((paper[0] - p.r).abs(),
        math.max((paper[1] - p.g).abs(), (paper[2] - p.b).abs()));
    final cutoff = 1.2 + amount * .018 + noise[index] * (2.5 + amount * .025);
    // Clean scans retain the old narrow band. A noisy photograph gets an
    // adaptive band; strength now meaningfully adjusts that measured noise.
    final coverage = ((difference - cutoff) / 3).clamp(0.0, 1.0);
    if (coverage < 1) {
      p.a = (p.a * coverage).round();
      if (p.a == 0) cleared++;
    }
  }
  return cleared;
}
