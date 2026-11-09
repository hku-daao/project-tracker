import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Glow behind a task or sub-task block. Completed also emits particles.
enum AsanaStatusAuraKind { completed, submitted, incomplete }

const asanaStatusAuraPad = 28.0;
const asanaStatusCompletedAuraPad = 42.0;

double asanaStatusAuraPadFor(AsanaStatusAuraKind kind) {
  return kind == AsanaStatusAuraKind.completed
      ? asanaStatusCompletedAuraPad
      : asanaStatusAuraPad;
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
  const AsanaStatusAura({super.key, required this.kind, required this.pad});

  final AsanaStatusAuraKind kind;
  final double pad;

  @override
  Widget build(BuildContext context) {
    if (kind == AsanaStatusAuraKind.incomplete) {
      return CustomPaint(
        painter: _AsanaStatusAuraPainter(kind: kind, t: 0, pad: pad),
      );
    }
    final clock = _AsanaStatusAuraClockScope.maybeOf(context);
    if (clock == null) {
      return CustomPaint(
        painter: _AsanaStatusAuraPainter(kind: kind, t: 0, pad: pad),
      );
    }
    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        return CustomPaint(
          painter: _AsanaStatusAuraPainter(kind: kind, t: clock.value, pad: pad),
        );
      },
    );
  }
}

class _AsanaStatusAuraPainter extends CustomPainter {
  const _AsanaStatusAuraPainter({
    required this.kind,
    required this.t,
    required this.pad,
  });

  final AsanaStatusAuraKind kind;
  final double t;
  final double pad;

  @override
  void paint(Canvas canvas, Size size) {
    final block = Rect.fromLTWH(
      pad,
      pad,
      math.max(0, size.width - pad * 2),
      math.max(0, size.height - pad * 2),
    );
    if (block.isEmpty) return;
    final shape = RRect.fromRectAndRadius(block, const Radius.circular(10));
    switch (kind) {
      case AsanaStatusAuraKind.incomplete:
        _paintIncomplete(canvas, shape);
      case AsanaStatusAuraKind.submitted:
        _paintSubmitted(canvas, shape);
      case AsanaStatusAuraKind.completed:
        _paintCompleted(canvas, block, shape);
    }
  }

  void _paintIncomplete(Canvas canvas, RRect shape) {
    canvas.drawRRect(
      shape.shift(const Offset(0, 9)),
      Paint()
        ..color = const Color(0x6B2C2628)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      shape.inflate(2),
      Paint()
        ..color = const Color(0x8C8E6E76)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
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

  static const _completedGlowColors = <Color>[
    Color(0xFFFFC83D),
    Color(0xFF3DDC97),
    Color(0xFFFF7B6B),
    Color(0xFF6EC8FF),
    Color(0xFFE57CFF),
  ];

  void _paintCompleted(Canvas canvas, Rect block, RRect shape) {
    final anchors = <Offset>[
      Offset(block.left + block.width * 0.18, block.top - 2),
      Offset(block.right - block.width * 0.12, block.top + 4),
      Offset(block.left - 2, block.center.dy),
      Offset(block.right + 2, block.center.dy + 6),
      Offset(block.center.dx, block.bottom + 2),
    ];
    for (var i = 0; i < _completedGlowColors.length; i++) {
      canvas.drawCircle(
        anchors[i],
        20,
        Paint()
          ..color = _completedGlowColors[i].withValues(alpha: 0.72)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }
    canvas.drawRRect(
      shape.inflate(2),
      Paint()
        ..color = const Color(0x66FFE39A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    const particles = 14;
    final travel = math.max(18.0, pad - 8);
    for (var i = 0; i < particles; i++) {
      final phase = (t + i / particles) % 1.0;
      final fade = math.sin(phase * math.pi);
      if (fade <= 0.03) continue;
      final color = _completedGlowColors[i % _completedGlowColors.length];
      final lane = (i % 7) / 6;
      final fromSide = i % 5 == 0;
      final originX = fromSide
          ? (i.isEven ? block.left : block.right)
          : block.left + block.width * (0.1 + 0.8 * lane);
      final originY = fromSide
          ? block.top + block.height * (0.15 + 0.25 * (i % 3))
          : block.top + 2;
      final rise = phase * travel;
      final drift = math.sin((i + 1) * 1.7) * 12 * phase;
      final point = Offset(originX + drift, originY - rise);
      final radius = i % 4 == 0 ? 2.7 : 1.6;
      canvas.drawCircle(
        point,
        radius + 2.2,
        Paint()
          ..color = color.withValues(alpha: 0.4 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = color.withValues(alpha: 0.95 * fade),
      );
      if (i % 3 == 0) {
        canvas.drawLine(
          point,
          point + Offset(drift * 0.15, 7 * (1 - phase)),
          Paint()
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: 0.7 * fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AsanaStatusAuraPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.t != t ||
        oldDelegate.pad != pad;
  }
}
