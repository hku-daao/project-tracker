import 'dart:async';
import 'dart:html' as html;
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
  });

  final bool Function() enabled;
  final bool imagesOnly;
  final bool Function(Offset globalPoint) contains;
  final void Function(bool hovering) onHover;
  final void Function(List<PickedFileBytes> files, int rejectedNonImages)
  onDrop;
  bool hovering = false;
}

class _WebFileDropHub {
  static final List<_DropReg> _regs = [];
  static bool _listening = false;

  static void attach(_DropReg reg) {
    _regs.add(reg);
    _ensure();
  }

  static void detach(_DropReg reg) {
    reg.onHover(false);
    _regs.remove(reg);
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

  static Future<void> _deliver(
    List<html.File> files,
    bool imagesOnly,
    void Function(List<PickedFileBytes> files, int rejectedNonImages) onDrop,
  ) async {
    final accepted = <PickedFileBytes>[];
    var rejected = 0;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final name = file.name;
      final image = _isImage(name, file.type);
      if (imagesOnly && !image) {
        rejected++;
        continue;
      }
      final bytes = await _readFileBytes(file);
      if (bytes == null || bytes.isEmpty) continue;
      accepted.add(PickedFileBytes(name: name, bytes: bytes));
    }
    onDrop(accepted, rejected);
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
}) {
  final reg = _DropReg(
    enabled: enabled,
    imagesOnly: imagesOnly,
    contains: contains,
    onHover: onHover,
    onDrop: onDrop,
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
