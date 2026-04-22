import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'picked_file_bytes.dart';

/// Web file dialog via [dart:html] so we do not rely on [file_picker]'s plugin registration
/// (which can throw [MissingPluginException] when [FilePickerWeb] is not registered).
Future<PickedFileBytes?> pickOneFileWithBytes() {
  final completer = Completer<PickedFileBytes?>();
  var changeTriggered = false;

  // iOS Safari (and some WebKit builds) ignore programmatic .click() on inputs with
  // display:none. Use an off-screen, minimally opaque element instead.
  final input = html.FileUploadInputElement()
    ..multiple = false
    ..accept = '*/*'
    ..style.position = 'fixed'
    ..style.left = '0'
    ..style.top = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.opacity = '0.01'
    ..style.overflow = 'hidden';

  void complete(PickedFileBytes? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    input.remove();
  }

  void scheduleCancelIfNoChange() {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!changeTriggered && !completer.isCompleted) {
        changeTriggered = true;
        complete(null);
      }
    });
  }

  void onWindowFocus(html.Event _) {
    html.window.removeEventListener('focus', onWindowFocus);
    scheduleCancelIfNoChange();
  }

  html.window.addEventListener('focus', onWindowFocus);

  input.onChange.listen((_) {
    if (changeTriggered) return;
    changeTriggered = true;
    html.window.removeEventListener('focus', onWindowFocus);

    final files = input.files;
    if (files == null || files.isEmpty) {
      complete(null);
      return;
    }
    final f = files.first;
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      if (completer.isCompleted) return;
      final raw = reader.result;
      if (raw is Uint8List) {
        if (raw.isEmpty) {
          complete(null);
        } else {
          complete(PickedFileBytes(name: f.name, bytes: raw));
        }
        return;
      }
      if (raw is ByteBuffer) {
        final bytes = raw.asUint8List();
        if (bytes.isEmpty) {
          complete(null);
        } else {
          complete(PickedFileBytes(name: f.name, bytes: bytes));
        }
        return;
      }
      complete(null);
    });
    reader.readAsArrayBuffer(f);
  });

  html.document.body!.append(input);
  input.click();

  Future<void>.delayed(const Duration(minutes: 5), () {
    if (!completer.isCompleted) {
      changeTriggered = true;
      html.window.removeEventListener('focus', onWindowFocus);
      complete(null);
    }
  });

  return completer.future;
}
