import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// iOS draws the main tabs as a floating Liquid Glass bar that the tab
/// screens scroll under; Android keeps the Material NavigationBar.
bool get usesGlassTabBar => defaultTargetPlatform == TargetPlatform.iOS;

/// Space a tab screen's scroll view leaves after its last item, so the
/// content can scroll clear of the floating glass tab bar. Zero on Android.
double glassTabBarInset(BuildContext context) =>
    usesGlassTabBar ? MediaQuery.paddingOf(context).bottom : 0;

/// Keeps a screen out of the strip iPhone Duo reserves along one side for the
/// status bar and the tab bar. The strip keeps the colour of a page, so it
/// never shows as a black bar. Other devices have no strip and nothing changes.
class VerticalBarInset extends StatelessWidget {
  const VerticalBarInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!usesGlassTabBar) return child;
    final hasStrip = GlassVerticalBar.maybeOf(context) != null;
    // The same widgets with or without a strip: rotating the open phone adds
    // or removes it, and that must not rebuild the screen from scratch.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        bottom: false,
        left: hasStrip,
        right: hasStrip,
        child: child,
      ),
    );
  }
}
