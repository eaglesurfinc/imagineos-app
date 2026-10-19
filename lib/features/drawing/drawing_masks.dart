import 'dart:typed_data';

/// Pixel-centre, even/odd polygon mask shared by selection and extraction.
Uint8List polygonMask(int width, int height, List<List<double>> polygon) {
  final mask = Uint8List(width * height);
  if (polygon.length < 3) return mask;
  for (var y = 0; y < height; y++) {
    final crossings = <double>[];
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[j], b = polygon[i], scan = y + .5;
      if ((a[1] > scan) != (b[1] > scan)) {
        crossings.add(a[0] + (scan - a[1]) * (b[0] - a[0]) / (b[1] - a[1]));
      }
    }
    crossings.sort();
    var interval = 0;
    for (var x = 0; x < width; x++) {
      while (interval < crossings.length && x + .5 >= crossings[interval]) {
        interval++;
      }
      if (interval.isOdd) mask[y * width + x] = 1;
    }
  }
  return mask;
}
