import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/drive_math.dart';
import '../../core/protocol.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/battery_gauge.dart';
import '../widgets/joystick.dart';
import '../widgets/status_widgets.dart';

/// Main driving screen. Portrait: stacked. Landscape / tablet: info on the
/// left, joystick on the right where the thumb is.
class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  bool _tilt = false;
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  double _ax0 = 0, _ay0 = 0;
  bool _haveNeutral = false;
  DriveInput _tiltInput = DriveInput.zero;

  @override
  void dispose() {
    _tiltSub?.cancel();
    super.dispose();
  }

  // ---------- input ----------

  void _onStick(double dx, double dy) {
    final scope = AppScope.read(context);
    final s = scope.settings.value;
    scope.rover.drive(shapeJoystick(dx, dy, deadZone: s.deadZone, expo: s.expo));
  }

  void _setTilt(bool on) {
    final scope = AppScope.read(context);
    Haptics.medium(context);
    _tiltSub?.cancel();
    _tiltSub = null;
    scope.rover.drive(DriveInput.zero);
    setState(() {
      _tilt = on;
      _haveNeutral = false;
      _tiltInput = DriveInput.zero;
    });
    if (!on) return;

    _tiltSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      (e) {
        if (!_haveNeutral) {
          // the pose when tilt is switched on counts as "stopped"
          _ax0 = e.x;
          _ay0 = e.y;
          _haveNeutral = true;
          return;
        }
        final s = scope.settings.value;
        final input = tiltToDrive(
          ax: e.x,
          ay: e.y,
          neutralX: _ax0,
          neutralY: _ay0,
          fullScale: s.tiltFullScale,
        );
        scope.rover.drive(input);
        if (mounted) setState(() => _tiltInput = input);
      },
      onError: (Object _) {
        if (!mounted) return;
        _setTilt(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This phone has no motion sensor. Tilt is off.')),
        );
      },
      cancelOnError: true,
    );
  }

  void _stop() {
    Haptics.heavy(context);
    if (_tilt) _setTilt(false);
    AppScope.read(context).rover.stop();
  }

  // ---------- layout ----------

  @override
  Widget build(BuildContext context) {
    final rover = AppScope.of(context).rover;
    return ListenableBuilder(
      listenable: rover,
      builder: (context, _) {
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > box.maxHeight && box.maxWidth >= 560;
          return wide ? _wideLayout(box) : _narrowLayout(box);
        });
      },
    );
  }

  Widget _narrowLayout(BoxConstraints box) {
    final stick = (box.maxWidth * 0.68).clamp(180.0, 300.0);
    // STOP sits outside the scroll view so it is always on screen,
    // even with large system text.
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s2, Tokens.s4, Tokens.s4),
            children: [
              _statusAndBattery(),
              const SizedBox(height: Tokens.s4),
              _modeSelector(),
              const SizedBox(height: Tokens.s3),
              _actions(),
              const SizedBox(height: Tokens.s5),
              Center(child: _controlArea(stick)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s2, Tokens.s4, Tokens.s3),
          child: _bottomBar(),
        ),
      ],
    );
  }

  Widget _wideLayout(BoxConstraints box) {
    final stick = (box.maxHeight * 0.62).clamp(160.0, 320.0);
    return Padding(
      padding: const EdgeInsets.all(Tokens.s4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: ListView(
              children: [
                _statusAndBattery(),
                const SizedBox(height: Tokens.s3),
                _modeSelector(),
                const SizedBox(height: Tokens.s3),
                _actions(),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s5),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: _controlArea(stick)),
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                _bottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- sections ----------

  Widget _statusAndBattery() {
    final rover = AppScope.of(context).rover;
    final live = rover.isConnected ? rover.telemetry : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BatteryGauge(percent: live?.percent, volts: live?.volts, size: 118),
        const SizedBox(width: Tokens.s4),
        Expanded(child: StatusBanner(rover: rover)),
      ],
    );
  }

  Widget _modeSelector() {
    final rover = AppScope.of(context).rover;
    return Semantics(
      label: 'Ride mode',
      child: SegmentedButton<RideMode>(
        showSelectedIcon: false,
        segments: [
          for (final m in RideMode.values)
            ButtonSegment(
              value: m,
              label: Text(m.label),
              tooltip: '${m.label}: up to ${m.maxPowerPercent}% power',
              icon: Icon(switch (m) {
                RideMode.eco => Icons.eco_rounded,
                RideMode.ride => Icons.two_wheeler_rounded,
                RideMode.sport => Icons.bolt_rounded,
              }),
            ),
        ],
        selected: {rover.mode},
        onSelectionChanged: rover.isConnected
            ? (s) {
                Haptics.tap(context);
                rover.setMode(s.first);
              }
            : null,
      ),
    );
  }

  Widget _actions() {
    final rover = AppScope.of(context).rover;
    final t = rover.telemetry;
    final on = rover.isConnected;
    final act = t?.activity ?? Activity.none;
    final drivable = rover.canDrive;

    final tiles = [
      ActionTile(
        icon: Icons.rocket_launch_rounded,
        label: act == Activity.cooldown ? 'Cooling' : 'Turbo',
        active: act == Activity.turbo,
        tooltip: '3 s of full power, then 10 s cool-down',
        onPressed: drivable && act != Activity.cooldown && act != Activity.turbo
            ? () {
                Haptics.medium(context);
                rover.turbo();
              }
            : null,
      ),
      ActionTile(
        icon: act == Activity.recording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
        label: act == Activity.recording ? 'Stop rec' : 'Record',
        active: act == Activity.recording,
        tooltip: 'Record up to 60 s of driving',
        onPressed: drivable && act != Activity.playing
            ? () {
                Haptics.tap(context);
                rover.toggleRecord();
              }
            : null,
      ),
      ActionTile(
        icon: act == Activity.playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        label: act == Activity.playing ? 'Stop' : 'Replay',
        active: act == Activity.playing,
        tooltip: (t?.pathSeconds ?? 0) > 0
            ? 'Replay the ${t!.pathSeconds} s recorded path'
            : 'Record a path first',
        onPressed: drivable && act != Activity.recording && (t?.pathSeconds ?? 0) > 0
            ? () {
                Haptics.tap(context);
                rover.togglePlay();
              }
            : null,
      ),
      ActionTile(
        icon: Icons.wb_twilight_rounded,
        label: 'Find',
        tooltip: 'Flash the rover lights',
        onPressed: on
            ? () {
                Haptics.tap(context);
                rover.find();
              }
            : null,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: Tokens.s2),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  Widget _controlArea(double size) {
    final rover = AppScope.of(context).rover;
    final enabled = rover.canDrive;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _tilt
          ? _TiltIndicator(key: const ValueKey('tilt'), input: _tiltInput, size: size)
          : Joystick(
              key: const ValueKey('stick'),
              size: size,
              enabled: enabled,
              onEngage: () => Haptics.tap(context),
              onChanged: _onStick,
            ),
    );
  }

  Widget _bottomBar() {
    final rover = AppScope.of(context).rover;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
                textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
              ),
              onPressed: _stop,
              icon: const Icon(Icons.pan_tool_rounded),
              label: const Text('STOP'),
            ),
          ),
        ),
        const SizedBox(width: Tokens.s3),
        SizedBox(
          height: 56,
          child: FilledButton.tonalIcon(
            onPressed: rover.canDrive || _tilt ? () => _setTilt(!_tilt) : null,
            icon: Icon(_tilt ? Icons.gamepad_rounded : Icons.screen_rotation_rounded),
            label: Text(_tilt ? 'Stick' : 'Tilt'),
          ),
        ),
      ],
    );
  }
}

/// Bubble level that shows what tilt is sending.
class _TiltIndicator extends StatelessWidget {
  const _TiltIndicator({super.key, required this.input, required this.size});

  final DriveInput input;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = size / 2;
    const dot = 28.0;
    return Semantics(
      label: 'Tilt steering on. Tilt the phone to drive. '
          'Steer ${(input.x * 100).round()} percent, throttle ${(input.y * 100).round()} percent.',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHigh,
                border: Border.all(color: scheme.primary, width: 2),
              ),
            ),
            Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            Transform.translate(
              offset: Offset(input.x * (r - dot), -input.y * (r - dot)),
              child: Container(
                width: dot * 2,
                height: dot * 2,
                decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
              ),
            ),
            Positioned(
              bottom: Tokens.s4,
              child: Text('Tilt to drive',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}
