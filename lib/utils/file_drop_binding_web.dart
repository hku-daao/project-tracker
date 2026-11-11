import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';

import 'file_drop_binding.dart';
import 'picked_file_bytes.dart';

export 'file_drop_binding.dart';

class _DropReg {
  _DropReg({
    required this.enabled,
    required this.imagesOnly,
    required this.contains,
    required this.onHover,
    required this.onDrop,
    required this.acceptsPaste,
  });

  final bool Function() enabled;
  final bool imagesOnly;
  final bool Function(Offset globalPoint) contains;
  final void Function(bool hovering) onHover;
  final void Function(List<PickedFileBytes> files, int rejectedNonImages)
  onDrop;
  final bool Function()? acceptsPaste;
  bool hovering = false;
}

class _WebFileDropHub {
  static final List<_DropReg> _regs = [];
  static bool _listening = false;
  static _DropReg? _lastImagePointer;

  static void attach(_DropReg reg) {
    _regs.add(reg);
    _ensure();
  }

  static void detach(_DropReg reg) {
    reg.onHover(false);
    _regs.remove(reg);
    if (identical(_lastImagePointer, reg)) _lastImagePointer = null;
  }

  static void _ensure() {
    if (_listening) return;
    _listening = true;
    html.document.onDragOver.listen((event) {
      if (!_isFileDrag(event)) return;
      event.preventDefault();
      final point = _point(event);
      for (final reg in _regs) {
        final hit = reg.enabled() && reg.contains(point);
        if (hit != reg.hovering) {
          reg.hovering = hit;
          reg.onHover(hit);
        }
      }
      if (_regs.any((reg) => reg.hovering)) {
        event.dataTransfer.dropEffect = 'copy';
      }
    });
    html.document.onDrop.listen((event) {
      if (!_isFileDrag(event)) return;
      event.preventDefault();
      final point = _point(event);
      _DropReg? target;
      for (final reg in _regs.reversed) {
        reg.hovering = false;
        reg.onHover(false);
        if (target == null && reg.enabled() && reg.contains(point)) {
          target = reg;
        }
      }
      final files = event.dataTransfer.files;
      if (target == null || files == null || files.isEmpty) return;
      final imagesOnly = target.imagesOnly;
      final onDrop = target.onDrop;
      unawaited(_deliver(files, imagesOnly, onDrop));
    });
    html.document.onDragEnd.listen((_) {
      for (final reg in _regs) {
        if (!reg.hovering) continue;
        reg.hovering = false;
        reg.onHover(false);
      }
    });
    html.EventStreamProvider<html.MouseEvent>('mousedown')
        .forTarget(html.document, useCapture: true)
        .listen(_onPointerDown);
    html.EventStreamProvider<html.ClipboardEvent>('paste')
        .forTarget(html.document, useCapture: true)
        .listen(_onPaste);
  }

  static void _onPointerDown(html.MouseEvent event) {
    final point = _point(event);
    _lastImagePointer = null;
    for (final reg in _regs.reversed) {
      if (!reg.imagesOnly || !reg.enabled()) continue;
      if (!reg.contains(point)) continue;
      _lastImagePointer = reg;
      break;
    }
  }

  static void _onPaste(html.ClipboardEvent event) {
    final data = event.clipboardData;
    if (data == null) return;
    final paths = _imagePaths(
      _safeGet(data, 'text/plain'),
      _safeGet(data, 'text/uri-list'),
    );
    List<html.File> files = const [];
    try {
      files = _imageFilesFromClipboard(data, paths.isNotEmpty);
    } catch (_) {}
    if (files.isEmpty && paths.isEmpty) return;
    final target = _pasteTarget();
    if (target == null) return;
    event.preventDefault();
    event.stopPropagation();
    final onDrop = target.onDrop;
    final preferredName = paths.isEmpty ? null : _basename(paths.first);
    if (files.isNotEmpty) {
      unawaited(() async {
        final delivered = await _deliver(
          files,
          true,
          onDrop,
          preferredName: preferredName,
          notifyWhenEmpty: paths.isEmpty,
        );
        if (delivered || paths.isEmpty) return;
        await _pasteFromClipboardRead(onDrop, paths);
      }());
      return;
    }
    unawaited(_pasteFromClipboardRead(onDrop, paths));
  }

  static _DropReg? _pasteTarget() {
    for (final reg in _regs.reversed) {
      if (_pasteTargets(reg)) return reg;
    }
    final last = _lastImagePointer;
    if (last != null &&
        _regs.contains(last) &&
        last.imagesOnly &&
        last.enabled()) {
      return last;
    }
    return null;
  }

  static bool _pasteTargets(_DropReg reg) {
    if (!reg.imagesOnly || !reg.enabled()) return false;
    if (reg.acceptsPaste?.call() == true) return true;
    final active = html.document.activeElement;
    if (active is! html.Element) return false;
    final rect = active.getBoundingClientRect();
    final width = rect.width.toDouble();
    final height = rect.height.toDouble();
    if (width <= 0 || height <= 0) return false;
    return reg.contains(
      Offset(rect.left.toDouble() + width / 2, rect.top.toDouble() + height / 2),
    );
  }

  static List<html.File> _imageFilesFromClipboard(
    html.DataTransfer data,
    bool textLooksLikeImage,
  ) {
    final raw = <html.File>[];
    void take(html.File? file) {
      if (file == null) return;
      raw.add(file);
    }

    final files = data.files;
    if (files != null) {
      for (final file in files) {
        take(file);
      }
    }
    final items = data.items;
    if (items != null) {
      final count = items.length ?? 0;
      for (var i = 0; i < count; i++) {
        final item = items.item(i);
        if ((item.kind ?? '').toLowerCase() != 'file') continue;
        take(item.getAsFile());
      }
    }

    final out = <html.File>[];
    final seen = <String>{};
    for (final file in raw) {
      final opaque =
          file.type.isEmpty || file.type.toLowerCase() == 'application/octet-stream';
      if (!_isImage(file.name, file.type) && !(textLooksLikeImage && opaque)) {
        continue;
      }
      final key = '${file.name}:${file.size}';
      if (!seen.add(key)) continue;
      out.add(file);
    }
    return out;
  }

  static String _safeGet(html.DataTransfer data, String type) {
    try {
      return data.getData(type);
    } catch (_) {
      return '';
    }
  }

  static List<String> _imagePaths(String plain, String uriList) {
    final out = <String>[];
    void add(String raw) {
      var text = raw.trim();
      if (text.isEmpty) return;
      final lower = text.toLowerCase();
      if (lower.startsWith('file:')) {
        final parsed = Uri.tryParse(text);
        if (parsed != null && parsed.scheme == 'file' && parsed.path.isNotEmpty) {
          text = Uri.decodeFull(parsed.path);
        }
      }
      if (!_looksLikeImagePath(text)) return;
      out.add(text);
    }

    final plainLines = plain.split(RegExp(r'\r?\n'));
    if (plainLines.length == 1) {
      add(plain);
    } else {
      for (final line in plainLines) {
        add(line);
      }
    }
    for (final line in uriList.split(RegExp(r'\r?\n'))) {
      add(line);
    }
    return out;
  }

  static bool _looksLikeImagePath(String text) {
    if (!_isImage(text, null)) return false;
    final lower = text.toLowerCase();
    return lower.startsWith('/') ||
        lower.startsWith('file:') ||
        lower.startsWith('~/');
  }

  static String _basename(String path) {
    var text = path.trim();
    final lower = text.toLowerCase();
    if (lower.startsWith('file:')) {
      final parsed = Uri.tryParse(text);
      if (parsed != null && parsed.scheme == 'file' && parsed.path.isNotEmpty) {
        text = Uri.decodeFull(parsed.path);
      }
    }
    final slash = text.lastIndexOf(RegExp(r'[\\/]'));
    if (slash >= 0 && slash < text.length - 1) {
      text = text.substring(slash + 1);
    }
    return text;
  }

  static bool _isFileDrag(html.Event event) {
    if (event is! html.MouseEvent) return false;
    final types = event.dataTransfer.types;
    if (types == null) return false;
    for (final type in types) {
      if (type.toString().toLowerCase() == 'files') return true;
    }
    return false;
  }

  static Offset _point(html.Event event) {
    final mouse = event as html.MouseEvent;
    return Offset(mouse.client.x.toDouble(), mouse.client.y.toDouble());
  }

  static Future<bool> _deliver(
    List<html.File> files,
    bool imagesOnly,
    void Function(List<PickedFileBytes> files, int rejectedNonImages) onDrop, {
    String? preferredName,
    bool notifyWhenEmpty = true,
  }) async {
    final accepted = <PickedFileBytes>[];
    var rejected = 0;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final image =
          _isImage(file.name, file.type) ||
          (preferredName != null && _isImage(preferredName, file.type));
      if (imagesOnly && !image) {
        rejected++;
        continue;
      }
      final bytes = await _readFileBytes(file);
      if (bytes == null || bytes.isEmpty) continue;
      accepted.add(
        PickedFileBytes(
          name: _fileName(
            file,
            image,
            accepted.length,
            preferredName: preferredName,
          ),
          bytes: bytes,
        ),
      );
    }
    if (accepted.isEmpty && !notifyWhenEmpty) return false;
    onDrop(accepted, rejected);
    return accepted.isNotEmpty;
  }

  static Future<void> _pasteFromClipboardRead(
    void Function(List<PickedFileBytes> files, int rejectedNonImages) onDrop,
    List<String> paths,
  ) async {
    try {
      final items = (await _jsClipboardRead().toDart).toDart;
      for (final raw in items) {
        final item = _JsClipItem(raw);
        String? imageType;
        for (final type in item.types.toDart) {
          final name = type.toDart.toLowerCase();
          if (name.startsWith('image/')) {
            imageType = type.toDart;
            break;
          }
        }
        if (imageType == null) continue;
        final blob = _JsBlob(await item.getType(imageType.toJS).toDart);
        final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
        if (bytes.isEmpty) continue;
        final preferred = paths.isEmpty ? '' : _basename(paths.first);
        final name = _isImage(preferred, null)
            ? preferred
            : 'pasted.${_imageExt(imageType)}';
        onDrop([PickedFileBytes(name: name, bytes: bytes)], 0);
        return;
      }
    } catch (_) {}
    onDrop(const [], -1);
  }

  static String _fileName(
    html.File file,
    bool image,
    int index, {
    String? preferredName,
  }) {
    var raw = file.name.trim();
    if (raw.contains('/') || raw.contains('\\')) raw = _basename(raw);
    if (!image) return raw.isEmpty ? 'file' : raw;
    final ext = _imageExt(file.type);
    final preferred = (preferredName ?? '').trim();
    if (raw.isEmpty || !_isImage(raw, null)) {
      if (index == 0 && _isImage(preferred, null)) return _basename(preferred);
      return index == 0 ? 'pasted.$ext' : 'pasted-${index + 1}.$ext';
    }
    if (!raw.contains('.')) return '$raw.$ext';
    return raw;
  }

  static String _imageExt(String? mime) {
    switch (mime?.toLowerCase().trim()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/bmp':
        return 'bmp';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
      default:
        return 'png';
    }
  }

  static bool _isImage(String name, String? mime) {
    final type = mime?.toLowerCase().trim() ?? '';
    if (type.startsWith('image/')) return true;
    final n = name.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.bmp') ||
        n.endsWith('.heic') ||
        n.endsWith('.heif');
  }
}

class _WebFileDropBinding implements FileDropBindingHandle {
  _WebFileDropBinding(this._reg);

  final _DropReg _reg;

  @override
  void dispose() => _WebFileDropHub.detach(_reg);
}

FileDropBindingHandle bindFileDrop({
  required bool Function() enabled,
  required bool imagesOnly,
  required bool Function(Offset globalPoint) contains,
  required void Function(bool hovering) onHover,
  required void Function(List<PickedFileBytes> files, int rejectedNonImages)
  onDrop,
  bool Function()? acceptsPaste,
}) {
  final reg = _DropReg(
    enabled: enabled,
    imagesOnly: imagesOnly,
    contains: contains,
    onHover: onHover,
    onDrop: onDrop,
    acceptsPaste: acceptsPaste,
  );
  _WebFileDropHub.attach(reg);
  return _WebFileDropBinding(reg);
}

Future<Uint8List?> _readFileBytes(html.File file) {
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
  reader.readAsArrayBuffer(file);
  return completer.future;
}

@JS('navigator.clipboard.read')
external JSPromise<JSArray<JSObject>> _jsClipboardRead();

extension type _JsClipItem(JSObject _) implements JSObject {
  external JSArray<JSString> get types;
  external JSPromise<JSObject> getType(JSString type);
}

extension type _JsBlob(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
