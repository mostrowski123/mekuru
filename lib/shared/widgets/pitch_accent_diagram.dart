import 'package:flutter/material.dart';

/// Splits a Japanese reading into morae (rhythmic units).
///
/// Small kana (ゃゅょぁぃぅぇぉ and katakana equivalents) combine with the
/// preceding character into a single mora. ー, っ, ッ, and ん/ン are
/// individual morae.
List<String> splitIntoMorae(String reading) {
  const smallKana = {
    'ゃ',
    'ゅ',
    'ょ',
    'ぁ',
    'ぃ',
    'ぅ',
    'ぇ',
    'ぉ',
    'ャ',
    'ュ',
    'ョ',
    'ァ',
    'ィ',
    'ゥ',
    'ェ',
    'ォ',
  };

  final morae = <String>[];
  final runes = reading.runes.toList();

  for (var i = 0; i < runes.length; i++) {
    final char = String.fromCharCode(runes[i]);
    // Check if next character is a small kana that should combine
    if (i + 1 < runes.length) {
      final next = String.fromCharCode(runes[i + 1]);
      if (smallKana.contains(next)) {
        morae.add('$char$next');
        i++; // skip the small kana
        continue;
      }
    }
    morae.add(char);
  }

  return morae;
}

/// Generates a list of high/low pitch values for each mora.
///
/// Returns a list of booleans where `true` = high pitch.
/// The list length is `morae.length + 1` (extra for the particle).
///
/// Pitch patterns:
/// - position 0 (heiban): L H H H ... H (particle stays high)
/// - position 1 (atamadaka): H L L L ... L (drops after first)
/// - 1 < position < n (nakadaka): L H ... H L ... L (drops after position)
/// - position == n (odaka): L H H ... H L (drops on particle)
List<bool> pitchPattern(int position, int moraCount) {
  final n = moraCount;
  // length = morae + 1 for particle
  final pattern = List<bool>.filled(n + 1, false);

  if (position == 0) {
    // Heiban: LHHH...H (particle high)
    for (var i = 1; i <= n; i++) {
      pattern[i] = true;
    }
  } else if (position == 1) {
    // Atamadaka: HLLL...L
    pattern[0] = true;
  } else {
    // Nakadaka or Odaka: LHHHLL...L
    for (var i = 1; i < position; i++) {
      pattern[i] = true;
    }
    // For odaka (position == n), the last mora is high
    if (position <= n) {
      pattern[position - 1] = true;
    }
  }

  return pattern;
}

/// A visual diagram showing the pitch accent pattern for a Japanese word.
///
/// Draws mora text along the baseline with dots above at high/low positions,
/// connected by lines. A red dot marks the downstep position.
class PitchAccentDiagram extends StatelessWidget {
  const PitchAccentDiagram({
    super.key,
    required this.reading,
    required this.downstepPosition,
    this.fontSize = 14.0,
    this.color,
  });

  final String reading;
  final int downstepPosition;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final morae = splitIntoMorae(reading);
    if (morae.isEmpty) return const SizedBox.shrink();

    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    final downstepColor = Theme.of(context).colorScheme.error;

    return CustomPaint(
      painter: _PitchAccentPainter(
        morae: morae,
        downstepPosition: downstepPosition,
        fontSize: fontSize,
        textColor: effectiveColor,
        lineColor: effectiveColor,
        downstepColor: downstepColor,
      ),
      child: SizedBox(
        width: _PitchAccentPainter.calculateWidth(morae, fontSize),
        height: _PitchAccentPainter.calculateHeight(fontSize),
      ),
    );
  }
}

class _PitchAccentPainter extends CustomPainter {
  _PitchAccentPainter({
    required this.morae,
    required this.downstepPosition,
    required this.fontSize,
    required this.textColor,
    required this.lineColor,
    required this.downstepColor,
  });

  final List<String> morae;
  final int downstepPosition;
  final double fontSize;
  final Color textColor;
  final Color lineColor;
  final Color downstepColor;

  static const double _dotRadius = 3.0;
  static const double _lineWidth = 1.5;
  static const double _moraSpacing = 4.0;
  static const double _particleExtraSpacing = 6.0;

  /// Height of the pitch diagram area above the text.
  static double _pitchAreaHeight(double fontSize) => fontSize * 1.1;

  static double calculateHeight(double fontSize) {
    return _pitchAreaHeight(fontSize) + fontSize + 4;
  }

  static double calculateWidth(List<String> morae, double fontSize) {
    double totalWidth = 0;
    for (var i = 0; i < morae.length; i++) {
      final tp = _createTextPainter(morae[i], fontSize);
      tp.layout();
      totalWidth += tp.width;
      if (i < morae.length - 1) totalWidth += _moraSpacing;
    }
    // Add space for particle marker
    totalWidth += _particleExtraSpacing;
    final particleTp = _createTextPainter('(', fontSize * 0.8);
    particleTp.layout();
    totalWidth += particleTp.width + _dotRadius * 2;
    return totalWidth;
  }

  static TextPainter _createTextPainter(
    String text,
    double size, [
    Color color = Colors.black,
  ]) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pattern = pitchPattern(downstepPosition, morae.length);
    final pitchAreaH = _pitchAreaHeight(fontSize);
    final highY = _dotRadius + 2;
    final lowY = pitchAreaH - _dotRadius - 2;
    final textY = pitchAreaH + 2;

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.6)
      ..strokeWidth = _lineWidth
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final downstepPaint = Paint()
      ..color = downstepColor
      ..style = PaintingStyle.fill;

    // Measure mora widths and compute x centers
    final moraCenters = <double>[];
    final moraWidths = <double>[];
    double x = 0;

    for (var i = 0; i < morae.length; i++) {
      final tp = _createTextPainter(morae[i], fontSize, textColor);
      tp.layout();
      moraWidths.add(tp.width);
      moraCenters.add(x + tp.width / 2);

      // Draw mora text
      tp.paint(canvas, Offset(x, textY));
      x += tp.width + _moraSpacing;
    }

    // Draw dots and connecting lines for morae
    for (var i = 0; i < morae.length; i++) {
      final cx = moraCenters[i];
      final cy = pattern[i] ? highY : lowY;

      // Draw connecting line to next mora
      if (i < morae.length - 1) {
        final nextCx = moraCenters[i + 1];
        final nextCy = pattern[i + 1] ? highY : lowY;
        canvas.drawLine(Offset(cx, cy), Offset(nextCx, nextCy), linePaint);
      }

      // Draw dot
      final isDownstep =
          downstepPosition > 0 && i == downstepPosition - 1 && i < morae.length;
      canvas.drawCircle(
        Offset(cx, cy),
        _dotRadius,
        isDownstep ? downstepPaint : dotPaint,
      );
    }

    // Draw particle dot (dashed line connection)
    if (morae.isNotEmpty) {
      final lastMoraCx = moraCenters.last;
      final lastMoraCy = pattern[morae.length - 1] ? highY : lowY;
      final particleCx =
          x - _moraSpacing + _particleExtraSpacing + _dotRadius * 2;
      final particleCy = pattern[morae.length] ? highY : lowY;

      // Dashed line to particle
      final dashPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.3)
        ..strokeWidth = _lineWidth
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(lastMoraCx, lastMoraCy),
        Offset(particleCx, particleCy),
        dashPaint,
      );

      // Particle dot (smaller, more transparent)
      canvas.drawCircle(
        Offset(particleCx, particleCy),
        _dotRadius * 0.7,
        Paint()..color = lineColor.withValues(alpha: 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PitchAccentPainter oldDelegate) {
    return oldDelegate.morae != morae ||
        oldDelegate.downstepPosition != downstepPosition ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.textColor != textColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.downstepColor != downstepColor;
  }
}
