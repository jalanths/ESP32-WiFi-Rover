import 'package:flutter/material.dart';

import '../../core/protocol.dart';
import '../../state/rover_controller.dart';
import '../theme.dart';

/// Coloured card with the rover's state. Cross-fades when the state changes.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.rover});

  final RoverController rover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (String title, String detail, Severity sev) = switch (rover.phase) {
      LinkPhase.disconnected => (
          'Not connected',
          rover.errorMessage ?? 'Join the ATHER-ROVER Wi-Fi, then tap Connect.',
          Severity.info,
        ),
      LinkPhase.connecting => ('Connecting...', 'Reaching ${rover.host}', Severity.info),
      LinkPhase.reconnecting => (
          'Reconnecting',
          rover.errorMessage ?? 'Trying again shortly',
          Severity.warning,
        ),
      LinkPhase.connected when rover.isStale => (
          'Signal weak',
          'No data from the rover. Move closer.',
          Severity.warning,
        ),
      LinkPhase.connected when rover.telemetry == null => (
          'Connected',
          'Waiting for the first reading...',
          Severity.info,
        ),
      LinkPhase.connected => (
          rover.telemetry!.state.label,
          rover.telemetry!.state.detail,
          rover.telemetry!.state.severity,
        ),
    };
    final color = severityColor(scheme, sev);

    return Semantics(
      liveRegion: true,
      label: 'Status: $title. $detail',
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Container(
          key: ValueKey('$title|$detail'),
          width: double.infinity,
          padding: const EdgeInsets.all(Tokens.s4),
          decoration: BoxDecoration(
            color: color.withAlpha(36),
            borderRadius: BorderRadius.circular(Tokens.radius),
            border: Border.all(color: color.withAlpha(110)),
          ),
          child: Row(
            children: [
              Icon(severityIcon(sev), color: color, size: 28),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small chip in the app bar: link state at a glance.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.rover});

  final RoverController rover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (String label, Color color, bool busy) = switch (rover.phase) {
      LinkPhase.connected when rover.isStale =>
        ('Weak', severityColor(scheme, Severity.warning), false),
      LinkPhase.connected => ('Online', scheme.primary, false),
      LinkPhase.connecting => ('Connecting', scheme.tertiary, true),
      LinkPhase.reconnecting => ('Retrying', severityColor(scheme, Severity.warning), true),
      LinkPhase.disconnected => ('Offline', scheme.outline, false),
    };

    return Semantics(
      label: 'Connection $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Icon + big value + caption. Used on the Trip screen.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color ?? scheme.primary),
              const SizedBox(height: Tokens.s2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
              Text(label,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square action button with icon and label; shows an "active" state.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final bg = active ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = active
        ? scheme.onPrimary
        : (enabled ? scheme.onSurface : scheme.onSurface.withAlpha(97));

    final tile = Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64, minWidth: Tokens.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Tokens.s2, horizontal: Tokens.s1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(height: Tokens.s1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}
