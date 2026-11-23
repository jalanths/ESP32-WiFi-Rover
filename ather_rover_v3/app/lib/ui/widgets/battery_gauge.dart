import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 270-degree ring showing battery percent, with volts underneath.
/// The ring animates smoothly between telemetry frames.
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.percent,
    required this.volts,
    this.size = 140,
    this.charging = false,
  });

  /// null = no data yet.
  final int? percent;
  final double? volts;
  final double size;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = percent;
    final color = p == null ? scheme.outline : batteryColor(scheme, p);
    final label = p == null
        ? 'Battery: no data'
        : 'Battery $p percent, ${volts?.toStringAsFixed(2) ?? '-'} volts';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: (p ?? 0) / 100),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(
              value: v,
              color: color,
              track: scheme.surfaceContainerHighest,
              stroke: size * 0.09,
            ),
            child: Center(
              child: FittedBox(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p == null ? '--' : '$p%',
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        volts == null ? 'waiting' : '${volts!.toStringAsFixed(2)} V',
                        style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  static const double _start = math.pi * 0.75; // bottom-left
  static const double _sweep = math.pi * 1.5; // 270 degrees

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, _start, _sweep, false, base..color = track);
    final v = value.clamp(0.0, 1.0);
    if (v > 0) {
      canvas.drawArc(arcRect, _start, _sweep * v, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}
