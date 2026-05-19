import 'dart:math';

/// A Dart implementation of the One Euro Filter for jitter reduction.
/// It is particularly effective for smoothing live data like document corners.
class OneEuroFilter {
  final double freq;
  final double minCutoff;
  final double beta;
  final double dCutoff;

  final LowPassFilter _xFilter;
  final LowPassFilter _dxFilter;
  double? _lastTime;

  OneEuroFilter({
    this.freq = 30.0,
    this.minCutoff = 1.0,
    this.beta = 0.0,
    this.dCutoff = 1.0,
  })  : _xFilter = LowPassFilter(_alpha(freq, minCutoff)),
        _dxFilter = LowPassFilter(_alpha(freq, dCutoff));

  double filter(double value, {double? timestamp}) {
    if (_lastTime != null && timestamp != null) {
      final dTime = timestamp - _lastTime!;
      if (dTime > 0) {
        // Update frequency based on actual time difference
        final currentFreq = 1.0 / dTime;
        final dValue = (value - _xFilter.lastValue) * currentFreq;
        final edValue = _dxFilter.filter(dValue, alpha: _alpha(currentFreq, dCutoff));
        final cutoff = minCutoff + beta * edValue.abs();
        _lastTime = timestamp;
        return _xFilter.filter(value, alpha: _alpha(currentFreq, cutoff));
      }
    }

    _lastTime = timestamp ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
    return _xFilter.filter(value);
  }

  static double _alpha(double freq, double cutoff) {
    final te = 1.0 / freq;
    final tau = 1.0 / (2 * pi * cutoff);
    return 1.0 / (1.0 + tau / te);
  }
}

class LowPassFilter {
  double _lastValue;
  double _alpha;

  LowPassFilter(this._alpha, [this._lastValue = 0.0]);

  double get lastValue => _lastValue;

  double filter(double value, {double? alpha}) {
    if (alpha != null) _alpha = alpha;
    _lastValue = _alpha * value + (1.0 - _alpha) * _lastValue;
    return _lastValue;
  }
}

/// A specialized smoother for a set of 4 document corners (8 coordinates).
class CornerSmoother {
  final List<OneEuroFilter> _filters;

  CornerSmoother({
    double minCutoff = 0.5, // Lower = more smoothing when still
    double beta = 0.05,     // Higher = less lag when moving
  }) : _filters = List.generate(
          8,
          (_) => OneEuroFilter(minCutoff: minCutoff, beta: beta),
        );

  List<double> filter(List<double> points) {
    if (points.length != 8) return points;
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return List.generate(8, (i) => _filters[i].filter(points[i], timestamp: timestamp));
  }
}
