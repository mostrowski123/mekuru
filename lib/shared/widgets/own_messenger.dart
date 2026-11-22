import 'package:flutter/material.dart';

/// [sheet] with a messenger of its own, so its messages show on it rather
/// than on the page underneath. A Scaffold fills the height it is given, so
/// it lies over the sheet instead of holding it: the sheet keeps the height
/// of its content and the barrier stays tappable.
Widget withOwnMessenger(Widget sheet) => ScaffoldMessenger(
  child: Stack(
    children: [
      sheet,
      const Positioned.fill(
        child: IgnorePointer(
          child: Scaffold(backgroundColor: Colors.transparent),
        ),
      ),
    ],
  ),
);
