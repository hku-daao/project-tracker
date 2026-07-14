import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../generated/logo_base64.g.dart';

/// Project Tracker logo — on web uses embedded/favicon bytes (asset bundle is unreliable on some deploys).
class ProjectTrackerLogo extends StatelessWidget {
  const ProjectTrackerLogo({
    super.key,
    required this.height,
    this.semanticLabel = 'Project Tracker logo',
  });

  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheH = (height * dpr).round().clamp(1, 4096);

    if (kIsWeb) {
      final embedded = _embeddedBytes();
      if (embedded != null) {
        return Image.memory(
          embedded,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheHeight: cacheH,
          semanticLabel: semanticLabel,
        );
      }
      return Image.network(
        Uri.base.resolve('favicon.png').toString(),
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        cacheHeight: cacheH,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/images/logo.png',
            height: height,
            fit: BoxFit.contain,
            cacheHeight: cacheH,
            semanticLabel: semanticLabel,
          );
        },
      );
    }

    return Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      cacheHeight: cacheH,
      semanticLabel: semanticLabel,
    );
  }

  static Uint8List? _embeddedBytes() {
    final raw = kEmbeddedLogoPngBase64.trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }
}
