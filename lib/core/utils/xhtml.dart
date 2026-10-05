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
