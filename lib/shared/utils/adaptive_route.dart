import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Returns a [CupertinoPageRoute] on iOS for native slide transitions,
/// and a [MaterialPageRoute] on all other platforms.
PageRoute<T> adaptiveRoute<T>({required WidgetBuilder builder}) {
  if (Platform.isIOS) {
    return CupertinoPageRoute<T>(builder: builder);
  }
  return MaterialPageRoute<T>(builder: builder);
}
