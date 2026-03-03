import 'dart:ui' show Rect;

/// Manifest for a single mokuro book discovered in a directory.
/// Contains paths but no parsed page data yet.
class MokuroBookManifest {
  final String title;
  final String htmlPath;
  final String imageDirPath;
  final String ocrDirPath;
  final List<String> imageFileNames;
  final String? safTreeUri;
  final String? safImageDirRelativePath;

  const MokuroBookManifest({
    required this.title,
    required this.htmlPath,
    required this.imageDirPath,
    required this.ocrDirPath,
    required this.imageFileNames,
    this.safTreeUri,
    this.safImageDirRelativePath,
  });
}

/// A fully parsed mokuro book with all page data.
class MokuroBook {
  static const int currentAutoCropVersion = 3;

  final String title;
  final String imageDirPath;
  final String? safTreeUri;
  final String? safImageDirRelativePath;
  final int autoCropVersion;
  final List<MokuroPage> pages;

  const MokuroBook({
    required this.title,
    required this.imageDirPath,
    this.safTreeUri,
    this.safImageDirRelativePath,
    this.autoCropVersion = 0,
    required this.pages,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'imageDirPath': imageDirPath,
    if (safTreeUri != null) 'safTreeUri': safTreeUri,
    if (safImageDirRelativePath != null)
      'safImageDirRelativePath': safImageDirRelativePath,
    'autoCropVersion': autoCropVersion,
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory MokuroBook.fromJson(Map<String, dynamic> json) => MokuroBook(
    title: (json['title'] as String?) ?? '',
    imageDirPath: json['imageDirPath'] as String,
    safTreeUri: json['safTreeUri'] as String?,
    safImageDirRelativePath: json['safImageDirRelativePath'] as String?,
    autoCropVersion: (json['autoCropVersion'] as num?)?.toInt() ?? 0,
    pages: (json['pages'] as List)
        .map((p) => MokuroPage.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

/// A single manga page with its OCR data and computed word positions.
class MokuroPage {
  final int pageIndex;
  final String imageFileName;
  final int imgWidth;
  final int imgHeight;
  final List<MokuroTextBlock> blocks;
  final Rect? contentBounds;

  const MokuroPage({
    required this.pageIndex,
    required this.imageFileName,
    required this.imgWidth,
    required this.imgHeight,
    required this.blocks,
    this.contentBounds,
  });

  MokuroPage copyWith({List<MokuroTextBlock>? blocks, Rect? contentBounds}) =>
      MokuroPage(
        pageIndex: pageIndex,
        imageFileName: imageFileName,
        imgWidth: imgWidth,
        imgHeight: imgHeight,
        blocks: blocks ?? this.blocks,
        contentBounds: contentBounds ?? this.contentBounds,
      );

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'imageFileName': imageFileName,
    'imgWidth': imgWidth,
    'imgHeight': imgHeight,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (contentBounds != null)
      'contentBounds': [
        contentBounds!.left,
        contentBounds!.top,
        contentBounds!.right,
        contentBounds!.bottom,
      ],
  };

  factory MokuroPage.fromJson(Map<String, dynamic> json) {
    final cb = json['contentBounds'] as List?;
    return MokuroPage(
      pageIndex: json['pageIndex'] as int,
      imageFileName: json['imageFileName'] as String,
      imgWidth: json['imgWidth'] as int,
      imgHeight: json['imgHeight'] as int,
      blocks: (json['blocks'] as List)
          .map((b) => MokuroTextBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      contentBounds: cb != null
          ? Rect.fromLTRB(
              (cb[0] as num).toDouble(),
              (cb[1] as num).toDouble(),
              (cb[2] as num).toDouble(),
              (cb[3] as num).toDouble(),
            )
          : null,
    );
  }
}

/// A text block (speech bubble or text region) from mokuro OCR.
class MokuroTextBlock {
  /// Bounding rectangle [x1, y1, x2, y2] in image pixel coordinates.
  final List<double> box;

  /// Whether the text is vertical (top-to-bottom).
  final bool vertical;

  /// Estimated font size from OCR.
  final double fontSize;

  /// Per-line quadrilateral coordinates: list of 4-point quads.
  /// Each quad is [[x1,y1],[x2,y2],[x3,y3],[x4,y4]].
  final List<List<List<double>>> linesCoords;

  /// Recognized text per line.
  final List<String> lines;

  /// Word-level data computed by MeCab segmentation.
  final List<MokuroWord> words;

  const MokuroTextBlock({
    required this.box,
    required this.vertical,
    required this.fontSize,
    required this.linesCoords,
    required this.lines,
    this.words = const [],
  });

  /// Full text of this block (all lines concatenated).
  String get fullText => lines.join();

  MokuroTextBlock copyWith({List<MokuroWord>? words}) => MokuroTextBlock(
    box: box,
    vertical: vertical,
    fontSize: fontSize,
    linesCoords: linesCoords,
    lines: lines,
    words: words ?? this.words,
  );

  Map<String, dynamic> toJson() => {
    'box': box,
    'vertical': vertical,
    'fontSize': fontSize,
    'linesCoords': linesCoords,
    'lines': lines,
    'words': words.map((w) => w.toJson()).toList(),
  };

  factory MokuroTextBlock.fromJson(
    Map<String, dynamic> json,
  ) => MokuroTextBlock(
    box: (json['box'] as List).map((e) => (e as num).toDouble()).toList(),
    vertical: json['vertical'] as bool,
    fontSize: (json['fontSize'] as num).toDouble(),
    linesCoords: (json['linesCoords'] as List)
        .map(
          (line) => (line as List)
              .map(
                (point) =>
                    (point as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList(),
        )
        .toList(),
    lines: (json['lines'] as List).cast<String>(),
    words:
        (json['words'] as List?)
            ?.map((w) => MokuroWord.fromJson(w as Map<String, dynamic>))
            .toList() ??
        [],
  );

  /// Parse a mokuro OCR JSON block into a [MokuroTextBlock].
  factory MokuroTextBlock.fromOcrJson(
    Map<String, dynamic> json,
  ) => MokuroTextBlock(
    box: (json['box'] as List).map((e) => (e as num).toDouble()).toList(),
    vertical: json['vertical'] as bool,
    fontSize: (json['font_size'] as num).toDouble(),
    linesCoords: (json['lines_coords'] as List)
        .map(
          (line) => (line as List)
              .map(
                (point) =>
                    (point as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList(),
        )
        .toList(),
    lines: (json['lines'] as List).cast<String>(),
  );
}

/// A single word within a text block, with its bounding box in image coords.
class MokuroWord {
  final String surface;
  final String? dictionaryForm;
  final String? reading;

  /// Bounding box in image pixel coordinates.
  final Rect boundingBox;

  final int blockIndex;
  final int lineIndex;
  final int charStartInLine;
  final int charEndInLine;

  const MokuroWord({
    required this.surface,
    this.dictionaryForm,
    this.reading,
    required this.boundingBox,
    required this.blockIndex,
    required this.lineIndex,
    required this.charStartInLine,
    required this.charEndInLine,
  });

  Map<String, dynamic> toJson() => {
    'surface': surface,
    if (dictionaryForm != null) 'dictForm': dictionaryForm,
    if (reading != null) 'reading': reading,
    'box': [
      boundingBox.left,
      boundingBox.top,
      boundingBox.right,
      boundingBox.bottom,
    ],
    'blockIdx': blockIndex,
    'lineIdx': lineIndex,
    'charStart': charStartInLine,
    'charEnd': charEndInLine,
  };

  factory MokuroWord.fromJson(Map<String, dynamic> json) {
    final box = json['box'] as List;
    return MokuroWord(
      surface: json['surface'] as String,
      dictionaryForm: json['dictForm'] as String?,
      reading: json['reading'] as String?,
      boundingBox: Rect.fromLTRB(
        (box[0] as num).toDouble(),
        (box[1] as num).toDouble(),
        (box[2] as num).toDouble(),
        (box[3] as num).toDouble(),
      ),
      blockIndex: json['blockIdx'] as int,
      lineIndex: json['lineIdx'] as int,
      charStartInLine: json['charStart'] as int,
      charEndInLine: json['charEnd'] as int,
    );
  }
}
