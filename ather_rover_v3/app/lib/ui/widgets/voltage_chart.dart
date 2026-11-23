import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/protocol.dart';
import '../../state/rover_controller.dart';
import '../theme.dart';

/// Line chart of recent battery voltage with the 3.7 V limp and 3.6 V cut-off
/// lines marked, so the rider sees how close the cut-off is.
class VoltageChart extends StatelessWidget {
  const VoltageChart({super.key, required this.volts, this.height = 160});

  final List<double> volts;
  final double height;

  static const double vMax = 4.25;

  /// Bottom of the chart: normally 3.4 V, lower if the battery went lower,
  /// so a deeply drained pack is still drawn instead of a flat line.
  static double floorFor(List<double> volts) {
    if (volts.isEmpty) return 3.4;
    final lowest = volts.reduce(math.min);
    return lowest >= 3.45 ? 3.4 : ((lowest - 0.1) * 5).floorToDouble() / 5;
  }
  static const double limp = 3.7, cutoff = 3.6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final summary = volts.isEmpty
        ? 'Battery voltage chart, no data yet'
        : 'Battery voltage chart, ${volts.length} readings, '
            'latest ${volts.last.toStringAsFixed(2)} volts, '
            'lowest ${volts.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)} volts';

    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: volts.length < 2
            ? Center(
                child: Text('Collecting data...',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              )
            : CustomPaint(
                painter: _ChartPainter(
                  volts: volts,
                  vMin: floorFor(volts),
                  line: scheme.primary,
                  grid: scheme.outlineVariant,
                  limpColor: severityColor(scheme, Severity.warning),
                  cutColor: scheme.error,
                  labelStyle: text.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.volts,
    required this.vMin,
    required this.line,
    required this.grid,
    required this.limpColor,
    required this.cutColor,
    required this.labelStyle,
  });

  final List<double> volts;
  final double vMin;
  final Color line, grid, limpColor, cutColor;
  final TextStyle labelStyle;

  static const double _left = 36; // room for axis labels

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _left;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    double yFor(double v) {
      final t = ((v - vMin) / (VoltageChart.vMax - vMin)).clamp(0.0, 1.0);
      return h - t * h;
    }

    // grid + labels
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 4.2; v > vMin + 0.05; v -= 0.2) {
      final y = yFor(v);
      canvas.drawLine(Offset(_left, y), Offset(size.width, y), gridPaint);
      _label(canvas, v.toStringAsFixed(1), Offset(0, y - 7));
    }

    // thresholds
    _dashed(canvas, yFor(VoltageChart.limp), size.width, limpColor);
    _dashed(canvas, yFor(VoltageChart.cutoff), size.width, cutColor);

    // data
    final n = volts.length;
    final dx = w / math.max(RoverController.historyLength - 1, n - 1);
    final startX = _left + w - dx * (n - 1); // newest point at the right edge
    final path = Path();
    for (var i = 0; i < n; i++) {
      final p = Offset(startX + dx * i, yFor(volts[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(startX + dx * (n - 1), h)
      ..lineTo(startX, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withAlpha(90), line.withAlpha(0)],
        ).createShader(Rect.fromLTWH(_left, 0, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    // latest point
    canvas.drawCircle(Offset(startX + dx * (n - 1), yFor(volts.last)), 4, Paint()..color = line);
  }

  void _dashed(Canvas canvas, double y, double right, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = _left; x < right; x += 8) {
      canvas.drawLine(Offset(x, y), Offset((x + 4).clamp(0, right).toDouble(), y), p);
    }
  }

  void _label(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.volts != volts || old.vMin != vMin || old.line != line || old.grid != grid || old.labelStyle != labelStyle;
}

