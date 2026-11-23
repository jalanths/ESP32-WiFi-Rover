import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/protocol.dart';
import '../../state/rover_controller.dart';
import '../../state/settings_controller.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'onboarding_screen.dart';

const String kAppVersion = '3.0.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  bool _hostInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hostInit) {
      _host = TextEditingController(text: AppScope.of(context).settings.value.host);
      _hostInit = true;
    }
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final scope = AppScope.read(context);
    FocusScope.of(context).unfocus();
    final err = await scope.settings.setHost(_host.text);
    if (err != null || !mounted) return;
    Haptics.tap(context);
    await scope.rover.connect(host: scope.settings.value.host);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.rover, scope.settings]),
      builder: (context, _) {
        final rover = scope.rover;
        final settings = scope.settings;
        final s = settings.value;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
          children: [
            const _Header('Connection'),
            _connectionCard(rover),
            const _Header('Driving feel'),
            _sliderTile(
              icon: Icons.blur_circular_rounded,
              title: 'Joystick dead zone',
              subtitle: 'Ignore tiny thumb movements near the centre',
              value: s.deadZone,
              min: 0,
              max: AppSettings.deadZoneMax,
              divisions: 25,
              label: '${(s.deadZone * 100).round()}%',
              onChanged: settings.setDeadZone,
            ),
            _sliderTile(
              icon: Icons.show_chart_rounded,
              title: 'Joystick expo',
              subtitle: 'Higher = gentler near the centre, same top speed',
              value: s.expo,
              min: 0,
              max: AppSettings.expoMax,
              divisions: 16,
              label: '${(s.expo * 100).round()}%',
              onChanged: settings.setExpo,
            ),
            _sliderTile(
              icon: Icons.screen_rotation_rounded,
              title: 'Tilt for full speed',
              subtitle: 'Smaller = more sensitive',
              value: s.tiltFullScale,
              min: AppSettings.tiltMin,
              max: AppSettings.tiltMax,
              divisions: 10,
              label: 'about ${_tiltDegrees(s.tiltFullScale)}°',
              onChanged: settings.setTiltFullScale,
            ),
            _trimTile(rover),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: settings.resetDriving,
                  child: const Text('Restore default feel'),
                ),
              ),
            ),
            const _Header('App'),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Theme'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Tokens.s2),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => settings.setThemeMode(v.first),
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Haptic feedback'),
              subtitle: const Text('Buzz on STOP, mode changes and buttons'),
              value: s.haptics,
              onChanged: settings.setHaptics,
            ),
            const _Header('About'),
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: const Text('Rover firmware'),
              subtitle: Text(rover.telemetry == null
                  ? 'Connect to read the version'
                  : '${rover.telemetry!.firmware} · ${rover.telemetry!.selfTest.message}'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Show the quick guide'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OnboardingScreen(onDone: () => Navigator.of(context).pop()),
              )),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('About this app'),
              subtitle: const Text('Version $kAppVersion'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Ather Rover',
                applicationVersion: kAppVersion,
                applicationIcon: const Icon(Icons.electric_moped_rounded, size: 40),
                children: const [
                  Text('Wi-Fi controller for the ESP32 Wi-Fi rover. '
                      'Works with rover firmware 2.0 over WebSocket port 81.'),
                ],
              ),
            ),
            const SizedBox(height: Tokens.s5),
          ],
        );
      },
    );
  }

  Widget _connectionCard(RoverController rover) {
    final busy = rover.phase == LinkPhase.connecting;
    final online = rover.phase == LinkPhase.connected;
    final retrying = rover.phase == LinkPhase.reconnecting;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _host,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enabled: !online && !busy,
              decoration: const InputDecoration(
                labelText: 'Rover address',
                helperText: 'Default 192.168.4.1 on the ATHER-ROVER Wi-Fi',
                prefixIcon: Icon(Icons.router_outlined),
                border: OutlineInputBorder(),
              ),
              validator: validateHost,
              onFieldSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: Tokens.s3),
            Row(
              children: [
                Expanded(
                  child: online || retrying
                      ? OutlinedButton.icon(
                          onPressed: rover.disconnect,
                          icon: const Icon(Icons.link_off_rounded),
                          label: Text(retrying ? 'Stop retrying' : 'Disconnect'),
                        )
                      : FilledButton.icon(
                          onPressed: busy ? null : _connect,
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.link_rounded),
                          label: Text(busy ? 'Connecting' : 'Connect'),
                        ),
                ),
              ],
            ),
            if (rover.errorMessage != null && !online) ...[
              const SizedBox(height: Tokens.s2),
              Text(rover.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trimTile(RoverController rover) {
    final on = rover.isConnected;
    final t = rover.trim;
    final side = t.abs() < 0.005 ? 'centred' : (t > 0 ? 'corrects a right drift' : 'corrects a left drift');
    return ListTile(
      leading: const Icon(Icons.straighten_rounded),
      title: const Text('Straight-line trim'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(on
              ? 'Saved on the rover. ${(t * 100).round()}% ($side)'
              : 'Connect to adjust. Saved on the rover.'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: t.clamp(-Commands.trimLimit, Commands.trimLimit),
                  min: -Commands.trimLimit,
                  max: Commands.trimLimit,
                  divisions: 60,
                  label: '${(t * 100).round()}%',
                  semanticFormatterCallback: (v) => 'Trim ${(v * 100).round()} percent',
                  onChanged: on ? rover.previewTrim : null,
                  onChangeEnd: on ? rover.setTrim : null,
                ),
              ),
              IconButton(
                tooltip: 'Reset trim to 0',
                onPressed: on && t != 0 ? () => rover.setTrim(0) : null,
                icon: const Icon(Icons.center_focus_strong_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$subtitle · $label'),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// Rough tilt angle for a given m/s^2: asin(a / g).
  static int _tiltDegrees(double a) =>
      (math.asin((a / 9.81).clamp(0.0, 1.0)) * 180 / math.pi).round();
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s5, Tokens.s4, Tokens.s2),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
