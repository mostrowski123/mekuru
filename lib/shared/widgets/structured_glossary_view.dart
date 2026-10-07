import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mekuru/core/platform/image_convert.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/data/services/structured_content.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/hit_testable_rich_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';

/// One dictionary row's definition.
///
/// Plain-string rows keep the compact "a; b; c" line. Yomitan structured
/// content (Jitendex, Wiktionary, JMdict's notes and forms tables) is laid
/// out: list markers, tag badges, example sentences with furigana, info
/// boxes, tables, collapsible sections and images. Japanese text stays
/// tappable for lookups, and `?query=` links look their word up.
class StructuredGlossaryView extends StatefulWidget {
  const StructuredGlossaryView({
    super.key,
    required this.glossaries,
    required this.dictionaryId,
    required this.style,
    this.number,
    this.onWordTap,
  });

  /// The stored glossaries JSON of one row.
  final String glossaries;
  final int dictionaryId;
  final TextStyle style;

  /// Shown as "N. " when a dictionary has several rows for a word.
  final int? number;
  final ValueChanged<String>? onWordTap;

  @override
  State<StructuredGlossaryView> createState() => _StructuredGlossaryViewState();
}

class _StructuredGlossaryViewState extends State<StructuredGlossaryView> {
  List<ScNode>? _nodes;
  String _plain = '';

  /// The rendered definition, kept across parent rebuilds: rebuilding it
  /// would re-run MeCab and relay out every paragraph holding ruby, badges
  /// or images (a WidgetSpan never compares equal to a new one).
  Widget? _body;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _body = null;
  }

  @override
  void didUpdateWidget(StructuredGlossaryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glossaries != widget.glossaries) _parse();
    if (oldWidget.glossaries != widget.glossaries ||
        oldWidget.dictionaryId != widget.dictionaryId ||
        oldWidget.style != widget.style ||
        oldWidget.number != widget.number ||
        (oldWidget.onWordTap == null) != (widget.onWordTap == null)) {
      _body = null;
    }
  }

  void _parse() {
    _nodes = parseRichGlossaries(widget.glossaries);
    // The compact "a; b; c" line plain-string rows have always shown.
    _plain = _nodes == null
        ? GlossaryParser.oneLine(
            GlossaryParser.parse(widget.glossaries).join('\n'),
          )
        : '';
  }

  /// Taps reach the current callback, so a kept body never calls a stale one.
  void _tap(String word) => widget.onWordTap?.call(word);

  @override
  Widget build(BuildContext context) => _body ??= _render(context);

  Widget _render(BuildContext context) {
    final nodes = _nodes;
    final number = widget.number;
    final onWordTap = widget.onWordTap == null ? null : _tap;
    if (nodes == null) {
      final line = number == null ? _plain : '$number. $_plain';
      return onWordTap == null
          ? Text(line, style: widget.style)
          : TappableDefinitionText(
              text: line,
              style: widget.style,
              onWordTap: onWordTap,
            );
    }

    final body = _column(
      _Renderer(
        context,
        dictionaryId: widget.dictionaryId,
        onWordTap: onWordTap,
      ).blocks(nodes, widget.style),
    );
    if (number == null) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$number. ', style: widget.style),
        Expanded(child: body),
      ],
    );
  }
}

Widget _column(List<Widget> children) => children.length == 1
    ? children.single
    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);

/// Turns parsed nodes into widgets.
class _Renderer {
  _Renderer(
    BuildContext context, {
    required this.dictionaryId,
    required this.onWordTap,
  }) : theme = Theme.of(context);

  _Renderer._(this.dictionaryId, this.onWordTap, this.theme);

  final int dictionaryId;
  final ValueChanged<String>? onWordTap;
  final ThemeData theme;

  static const _inlineTags = {'span', 'a', 'ruby', 'rt', 'rp', 'br'};

  /// Jitendex marks forms-table cells with a class and draws the symbol with
  /// CSS; old and out-of-date forms use the kanji for old.
  static const _formSymbols = {
    'form-valid': '◇',
    'form-pri': '△',
    'form-irr': '✕',
    'form-out': '古',
    'form-old': '旧',
    'form-rare': '▽',
  };

  bool _isInline(ScNode node) =>
      node is! ScElement || _inlineTags.contains(node.tag);

  List<Widget> blocks(
    List<ScNode> nodes,
    TextStyle style, {
    TextAlign align = TextAlign.start,
  }) {
    final out = <Widget>[];
    var run = <ScNode>[];
    void flush() {
      final paragraph = this.paragraph(run, style, align: align);
      if (paragraph != null) out.add(paragraph);
      run = [];
    }

    for (final node in nodes) {
      if (_isInline(node)) {
        run.add(node);
      } else {
        flush();
        out.add(block(node as ScElement, style));
      }
    }
    flush();
    return out;
  }

  Widget block(ScElement el, TextStyle style) {
    final s = textStyle(el, style);
    return switch (el.tag) {
      'ul' || 'ol' => list(el, s),
      'table' => table(el, s),
      'details' => details(el, s),
      _ => container(el, s),
    };
  }

  Widget container(ScElement el, TextStyle style) {
    final align = _align(el);
    final children = blocks(el.children, style, align: align);
    if (children.isEmpty) return const SizedBox.shrink();
    var widget = _column(children);
    final accent = _boxAccent(el);
    if (accent != null) {
      widget = Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: widget,
      );
    }
    if (align == TextAlign.end) {
      widget = Align(alignment: AlignmentDirectional.centerEnd, child: widget);
    }
    return widget;
  }

  Widget list(ScElement el, TextStyle style) {
    final items = [
      for (final child in el.children)
        if (child is ScElement && child.tag == 'li') child,
    ];
    if (el.content == 'glossary') {
      // The house style for gloss lists: one "a; b; c" line.
      return paragraph([
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const ScText('; '),
              ...items[i].children,
            ],
          ], style) ??
          const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          _listItem(el, items[i], i, items.length, style),
      ],
    );
  }

  Widget _listItem(
    ScElement list,
    ScElement item,
    int index,
    int count,
    TextStyle style,
  ) {
    final s = textStyle(item, style);
    final body = blocks(item.children, s);
    if (body.isEmpty) return const SizedBox.shrink();
    final marker = _marker(list, item, index, count);
    if (marker == null) return _column(body);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: Text(marker, style: s),
        ),
        Expanded(child: _column(body)),
      ],
    );
  }

  String? _marker(ScElement list, ScElement item, int index, int count) {
    final type = (item.style['listStyleType'] ?? list.style['listStyleType'])
        ?.toString()
        .trim();
    final quoted = quotedListMarker(type);
    if (quoted != null) return quoted.isEmpty ? null : quoted;
    if (type != null) {
      switch (type) {
        case 'none':
          return null;
        case 'disc':
          return '•';
        case 'circle':
          return '◦';
        case 'square':
          return '▪';
        case 'decimal':
          return '${index + 1}.';
      }
    }
    if (count == 1) return null;
    return list.tag == 'ol' ? '${index + 1}.' : '•';
  }

  Widget table(ScElement el, TextStyle style) {
    final rows = <List<ScElement>>[];
    void collect(ScElement parent) {
      for (final child in parent.children) {
        if (child is! ScElement) continue;
        if (child.tag == 'tr') {
          rows.add([
            for (final cell in child.children)
              if (cell is ScElement && (cell.tag == 'td' || cell.tag == 'th'))
                cell,
          ]);
        } else if (const {'thead', 'tbody', 'tfoot'}.contains(child.tag)) {
          collect(child);
        }
      }
    }

    collect(el);
    final columns = rows.fold(0, (m, row) => row.length > m ? row.length : m);
    if (columns == 0) return const SizedBox.shrink();
    // colSpan/rowSpan are ignored: Flutter's Table has no spans.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < columns; i++)
                  i < row.length ? _cell(row[i], style) : const SizedBox(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(ScElement cell, TextStyle style) {
    final s = textStyle(
      cell,
      cell.tag == 'th' ? style.copyWith(fontWeight: FontWeight.w600) : style,
    );
    final symbol = _formSymbols[cell.data['class']];
    final body = symbol != null && _plainText(cell.children).trim().isEmpty
        ? [Text(symbol, style: s)]
        : blocks(cell.children, s, align: _align(cell));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: body.isEmpty ? const SizedBox() : _column(body),
    );
  }

  Widget details(ScElement el, TextStyle style) {
    ScElement? summary;
    final rest = <ScNode>[];
    for (final child in el.children) {
      if (summary == null && child is ScElement && child.tag == 'summary') {
        summary = child;
      } else {
        rest.add(child);
      }
    }
    final summaryStyle = textStyle(
      summary ?? el,
      style,
    ).copyWith(fontWeight: FontWeight.w600);
    return _Details(
      initiallyOpen: el.open,
      summary: summary == null
          ? [Text('…', style: summaryStyle)]
          // No lookups: a tap on the summary opens the section, also when
          // it is Japanese (Japanese Wiktionary's section names).
          : _Renderer._(
              dictionaryId,
              null,
              theme,
            ).blocks(summary.children, summaryStyle),
      // Built on opening: Wiktionary keeps most of an entry collapsed.
      buildBody: () => blocks(rest, style),
      iconColor: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// A run of inline nodes as one paragraph; null when it has nothing to show.
  Widget? paragraph(
    List<ScNode> nodes,
    TextStyle style, {
    TextAlign align = TextAlign.start,
  }) {
    if (nodes.isEmpty) return null;
    final builder = _ParagraphBuilder(this);
    for (final node in nodes) {
      builder.add(node, style);
    }
    if (builder.isBlank) return null;
    final span = TextSpan(style: style, children: builder.spans);
    final onWordTap = this.onWordTap;
    final targets = onWordTap == null
        ? const <TextTapTarget>[]
        : builder.targets();
    if (targets.isEmpty) return Text.rich(span, textAlign: align);
    return HitTestableRichText(
      text: span,
      targets: targets,
      onTapTarget: onWordTap!,
      textAlign: align,
    );
  }

  TextStyle textStyle(ScElement el, TextStyle base) {
    final fontSize = base.fontSize ?? 16;
    final muted = theme.colorScheme.onSurfaceVariant;
    var s = switch (el.content) {
      'example-sentence-a' => base.copyWith(fontSize: fontSize * 1.15),
      'example-sentence-b' ||
      'example-sentence-c' ||
      'xref-glossary' ||
      'antonym-glossary' => base.copyWith(
        fontSize: fontSize * 0.85,
        color: muted,
      ),
      'example-keyword' || 'bold-text' => base.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
      'attribution' || 'graphic-attribution' => base.copyWith(
        fontSize: fontSize * 0.7,
        color: muted,
      ),
      'attribution-footnote' || 'reference-label' => base.copyWith(
        fontSize: fontSize * 0.8,
        color: muted,
      ),
      _ => base,
    };
    if (el.data['class'] == 'extra-label') {
      s = s.copyWith(
        fontSize: fontSize * 0.8,
        fontStyle: FontStyle.italic,
        color: muted,
      );
    }

    // Inline style, without colors: they would break dark mode.
    final style = el.style;
    if (style.isEmpty) return s;
    final size = _cssFontSize(style['fontSize'], s.fontSize ?? fontSize);
    final decoration = style['textDecorationLine']?.toString() ?? '';
    final verticalAlign = style['verticalAlign'];
    return s.copyWith(
      fontWeight: style['fontWeight'] == 'bold' ? FontWeight.bold : null,
      fontStyle: style['fontStyle'] == 'italic' ? FontStyle.italic : null,
      fontSize: verticalAlign == 'super' || verticalAlign == 'sub'
          ? (size ?? s.fontSize ?? fontSize) * 0.75
          : size,
      decoration: decoration.contains('underline')
          ? TextDecoration.underline
          : decoration.contains('line-through')
          ? TextDecoration.lineThrough
          : null,
    );
  }

  static final _cssSize = RegExp(r'^([\d.]+)(em|%|px)$');

  static double? _cssFontSize(Object? value, double current) {
    if (value is! String) return null;
    final match = _cssSize.firstMatch(value.trim());
    if (match == null) {
      return switch (value.trim()) {
        'small' || 'smaller' => current * 0.85,
        'large' || 'larger' => current * 1.2,
        _ => null,
      };
    }
    final n = double.tryParse(match.group(1)!);
    if (n == null) return null;
    return switch (match.group(2)) {
      'em' => current * n,
      '%' => current * n / 100,
      _ => n,
    };
  }

  TextAlign _align(ScElement el) {
    if (el.content == 'attribution') return TextAlign.end;
    return switch (el.style['textAlign']) {
      'center' => TextAlign.center,
      'right' || 'end' => TextAlign.end,
      _ => TextAlign.start,
    };
  }

  // Jitendex's colors.
  static const _brown = Color(0xFFA52A2A);
  static const _purple = Color(0xFF800080);
  static const _green = Color(0xFF2E7D32);

  Color? _boxAccent(ScElement el) {
    if (el.data['class'] != 'extra-box') return null;
    return switch (el.content) {
      'xref' => const Color(0xFF1A73E8),
      'sense-note' => const Color(0xFFDAA520),
      'antonym' => _brown,
      'lang-source' => _purple,
      'info-gloss' => _green,
      _ => theme.colorScheme.onSurfaceVariant,
    };
  }

  bool isBadge(ScElement el) =>
      el.tag == 'span' && (el.data['class'] == 'tag' || el.content == 'tag');

  Widget badge(ScElement el, TextStyle style) {
    final (background, foreground) = switch (el.content) {
      'misc-info' => (_brown, Colors.white),
      'field-info' => (_purple, Colors.white),
      'dialect-info' => (_green, Colors.white),
      'lang-source-wasei' => (const Color(0xFFFFA500), Colors.black),
      _ => (const Color(0xFF565656), Colors.white),
    };
    final chip = Container(
      margin: const EdgeInsetsDirectional.only(end: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _plainText(el.children),
        style: style.copyWith(
          fontSize: (style.fontSize ?? 16) * 0.72,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
    final title = el.title;
    return title == null ? chip : Tooltip(message: title, child: chip);
  }

  Widget image(ScImage image, TextStyle style) => _ScImageView(
    image: image,
    dictionaryId: dictionaryId,
    fontSize: style.fontSize ?? 16,
    color: style.color ?? theme.colorScheme.onSurface,
  );

  /// The word a `?query=…` link looks up; null for other links.
  String? lookupQuery(String? href) => lookupLink(href)?['query'];
}

/// The text of [nodes] without ruby readings.
String _plainText(List<ScNode> nodes) => nodes
    .map(
      (node) => switch (node) {
        ScText(:final text) => text,
        ScElement(:final tag, :final children)
            when tag != 'rt' && tag != 'rp' =>
          _plainText(children),
        _ => '',
      },
    )
    .join();

/// Builds one paragraph's spans and the taps they answer.
///
/// Ruby, badges and images are WidgetSpans, one placeholder each in the
/// laid-out text. Tap targets are found on the logical text (ruby base
/// included, readings left out) and mapped back to layout offsets.
class _ParagraphBuilder {
  _ParagraphBuilder(this.r);

  final _Renderer r;
  final spans = <InlineSpan>[];
  final _logical = StringBuffer();

  /// Layout offset of each logical code unit.
  final _layoutOf = <int>[];
  var _layout = 0;
  final _links = <({int start, int end, String value})>[];
  var _hasContent = false;

  bool get isBlank => !_hasContent;

  void _text(String text, TextStyle style) {
    if (text.isEmpty) return;
    if (text.trim().isNotEmpty) _hasContent = true;
    spans.add(TextSpan(text: text, style: style));
    for (var i = 0; i < text.length; i++) {
      _layoutOf.add(_layout + i);
    }
    _logical.write(text);
    _layout += text.length;
  }

  void _widget(
    Widget child, {
    String logical = '￼',
    PlaceholderAlignment alignment = PlaceholderAlignment.middle,
  }) {
    _hasContent = true;
    spans.add(WidgetSpan(alignment: alignment, child: child));
    for (var i = 0; i < logical.length; i++) {
      _layoutOf.add(_layout);
    }
    _logical.write(logical);
    _layout += 1;
  }

  void add(ScNode node, TextStyle style) {
    switch (node) {
      case ScText(:final text):
        _text(text, style);
      case ScImage():
        _widget(r.image(node, style));
      case ScElement():
        _element(node, style);
    }
  }

  void _element(ScElement el, TextStyle style) {
    switch (el.tag) {
      case 'rt' || 'rp':
        return;
      case 'br':
        _text('\n', style);
        return;
      case 'ruby':
        final base = _plainText(el.children);
        final reading = _plainText([
          for (final child in el.children)
            if (child is ScElement && child.tag == 'rt') ...child.children,
        ]);
        if (reading.isEmpty) {
          _text(base, style);
        } else {
          _widget(
            _Ruby(base: base, reading: reading, style: style),
            logical: base.isEmpty ? '￼' : base,
            alignment: PlaceholderAlignment.bottom,
          );
        }
        return;
    }
    if (r.isBadge(el)) {
      _widget(r.badge(el, style));
      return;
    }
    final s = r.textStyle(el, style);
    final query = el.tag == 'a' ? r.lookupQuery(el.href) : null;
    if (query == null) {
      for (final child in el.children) {
        add(child, s);
      }
      return;
    }
    final start = _logical.length;
    final primary = r.theme.colorScheme.primary;
    final linkStyle = s.copyWith(
      color: primary,
      decoration: TextDecoration.underline,
      decorationColor: primary.withAlpha(100),
    );
    for (final child in el.children) {
      add(child, linkStyle);
    }
    if (_logical.length > start) {
      _links.add((start: start, end: _logical.length, value: query));
    }
  }

  /// Links first, then the Japanese words outside them, in layout offsets.
  List<TextTapTarget> targets() {
    TextTapTarget target(int start, int end, String value) => TextTapTarget(
      start: _layoutOf[start],
      end: _layoutOf[end - 1] + 1,
      value: value,
    );
    final targets = [
      for (final link in _links) target(link.start, link.end, link.value),
    ];
    var offset = 0;
    for (final segment in tapSegments(_logical.toString())) {
      final start = offset;
      final end = offset += segment.text.length;
      final value = segment.tapValue;
      if (value == null ||
          _links.any((link) => start < link.end && end > link.start)) {
        continue;
      }
      targets.add(target(start, end, value));
    }
    return targets;
  }
}

class _Ruby extends StatelessWidget {
  const _Ruby({required this.base, required this.reading, required this.style});

  final String base;
  final String reading;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          reading,
          style: style.copyWith(
            fontSize: (style.fontSize ?? 16) * 0.5,
            height: 1.0,
            decoration: TextDecoration.none,
          ),
        ),
        Text(base, style: style),
      ],
    );
  }
}

class _Details extends StatefulWidget {
  const _Details({
    required this.initiallyOpen,
    required this.summary,
    required this.buildBody,
    required this.iconColor,
  });

  final bool initiallyOpen;
  final List<Widget> summary;
  final List<Widget> Function() buildBody;
  final Color iconColor;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> with AutomaticKeepAliveClientMixin {
  late bool _open = widget.initiallyOpen;

  /// A section the user opened or closed keeps that state when a lazy list
  /// scrolls its row away.
  @override
  bool get wantKeepAlive => _open != widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = _open ? widget.buildBody() : const <Widget>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () {
              setState(() => _open = !_open);
              updateKeepAlive();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: widget.iconColor,
                ),
                Flexible(child: _column(widget.summary)),
              ],
            ),
          ),
        ),
        if (body.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 18),
            child: _column(body),
          ),
      ],
    );
  }
}

class _ScImageView extends ConsumerStatefulWidget {
  const _ScImageView({
    required this.image,
    required this.dictionaryId,
    required this.fontSize,
    required this.color,
  });

  final ScImage image;
  final int dictionaryId;
  final double fontSize;
  final Color color;

  @override
  ConsumerState<_ScImageView> createState() => _ScImageViewState();
}

class _ScImageViewState extends ConsumerState<_ScImageView>
    with AutomaticKeepAliveClientMixin {
  late bool _shown = !widget.image.collapsed;

  /// An image the user revealed stays revealed when a lazy list scrolls
  /// its row away.
  @override
  bool get wantKeepAlive => _shown == widget.image.collapsed;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final image = widget.image;
    if (!_shown) {
      return InkWell(
        onTap: () {
          setState(() => _shown = true);
          updateKeepAlive();
        },
        child: Icon(
          Icons.image_outlined,
          size: widget.fontSize * 1.2,
          color: widget.color,
        ),
      );
    }
    final scale = image.inEm ? widget.fontSize : 1.0;
    final width = image.width == null ? null : image.width! * scale;
    final height = image.height == null ? null : image.height! * scale;
    Uint8List? svg;
    if (image.path.toLowerCase().endsWith('.svg')) {
      final media = ref.watch(
        dictionaryMediaProvider((widget.dictionaryId, image.path)),
      );
      svg = media.value;
      if (svg == null) {
        // Hold the image's place while it loads, so the text does not jump.
        return media.isLoading
            ? SizedBox(width: width, height: height)
            : const SizedBox.shrink();
      }
    }

    Widget child = _picture(
      svg,
      width: width,
      height: height,
      color: widget.color,
    );
    child = GestureDetector(
      onTap: () => _openFullScreen(context, svg),
      child: child,
    );
    final title = image.title;
    if (title != null) child = Tooltip(message: title, child: child);
    return Semantics(image: true, label: image.alt ?? title, child: child);
  }

  /// [svg] holds an SVG's bytes; other images load through [_MediaImage].
  Widget _picture(
    Uint8List? svg, {
    double? width,
    double? height,
    required Color color,
  }) {
    final monochrome = widget.image.monochrome;
    final Widget picture = svg != null
        ? SvgPicture.memory(
            svg,
            width: width,
            height: height,
            colorFilter: monochrome
                ? ColorFilter.mode(color, BlendMode.srcIn)
                : null,
          )
        : Image(
            image: _MediaImage(
              ref.read(dictionaryRepositoryProvider),
              widget.dictionaryId,
              widget.image.path,
            ),
            width: width,
            height: height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            color: monochrome ? color : null,
            colorBlendMode: monochrome ? BlendMode.srcIn : null,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
    return widget.image.background
        ? ColoredBox(color: Colors.white, child: picture)
        : picture;
  }

  void _openFullScreen(BuildContext context, Uint8List? svg) {
    // Built now, while this row is on screen: the results behind the viewer
    // can change and take the row away while the viewer is still open.
    final picture = SizedBox.expand(child: _picture(svg, color: Colors.white));
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(maxScale: 8, child: picture),
              ),
              SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: MaterialLocalizations.of(
                      dialogContext,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A dictionary image, kept in Flutter's image cache under its dictionary
/// and path: a definition scrolled back into view reads and decodes it
/// only once.
@immutable
class _MediaImage extends ImageProvider<_MediaImage> {
  const _MediaImage(this.repository, this.dictionaryId, this.path);

  final DictionaryRepository repository;
  final int dictionaryId;
  final String path;

  @override
  Future<_MediaImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _MediaImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: path,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final Uint8List? bytes;
    try {
      bytes = await repository.getMedia(dictionaryId, path);
    } catch (_) {
      // Unlike a missing image, a failed read may work next time.
      PaintingBinding.instance.imageCache.evict(this);
      rethrow;
    }
    final image = bytes ?? (throw StateError('No image at $path'));
    // Jitendex's AVIF pictures, which Android 7-11 can't decode itself.
    return decodeWithAvifFallback(
      image,
      () async => decode(await ui.ImmutableBuffer.fromUint8List(image)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _MediaImage &&
      other.dictionaryId == dictionaryId &&
      other.path == path;

  @override
  int get hashCode => Object.hash(dictionaryId, path);
}
