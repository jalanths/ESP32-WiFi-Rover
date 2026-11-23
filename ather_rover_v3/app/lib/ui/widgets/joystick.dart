import 'package:flutter/material.dart';

/// Round thumb-stick. Reports the raw knob position: dx right = +1,
/// dy up = +1, length <= 1. Springs back to the centre on release.
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    required this.onChanged,
    this.onEngage,
    this.enabled = true,
    this.size = 240,
  });

  final void Function(double dx, double dy) onChanged;

  /// Called once when a finger lands (for haptics).
  final VoidCallback? onEngage;
  final bool enabled;
  final double size;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> with SingleTickerProviderStateMixin {
  Offset _knob = Offset.zero; // -1..1, screen axes (y down)
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  Offset _releaseFrom = Offset.zero;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() {
      setState(() => _knob = Offset.lerp(_releaseFrom, Offset.zero,
          Curves.easeOutBack.transform(_spring.value))!);
    });
  }

  void _start(Offset local) {
    _spring.stop();
    _active = true;
    widget.onEngage?.call();
    _move(local);
  }

  void _move(Offset local) {
    final r = widget.size / 2;
    var d = (local - Offset(r, r)) / r;
    if (d.distance > 1) d = d / d.distance;
    setState(() => _knob = d);
    widget.onChanged(d.dx, -d.dy);
  }

  void _release() {
    if (!_active) return;
    _active = false;
    widget.onChanged(0, 0);
    _releaseFrom = _knob;
    _spring.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant Joystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _active = false;
      _spring.stop();
      _knob = Offset.zero;
      // report after this frame; never call a parent setter during build
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(0, 0));
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    final knobR = size * 0.16;
    final travel = size / 2 - knobR;
    final on = widget.enabled;

    return Semantics(
      label: on ? 'Joystick. Drag to drive, release to stop.' : 'Joystick disabled',
      enabled: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: on ? (d) => _start(d.localPosition) : null,
        onPanUpdate: on ? (d) => _move(d.localPosition) : null,
        onPanEnd: on ? (_) => _release() : null,
        onPanCancel: on ? _release : null,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _BasePainter(
              ring: scheme.outlineVariant,
              fill: scheme.surfaceContainerHigh,
              accent: on ? scheme.primary : scheme.outline,
              knob: _knob,
            ),
            child: Center(
              child: Transform.translate(
                offset: _knob * travel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: knobR * 2,
                  height: knobR * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: on
                          ? [scheme.primaryContainer, scheme.primary]
                          : [scheme.surfaceContainerHighest, scheme.outline],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withAlpha(_active ? 90 : 50),
                        blurRadius: _active ? 18 : 10,
                        offset: const Offset(0, 4),
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

class _BasePainter extends CustomPainter {
  _BasePainter({required this.ring, required this.fill, required this.accent, required this.knob});

  final Color ring, fill, accent;
  final Offset knob;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = fill);
    final line = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, r - 1, line);
    canvas.drawCircle(c, r * 0.55, line);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), line);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), line);

    // direction hint: arc on the rim that follows the knob
    if (knob.distance > 0.05) {
      final angle = knob.direction;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 4),
        angle - 0.5,
        1.0,
        false,
        Paint()
          ..color = accent.withAlpha((80 + 175 * knob.distance).round().clamp(0, 255))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BasePainter old) =>
      old.knob != knob || old.ring != ring || old.fill != fill || old.accent != accent;
}
