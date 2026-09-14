import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 静态波形（转写完成后展示）。[peaks] 为 0..1 归一化幅度；为空时绘制
/// 低幅装饰性波形。
class StaticWaveform extends StatelessWidget {
  const StaticWaveform({
    super.key,
    required this.peaks,
    this.color = const Color(0xFFE5474D),
    this.height = 56,
  });

  final List<double> peaks;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePainter(peaks: peaks, color: color),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.peaks, required this.color});

  final List<double> peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const barWidth = 2.0;
    const gap = 2.2;
    final count = (size.width / (barWidth + gap)).floor();
    final centerY = size.height / 2;

    for (var i = 0; i < count; i++) {
      final v = peaks.isEmpty
          ? 0.12 + 0.22 * (0.5 + 0.5 * math.sin(i * 0.55))
          : peaks[(i * peaks.length ~/ count).clamp(0, peaks.length - 1)];
      final h = (v * (size.height - 6)).clamp(2.0, size.height - 4);
      final x = i * (barWidth + gap) + barWidth / 2;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.peaks != peaks || old.color != color;
}

/// 实时录音波形：两侧对称的动态柱状图。
class LiveWaveBars extends StatelessWidget {
  const LiveWaveBars({
    super.key,
    required this.values,
    this.color = const Color(0xFFE5474D),
    this.maxHeight = 44,
    this.mirror = true,
  });

  final List<double> values;
  final Color color;
  final double maxHeight;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    if (mirror) {
      return Row(children: [for (final v in values.reversed) _bar(v)]);
    }
    return Row(children: [for (final v in values) _bar(v)]);
  }

  Widget _bar(double v) {
    final h = (v.clamp(0.0, 1.0) * maxHeight).clamp(3.0, maxHeight);
    return Container(
      width: 3,
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.35 + 0.65 * v),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
