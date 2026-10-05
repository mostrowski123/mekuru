import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mekuru/l10n/l10n.dart';

/// A Free books tab's search box. [onChanged] runs once typing pauses for
/// 250 ms, so a fast typist doesn't refilter the catalog per keystroke.
class FreeBooksSearchField extends StatefulWidget {
  const FreeBooksSearchField({
    super.key,
    required this.initialText,
    required this.hintText,
    required this.onChanged,
  });

  final String initialText;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<FreeBooksSearchField> createState() => _FreeBooksSearchFieldState();
}

class _FreeBooksSearchFieldState extends State<FreeBooksSearchField> {
  late final _controller = TextEditingController(text: widget.initialText);
  late var _sent = widget.initialText;
  Timer? _debounce;

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (text == _sent) return;
      _sent = text;
      widget.onChanged(text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    // Rebuilds only the field per keystroke, for the clear button.
    child: ValueListenableBuilder(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        controller: _controller,
        onChanged: _changed,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: context.l10n.commonClearSearch,
                  onPressed: () {
                    _controller.clear();
                    _changed('');
                  },
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    ),
  );
}
