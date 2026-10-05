import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// iOS draws the main tabs as a floating Liquid Glass bar that the tab
/// screens scroll under; Android keeps the Material NavigationBar.
bool get usesGlassTabBar => defaultTargetPlatform == TargetPlatform.iOS;

/// Space a tab screen's scroll view leaves after its last item, so the
/// content can scroll clear of the floating glass tab bar. Zero on Android.
double glassTabBarInset(BuildContext context) =>
    usesGlassTabBar ? MediaQuery.paddingOf(context).bottom : 0;
