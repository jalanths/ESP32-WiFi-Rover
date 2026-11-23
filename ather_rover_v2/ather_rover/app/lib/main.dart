import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'rover_client.dart';

// Tilt steering: how many m/s² of tilt gives full stick, and the dead zone.
// If tilting drives the wrong way on your phone, flip the matching sign.
const double kTiltFull = 5.0;
const double kTiltDeadZone = 0.12;
const double kTiltSteerSign = -1.0;
const double kTiltThrottleSign = -1.0;

void main() => runApp(const RoverApp());

class RoverApp extends StatelessWidget {
  const RoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ather Rover',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D9E75)),
        useMaterial3: true,
      ),
      home: const ControlScreen(),
    );
  }
}

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final RoverClient rover = RoverClient();

  // tilt steering
  bool tilt = false;
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  double _ax0 = 0,
      _ay0 = 0; // phone position when tilt was switched on = neutral
  bool _tiltCalibrated = false;

  @override
  void initState() {
    super.initState();
    rover.addListener(() {
      if (!rover.connected && tilt) _setTilt(false);
      if (mounted) setState(() {});
    });
    rover.connect();
  }

  @override
  void dispose() {
    _tiltSub?.cancel();
    rover.dispose();
    super.dispose();
  }

  double _dead(double v) {
    if (v.abs() < kTiltDeadZone) return 0;
    final s = (v.abs() - kTiltDeadZone) / (1 - kTiltDeadZone);
    return v.isNegative ? -s : s;
  }

  void _setTilt(bool on) {
    _tiltSub?.cancel();
    _tiltSub = null;
    rover.drive(0, 0);
    setState(() => tilt = on);
    if (!on) return;
    _tiltCalibrated = false;
    _tiltSub = accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 20))
        .listen(onError: (Object _) {
      // phone has no accelerometer: switch tilt back off
      if (mounted) _setTilt(false);
    }, (e) {
      if (!_tiltCalibrated) {
        _ax0 = e.x;
        _ay0 = e.y;
        _tiltCalibrated = true;
        return;
      }
      final steer =
          (kTiltSteerSign * (e.x - _ax0) / kTiltFull).clamp(-1.0, 1.0);
      final throttle =
          (kTiltThrottleSign * (e.y - _ay0) / kTiltFull).clamp(-1.0, 1.0);
      rover.drive(_dead(steer), _dead(throttle));
    });
  }

  String _fmtDrive(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _editHost() async {
    final controller = TextEditingController(text: rover.host);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rover address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration:
              const InputDecoration(helperText: 'Default is 192.168.4.1'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      rover.host = result;
      rover.connect();
    }
  }

  Color _stateColor(BuildContext context) {
    if (!rover.connected) return Colors.grey;
    switch (rover.state) {
      case 'OK':
        return const Color(0xFF1D9E75);
      case 'LIMP':
      case 'OVERLOAD':
        return const Color(0xFFBA7517);
      default:
        return const Color(0xFFE24B4A);
    }
  }

  String get _stateLabel {
    if (rover.connecting) return 'Connecting';
    if (!rover.connected) return 'Not connected';
    switch (rover.state) {
      case 'OK':
        return 'Ready';
      case 'LIMP':
        return 'Limp mode: low battery';
      case 'LOWBATT':
        return 'Battery cut-off';
      case 'FAILSAFE':
        return 'Fail-safe stop';
      case 'OVERLOAD':
        return 'Overload: easing off';
      case 'FAULT':
        return 'Motor driver fault';
      case 'SLEEP':
        return 'Asleep: move the joystick to wake';
      default:
        return rover.state;
    }
  }

  String get _selfTestLabel {
    switch (rover.selfTest) {
      case 'OK':
        return 'Self-test passed';
      case 'BATT_SENSE':
        return 'Self-test: battery sense wire not connected';
      case 'BATT_LOW':
        return 'Self-test: battery too low';
      case 'DRIVER':
        return 'Self-test: motor driver fault';
      default:
        return 'Self-test: ${rover.selfTest}';
    }
  }

  Future<void> _openCalibrate() async {
    final controller = TextEditingController();
    String? errorText;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Calibrate battery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Stop the rover, measure the battery with a multimeter, '
                  'and enter the reading.'),
              const SizedBox(height: 8),
              Text(
                  'Rover reads ${rover.loadVolts.toStringAsFixed(2)} V now '
                  '(correction ${rover.calibration.toStringAsFixed(3)})',
                  style: Theme.of(ctx).textTheme.bodySmall),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Multimeter reading',
                  suffixText: 'V',
                  hintText: 'e.g. 4.12',
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) setDialog(() => errorText = null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0.0),
              child: const Text('Reset'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'));
                if (v == null || v < 3.0 || v > 4.4) {
                  setDialog(() =>
                      errorText = 'Enter a voltage between 3.00 and 4.40');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null) rover.calibrateBattery(result);
  }

  Future<void> _openTrim() async {
    double value = rover.trim;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Straight-line trim',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                  'Drive straight at full stick. Move the slider toward the '
                  'side the rover drifts to.'),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Drifts left'),
                  Expanded(
                    child: Slider(
                      value: value,
                      min: -0.30,
                      max: 0.30,
                      divisions: 60,
                      label: (value * 100).round().toString(),
                      onChanged: (v) => setSheet(() => value = v),
                      onChangeEnd: rover.setTrim,
                    ),
                  ),
                  const Text('Drifts right'),
                ],
              ),
              Text('Trim ${(value * 100).round()}  (saved on the rover)'),
              TextButton(
                onPressed: () {
                  setSheet(() => value = 0);
                  rover.setTrim(0);
                },
                child: const Text('Reset to 0'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ather Rover'),
        actions: [
          IconButton(
            tooltip: tilt ? 'Tilt steering on' : 'Tilt steering off',
            isSelected: tilt,
            icon: const Icon(Icons.screen_rotation_alt),
            selectedIcon:
                const Icon(Icons.screen_rotation_alt, color: Color(0xFF1D9E75)),
            onPressed: rover.connected ? () => _setTilt(!tilt) : null,
          ),
          IconButton(
            tooltip: 'Straight-line trim',
            icon: const Icon(Icons.tune),
            onPressed: rover.connected ? _openTrim : null,
          ),
          IconButton(
            tooltip: 'Rover address',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: _editHost,
          ),
          IconButton(
            tooltip: 'Reconnect',
            icon: const Icon(Icons.refresh),
            onPressed: rover.connect,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Status
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 12, color: _stateColor(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_stateLabel,
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          Text('fw ${rover.firmware}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: rover.connected && rover.hasCalibration
                            ? _openCalibrate
                            : null,
                        child: Row(
                          children: [
                            const Icon(Icons.battery_full, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value:
                                    rover.connected ? rover.percent / 100 : 0,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(rover.connected
                                ? '${rover.percent}%  ${rover.volts.toStringAsFixed(2)} V'
                                : '--'),
                            if (rover.connected && rover.hasCalibration)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.edit_outlined, size: 16),
                              ),
                          ],
                        ),
                      ),
                      if (rover.connected && rover.selfTest.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _selfTestLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: rover.selfTest == 'OK'
                                ? const Color(0xFF0F6E56)
                                : scheme.error,
                          ),
                        ),
                      ],
                      if (rover.connected) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(rover.rangeMin < 0
                                ? 'Range: learning...'
                                : 'Range ~${rover.rangeMin} min'),
                            Text('Drive ${_fmtDrive(rover.driveSec)}'),
                            Text('Min ${rover.minVolts.toStringAsFixed(2)} V'),
                            Text('Used ${rover.usedPct}%'),
                            InkWell(
                              onTap: rover.resetTrip,
                              child: const Text('Reset trip',
                                  style: TextStyle(
                                      decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: BatteryGraphPainter(
                              rover.voltHistory,
                              line: scheme.primary,
                              grid: scheme.outlineVariant,
                            ),
                          ),
                        ),
                      ],
                      if (rover.error != null && !rover.connected) ...[
                        const SizedBox(height: 8),
                        Text(rover.error!,
                            style: TextStyle(color: scheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Ride modes
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RoverMode>(
                  segments: const [
                    ButtonSegment(value: RoverMode.eco, label: Text('Eco')),
                    ButtonSegment(value: RoverMode.ride, label: Text('Ride')),
                    ButtonSegment(value: RoverMode.sport, label: Text('Sport')),
                  ],
                  selected: {rover.mode},
                  onSelectionChanged: rover.connected
                      ? (Set<RoverMode> s) => rover.setMode(s.first)
                      : null,
                ),
              ),

              const SizedBox(height: 8),

              // Turbo, record, play, find
              Row(
                children: [
                  _ActionButton(
                    label: rover.activity == 'COOL' ? 'Cooling' : 'Turbo',
                    icon: Icons.bolt,
                    active: rover.activity == 'TURBO',
                    onPressed: rover.connected && rover.activity != 'COOL'
                        ? rover.turbo
                        : null,
                  ),
                  _ActionButton(
                    label: rover.activity == 'REC' ? 'Stop rec' : 'Record',
                    icon: Icons.fiber_manual_record,
                    active: rover.activity == 'REC',
                    onPressed: rover.connected ? rover.toggleRecord : null,
                  ),
                  _ActionButton(
                    label: rover.activity == 'PLAY'
                        ? 'Stop'
                        : (rover.pathSec > 0
                            ? 'Play ${rover.pathSec}s'
                            : 'Play'),
                    icon: rover.activity == 'PLAY'
                        ? Icons.stop
                        : Icons.play_arrow,
                    active: rover.activity == 'PLAY',
                    onPressed: rover.connected &&
                            (rover.pathSec > 0 || rover.activity == 'PLAY')
                        ? rover.togglePlay
                        : null,
                  ),
                  _ActionButton(
                    label: 'Find',
                    icon: Icons.highlight,
                    active: false,
                    onPressed: rover.connected ? rover.find : null,
                  ),
                ],
              ),

              // Joystick (sized to fit the space left on the screen)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size =
                        (c.biggest.shortestSide - 16).clamp(120.0, 240.0);
                    return Center(
                      child: tilt
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.screen_rotation_alt, size: 48),
                                SizedBox(height: 8),
                                Text(
                                    'Tilt steering on\nTilt forward to drive, sideways to turn',
                                    textAlign: TextAlign.center),
                              ],
                            )
                          : Joystick(
                              size: size,
                              enabled: rover.connected,
                              onChanged: rover.drive,
                            ),
                    );
                  },
                ),
              ),

              // Stop
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE24B4A)),
                  onPressed: rover.connected
                      ? () {
                          if (tilt) _setTilt(false);
                          rover.stop();
                        }
                      : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('STOP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round joystick. Reports x (right = +1) and y (up = +1), both -1..1.
class Joystick extends StatefulWidget {
  const Joystick(
      {super.key,
      required this.onChanged,
      this.enabled = true,
      this.size = 240});

  final void Function(double x, double y) onChanged;
  final bool enabled;
  final double size;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero; // -1..1 on both axes

  void _update(Offset local) {
    final r = widget.size / 2;
    var d = (local - Offset(r, r)) / r;
    if (d.distance > 1) d = d / d.distance;
    setState(() => _knob = d);
    widget.onChanged(d.dx, -d.dy);
  }

  void _release() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  void didUpdateWidget(covariant Joystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _knob = Offset.zero;
      widget.onChanged(0, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = widget.size / 2;
    const knobR = 36.0;
    final travel = r - knobR;

    return GestureDetector(
      onPanStart: widget.enabled ? (d) => _update(d.localPosition) : null,
      onPanUpdate: widget.enabled ? (d) => _update(d.localPosition) : null,
      onPanEnd: widget.enabled ? (_) => _release() : null,
      onPanCancel: widget.enabled ? _release : null,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant, width: 2),
              ),
            ),
            Positioned(
                top: 10,
                child: Icon(Icons.keyboard_arrow_up, color: scheme.outline)),
            Positioned(
                bottom: 10,
                child: Icon(Icons.keyboard_arrow_down, color: scheme.outline)),
            Positioned(
                left: 10,
                child: Icon(Icons.keyboard_arrow_left, color: scheme.outline)),
            Positioned(
                right: 10,
                child: Icon(Icons.keyboard_arrow_right, color: scheme.outline)),
            Transform.translate(
              offset: Offset(_knob.dx * travel, _knob.dy * travel),
              child: Container(
                width: knobR * 2,
                height: knobR * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.enabled ? scheme.primary : scheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the four small buttons under the ride modes.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            backgroundColor: active ? scheme.primaryContainer : null,
          ),
          onPressed: onPressed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// Battery voltage over the last minute, with lines at 3.7 V (warning)
/// and 3.6 V (cut-off), to show how the voltage sags under load.
class BatteryGraphPainter extends CustomPainter {
  BatteryGraphPainter(this.history, {required this.line, required this.grid});

  final List<double> history;
  final Color line;
  final Color grid;

  static const double lo = 3.3, hi = 4.25;

  double _y(double v, Size s) =>
      s.height - ((v.clamp(lo, hi) - lo) / (hi - lo)) * s.height;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final t in [3.6, 3.7]) {
      canvas.drawLine(
          Offset(0, _y(t, size)), Offset(size.width, _y(t, size)), gridPaint);
    }
    if (history.length < 2) return;
    final path = Path();
    for (var i = 0; i < history.length; i++) {
      final x = i / 119 * size.width;
      final y = _y(history[i], size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  // The history list is updated in place, so a full 120-sample list with a
  // steady voltage would look "unchanged". Telemetry only arrives twice a
  // second, so simply redraw on every rebuild.
  @override
  bool shouldRepaint(covariant BatteryGraphPainter old) => true;
}
