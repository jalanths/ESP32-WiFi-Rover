import 'package:flutter/material.dart';

import 'rover_client.dart';

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

  @override
  void initState() {
    super.initState();
    rover.addListener(() {
      if (mounted) setState(() {});
    });
    rover.connect();
  }

  @override
  void dispose() {
    rover.dispose();
    super.dispose();
  }

  Future<void> _editHost() async {
    final controller = TextEditingController(text: rover.host);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rover address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(helperText: 'Default is 192.168.4.1'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
      default:
        return rover.state;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ather Rover'),
        actions: [
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
                          Icon(Icons.circle, size: 12, color: _stateColor(context)),
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
                      Row(
                        children: [
                          const Icon(Icons.battery_full, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: rover.connected ? rover.percent / 100 : 0,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(rover.connected
                              ? '${rover.percent}%  ${rover.volts.toStringAsFixed(2)} V'
                              : '--'),
                        ],
                      ),
                      if (rover.error != null && !rover.connected) ...[
                        const SizedBox(height: 8),
                        Text(rover.error!, style: TextStyle(color: scheme.error)),
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

              // Joystick
              Expanded(
                child: Center(
                  child: Joystick(
                    enabled: rover.connected,
                    onChanged: rover.drive,
                  ),
                ),
              ),

              // Stop
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE24B4A)),
                  onPressed: rover.connected ? rover.stop : null,
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
  const Joystick({super.key, required this.onChanged, this.enabled = true, this.size = 240});

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
            Positioned(top: 10, child: Icon(Icons.keyboard_arrow_up, color: scheme.outline)),
            Positioned(bottom: 10, child: Icon(Icons.keyboard_arrow_down, color: scheme.outline)),
            Positioned(left: 10, child: Icon(Icons.keyboard_arrow_left, color: scheme.outline)),
            Positioned(right: 10, child: Icon(Icons.keyboard_arrow_right, color: scheme.outline)),
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
