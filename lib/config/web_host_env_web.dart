import 'dart:html' as html;

import 'environment_config.dart';

/// True when built with `DEPLOY_ENV=testing` (see deploy/*.env.example).
bool get isTestWebHost => AppEnvironment.isTesting;

bool get isDeployedWebHost {
  final host = (html.window.location.hostname ?? '').toLowerCase();
  if (host.isEmpty) return false;
  return host != 'localhost' && host != '127.0.0.1';
}

String get webOrigin => html.window.location.origin;
