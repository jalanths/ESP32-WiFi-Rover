import 'package:flutter/material.dart';

import '../../core/drive_math.dart';
import '../../core/protocol.dart';
import '../../state/rover_controller.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/status_widgets.dart';
import '../widgets/voltage_chart.dart';

/// Trip stats, live voltage chart and the event log.
class TripScreen extends StatelessWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rover = AppScope.of(context).rover;
    return ListenableBuilder(
      listenable: rover,
      builder: (context, _) {
        final t = rover.telemetry;
        final width = MediaQuery.sizeOf(context).width;
        final columns = width >= 560 ? 3 : 2;
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;

        final stats = <Widget>[
          StatTile(
            icon: Icons.timer_outlined,
            value: t == null ? '--' : formatDuration(t.driveSeconds),
            label: 'Drive time',
          ),
          StatTile(
            icon: Icons.route_rounded,
            value: t == null
                ? '--'
                : (t.rangeMinutes == null ? 'Learning' : '${t.rangeMinutes} min'),
            label: 'Range left (after 1 min of driving)',
          ),
          StatTile(
            icon: Icons.battery_charging_full_rounded,
            value: t == null ? '--' : '${t.usedPercent}%',
            label: 'Battery used',
          ),
          StatTile(
            icon: Icons.south_rounded,
            value: t?.minVolts == null ? '--' : '${t!.minVolts!.toStringAsFixed(2)} V',
            label: 'Lowest voltage',
            color: (t?.minVolts ?? 9) < 3.7 ? severityColor(scheme, Severity.warning) : null,
          ),
          StatTile(
            icon: Icons.gesture_rounded,
            value: t == null ? '--' : '${t.pathSeconds} s',
            label: 'Recorded path',
          ),
          StatTile(
            icon: Icons.memory_rounded,
            value: t?.firmware ?? '--',
            label: t == null ? 'Firmware' : 'Firmware · ${t.selfTest.message}',
            color: t != null && !t.selfTest.passed
                ? severityColor(scheme, Severity.warning)
                : null,
          ),
        ];

        return ListView(
          padding: const EdgeInsets.all(Tokens.s4),
          children: [
            if (t != null && !t.hasTripData)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: Text(
                  'This rover runs firmware ${t.firmware}. Flash firmware 2.0 for trip stats.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            // Wrap instead of a fixed-ratio grid: tiles grow with large text
            LayoutBuilder(builder: (context, box) {
              final tileW = (box.maxWidth - Tokens.s2 * (columns - 1)) / columns;
              return Wrap(
                spacing: Tokens.s2,
                runSpacing: Tokens.s2,
                children: [for (final w in stats) SizedBox(width: tileW, child: w)],
              );
            }),
            const SizedBox(height: Tokens.s4),
            _Section(
              title: 'Battery voltage, last 60 s',
              footer: Wrap(
                spacing: Tokens.s4,
                children: [
                  _Legend(color: severityColor(scheme, Severity.warning), text: '3.7 V limp'),
                  _Legend(color: scheme.error, text: '3.6 V cut-off'),
                ],
              ),
              child: VoltageChart(volts: [for (final s in rover.history) s.volts]),
            ),
            const SizedBox(height: Tokens.s4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: rover.isConnected ? () => _confirmReset(context, rover) : null,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset trip'),
              ),
            ),
            const SizedBox(height: Tokens.s4),
            _EventLog(rover: rover),
          ],
        );
      },
    );
  }

  Future<void> _confirmReset(BuildContext context, RoverController rover) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('Reset trip?'),
        content: const Text('Drive time, battery used, lowest voltage and range start again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) rover.resetTrip();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.footer});

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Tokens.s3),
            child,
            if (footer != null) ...[const SizedBox(height: Tokens.s2), footer!],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.rover});

  final RoverController rover;

  @override
  Widget build(BuildContext context) {
    final events = rover.events;
    final scheme = Theme.of(context).colorScheme;
    final loc = MaterialLocalizations.of(context);

    return _Section(
      title: 'Event log',
      footer: events.isEmpty
          ? null
          : TextButton.icon(
              onPressed: rover.clearEvents,
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('Clear log'),
            ),
      child: events.isEmpty
          ? Text('Nothing yet. Connection changes and warnings appear here.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          : Column(
              children: [
                for (final e in events.take(20))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(severityIcon(e.severity), color: severityColor(scheme, e.severity)),
                    title: Text(e.message),
                    trailing: Text(
                      loc.formatTimeOfDay(TimeOfDay.fromDateTime(e.time)),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
    );
  }
}
