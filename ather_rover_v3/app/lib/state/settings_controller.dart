import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/protocol.dart';

/// Minimal key-value interface so settings can be tested without a device.
abstract class KeyValueStore {
  String? getString(String key);
  double? getDouble(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setDouble(String key, double value);
  Future<void> setBool(String key, bool value);
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, Object>? initial]) : _data = {...?initial};
  final Map<String, Object> _data;

  @override
  String? getString(String key) => _data[key] is String ? _data[key] as String : null;
  @override
  double? getDouble(String key) => _data[key] is double ? _data[key] as double : null;
  @override
  bool? getBool(String key) => _data[key] is bool ? _data[key] as bool : null;
  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }
  @override
  Future<void> setDouble(String key, double value) async {
    _data[key] = value;
  }
  @override
  Future<void> setBool(String key, bool value) async {
    _data[key] = value;
  }
}

class PrefsStore implements KeyValueStore {
  PrefsStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsStore> create() async =>
      PrefsStore(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  double? getDouble(String key) => _prefs.getDouble(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  @override
  Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value);
  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}

@immutable
class AppSettings {
  const AppSettings({
    this.host = defaultHost,
    this.themeMode = ThemeMode.system,
    this.haptics = true,
    this.tiltFullScale = 5.0,
    this.deadZone = 0.08,
    this.expo = 0.3,
    this.onboarded = false,
  });

  static const String defaultHost = '192.168.4.1';

  // Allowed ranges, shared by the sliders and the loader.
  static const double tiltMin = 3.0, tiltMax = 8.0;
  static const double deadZoneMax = 0.25;
  static const double expoMax = 0.8;

  final String host;
  final ThemeMode themeMode;
  final bool haptics;

  /// m/s^2 of tilt for full output. Lower = more sensitive.
  final double tiltFullScale;
  final double deadZone;
  final double expo;

  /// The first-run guide has been seen.
  final bool onboarded;

  AppSettings copyWith({
    String? host,
    ThemeMode? themeMode,
    bool? haptics,
    double? tiltFullScale,
    double? deadZone,
    double? expo,
    bool? onboarded,
  }) =>
      AppSettings(
        host: host ?? this.host,
        themeMode: themeMode ?? this.themeMode,
        haptics: haptics ?? this.haptics,
        tiltFullScale: (tiltFullScale ?? this.tiltFullScale).clamp(tiltMin, tiltMax),
        deadZone: (deadZone ?? this.deadZone).clamp(0.0, deadZoneMax),
        expo: (expo ?? this.expo).clamp(0.0, expoMax),
        onboarded: onboarded ?? this.onboarded,
      );
}

/// Loads, validates and persists [AppSettings].
class SettingsController extends ChangeNotifier {
  SettingsController(this._store);

  final KeyValueStore _store;
  AppSettings _value = const AppSettings();
  AppSettings get value => _value;

  static const _kHost = 'host', _kTheme = 'theme', _kHaptics = 'haptics';
  static const _kTilt = 'tilt', _kDead = 'deadZone', _kExpo = 'expo', _kOnb = 'onboarded';

  /// Reads stored values; anything corrupt or out of range falls back safely.
  void load() {
    final host = _store.getString(_kHost);
    final themeName = _store.getString(_kTheme);
    _value = const AppSettings().copyWith(
      host: (host != null && validateHost(host) == null) ? host : null,
      themeMode: ThemeMode.values.where((m) => m.name == themeName).firstOrNull,
      haptics: _store.getBool(_kHaptics),
      tiltFullScale: _finite(_store.getDouble(_kTilt)),
      deadZone: _finite(_store.getDouble(_kDead)),
      expo: _finite(_store.getDouble(_kExpo)),
      onboarded: _store.getBool(_kOnb),
    );
    notifyListeners();
  }

  static double? _finite(double? v) => (v != null && v.isFinite) ? v : null;

  /// Returns an error message instead of saving an invalid host.
  Future<String?> setHost(String host) async {
    final h = host.trim();
    final err = validateHost(h);
    if (err != null) return err;
    _value = _value.copyWith(host: h);
    notifyListeners();
    await _store.setString(_kHost, h);
    return null;
  }

  Future<void> setThemeMode(ThemeMode m) => _save(_value.copyWith(themeMode: m));
  Future<void> setHaptics(bool on) => _save(_value.copyWith(haptics: on));
  Future<void> setTiltFullScale(double v) => _save(_value.copyWith(tiltFullScale: v));
  Future<void> setDeadZone(double v) => _save(_value.copyWith(deadZone: v));
  Future<void> setExpo(double v) => _save(_value.copyWith(expo: v));
  Future<void> setOnboarded() => _save(_value.copyWith(onboarded: true));

  Future<void> resetDriving() => _save(_value.copyWith(
        tiltFullScale: const AppSettings().tiltFullScale,
        deadZone: const AppSettings().deadZone,
        expo: const AppSettings().expo,
      ));

  Future<void> _save(AppSettings next) async {
    _value = next;
    notifyListeners();
    await Future.wait([
      _store.setString(_kTheme, next.themeMode.name),
      _store.setBool(_kHaptics, next.haptics),
      _store.setDouble(_kTilt, next.tiltFullScale),
      _store.setDouble(_kDead, next.deadZone),
      _store.setDouble(_kExpo, next.expo),
      _store.setBool(_kOnb, next.onboarded),
    ]);
  }
}
