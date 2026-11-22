import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// A download button's tap: a light haptic, [askNetwork] for a download of
/// [size] ([body] defaults to the dictionary wording), then [download] with
/// the answer, not awaited. Callers read their notifier before calling: the
/// tile can unmount while the question is up.
Future<void> askThenDownload(
  BuildContext context,
  String size,
  Future<void> Function(NetworkConsent network) download, {
  String Function(String size)? body,
}) async {
  AppHaptics.light();
  final network = await askNetwork(
    context,
    size: size,
    body: body ?? (size) => context.l10n.catalogMobileDataBody(size: size),
  );
  if (network != null) unawaited(download(network));
}

/// The one mobile-data question, asked before every add-on download. On Wi-Fi
/// ([isOnWifi]) it asks nothing and answers [NetworkConsent.wifiOnly]. With
/// no network at all ([isConnected]) it asks nothing either: it says there
/// is no connection and answers null. Otherwise it asks "Download over
/// mobile data?" with [body] of the download's [size] (through a VPN on
/// Android, [isOnVpn], it says the VPN is why it asks), and answers
/// [NetworkConsent.mobileData] for Download, null for Cancel or Back.
/// Nothing is remembered: the next download asks again.
Future<NetworkConsent?> askNetwork(
  BuildContext context, {
  required String size,
  required String Function(String size) body,
}) async {
  if (await isOnWifi()) return NetworkConsent.wifiOnly;
  if (!context.mounted) return null;
  if (!await isConnected()) {
    if (context.mounted) await _sayOffline(context);
    return null;
  }
  final vpn = await isOnVpn();
  if (!context.mounted) return null;
  final l = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(vpn ? l.mobileDataVpnTitle : l.localOcrMobileDownloadTitle),
      content: Text(vpn ? l.mobileDataVpnBody(size: size) : body(size)),
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
  return confirmed == true ? NetworkConsent.mobileData : null;
}

/// A dialog, as the question would have been: it shows above a bottom sheet,
/// where a snack bar would not.
Future<void> _sayOffline(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    content: Text(dialogContext.l10n.localOcrDownloadNetwork),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(dialogContext.l10n.commonOk),
      ),
    ],
  ),
);
