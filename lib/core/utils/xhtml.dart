import 'package:xml/xml.dart';

/// Parses an EPUB XHTML (or other XML) document, or null when it is not
/// well-formed.
XmlDocument? parseXhtml(String xhtml) {
  try {
    // The html5 entity mapping is mandatory: the default XML mapping leaves
    // named entities like &nbsp; undecoded, and re-encoding then turns them
    // into visible "&amp;nbsp;" text.
    return XmlDocument.parse(
      xhtml,
      entityMapping: const XmlDefaultEntityMapping.html5(),
    );
  } on XmlException {
    return null;
  }
}

/// [href] percent-decoded, or as it is when it does not decode: a '%' that
/// starts no escape (`100%.xhtml`), or escapes of bytes that are not UTF-8
/// (`a%FF.xhtml`). A browser takes such a link as its literal text, and so
/// does the reader (`decodeHref` in assets/epub_viewer/epub.js).
String decodeHref(String href) {
  try {
    return Uri.decodeFull(href);
  } on ArgumentError {
    return href;
  } on FormatException {
    return href;
  }
}
