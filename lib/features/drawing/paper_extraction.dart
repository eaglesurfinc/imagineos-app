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
          // Photographed white paper can be very dark under a phone shadow.
          // Brightness is not a paper classifier: the old 130 floor left
          // entire brown regions opaque regardless of cleanup strength.
          if (p.a > 240 && low >= 24 && high - low <= 65) {
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
  // Estimate the dominant page tint independently of illumination. Dark green
  // ink can be as bright as shadowed paper; it must not become a page sample.
  double median(List<double> values) {
    values.sort();
    return values[values.length ~/ 2];
  }

  final redGreen = median(all.map((c) => c[0] - c[1]).toList());
  final greenBlue = median(all.map((c) => c[1] - c[2]).toList());
  bool pageTint(List<double> value, double tolerance) =>
      ((value[0] - value[1]) - redGreen).abs() <= tolerance &&
      ((value[1] - value[2]) - greenBlue).abs() <= tolerance;
  for (var i = 0; i < samples.length; i++) {
    if (samples[i] != null && !pageTint(samples[i]!, 4 + noise[i] * 1.25))
      samples[i] = null;
  }
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
  final texture = Uint8List(originalAlpha.length);
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
    final local = <List<double>>[];
    for (final direction in const [
      [4, 0],
      [0, 4],
      [8, 0],
      [0, 8],
      [16, 0],
      [0, 16]
    ]) {
      var ax = p.x - direction[0], ay = p.y - direction[1];
      var bx = p.x + direction[0], by = p.y + direction[1];
      var extrapolate = false;
      // Clamping an opposite pair brightens the dark edge of a gradient.
      // At an image edge, extrapolate from two in-bounds page samples instead.
      if (ax < 0 || ay < 0) {
        ax = p.x + direction[0];
        ay = p.y + direction[1];
        bx = p.x + 2 * direction[0];
        by = p.y + 2 * direction[1];
        extrapolate = true;
      } else if (bx >= source.width || by >= source.height) {
        ax = p.x - direction[0];
        ay = p.y - direction[1];
        bx = p.x - 2 * direction[0];
        by = p.y - 2 * direction[1];
        extrapolate = true;
      }
      if (ax < 0 ||
          ay < 0 ||
          bx < 0 ||
          by < 0 ||
          ax >= source.width ||
          bx >= source.width ||
          ay >= source.height ||
          by >= source.height) continue;
      final a = source.getPixel(ax, ay), b = source.getPixel(bx, by);
      if (originalAlpha[ay * source.width + ax] < 240 ||
          originalAlpha[by * source.width + bx] < 240) continue;
      if (!pageTint([a.r.toDouble(), a.g.toDouble(), a.b.toDouble()],
              4 + noise[index] * 1.25) ||
          !pageTint([b.r.toDouble(), b.g.toDouble(), b.b.toDouble()],
              4 + noise[index] * 1.25)) continue;
      if (extrapolate &&
          math.max((a.r - b.r).abs(),
                  math.max((a.g - b.g).abs(), (a.b - b.b).abs())) >
              12 + noise[index] * 2) continue;
      final candidate = extrapolate
          ? [
              (2 * a.r - b.r).toDouble(),
              (2 * a.g - b.g).toDouble(),
              (2 * a.b - b.b).toDouble()
            ]
          : [(a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2];
      if (candidate.reduce(math.min) < 24 ||
          candidate.reduce(math.max) - candidate.reduce(math.min) > 65)
        continue;
      // A pair crossing a hard shadow must not displace a valid pair that
      // follows the paper on this side. Filter before selecting the brightest.
      final delta = List.generate(3, (i) => candidate[i] - paper[i]);
      // A change shared by all channels is page illumination. Allow a wider
      // range there, while a changed tint still protects pale colored artwork.
      final lighting =
          delta.reduce(math.max) - delta.reduce(math.min) < 3 + noise[index];
      final limit = lighting ? 48.0 : 10 + noise[index] * 2;
      if (delta.any((value) => value.abs() >= limit)) continue;
      local.add(candidate);
    }
    if (local.isNotEmpty) {
      local.sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
      paper = local[((local.length - 1) * .60).round()];
    }
    final difference = math.max((paper[0] - p.r).abs(),
        math.max((paper[1] - p.g).abs(), (paper[2] - p.b).abs()));
    // Texture cleanup must never grow into a wide ink-erasing band. Remaining
    // isolated paper grain is handled by the bounded component pass below.
    final cutoff =
        math.min(20.0, 1.2 + amount * .018 + noise[index] * (5 + amount * .03));
    // Clean scans retain the old narrow band. A noisy photograph gets an
    // adaptive band; strength now meaningfully adjusts that measured noise.
    // Colored ink changes the page tint; paper grain mainly changes brightness.
    // Keep that separate signal so stronger texture cleanup retains faint ink.
    final residual = [paper[0] - p.r, paper[1] - p.g, paper[2] - p.b];
    final chroma = residual.reduce(math.max) - residual.reduce(math.min);
    final tintIsPaper = pageTint(
        [p.r.toDouble(), p.g.toDouble(), p.b.toDouble()],
        4 + noise[index] * 1.25);
    if (pageTint([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()],
            12 + noise[index] * 2) &&
        noise[index] >= 1 &&
        difference <= cutoff + noise[index] * 2 + 3)
      texture[p.y * source.width + p.x] = 1;
    final coverage = (math.max(difference - cutoff,
                tintIsPaper ? 0.0 : chroma - (2 + noise[index] * 2.5)) /
            3)
        .clamp(0.0, 1.0);
    if (coverage < 1) {
      p.a = (p.a * coverage).round();
      if (p.a == 0) cleared++;
    }
  }
  // At full cleanup, remove isolated photographic paper flecks. Never remove
  // a component carrying a different ink tint, a clean-scan dot, or a longer
  // line. This runs inside the selected region only and leaves RGB unchanged.
  if (amount == 100) {
    final seen = Uint8List(texture.length);
    for (var start = 0; start < texture.length; start++) {
      if (seen[start] != 0 ||
          texture[start] == 0 ||
          source.getPixel(start % source.width, start ~/ source.width).a == 0)
        continue;
      final component = <int>[start];
      seen[start] = 1;
      var onlyTexture = true;
      for (var i = 0; i < component.length; i++) {
        final index = component[i],
            x = index % source.width,
            y = index ~/ source.width;
        if (texture[index] == 0) onlyTexture = false;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= source.width || ny >= source.height)
              continue;
            final next = ny * source.width + nx;
            if (seen[next] != 0 ||
                (mask != null && mask[next] == 0) ||
                source.getPixel(nx, ny).a == 0) continue;
            seen[next] = 1;
            component.add(next);
          }
        }
      }
      if (onlyTexture && component.length <= 128) {
        for (final index in component) {
          source.getPixel(index % source.width, index ~/ source.width).a = 0;
          cleared++;
        }
      }
    }
  }
  // Sampling above reads the original RGB even after alpha changes. Clear the
  // removed page's RGB only after sampling finishes, so the cutout carries no
  // hidden page pixels and compresses efficiently. Retained ink is unchanged.
  for (final p in source) {
    if (p.a == 0 && (mask == null || mask[p.y * source.width + p.x] != 0))
      p.setRgba(0, 0, 0, 0);
  }
  return cleared;
}
