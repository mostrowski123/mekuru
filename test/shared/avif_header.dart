import 'dart:typed_data';

List<int> _u32(int v) => [
  v >> 24 & 0xFF,
  v >> 16 & 0xFF,
  v >> 8 & 0xFF,
  v & 0xFF,
];

List<int> _box(String type, List<int> body) => [
  ..._u32(8 + body.length),
  ...type.codeUnits,
  ...body,
];

List<int> _ispe(int width, int height) =>
    _box('ispe', [0, 0, 0, 0, ..._u32(width), ..._u32(height)]);

/// The header of a 1200x1700 AVIF page as encoders lay it out: ftyp, then
/// meta holding a 64x91 thumbnail's, the image's and its alpha plane's sizes,
/// then mdat with a size of 0 (to the end of the file).
Uint8List avifHeader({String major = 'avif', String compatible = 'mif1'}) =>
    Uint8List.fromList([
      ..._box('ftyp', [
        ...major.codeUnits,
        0, 0, 0, 0, // minor version
        ...compatible.codeUnits,
        ...'miaf'.codeUnits,
      ]),
      ..._box('meta', [
        0, 0, 0, 0, // version and flags
        ..._box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...'pict'.codeUnits]),
        ..._box('iprp', [
          ..._box('ipco', [
            ..._ispe(64, 91),
            ..._ispe(1200, 1700),
            ..._ispe(1200, 1700),
          ]),
        ]),
      ]),
      ..._u32(0),
      ...'mdat'.codeUnits,
      1,
      2,
      3,
    ]);

/// A 96x128 AVIF page (white, a black frame, a dark block) encoded by macOS
/// ImageIO: real encoder output, `irot` box included.
const avifPageBase64 =
    'AAAAIGZ0eXBhdmlmAAAAAE1pUHJhdmlmbWlhZm1pZjEAAAEhbWV0YQAAAAAAAAAhaGRs'
    'cgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAAAAAAAkZGluZgAAABxkcmVmAAAAAAAAAAEA'
    'AAAMdXJsIAAAAAEAAAAOcGl0bQAAAAAAAQAAACNpaW5mAAAAAAABAAAAFWluZmUCAAAA'
    'AAEAAGF2MDEAAAAAgWlwcnAAAABgaXBjbwAAABNjb2xybmNseAACAAIABoAAAAAMY2xs'
    'aQDLAEAAAAAUaXNwZQAAAAAAAABgAAAAgAAAAAlpcm90AAAAABBwaXhpAAAAAAMICAgA'
    'AAAMYXYxQ4EADAAAAAAZaXBtYQAAAAAAAAABAAEGgQIDBYaEAAAAHmlsb2MAAAAARAAA'
    'AQABAAAAAQAAAVEAAACCAAAAAW1kYXQAAAAAAAAAkhIACg0AAAADNf/n/8CBAQNCMm8U'
    'AGMgAwwwwgDdNOnVVqQa7PihyVt43VfZThhCUPYoOa0nRh2o6bwmKnR//IBJ4AsWQU4v'
    'ofPor/hrQUbdqH7bOA8iOXdaS54HynNIjQAVfIUU8TS0/v0di8Boa3uOOQsJzKc6/I17'
    'GfSZRKyb/zY=';
