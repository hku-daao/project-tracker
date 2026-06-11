import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'picked_file_bytes.dart';

/// Web file dialog via [dart:html] so we do not rely on [file_picker]'s plugin registration
/// (which can throw [MissingPluginException] when [FilePickerWeb] is not registered).
Future<PickedFileBytes?> pickOneFileWithBytes() async {
  final files = await pickFilesWithBytes(allowMultiple: false);
  return files.isEmpty ? null : files.first;
}

Future<List<PickedFileBytes>> pickFilesWithBytes({bool allowMultiple = true}) {
  final completer = Completer<List<PickedFileBytes>>();
  var changeTriggered = false;

  // iOS Safari (and some WebKit builds) ignore programmatic .click() on inputs with
  // display:none. Use an off-screen, minimally opaque element instead.
  final input = html.FileUploadInputElement()
    ..multiple = allowMultiple
    ..accept = '*/*'
    ..style.position = 'fixed'
    ..style.left = '0'
    ..style.top = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.opacity = '0.01'
    ..style.overflow = 'hidden';

  void complete(List<PickedFileBytes> value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    input.remove();
  }

  void scheduleCancelIfNoChange() {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!changeTriggered && !completer.isCompleted) {
        changeTriggered = true;
        complete(const []);
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
      complete(const []);
      return;
    }
    () async {
      final picked = <PickedFileBytes>[];
      for (final f in files) {
        final bytes = await _readFileBytes(f);
        if (bytes == null) continue;
        picked.add(PickedFileBytes(name: f.name, bytes: bytes));
      }
      complete(picked);
    }();
  });

  html.document.body!.append(input);
  input.click();

  Future<void>.delayed(const Duration(minutes: 5), () {
    if (!completer.isCompleted) {
      changeTriggered = true;
      html.window.removeEventListener('focus', onWindowFocus);
      complete(const []);
    }
  });

  return completer.future;
}

Future<Uint8List?> _readFileBytes(html.File f) {
  final completer = Completer<Uint8List?>();
  final reader = html.FileReader();
  reader.onError.listen((_) {
    if (!completer.isCompleted) completer.complete(null);
  });
  reader.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final raw = reader.result;
    if (raw is Uint8List) {
      completer.complete(raw);
      return;
    }
    if (raw is ByteBuffer) {
      completer.complete(raw.asUint8List());
      return;
    }
    completer.complete(null);
  });
  reader.readAsArrayBuffer(f);
  return completer.future;
}
