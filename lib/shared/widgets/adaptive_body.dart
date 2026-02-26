import 'dart:io';

import 'package:flutter/material.dart';

/// Wraps body content to provide a [Material] ancestor on iOS.
///
/// On iOS, [AdaptiveScaffold] uses [CupertinoPageScaffold] which does not
/// provide a Material widget in the tree. Any Material widgets (TextField,
/// ListTile, etc.) in the body will fail without this wrapper.
///
/// On Android this is a no-op pass-through since [AdaptiveScaffold] already
/// uses a Material [Scaffold].
class AdaptiveBody extends StatelessWidget {
  const AdaptiveBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return child;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(bottom: false, child: child),
    );
  }
}
