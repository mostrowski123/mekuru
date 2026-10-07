import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// Asks "Download over mobile data?" before a large download of [size]
/// starts off Wi-Fi; [body] names the size. Through a VPN ([isOnVpn]) it
/// says the VPN is why it asks. True only when the user picks Download.
Future<bool> confirmMobileData(
  BuildContext context, {
  required String size,
  required String body,
}) async {
  final vpn = await isOnVpn();
  if (!context.mounted) return false;
  final l = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(vpn ? l.mobileDataVpnTitle : l.localOcrMobileDownloadTitle),
      content: Text(vpn ? l.mobileDataVpnBody(size: size) : body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l.commonDownload),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Whether a large download may start now: on Wi-Fi, or off it once the
/// user agrees to use mobile data ([confirmMobileData]).
Future<bool> okToDownload(
  BuildContext context, {
  required String size,
  required String body,
}) async {
  if (await isOnWifi()) return true;
  if (!context.mounted) return false;
  return confirmMobileData(context, size: size, body: body);
}

/// Starts [download] of [size] on Wi-Fi, or off it once the user accepts
/// mobile data; [body] names what downloads, a dictionary when omitted. A
/// dictionary download that started on Wi-Fi stops if Wi-Fi goes, and
/// tapping Download again must not then go on over mobile data unasked.
/// Pass the notifier's method itself: the tile can unmount while the dialog
/// is up.
Future<void> askThenDownload(
  BuildContext context,
  String size,
  Future<void> Function() download, {
  String? body,
}) async {
  AppHaptics.light();
  body ??= context.l10n.catalogMobileDataBody(size: size);
  if (await okToDownload(context, size: size, body: body)) {
    unawaited(download());
  }
}
