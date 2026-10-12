// RAR archives for tests. Only RARLAB's own (proprietary) tool can compress
// RAR, so the compressed fixtures are libarchive's test archives
// (libarchive/test/*.rar.uu in the 3.8.9 release, BSD-2-Clause, see
// packages/rar_reader/third_party/libarchive/COPYING), named after them,
// and archives of pages are written uncompressed by [storedRar5].
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:rar_reader/rar_reader.dart';

/// `skip:` for tests that load the RAR reader: its build hook doesn't build
/// for Windows hosts, so on Windows those tests run only in CI (Linux).
final String? rarSkip = Platform.isWindows
    ? 'the RAR reader is not built for Windows hosts'
    : null;

/// Every entry of the RAR at [path] in archive order: its data, or null
/// when it is not a file (a folder or a link).
Map<String, Uint8List?> readRar(String path) {
  final reader = RarReader.open(path);
  try {
    return {
      for (var e = reader.nextEntry(); e != null; e = reader.nextEntry())
        e.name: e.isFile ? reader.readEntry() : null,
    };
  } finally {
    reader.close();
  }
}

/// A RAR 5 archive holding [files] uncompressed, in map order. Names use
/// '/' between folders. Written from RARLAB's published RAR 5.0 format
/// description: no RAR code involved, and no compression.
Uint8List storedRar5(Map<String, List<int>> files) {
  final out = BytesBuilder()
    ..add(const [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]);
  // Each header: CRC32 of everything after it, the size of the header's
  // fields, then the fields (type first). Data follows its header.
  void header(List<int> fields, [List<int> data = const []]) {
    final size = _vint(fields.length);
    out
      ..add(_uint32(getCrc32([...size, ...fields])))
      ..add(size)
      ..add(fields)
      ..add(data);
  }

  header(const [1, 0, 0]); // main archive header: type, flags, archive flags
  for (final MapEntry(key: name, value: data) in files.entries) {
    final nameBytes = utf8.encode(name);
    header([
      2, // file header
      2, // header flags: a data area follows
      ..._vint(data.length),
      4, // file flags: data CRC32 present
      ..._vint(data.length), // unpacked size
      0x20, // attributes: Windows "archive" (host OS 0 below)
      ..._uint32(getCrc32(data)),
      0, // compression: method 0 (store), smallest window
      0, // host OS: Windows; on Unix the attributes would be the file mode
      ..._vint(nameBytes.length),
      ...nameBytes,
    ], data);
  }
  header(const [5, 0, 0]); // end of archive: type, flags, end flags
  return out.takeBytes();
}

/// A copy of the RAR 4 archive [rar4] with MHD_SOLID set in its main
/// header. The header CRC is left stale: RarReader rejects solid RAR 4
/// archives from the flag before libarchive reads the header.
Uint8List markRar4Solid(List<int> rar4) =>
    Uint8List.fromList(rar4)..[10] |= 0x08;

List<int> _vint(int value) => [
  for (; value >= 0x80; value >>= 7) (value & 0x7F) | 0x80,
  value,
];

List<int> _uint32(int value) => [
  for (var shift = 0; shift < 32; shift += 8) (value >> shift) & 0xFF,
];

/// `test_read_format_rar.rar`: RAR 4: test.txt, testlink (symlink), testdir/test.txt, testdir/,
/// testemptydir/. Each text file is "test text document\r\n".
final rar4Basic = base64Decode(
  'UmFyIRoHAM+QcwAADQAAAAAAAACEUnQgkDIAFAAAABQAAAADQqLIvrd22j4UMAgApIEA'
  'AHRlc3QudHh0gAi3dto+t3baPnRlc3QgdGV4dCBkb2N1bWVudA0KnS90IJAyAAgAAAAI'
  'AAAAA3tEybbRTNg+FDAIAP+hAAB0ZXN0bGlua8AI0UzYPlBf2j50ZXN0LnR4dM3gdCCQ'
  'OgAUAAAAFAAAAANCosi+Y3faPhQwEACkgQAAdGVzdGRpclx0ZXN0LnR4dMDMY3faPmN3'
  '2j50ZXN0IHRleHQgZG9jdW1lbnQNCqHIdOCQMQAAAAAAAAAAAAMAAAAAY3faPhQwBwDt'
  'QQAAdGVzdGRpcsDMY3faPmR32j7m53TgkDYAAAAAAAAAAAADAAAAAJ2r1T4UMAwA7UEA'
  'AHRlc3RlbXB0eWRpcoDMnavVPsVd2j7EPXsAQAcA',
);

/// `test_read_format_rar_compress_normal.rar`: RAR 4, compressed: LibarchiveAddingTest.html (20111 bytes),
/// testlink, testdir/test.txt, testdir/LibarchiveAddingTest.html, testdir/,
/// testemptydir/.
final rar4CompressNormal = base64Decode(
  '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',
);

/// `test_read_format_rar_unicode.rar`: RAR 4 with Japanese (Unicode) names, see rar_reader_test.dart.
final rar4Unicode = base64Decode(
  'UmFyIRoHAM+QcwAADQAAAAAAAACoKXQgkpQAAAAAAAAAAAACAAAAACJp4T4UMG8AIAAA'
  'AJVcgr6C5lyQVoK1gqKDdINIg4uDX1yQVotLg2WDTINYg2cgg2iDTIOFg4GDk4NnLnR4'
  'dACIaGhgMIgwXKqwZVcwRDDVMKipMOswwDBcqrBlj4nGMK0workwyDAgyTCqrTDlMOEw'
  '8zCAyDAudHgAdADwJjmE5Jh0IJKTAAUAAAAFAAAAAtydb0K2VHQ+FDBuACAAAACVXIK+'
  'guZcir+OmpK3gqKDdINAg0ODi5a8bG9uZy1maWxlbmFtZS1pbi2Kv46aLnR4dACIaGhg'
  'MIgwXKoib1dbd5VEMKrVMKEwpDDrMIANVGxvbgBnLWZpAGxlbmEAbWUtaQpuLSJvV1sA'
  'LnR4dACwdnpoa2FuammULHTgklMAAAAAAAAAAAACAAAAACJp4T4UMC4AEAAAAJVcgr6C'
  '5lyQVoK1gqKDdINIg4uDXwCIaGhgMIgwXKqwZVcwRDDVMKipMOswwDAA8CY5hG14dOCS'
  'MwAAAAAAAAAAAAIAAAAAD2nhPhQwDgAQAAAAlVyCvoLmAIhoaGAwiDAA8OoJflkOdCCC'
  'SAA2AAAANgAAAAMlgvtdWFQLPxQwKADtoQAA6KGo44Gg44KIXOODleOCoeOCpOODqwCI'
  'aGhgMIgwXKrVMKEwpDDrMOa8ouWtl+mVt+OBhOODleOCoeOCpOODq+WQjWxvbmctZmls'
  'ZW5hbWUtaW4t5ryi5a2XLnR4dJtqdCCAQAAPAAAAEAAAAAMF0LYV3YRnQB0zIAC0gQAA'
  'YWJjZGVmZ2hpamtsbW5vcHFyc+ODhuOCueODiC50eHQAkP8Qf+S5/CeDMD0uHNLEPXsA'
  'QAcA',
);

/// `test_read_format_rar5_solid.rar`: RAR 5, solid: test.bin (1200 bytes) and test1.bin to test6.bin
/// (4096 bytes each).
final rar5Solid = base64Decode(
  'UmFyIRoHAQAJ78hvCwEFBwQGAQGAgIAA5TdjDCYCAwunAwSwCaSDAs1wynyAHQEIdGVz'
  'dC5iaW4KAxOLV6xb+BitHs01owEodlVWQfRgWNsMfHGMGDHxxiyyxjGWTGDBZZZZDHxs'
  'ssmMYskJ8ZCSST4yEhJJJISfOSSSEISSQhCSSQkkhCEvfnvmvfNaSlc5nqnT7me2XOjL'
  '3N9v7m97810a5zfXrl+/zvlq1rVa6df3Oct+a8/ebrdvo3u5W9/4ZoAEABANSlwHzz9f'
  'n7/b6fP4/D3+72+z1en0efzeXyeLw9/vdzt9rs9jr9XqdLo8/nc3mcvlcnkcbicLg8Df'
  'b3ebvdbncbfbbTZ7LYa/XazVanUafTaXSaLQ6DPZzN5nMV2Xy2VylVU1GTyOPx2MpqWk'
  'o8XicRhsLhJ+enZybmpnAX+/Xy9Xm73a6XO5XG3222SCoUa+yogW3hbbde0swbc8IjZl'
  'zQJhCQzSUcGW0JJtLIxSrP0XCT1Vq/flrHkjIlJW4pW4FLyRYKTKilCp7qVbKlo7wWxl'
  'i397LoX0vHLl9ZgpSZKgmiq5stXOFxZ0vBPE9nywNAVZQltcOXWoi/GKLB0ZZ2kLh0pe'
  'umKYxpZqnLj5AvlkioagtbUl3aoparLP1hdOtKTriMzcbuknAgMLgQEEgCCkgwLGshN+'
  'wB0BCXRlc3QxLmJpbgoDE2dfrFsaWp4QRmJ+aABABADVGzBJC0+9ne/6RJBbxBbbr2oJ'
  'g254RGzLmgTAEhmko4MtoSTaWRjG/BHxpLn6A2kojZlzQJfCQzSUcGW0JJtLIxjegj40'
  'lz1AbSURsy5oEvBIZpKODLaEk2lkYpTvhdljrlxu+Wuxb3V2EX64vXy4r3i4o3X/rjPw'
  'rqeSBCcCAwuYAASAIKSDAsuvZvHAHQEJdGVzdDIuYmluCgMTel+sWy1UcxdGCRVoAEAE'
  'ANbPj+/xgYzU/lO+I/x/M/Bo7yzjJwIDC6kABIAgpIMC2SOxn8AdAQl0ZXN0My5iaW4K'
  'AxN+X6xb0D0AA0Y6JmgAQAQA4TPj+sIf382Nq2gcSCNYAcSCNYAcSCNYAb5TviP8fzPw'
  'GKwj+ScCAwuYAASAIKSDAtQ+xBDAHQEJdGVzdDQuYmluCgMTgV+sW6EmHRJFChVoAEAE'
  'AOCz4/ojAxmx/Kd8R/j+Z+Dn4U6XJwIDC64ABIAgpIMC8lXRucAdAQl0ZXN0NS5iaW4K'
  'AxNcZ6xbG9RFEEQ1K2gAQAQA4DPj+saf395GaEuH2oQzQIMPtQhmfP4fahDM8ew/4U74'
  'j/H8z8BtS83NJwIDC5gABIAgpIMC/0ikNsAdAQl0ZXN0Ni5iaW4KAxNfZ6xbO4/UF0UK'
  'FWgAQAQA37Pj+iMDGbH8p3xH+P5n4B13VlEDBQQA',
);

/// `test_read_format_rar5_multiple_files.rar`: RAR 5: test1.bin to test4.bin, 4096 bytes each.
final rar5MultipleFiles = base64Decode(
  'UmFyIRoHAQDz4YLrCwEFBwAGAQGAgIAAAxaewicCAwvkAgSAIKSDAsayE36ABQEJdGVz'
  'dDEuYmluCgMTZ1+sWxpanhDK8WABEGRUZy9XBW9SSSSSSSSSSSSSSSSSSSSSSSSSSSSS'
  'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSST9/exzM7d9roun2pLrrtxu75nR5vOfJ8YzMM'
  '6cw1zOeZ5pz4n6gAgAgBsMPHTht6efl4+Hf3dvZ19XT0c/Ny8nHxcPBv727ube1s7Gvr'
  'aupp6WjoZ+dm5mXlZORj42LiYeFg4F/fXt5d3VzcW9ta2lnZWNhX11bWVdVU1FPTUtJR'
  '0VDQT89Ozk3NTMxLy0rKSclIyEfHRsZFxUTEQ8NCwkHBQMA/vz6+Pb1/fd9j3RS4Ut32'
  'cUKAz8MALZ0RvEaAh0IWsCwHCJ27S08IfnZoBZgBbOiN0jQEOhC1gWA4RO3KWnhD85NA'
  'LMALZ0RuEaAh0IWsCwHCJ23S08Ifm5oBZgBbOiNsjQEOhC1gWA4RNY/fRX5jVV99hK+m'
  '/FfMOU1zVNOtTQp+JH/+gE59beQnAgML5AIEgCCkgwLLr2bxgAUBCXRlc3QyLmJpbgoD'
  'E3pfrFstVHMXyfJgARBkVGcvVwVvUkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk'
  'kkkkkkkkkkkkkkkkkkkkkk/f3sczO3fa6Lp9qS667cbu+Z0ebznyfGMzDOnMNcznmeac'
  '+J+oAIAIAamHjpw29PPy8fDv7u3s6+rp6Ofm5eTj4uHg397d3Nva2djX1tXU09LR0M/O'
  'zczLysnIx8bFxMPCwcC/vr28u7q5uLe2tbSzsrGwr66trKuqqainpqWko6KhoJ+enZyb'
  'mpmYl5aVlJOSkZCPjo2Mi4qJiIeGhYSDgoGAf359fHt6/vu+x7opcKW77OKFAZ+GAFs6'
  'I3iNAQ6ELWBYDhE7dpaeEPzs0AswAtnRG6RoCHQhawLAcInblLTwh+cmgFmAFs6I3CNA'
  'Q6ELWBYDhE7bpaeEPzc0AswAtnRG2RoCHQhawLAcImsfvor8xqq++wlfTfivmHKa5qmn'
  'WpoU/Ej//QBzewC3JwIDC/ACBIAgpIMC2SOxn4AFAQl0ZXN0My5iaW4KAxN+X6xb0D0A'
  'A8n+bAEQdFVGL3V9SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS'
  'SSSSSSSSSTft+37exzmeOm72vC8dqS869czmZ3PDO85/T4xmYZ45nWHO5+/cOfyfqACA'
  'CAGwowusr6efl4+Hf3dvZ19XT0c/Ny8nHxcPBv727ube1s7Gvraupp6WjoZ+dm5mXlZO'
  'Rj42LiYeFg4F/fXt5d3VzcW9ta2lnZWNhX11bWVdVU1FPTUtJR0VDQT89Ozk3NTMxLy0'
  'rKSclIyEfHRsZFxUTEQ8NCwkHBQMA/vz6+Pb1/fe9T3BDfxDZezEGDqbCAmk4E2CZVg0'
  'wTbkwnjSZYUu3hEoeDTwA6GICaTgTXJlVzQ8abkANpMsKXbsiUPBp2AdDEBNJwJrEyqx'
  'oeNNyAG0mWFLt0RKHg06AOhiAmk4E1SZVU0PGm5ADaTLCl9T98EfmOVH32kj6b8R8xch'
  'zrUOPWhwafio//wAM0zNwCcCAwvwAgSAIKSDAtQ+xBCABQEJdGVzdDQuYmluCgMTgV+s'
  'W6EmHRLK/WwBEHRVRi91f5JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ'
  'JJJJJJJJJJJJJJJN+37d3sc5njpu9rwvHakvOvXM5mdzwzvOf0+MZmGeOZ1hzufv3Dn8'
  'n6gAgAgBrumFlVPTz8vHw7+7t7Ovq6ejn5uXk4+Lh4N/e3dzb2tnY19bV1NPS0dDPzs3'
  'My8rJyMfGxcTDwsHAv769vLu6ubi3trW0s7KxsK+urayrqqmop6alpKOioaCfnp2cm5q'
  'ZmJeWlZSTkpGQj46NjIuKiYiHhoWEg4KBgH9+fXx7ev773uvcEN/ENl7MQYOpsICaTgT'
  'YJlWDTBNuTCeNJlhS7XIlDwaXAOhiAmk4E1iZVY0PGm5ADaTLCl28IlDwaeAHQxATScC'
  'apMqqaHjTcgBtJlhS7dkSh4NOwDoYgJpOBNQmVUNDxpuQA2kywpfdfvgj8xyo++0kfTf'
  'iPmLkOdahx60ODT8VH/+AB13VlEDBQQA',
);

/// `test_read_format_rar4_encrypted.rar`: RAR 4: a.txt and c.txt readable ("This is from a.txt"), b.txt and
/// d.txt encrypted.
final rar4Encrypted = base64Decode(
  'UmFyIRoHAM+QcwAADQAAAAAAAAAqY3QgkCoAEgAAABIAAAACVW5a7mRXdlgdMAUAIAAA'
  'AGEudHh0APD8TBtUaGlzIGlzIGZyb20gYS50eHRfjnQklDIAIAAAABIAAAAChRT6qWdX'
  'dlgdMwUAIAAAAGIudHh0vgIbmnkqilUAsHKgNMn59g0Qf6jR1nzr1KS2yNRrgooen66w'
  'DfjatsdECurku8d0IJAqABIAAAASAAAAAjU9mpRuV3ZYHTAFACAAAABjLnR4dACwPkgt'
  'VGhpcyBpcyBmcm9tIGMudHh07cp0JJQyACAAAAASAAAAAiXhuiZNZHZYHTMFACAAAABk'
  'LnR4dK/ifRPzpVNSAPD7YY92+D/JR2gbUC02jMB4ydOpRar2iQPcvhjgjGZX2wT16cQ9'
  'ewBABwA=',
);

/// `test_read_format_rar5_encrypted.rar`: RAR 5, encrypted like [rar4Encrypted].
final rar5Encrypted = base64Decode(
  'UmFyIRoHAQAzkrXlCgEFBgAFAQGAgAA1/zIeHwIDCxIEEiBVblrugAAABWEudHh0CgMC'
  'fCGEo4J82gFUaGlzIGlzIGZyb20gYS50eHR6QXGzUAIDPDAEEiAYRaMCgAMABWIudHh0'
  'MAEAAw/HRF7hgPi1n9YrQzcIvFfN+jTfBqtdBdSTB3cPHY6AU+o1Zx1w8S1La5wanAoD'
  'AnJlmKaCfNoBY7pUstAQpUlftLrTwGmoOxu8uzgn14eTeHMvfJPi0ijEAN7+psA7fmxn'
  '1AVQANz4jXzxZh8CAwsSBBIgNT2alIAAAAVjLnR4dAoDAj5I6a6CfNoBVGhpcyBpcyBm'
  'cm9tIGMudHh07P3wXVICAzygAASSACDD32MSgAMABWQudHh0MAEAAw/HRF7hgPi1n9Yr'
  'QzcIvFfN883Wsxy0W6d8rDZYjrMOaYNM1EjpFevWrHe3owoDAnvFKfSPfNoB22ly9PZW'
  'jqb9GWXplbM2hTQ39Sqg0yeHsvXBAjLYql4dd1ZRAwUEAA==',
);

/// `test_read_format_rar_encryption_header.rar`: RAR 4 with encrypted file names: no entry can be listed.
final rar4EncryptedHeaders = base64Decode(
  'UmFyIRoHAM6Zc4AADQAAAAAAAADjLqtkp1x2jIRHQgDLysyfF2eRlxtxdgRzM7EaQ58b'
  'HnY/jQkFSsCaKbOiKstQBMBOSByi1fLAk0uZr4k8cUynzjcrVOE1V6w+SLWCMjUAx+uK'
  't3QJcE1M4y6rZKdcdoyqlt/wYnpuaKU6kwceLDrjja8yEJwG/PkSpHIUMXE+DS78M5Ck'
  'OS0EgiRDqN6E9yW/KIE3XLBqo8MI4oMHjXmjgiM8EReLj4NdANFmTjWFp+Muq2SnXHaM'
  'qmfUrzaWd0hrFE2d9SLu+g==',
);
