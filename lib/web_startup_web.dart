import 'package:flutter_web_plugins/url_strategy.dart';

import 'web_deep_link.dart';

void configureWebStartup() {
  // Read `?subtask=` / `/#/?subtask=` before path strategy; second pass must not clear session
  // if the query/hash was only visible before [usePathUrlStrategy].
  captureWebDeepLinkForSession(clearStaleWhenUrlEmpty: true);
  usePathUrlStrategy();
  captureWebDeepLinkForSession(clearStaleWhenUrlEmpty: false);
}
