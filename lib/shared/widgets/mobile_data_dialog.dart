import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/l10n/l10n.dart';

/// The one mobile-data question, asked before every add-on download. On Wi-Fi
/// ([isOnWifi]) it asks nothing and answers [NetworkConsent.wifiOnly]. Off it,
/// it asks "Download over mobile data?" with [body] of the download's [size]
/// (through a VPN on Android, [isOnVpn], it says the VPN is why it asks), and
/// answers [NetworkConsent.mobileData] for Download, null for Cancel or Back.
/// Nothing is remembered: the next download asks again.
Future<NetworkConsent?> askNetwork(
  BuildContext context, {
  required String size,
  required String Function(String size) body,
}) async {
  if (await isOnWifi()) return NetworkConsent.wifiOnly;
  if (!context.mounted) return null;
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
