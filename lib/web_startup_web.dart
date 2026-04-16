import 'package:flutter_web_plugins/url_strategy.dart';

import 'web_deep_link.dart';

void configureWebStartup() {
  // Read `?subtask=` / `/#/?subtask=` before path strategy mutates history.
  captureWebDeepLinkForSession();
  usePathUrlStrategy();
  captureWebDeepLinkForSession();
}
