import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Whether a TLS certificate that failed validation for [host]:[port] may be
/// accepted for the self-hosted server at [baseUrl] whose user turned on
/// "accept self-signed certificate". Only that server's own host and port
/// qualify, so a redirect to anywhere else still gets full validation.
bool acceptsUntrustedCertificate(String baseUrl, String host, int port) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.scheme != 'https') return false;
  return uri.host.toLowerCase() == host.toLowerCase() && uri.port == port;
}

/// dart:io client for the self-hosted server at [baseUrl] (Komga, Kavita or
/// a custom OCR server). With [allowSelfSigned] it accepts a certificate that
/// fails validation, such as a self-signed one, from that server only.
HttpClient serverIoClient(String baseUrl, {required bool allowSelfSigned}) {
  final client = HttpClient();
  if (allowSelfSigned) {
    client.badCertificateCallback = (cert, host, port) =>
        acceptsUntrustedCertificate(baseUrl, host, port);
  }
  return client;
}

/// package:http client for the self-hosted server at [baseUrl]; see
/// [serverIoClient]. Without [allowSelfSigned] it is the default client.
http.Client serverHttpClient(String baseUrl, {required bool allowSelfSigned}) =>
    allowSelfSigned
    ? IOClient(serverIoClient(baseUrl, allowSelfSigned: true))
    : http.Client();
