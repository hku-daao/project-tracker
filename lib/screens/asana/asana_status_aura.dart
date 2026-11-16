import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Glow behind a task or sub-task block.
/// Completed confetti and the incomplete grey glow share one rectangle:
/// the block plus the same margin on every side. That margin is half the
/// closest gap between map blocks, so neighboring effects meet and do not cross.
enum AsanaStatusAuraKind { completed, submitted, incomplete }

const asanaStatusAuraPad = 28.0;

/// Map blocks in a row are 30.8px apart. Each effect uses half of that.
const asanaStatusEffectMargin = 15.0;

class AsanaStatusAuraOutset {
  const AsanaStatusAuraOutset(this.x, this.y);

  final double x;
  final double y;
}

AsanaStatusAuraOutset asanaStatusAuraOutsetFor(AsanaStatusAuraKind kind) {
  return switch (kind) {
    AsanaStatusAuraKind.completed ||
    AsanaStatusAuraKind.incomplete => const AsanaStatusAuraOutset(
        asanaStatusEffectMargin,
        asanaStatusEffectMargin,
      ),
    AsanaStatusAuraKind.submitted => const AsanaStatusAuraOutset(
        asanaStatusAuraPad,
        asanaStatusAuraPad,
      ),
  };
}

AsanaStatusAuraKind? asanaStatusAuraKind(String label) {
  return switch (label) {
    'Completed' => AsanaStatusAuraKind.completed,
    'Submitted' => AsanaStatusAuraKind.submitted,
    'Incomplete' || 'Due today' || 'Overdue' => AsanaStatusAuraKind.incomplete,
    _ => null,
  };
}

/// One clock shared by every aura under [child].
class AsanaStatusAuraClock extends StatefulWidget {
  const AsanaStatusAuraClock({super.key, required this.child});

  final Widget child;

  @override
  State<AsanaStatusAuraClock> createState() => _AsanaStatusAuraClockState();
}

class _AsanaStatusAuraClockState extends State<AsanaStatusAuraClock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AsanaStatusAuraClockScope(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _AsanaStatusAuraClockScope extends InheritedWidget {
  const _AsanaStatusAuraClockScope({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AsanaStatusAuraClockScope>()
        ?.animation;
  }

  @override
  bool updateShouldNotify(_AsanaStatusAuraClockScope oldWidget) =>
      animation != oldWidget.animation;
}

class AsanaStatusAura extends StatelessWidget {
  const AsanaStatusAura({
    super.key,
    required this.kind,
    required this.padX,
    required this.padY,
  });

  final AsanaStatusAuraKind kind;
  final double padX;
  final double padY;

  @override
  Widget build(BuildContext context) {
    final clock = _AsanaStatusAuraClockScope.maybeOf(context);
    if (clock == null) {
      return CustomPaint(
        painter: _AsanaStatusAuraPainter(
          kind: kind,
          t: 0,
          padX: padX,
          padY: padY,
        ),
      );
    }
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        return CustomPaint(
          painter: _AsanaStatusAuraPainter(
            kind: kind,
            t: clock.value,
            padX: padX,
            padY: padY,
          ),
        );
      },
    );
  }
}

class _AsanaStatusAuraPainter extends CustomPainter {
  const _AsanaStatusAuraPainter({
    required this.kind,
    required this.t,
    required this.padX,
    required this.padY,
  });

  final AsanaStatusAuraKind kind;
  final double t;
  final double padX;
  final double padY;

  @override
  void paint(Canvas canvas, Size size) {
    final block = Rect.fromLTWH(
      padX,
      padY,
      math.max(0, size.width - padX * 2),
      math.max(0, size.height - padY * 2),
    );
    if (block.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final shape = RRect.fromRectAndRadius(block, const Radius.circular(10));
    switch (kind) {
      case AsanaStatusAuraKind.incomplete:
        _paintIncomplete(canvas, block);
      case AsanaStatusAuraKind.submitted:
        _paintSubmitted(canvas, shape);
      case AsanaStatusAuraKind.completed:
        _paintCompleted(canvas, block, shape);
    }
    canvas.restore();
  }

  static const _bubbleGreys = <Color>[
    Color(0xFF424242),
    Color(0xFF303030),
    Color(0xFF212121),
    Color(0xFF4A4A4A),
    Color(0xFF383838),
  ];

  void _paintIncomplete(Canvas canvas, Rect block) {
    final margin = math.min(padX, padY);
    final field = block.inflate(margin);
    final shape = RRect.fromRectAndRadius(block, const Radius.circular(10));
    canvas.save();
    canvas.clipRect(field);
    canvas.saveLayer(field, Paint());
    const steps = 5;
    for (var i = 0; i < steps; i++) {
      final outward = i / (steps - 1);
      final alpha = 0.55 * (1 - outward);
      canvas.drawRRect(
        shape.inflate(outward * margin),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = margin / steps + 2
          ..color = const Color(0xFF3A3A3A).withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    }
    final moving = t < 0.72;
    final pulse = moving ? Curves.easeOut.transform(t / 0.72) : 1.0;
    final ringAlpha = moving ? (1 - pulse) * 0.5 : 0.0;
    if (ringAlpha > 0) {
      canvas.drawRRect(
        shape.inflate(2 + (margin - 2) * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF424242).withValues(alpha: ringAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    const blobs = 27;
    for (var i = 0; i < blobs; i++) {
      final phase = (t * 0.8 + i / blobs) % 1.0;
      final grow = Curves.easeOut.transform(phase);
      final fade = (1 - phase) * 0.95;
      if (fade <= 0.02) continue;
      final side = i % 4;
      final along = ((i * 37) % 100) / 100.0;
      final Offset edge;
      final Offset outward;
      if (side == 0) {
        edge = Offset(block.left + block.width * (0.12 + 0.76 * along), block.top);
        outward = const Offset(0, -1);
      } else if (side == 1) {
        edge = Offset(block.right, block.top + block.height * (0.12 + 0.76 * along));
        outward = const Offset(1, 0);
      } else if (side == 2) {
        edge = Offset(
          block.left + block.width * (0.18 + 0.64 * (1 - along)),
          block.bottom,
        );
        outward = const Offset(0, 1);
      } else {
        edge = Offset(block.left, block.top + block.height * (0.18 + 0.64 * along));
        outward = const Offset(-1, 0);
      }
      final maxRadius = margin * 0.9;
      final radius = 7 + grow * (maxRadius - 7);
      final center = _insideBlock(
        block,
        edge - outward * (radius * 0.45),
      );
      final paint = Paint()
        ..color = _bubbleGreys[i % _bubbleGreys.length].withValues(alpha: fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(center, radius, paint);
      final satellite = _insideBlock(
        block,
        center +
            Offset(outward.dy, outward.dx) * (i.isEven ? radius * 0.18 : -radius * 0.18),
      );
      canvas.drawCircle(satellite, radius * 0.48, paint);
    }
    _fadeTowardBoundary(canvas, block, field);
    canvas.restore();
    canvas.restore();
  }

  /// Grey near the block stays dark. Grey at the outer edge fades out,
  /// the same way the completed halo thins toward its boundary.
  void _fadeTowardBoundary(Canvas canvas, Rect block, Rect field) {
    void fade(Rect area, Alignment begin, Alignment end) {
      if (area.width <= 0 || area.height <= 0) return;
      canvas.drawRect(
        area,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: begin,
            end: end,
            colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ).createShader(area),
      );
    }

    fade(
      Rect.fromLTRB(field.left, field.top, field.right, block.top),
      Alignment.bottomCenter,
      Alignment.topCenter,
    );
    fade(
      Rect.fromLTRB(field.left, block.bottom, field.right, field.bottom),
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    fade(
      Rect.fromLTRB(field.left, field.top, block.left, field.bottom),
      Alignment.centerRight,
      Alignment.centerLeft,
    );
    fade(
      Rect.fromLTRB(block.right, field.top, field.right, field.bottom),
      Alignment.centerLeft,
      Alignment.centerRight,
    );
  }

  Offset _insideBlock(Rect block, Offset point) {
    return Offset(
      point.dx.clamp(block.left, block.right),
      point.dy.clamp(block.top, block.bottom),
    );
  }

  void _paintSubmitted(Canvas canvas, RRect shape) {
    canvas.drawRRect(
      shape.inflate(2),
      Paint()
        ..color = const Color(0x94E8A317)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final moving = t < 0.72;
    final pulse = moving ? Curves.easeOut.transform(t / 0.72) : 1.0;
    final ringAlpha = moving ? (1 - pulse) * 0.55 : 0.0;
    if (ringAlpha <= 0) return;
    canvas.drawRRect(
      shape.inflate(3 + 14 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFE8A317).withValues(alpha: ringAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  static const _partyColors = <Color>[
    Color(0xFFFFD54F),
    Color(0xFFFF5252),
    Color(0xFF69F0AE),
    Color(0xFF40C4FF),
    Color(0xFFE040FB),
    Color(0xFFFFAB40),
    Color(0xFFB388FF),
    Color(0xFFEEFF41),
    Color(0xFFFF80AB),
    Color(0xFF18FFFF),
  ];

  void _paintCompleted(Canvas canvas, Rect block, RRect shape) {
    final reach = math.min(padX, padY);
    final field = block.inflate(reach);
    canvas.save();
    canvas.clipRect(field);
    const steps = 5;
    for (var i = 0; i < steps; i++) {
      final outward = i / (steps - 1);
      final alpha = 0.22 * (1 - outward);
      final rainbow = SweepGradient(
        startAngle: t * math.pi * 2,
        colors: [
          Color.fromRGBO(229, 57, 53, alpha),
          Color.fromRGBO(251, 140, 0, alpha),
          Color.fromRGBO(253, 216, 53, alpha),
          Color.fromRGBO(67, 160, 71, alpha),
          Color.fromRGBO(30, 136, 229, alpha),
          Color.fromRGBO(142, 36, 170, alpha),
          Color.fromRGBO(229, 57, 53, alpha),
        ],
      ).createShader(block.inflate(reach));
      canvas.drawRRect(
        shape.inflate(outward * reach),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = reach / steps + 1.5
          ..shader = rainbow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
    canvas.restore();
    _paintConfettiRain(canvas, block, reach, reach);
  }

  /// One falling field around the block. A piece travels the full margin,
  /// so the top, sides, and bottom are the same rain.
  void _paintConfettiRain(
    Canvas canvas,
    Rect block,
    double reachX,
    double reachY,
  ) {
    final area = Rect.fromLTRB(
      block.left - reachX,
      block.top - reachY,
      block.right + reachX,
      block.bottom + reachY,
    );
    final lanes = <double>[];
    void addLanes(double from, double to, int count) {
      if (to <= from || count <= 0) return;
      for (var i = 0; i < count; i++) {
        lanes.add(from + (to - from) * (i + 0.5) / count);
      }
    }

    addLanes(area.left, block.left, 4);
    addLanes(block.right, area.right, 4);
    final gap = math.max(12.0, block.height / 8);
    addLanes(block.left, block.right, math.max(1, (block.width / gap).round()));
    const drops = 8;
    for (var lane = 0; lane < lanes.length; lane++) {
      for (var drop = 0; drop < drops; drop++) {
        final i = lane * drops + drop;
        final phase = (t * 1.45 + (drop + lane * 0.37) / drops) % 1.0;
        final drift = math.sin(i * 1.7 + t * math.pi * 2) * 1.1;
        final point = Offset(
          lanes[lane] + drift,
          area.top + area.height * phase,
        );
        if (!area.contains(point) || block.contains(point)) continue;
        _paintConfettiPiece(canvas, point, i, phase);
      }
    }
  }

  void _paintConfettiPiece(Canvas canvas, Offset point, int i, double phase) {
    final paint = Paint()
      ..color = _partyColors[i % _partyColors.length].withValues(alpha: 0.95);
    if (i % 5 == 0) {
      _paintStar(canvas, point, 2.4, paint);
    } else if (i % 2 == 0) {
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(i * 0.65 + phase * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2.2, -1.0, 4.4, 2.0),
          const Radius.circular(0.4),
        ),
        paint,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(point, i % 3 == 0 ? 1.8 : 1.3, paint);
    }
  }

  void _paintStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final arm = i.isEven ? radius : radius * 0.38;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = center + Offset(math.cos(angle) * arm, math.sin(angle) * arm);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AsanaStatusAuraPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.t != t ||
        oldDelegate.padX != padX ||
        oldDelegate.padY != padY;
  }
}
