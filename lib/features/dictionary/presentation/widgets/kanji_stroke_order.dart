import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Displays a kanji character's stroke order diagram from KanjiVG SVG data.
///
/// The SVG asset is loaded from `assets/kanjivg/kanji/{codepoint}.svg` where
/// the codepoint is the 5-digit zero-padded hex Unicode value.
///
/// Supports animated stroke-by-stroke playback and a static view showing
/// all strokes with numbered labels.
class KanjiStrokeOrder extends StatefulWidget {
  const KanjiStrokeOrder({
    super.key,
    required this.kanji,
    this.size = 140,
  });

  /// The single kanji character to display stroke order for.
  final String kanji;

  /// The size (width and height) of the stroke order diagram.
  final double size;

  @override
  State<KanjiStrokeOrder> createState() => _KanjiStrokeOrderState();
}

class _KanjiStrokeOrderState extends State<KanjiStrokeOrder>
    with SingleTickerProviderStateMixin {
  String? _svgData;
  bool _hasAsset = false;
  bool _loading = true;
  int _strokeCount = 0;
  int _currentStroke = 0;
  bool _isAnimating = false;
  AnimationController? _animController;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  @override
  void didUpdateWidget(KanjiStrokeOrder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kanji != widget.kanji) {
      _animController?.stop();
      _isAnimating = false;
      _currentStroke = 0;
      _loadSvg();
    }
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }

  String _assetPath() {
    final codepoint = widget.kanji.codeUnitAt(0).toRadixString(16).padLeft(5, '0');
    return 'assets/kanjivg/kanji/$codepoint.svg';
  }

  Future<void> _loadSvg() async {
    setState(() => _loading = true);

    try {
      final data = await rootBundle.loadString(_assetPath());
      // Count strokes by counting <path> elements in StrokePaths group
      final pathPattern = RegExp(r'<path\s');
      final count = pathPattern.allMatches(data).length;

      if (mounted) {
        setState(() {
          _svgData = data;
          _hasAsset = true;
          _loading = false;
          _strokeCount = count;
          _currentStroke = count; // Show all strokes initially
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasAsset = false;
          _loading = false;
        });
      }
    }
  }

  void _startAnimation() {
    if (_strokeCount == 0 || _svgData == null) return;

    _animController?.dispose();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _strokeCount * 500),
    );

    setState(() {
      _currentStroke = 0;
      _isAnimating = true;
    });

    _animController!.addListener(() {
      if (!mounted) return;
      final newStroke = (_animController!.value * _strokeCount).ceil();
      if (newStroke != _currentStroke) {
        setState(() => _currentStroke = newStroke);
      }
    });

    _animController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _isAnimating = false);
      }
    });

    _animController!.forward();
  }

  /// Build SVG data showing only the first [upToStroke] strokes.
  String _buildPartialSvg(String svgData, int upToStroke) {
    if (upToStroke >= _strokeCount) return svgData;

    // Hide strokes beyond upToStroke by setting their style to transparent
    var result = svgData;
    for (var i = upToStroke + 1; i <= _strokeCount; i++) {
      // Match path elements with stroke IDs and hide them
      final pathId = RegExp(r'id="kvg:[0-9a-f]+-s' + i.toString() + r'"');
      result = result.replaceAllMapped(pathId, (m) {
        return '${m.group(0)} style="display:none"';
      });
      // Also hide corresponding stroke numbers
      result = result.replaceFirst(
        RegExp('>$i</text>'),
        ' style="display:none">$i</text>',
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_hasAsset || _svgData == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Adjust SVG colors for dark mode
    var displaySvg = _buildPartialSvg(_svgData!, _currentStroke);
    if (isDark) {
      displaySvg = displaySvg
          .replaceAll('stroke:#000000', 'stroke:#ffffff')
          .replaceAll('fill:#808080', 'fill:#a0a0a0');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: SvgPicture.string(
            displaySvg,
            width: widget.size - 16,
            height: widget.size - 16,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_strokeCount strokes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: IconButton(
                onPressed: _isAnimating ? null : _startAnimation,
                icon: Icon(
                  _isAnimating ? Icons.hourglass_top : Icons.play_arrow,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Animate stroke order',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
