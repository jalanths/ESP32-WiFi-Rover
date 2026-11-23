import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/drive_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/trip_screen.dart';
import 'theme.dart';
import 'widgets/status_widgets.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('Drive', Icons.gamepad_outlined, Icons.gamepad_rounded),
  _Dest('Trip', Icons.insights_outlined, Icons.insights_rounded),
  _Dest('Settings', Icons.tune_outlined, Icons.tune_rounded),
];

/// Adaptive navigation: bottom bar on phones in portrait, side rail when the
/// screen is wide (landscape phone, tablet, desktop).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int i) {
    if (i == _index) return;
    Haptics.tap(context);
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final rover = AppScope.of(context).rover;
    final wide = MediaQuery.sizeOf(context).width >= 600;

    // IndexedStack keeps each tab's state (tilt, scroll position) alive.
    final body = IndexedStack(
      index: _index,
      children: const [DriveScreen(), TripScreen(), SettingsScreen()],
    );

    final appBar = AppBar(
      centerTitle: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.electric_moped_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: Tokens.s2),
          const Flexible(child: Text('Ather Rover', overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: [
        ListenableBuilder(
          listenable: rover,
          builder: (context, _) => ConnectionPill(rover: rover),
        ),
        const SizedBox(width: Tokens.s4),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _dests)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _dests)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
