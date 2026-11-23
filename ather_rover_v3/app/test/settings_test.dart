import 'package:ather_rover/state/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults when nothing is stored', () {
    final c = SettingsController(MemoryStore())..load();
    expect(c.value.host, AppSettings.defaultHost);
    expect(c.value.themeMode, ThemeMode.system);
    expect(c.value.haptics, isTrue);
    expect(c.value.onboarded, isFalse);
  });

  test('saved values survive a reload', () async {
    final store = MemoryStore();
    final c = SettingsController(store)..load();
    expect(await c.setHost('10.0.0.7'), isNull);
    await c.setThemeMode(ThemeMode.dark);
    await c.setHaptics(false);
    await c.setDeadZone(0.15);
    await c.setOnboarded();

    final again = SettingsController(store)..load();
    expect(again.value.host, '10.0.0.7');
    expect(again.value.themeMode, ThemeMode.dark);
    expect(again.value.haptics, isFalse);
    expect(again.value.deadZone, closeTo(0.15, 1e-9));
    expect(again.value.onboarded, isTrue);
  });

  test('invalid host is refused and not saved', () async {
    final store = MemoryStore();
    final c = SettingsController(store)..load();
    expect(await c.setHost('999.1.1.1'), isNotNull);
    expect(c.value.host, AppSettings.defaultHost);
    expect(store.getString('host'), isNull);
  });

  test('corrupt or out-of-range stored values fall back safely', () {
    final c = SettingsController(MemoryStore({
      'host': 'not a host!',
      'theme': 'purple',
      'tilt': 99.0,
      'deadZone': double.nan,
      'expo': -3.0,
    }))
      ..load();
    expect(c.value.host, AppSettings.defaultHost);
    expect(c.value.themeMode, ThemeMode.system);
    expect(c.value.tiltFullScale, AppSettings.tiltMax);
    expect(c.value.deadZone, const AppSettings().deadZone);
    expect(c.value.expo, 0);
  });
}
