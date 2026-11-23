import 'package:flutter/material.dart';

import 'app.dart';
import 'state/rover_controller.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsController(await PrefsStore.create())..load();
  final rover = RoverController();

  runApp(RoverApp(rover: rover, settings: settings));
}
