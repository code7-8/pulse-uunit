import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'state/app_controller.dart';
import 'services/demo_api_client.dart';
import 'ui/pulse_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  const demo = bool.fromEnvironment('DEMO_MODE');
  runApp(
    PulseApp(controller: AppController(api: demo ? DemoApiClient() : null)),
  );
}
