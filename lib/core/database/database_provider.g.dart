// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_provider.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookTypeMeta = const VerificationMeta(
    'bookType',
  );
  @override
  late final GeneratedColumn<String> bookType = GeneratedColumn<String>(
    'book_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('epub'),
  );
  static const VerificationMeta _coverImagePathMeta = const VerificationMeta(
    'coverImagePath',
  );
  @override
  late final GeneratedColumn<String> coverImagePath = GeneratedColumn<String>(
    'cover_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalPagesMeta = const VerificationMeta(
    'totalPages',
  );
  @override
  late final GeneratedColumn<int> totalPages = GeneratedColumn<int>(
    'total_pages',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReadCfiMeta = const VerificationMeta(
    'lastReadCfi',
  );
  @override
  late final GeneratedColumn<String> lastReadCfi = GeneratedColumn<String>(
    'last_read_cfi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readProgressMeta = const VerificationMeta(
    'readProgress',
  );
  @override
  late final GeneratedColumn<double> readProgress = GeneratedColumn<double>(
    'read_progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageProgressionDirectionMeta =
      const VerificationMeta('pageProgressionDirection');
  @override
  late final GeneratedColumn<String> pageProgressionDirection =
      GeneratedColumn<String>(
        'page_progression_direction',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _primaryWritingModeMeta =
      const VerificationMeta('primaryWritingMode');
  @override
  late final GeneratedColumn<String> primaryWritingMode =
      GeneratedColumn<String>(
        'primary_writing_mode',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _overrideVerticalTextMeta =
      const VerificationMeta('overrideVerticalText');
  @override
  late final GeneratedColumn<bool> overrideVerticalText = GeneratedColumn<bool>(
    'override_vertical_text',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("override_vertical_text" IN (0, 1))',
    ),
  );
  static const VerificationMeta _overrideReadingDirectionMeta =
      const VerificationMeta('overrideReadingDirection');
  @override
  late final GeneratedColumn<String> overrideReadingDirection =
      GeneratedColumn<String>(
        'override_reading_direction',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    filePath,
    bookType,
    coverImagePath,
    totalPages,
    lastReadCfi,
    readProgress,
    dateAdded,
    lastReadAt,
    language,
    pageProgressionDirection,
    primaryWritingMode,
    overrideVerticalText,
    overrideReadingDirection,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<Book> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('book_type')) {
      context.handle(
        _bookTypeMeta,
        bookType.isAcceptableOrUnknown(data['book_type']!, _bookTypeMeta),
      );
    }
    if (data.containsKey('cover_image_path')) {
      context.handle(
        _coverImagePathMeta,
        coverImagePath.isAcceptableOrUnknown(
          data['cover_image_path']!,
          _coverImagePathMeta,
        ),
      );
    }
    if (data.containsKey('total_pages')) {
      context.handle(
        _totalPagesMeta,
        totalPages.isAcceptableOrUnknown(data['total_pages']!, _totalPagesMeta),
      );
    }
    if (data.containsKey('last_read_cfi')) {
      context.handle(
        _lastReadCfiMeta,
        lastReadCfi.isAcceptableOrUnknown(
          data['last_read_cfi']!,
          _lastReadCfiMeta,
        ),
      );
    }
    if (data.containsKey('read_progress')) {
      context.handle(
        _readProgressMeta,
        readProgress.isAcceptableOrUnknown(
          data['read_progress']!,
          _readProgressMeta,
        ),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('page_progression_direction')) {
      context.handle(
        _pageProgressionDirectionMeta,
        pageProgressionDirection.isAcceptableOrUnknown(
          data['page_progression_direction']!,
          _pageProgressionDirectionMeta,
        ),
      );
    }
    if (data.containsKey('primary_writing_mode')) {
      context.handle(
        _primaryWritingModeMeta,
        primaryWritingMode.isAcceptableOrUnknown(
          data['primary_writing_mode']!,
          _primaryWritingModeMeta,
        ),
      );
    }
    if (data.containsKey('override_vertical_text')) {
      context.handle(
        _overrideVerticalTextMeta,
        overrideVerticalText.isAcceptableOrUnknown(
          data['override_vertical_text']!,
          _overrideVerticalTextMeta,
        ),
      );
    }
    if (data.containsKey('override_reading_direction')) {
      context.handle(
        _overrideReadingDirectionMeta,
        overrideReadingDirection.isAcceptableOrUnknown(
          data['override_reading_direction']!,
          _overrideReadingDirectionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      bookType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_type'],
      )!,
      coverImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image_path'],
      ),
      totalPages: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_pages'],
      )!,
      lastReadCfi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_read_cfi'],
      ),
      readProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}read_progress'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      pageProgressionDirection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_progression_direction'],
      ),
      primaryWritingMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}primary_writing_mode'],
      ),
      overrideVerticalText: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}override_vertical_text'],
      ),
      overrideReadingDirection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}override_reading_direction'],
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class Book extends DataClass implements Insertable<Book> {
  final int id;
  final String title;
  final String filePath;

  /// Book format: 'epub' or 'manga'. Defaults to 'epub' for backward compat.
  final String bookType;
  final String? coverImagePath;
  final int totalPages;
  final String? lastReadCfi;
  final double readProgress;
  final DateTime dateAdded;
  final DateTime? lastReadAt;
  final String? language;
  final String? pageProgressionDirection;

  /// The `primary-writing-mode` from OPF metadata (e.g. `vertical-rl`,
  /// `horizontal-tb`). Used to determine whether content is vertical text.
  final String? primaryWritingMode;

  /// User's per-book override for vertical text display.
  /// `null` means "use the book's default" (based on language/ppd).
  final bool? overrideVerticalText;

  /// User's per-book override for reading direction ('ltr' or 'rtl').
  /// `null` means "use the book's default" (based on language/ppd).
  final String? overrideReadingDirection;
  const Book({
    required this.id,
    required this.title,
    required this.filePath,
    required this.bookType,
    this.coverImagePath,
    required this.totalPages,
    this.lastReadCfi,
    required this.readProgress,
    required this.dateAdded,
    this.lastReadAt,
    this.language,
    this.pageProgressionDirection,
    this.primaryWritingMode,
    this.overrideVerticalText,
    this.overrideReadingDirection,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['file_path'] = Variable<String>(filePath);
    map['book_type'] = Variable<String>(bookType);
    if (!nullToAbsent || coverImagePath != null) {
      map['cover_image_path'] = Variable<String>(coverImagePath);
    }
    map['total_pages'] = Variable<int>(totalPages);
    if (!nullToAbsent || lastReadCfi != null) {
      map['last_read_cfi'] = Variable<String>(lastReadCfi);
    }
    map['read_progress'] = Variable<double>(readProgress);
    map['date_added'] = Variable<DateTime>(dateAdded);
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || pageProgressionDirection != null) {
      map['page_progression_direction'] = Variable<String>(
        pageProgressionDirection,
      );
    }
    if (!nullToAbsent || primaryWritingMode != null) {
      map['primary_writing_mode'] = Variable<String>(primaryWritingMode);
    }
    if (!nullToAbsent || overrideVerticalText != null) {
      map['override_vertical_text'] = Variable<bool>(overrideVerticalText);
    }
    if (!nullToAbsent || overrideReadingDirection != null) {
      map['override_reading_direction'] = Variable<String>(
        overrideReadingDirection,
      );
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      filePath: Value(filePath),
      bookType: Value(bookType),
      coverImagePath: coverImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverImagePath),
      totalPages: Value(totalPages),
      lastReadCfi: lastReadCfi == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadCfi),
      readProgress: Value(readProgress),
      dateAdded: Value(dateAdded),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      pageProgressionDirection: pageProgressionDirection == null && nullToAbsent
          ? const Value.absent()
          : Value(pageProgressionDirection),
      primaryWritingMode: primaryWritingMode == null && nullToAbsent
          ? const Value.absent()
          : Value(primaryWritingMode),
      overrideVerticalText: overrideVerticalText == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideVerticalText),
      overrideReadingDirection: overrideReadingDirection == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideReadingDirection),
    );
  }

  factory Book.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Book(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      filePath: serializer.fromJson<String>(json['filePath']),
      bookType: serializer.fromJson<String>(json['bookType']),
      coverImagePath: serializer.fromJson<String?>(json['coverImagePath']),
      totalPages: serializer.fromJson<int>(json['totalPages']),
      lastReadCfi: serializer.fromJson<String?>(json['lastReadCfi']),
      readProgress: serializer.fromJson<double>(json['readProgress']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      language: serializer.fromJson<String?>(json['language']),
      pageProgressionDirection: serializer.fromJson<String?>(
        json['pageProgressionDirection'],
      ),
      primaryWritingMode: serializer.fromJson<String?>(
        json['primaryWritingMode'],
      ),
      overrideVerticalText: serializer.fromJson<bool?>(
        json['overrideVerticalText'],
      ),
      overrideReadingDirection: serializer.fromJson<String?>(
        json['overrideReadingDirection'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'filePath': serializer.toJson<String>(filePath),
      'bookType': serializer.toJson<String>(bookType),
      'coverImagePath': serializer.toJson<String?>(coverImagePath),
      'totalPages': serializer.toJson<int>(totalPages),
      'lastReadCfi': serializer.toJson<String?>(lastReadCfi),
      'readProgress': serializer.toJson<double>(readProgress),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'language': serializer.toJson<String?>(language),
      'pageProgressionDirection': serializer.toJson<String?>(
        pageProgressionDirection,
      ),
      'primaryWritingMode': serializer.toJson<String?>(primaryWritingMode),
      'overrideVerticalText': serializer.toJson<bool?>(overrideVerticalText),
      'overrideReadingDirection': serializer.toJson<String?>(
        overrideReadingDirection,
      ),
    };
  }

  Book copyWith({
    int? id,
    String? title,
    String? filePath,
    String? bookType,
    Value<String?> coverImagePath = const Value.absent(),
    int? totalPages,
    Value<String?> lastReadCfi = const Value.absent(),
    double? readProgress,
    DateTime? dateAdded,
    Value<DateTime?> lastReadAt = const Value.absent(),
    Value<String?> language = const Value.absent(),
    Value<String?> pageProgressionDirection = const Value.absent(),
    Value<String?> primaryWritingMode = const Value.absent(),
    Value<bool?> overrideVerticalText = const Value.absent(),
    Value<String?> overrideReadingDirection = const Value.absent(),
  }) => Book(
    id: id ?? this.id,
    title: title ?? this.title,
    filePath: filePath ?? this.filePath,
    bookType: bookType ?? this.bookType,
    coverImagePath: coverImagePath.present
        ? coverImagePath.value
        : this.coverImagePath,
    totalPages: totalPages ?? this.totalPages,
    lastReadCfi: lastReadCfi.present ? lastReadCfi.value : this.lastReadCfi,
    readProgress: readProgress ?? this.readProgress,
    dateAdded: dateAdded ?? this.dateAdded,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    language: language.present ? language.value : this.language,
    pageProgressionDirection: pageProgressionDirection.present
        ? pageProgressionDirection.value
        : this.pageProgressionDirection,
    primaryWritingMode: primaryWritingMode.present
        ? primaryWritingMode.value
        : this.primaryWritingMode,
    overrideVerticalText: overrideVerticalText.present
        ? overrideVerticalText.value
        : this.overrideVerticalText,
    overrideReadingDirection: overrideReadingDirection.present
        ? overrideReadingDirection.value
        : this.overrideReadingDirection,
  );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      bookType: data.bookType.present ? data.bookType.value : this.bookType,
      coverImagePath: data.coverImagePath.present
          ? data.coverImagePath.value
          : this.coverImagePath,
      totalPages: data.totalPages.present
          ? data.totalPages.value
          : this.totalPages,
      lastReadCfi: data.lastReadCfi.present
          ? data.lastReadCfi.value
          : this.lastReadCfi,
      readProgress: data.readProgress.present
          ? data.readProgress.value
          : this.readProgress,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      language: data.language.present ? data.language.value : this.language,
      pageProgressionDirection: data.pageProgressionDirection.present
          ? data.pageProgressionDirection.value
          : this.pageProgressionDirection,
      primaryWritingMode: data.primaryWritingMode.present
          ? data.primaryWritingMode.value
          : this.primaryWritingMode,
      overrideVerticalText: data.overrideVerticalText.present
          ? data.overrideVerticalText.value
          : this.overrideVerticalText,
      overrideReadingDirection: data.overrideReadingDirection.present
          ? data.overrideReadingDirection.value
          : this.overrideReadingDirection,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('filePath: $filePath, ')
          ..write('bookType: $bookType, ')
          ..write('coverImagePath: $coverImagePath, ')
          ..write('totalPages: $totalPages, ')
          ..write('lastReadCfi: $lastReadCfi, ')
          ..write('readProgress: $readProgress, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('language: $language, ')
          ..write('pageProgressionDirection: $pageProgressionDirection, ')
          ..write('primaryWritingMode: $primaryWritingMode, ')
          ..write('overrideVerticalText: $overrideVerticalText, ')
          ..write('overrideReadingDirection: $overrideReadingDirection')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    filePath,
    bookType,
    coverImagePath,
    totalPages,
    lastReadCfi,
    readProgress,
    dateAdded,
    lastReadAt,
    language,
    pageProgressionDirection,
    primaryWritingMode,
    overrideVerticalText,
    overrideReadingDirection,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.filePath == this.filePath &&
          other.bookType == this.bookType &&
          other.coverImagePath == this.coverImagePath &&
          other.totalPages == this.totalPages &&
          other.lastReadCfi == this.lastReadCfi &&
          other.readProgress == this.readProgress &&
          other.dateAdded == this.dateAdded &&
          other.lastReadAt == this.lastReadAt &&
          other.language == this.language &&
          other.pageProgressionDirection == this.pageProgressionDirection &&
          other.primaryWritingMode == this.primaryWritingMode &&
          other.overrideVerticalText == this.overrideVerticalText &&
          other.overrideReadingDirection == this.overrideReadingDirection);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> filePath;
  final Value<String> bookType;
  final Value<String?> coverImagePath;
  final Value<int> totalPages;
  final Value<String?> lastReadCfi;
  final Value<double> readProgress;
  final Value<DateTime> dateAdded;
  final Value<DateTime?> lastReadAt;
  final Value<String?> language;
  final Value<String?> pageProgressionDirection;
  final Value<String?> primaryWritingMode;
  final Value<bool?> overrideVerticalText;
  final Value<String?> overrideReadingDirection;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.filePath = const Value.absent(),
    this.bookType = const Value.absent(),
    this.coverImagePath = const Value.absent(),
    this.totalPages = const Value.absent(),
    this.lastReadCfi = const Value.absent(),
    this.readProgress = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.language = const Value.absent(),
    this.pageProgressionDirection = const Value.absent(),
    this.primaryWritingMode = const Value.absent(),
    this.overrideVerticalText = const Value.absent(),
    this.overrideReadingDirection = const Value.absent(),
  });
  BooksCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String filePath,
    this.bookType = const Value.absent(),
    this.coverImagePath = const Value.absent(),
    this.totalPages = const Value.absent(),
    this.lastReadCfi = const Value.absent(),
    this.readProgress = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.language = const Value.absent(),
    this.pageProgressionDirection = const Value.absent(),
    this.primaryWritingMode = const Value.absent(),
    this.overrideVerticalText = const Value.absent(),
    this.overrideReadingDirection = const Value.absent(),
  }) : title = Value(title),
       filePath = Value(filePath);
  static Insertable<Book> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? filePath,
    Expression<String>? bookType,
    Expression<String>? coverImagePath,
    Expression<int>? totalPages,
    Expression<String>? lastReadCfi,
    Expression<double>? readProgress,
    Expression<DateTime>? dateAdded,
    Expression<DateTime>? lastReadAt,
    Expression<String>? language,
    Expression<String>? pageProgressionDirection,
    Expression<String>? primaryWritingMode,
    Expression<bool>? overrideVerticalText,
    Expression<String>? overrideReadingDirection,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (filePath != null) 'file_path': filePath,
      if (bookType != null) 'book_type': bookType,
      if (coverImagePath != null) 'cover_image_path': coverImagePath,
      if (totalPages != null) 'total_pages': totalPages,
      if (lastReadCfi != null) 'last_read_cfi': lastReadCfi,
      if (readProgress != null) 'read_progress': readProgress,
      if (dateAdded != null) 'date_added': dateAdded,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (language != null) 'language': language,
      if (pageProgressionDirection != null)
        'page_progression_direction': pageProgressionDirection,
      if (primaryWritingMode != null)
        'primary_writing_mode': primaryWritingMode,
      if (overrideVerticalText != null)
        'override_vertical_text': overrideVerticalText,
      if (overrideReadingDirection != null)
        'override_reading_direction': overrideReadingDirection,
    });
  }

  BooksCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? filePath,
    Value<String>? bookType,
    Value<String?>? coverImagePath,
    Value<int>? totalPages,
    Value<String?>? lastReadCfi,
    Value<double>? readProgress,
    Value<DateTime>? dateAdded,
    Value<DateTime?>? lastReadAt,
    Value<String?>? language,
    Value<String?>? pageProgressionDirection,
    Value<String?>? primaryWritingMode,
    Value<bool?>? overrideVerticalText,
    Value<String?>? overrideReadingDirection,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      bookType: bookType ?? this.bookType,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      totalPages: totalPages ?? this.totalPages,
      lastReadCfi: lastReadCfi ?? this.lastReadCfi,
      readProgress: readProgress ?? this.readProgress,
      dateAdded: dateAdded ?? this.dateAdded,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      language: language ?? this.language,
      pageProgressionDirection:
          pageProgressionDirection ?? this.pageProgressionDirection,
      primaryWritingMode: primaryWritingMode ?? this.primaryWritingMode,
      overrideVerticalText: overrideVerticalText ?? this.overrideVerticalText,
      overrideReadingDirection:
          overrideReadingDirection ?? this.overrideReadingDirection,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (bookType.present) {
      map['book_type'] = Variable<String>(bookType.value);
    }
    if (coverImagePath.present) {
      map['cover_image_path'] = Variable<String>(coverImagePath.value);
    }
    if (totalPages.present) {
      map['total_pages'] = Variable<int>(totalPages.value);
    }
    if (lastReadCfi.present) {
      map['last_read_cfi'] = Variable<String>(lastReadCfi.value);
    }
    if (readProgress.present) {
      map['read_progress'] = Variable<double>(readProgress.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (pageProgressionDirection.present) {
      map['page_progression_direction'] = Variable<String>(
        pageProgressionDirection.value,
      );
    }
    if (primaryWritingMode.present) {
      map['primary_writing_mode'] = Variable<String>(primaryWritingMode.value);
    }
    if (overrideVerticalText.present) {
      map['override_vertical_text'] = Variable<bool>(
        overrideVerticalText.value,
      );
    }
    if (overrideReadingDirection.present) {
      map['override_reading_direction'] = Variable<String>(
        overrideReadingDirection.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('filePath: $filePath, ')
          ..write('bookType: $bookType, ')
          ..write('coverImagePath: $coverImagePath, ')
          ..write('totalPages: $totalPages, ')
          ..write('lastReadCfi: $lastReadCfi, ')
          ..write('readProgress: $readProgress, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('language: $language, ')
          ..write('pageProgressionDirection: $pageProgressionDirection, ')
          ..write('primaryWritingMode: $primaryWritingMode, ')
          ..write('overrideVerticalText: $overrideVerticalText, ')
          ..write('overrideReadingDirection: $overrideReadingDirection')
          ..write(')'))
        .toString();
  }
}

class $SavedWordsTable extends SavedWords
    with TableInfo<$SavedWordsTable, SavedWord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedWordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _expressionMeta = const VerificationMeta(
    'expression',
  );
  @override
  late final GeneratedColumn<String> expression = GeneratedColumn<String>(
    'expression',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readingMeta = const VerificationMeta(
    'reading',
  );
  @override
  late final GeneratedColumn<String> reading = GeneratedColumn<String>(
    'reading',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _glossariesMeta = const VerificationMeta(
    'glossaries',
  );
  @override
  late final GeneratedColumn<String> glossaries = GeneratedColumn<String>(
    'glossaries',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentenceContextMeta = const VerificationMeta(
    'sentenceContext',
  );
  @override
  late final GeneratedColumn<String> sentenceContext = GeneratedColumn<String>(
    'sentence_context',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    expression,
    reading,
    glossaries,
    sentenceContext,
    dateAdded,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_words';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedWord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('expression')) {
      context.handle(
        _expressionMeta,
        expression.isAcceptableOrUnknown(data['expression']!, _expressionMeta),
      );
    } else if (isInserting) {
      context.missing(_expressionMeta);
    }
    if (data.containsKey('reading')) {
      context.handle(
        _readingMeta,
        reading.isAcceptableOrUnknown(data['reading']!, _readingMeta),
      );
    }
    if (data.containsKey('glossaries')) {
      context.handle(
        _glossariesMeta,
        glossaries.isAcceptableOrUnknown(data['glossaries']!, _glossariesMeta),
      );
    } else if (isInserting) {
      context.missing(_glossariesMeta);
    }
    if (data.containsKey('sentence_context')) {
      context.handle(
        _sentenceContextMeta,
        sentenceContext.isAcceptableOrUnknown(
          data['sentence_context']!,
          _sentenceContextMeta,
        ),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedWord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedWord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      expression: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expression'],
      )!,
      reading: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reading'],
      )!,
      glossaries: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}glossaries'],
      )!,
      sentenceContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sentence_context'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
    );
  }

  @override
  $SavedWordsTable createAlias(String alias) {
    return $SavedWordsTable(attachedDatabase, alias);
  }
}

class SavedWord extends DataClass implements Insertable<SavedWord> {
  final int id;
  final String expression;
  final String reading;
  final String glossaries;
  final String sentenceContext;
  final DateTime dateAdded;
  const SavedWord({
    required this.id,
    required this.expression,
    required this.reading,
    required this.glossaries,
    required this.sentenceContext,
    required this.dateAdded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['expression'] = Variable<String>(expression);
    map['reading'] = Variable<String>(reading);
    map['glossaries'] = Variable<String>(glossaries);
    map['sentence_context'] = Variable<String>(sentenceContext);
    map['date_added'] = Variable<DateTime>(dateAdded);
    return map;
  }

  SavedWordsCompanion toCompanion(bool nullToAbsent) {
    return SavedWordsCompanion(
      id: Value(id),
      expression: Value(expression),
      reading: Value(reading),
      glossaries: Value(glossaries),
      sentenceContext: Value(sentenceContext),
      dateAdded: Value(dateAdded),
    );
  }

  factory SavedWord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedWord(
      id: serializer.fromJson<int>(json['id']),
      expression: serializer.fromJson<String>(json['expression']),
      reading: serializer.fromJson<String>(json['reading']),
      glossaries: serializer.fromJson<String>(json['glossaries']),
      sentenceContext: serializer.fromJson<String>(json['sentenceContext']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'expression': serializer.toJson<String>(expression),
      'reading': serializer.toJson<String>(reading),
      'glossaries': serializer.toJson<String>(glossaries),
      'sentenceContext': serializer.toJson<String>(sentenceContext),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
    };
  }

  SavedWord copyWith({
    int? id,
    String? expression,
    String? reading,
    String? glossaries,
    String? sentenceContext,
    DateTime? dateAdded,
  }) => SavedWord(
    id: id ?? this.id,
    expression: expression ?? this.expression,
    reading: reading ?? this.reading,
    glossaries: glossaries ?? this.glossaries,
    sentenceContext: sentenceContext ?? this.sentenceContext,
    dateAdded: dateAdded ?? this.dateAdded,
  );
  SavedWord copyWithCompanion(SavedWordsCompanion data) {
    return SavedWord(
      id: data.id.present ? data.id.value : this.id,
      expression: data.expression.present
          ? data.expression.value
          : this.expression,
      reading: data.reading.present ? data.reading.value : this.reading,
      glossaries: data.glossaries.present
          ? data.glossaries.value
          : this.glossaries,
      sentenceContext: data.sentenceContext.present
          ? data.sentenceContext.value
          : this.sentenceContext,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedWord(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('glossaries: $glossaries, ')
          ..write('sentenceContext: $sentenceContext, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    expression,
    reading,
    glossaries,
    sentenceContext,
    dateAdded,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedWord &&
          other.id == this.id &&
          other.expression == this.expression &&
          other.reading == this.reading &&
          other.glossaries == this.glossaries &&
          other.sentenceContext == this.sentenceContext &&
          other.dateAdded == this.dateAdded);
}

class SavedWordsCompanion extends UpdateCompanion<SavedWord> {
  final Value<int> id;
  final Value<String> expression;
  final Value<String> reading;
  final Value<String> glossaries;
  final Value<String> sentenceContext;
  final Value<DateTime> dateAdded;
  const SavedWordsCompanion({
    this.id = const Value.absent(),
    this.expression = const Value.absent(),
    this.reading = const Value.absent(),
    this.glossaries = const Value.absent(),
    this.sentenceContext = const Value.absent(),
    this.dateAdded = const Value.absent(),
  });
  SavedWordsCompanion.insert({
    this.id = const Value.absent(),
    required String expression,
    this.reading = const Value.absent(),
    required String glossaries,
    this.sentenceContext = const Value.absent(),
    this.dateAdded = const Value.absent(),
  }) : expression = Value(expression),
       glossaries = Value(glossaries);
  static Insertable<SavedWord> custom({
    Expression<int>? id,
    Expression<String>? expression,
    Expression<String>? reading,
    Expression<String>? glossaries,
    Expression<String>? sentenceContext,
    Expression<DateTime>? dateAdded,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expression != null) 'expression': expression,
      if (reading != null) 'reading': reading,
      if (glossaries != null) 'glossaries': glossaries,
      if (sentenceContext != null) 'sentence_context': sentenceContext,
      if (dateAdded != null) 'date_added': dateAdded,
    });
  }

  SavedWordsCompanion copyWith({
    Value<int>? id,
    Value<String>? expression,
    Value<String>? reading,
    Value<String>? glossaries,
    Value<String>? sentenceContext,
    Value<DateTime>? dateAdded,
  }) {
    return SavedWordsCompanion(
      id: id ?? this.id,
      expression: expression ?? this.expression,
      reading: reading ?? this.reading,
      glossaries: glossaries ?? this.glossaries,
      sentenceContext: sentenceContext ?? this.sentenceContext,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (expression.present) {
      map['expression'] = Variable<String>(expression.value);
    }
    if (reading.present) {
      map['reading'] = Variable<String>(reading.value);
    }
    if (glossaries.present) {
      map['glossaries'] = Variable<String>(glossaries.value);
    }
    if (sentenceContext.present) {
      map['sentence_context'] = Variable<String>(sentenceContext.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedWordsCompanion(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('glossaries: $glossaries, ')
          ..write('sentenceContext: $sentenceContext, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }
}

class $DictionaryMetasTable extends DictionaryMetas
    with TableInfo<$DictionaryMetasTable, DictionaryMeta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DictionaryMetasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _dateImportedMeta = const VerificationMeta(
    'dateImported',
  );
  @override
  late final GeneratedColumn<DateTime> dateImported = GeneratedColumn<DateTime>(
    'date_imported',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isHiddenMeta = const VerificationMeta(
    'isHidden',
  );
  @override
  late final GeneratedColumn<bool> isHidden = GeneratedColumn<bool>(
    'is_hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    isEnabled,
    dateImported,
    sortOrder,
    isHidden,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dictionary_metas';
  @override
  VerificationContext validateIntegrity(
    Insertable<DictionaryMeta> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    }
    if (data.containsKey('date_imported')) {
      context.handle(
        _dateImportedMeta,
        dateImported.isAcceptableOrUnknown(
          data['date_imported']!,
          _dateImportedMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_hidden')) {
      context.handle(
        _isHiddenMeta,
        isHidden.isAcceptableOrUnknown(data['is_hidden']!, _isHiddenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DictionaryMeta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DictionaryMeta(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      dateImported: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_imported'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isHidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_hidden'],
      )!,
    );
  }

  @override
  $DictionaryMetasTable createAlias(String alias) {
    return $DictionaryMetasTable(attachedDatabase, alias);
  }
}

class DictionaryMeta extends DataClass implements Insertable<DictionaryMeta> {
  final int id;
  final String name;
  final bool isEnabled;
  final DateTime dateImported;
  final int sortOrder;
  final bool isHidden;
  const DictionaryMeta({
    required this.id,
    required this.name,
    required this.isEnabled,
    required this.dateImported,
    required this.sortOrder,
    required this.isHidden,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['date_imported'] = Variable<DateTime>(dateImported);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_hidden'] = Variable<bool>(isHidden);
    return map;
  }

  DictionaryMetasCompanion toCompanion(bool nullToAbsent) {
    return DictionaryMetasCompanion(
      id: Value(id),
      name: Value(name),
      isEnabled: Value(isEnabled),
      dateImported: Value(dateImported),
      sortOrder: Value(sortOrder),
      isHidden: Value(isHidden),
    );
  }

  factory DictionaryMeta.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DictionaryMeta(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      dateImported: serializer.fromJson<DateTime>(json['dateImported']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isHidden: serializer.fromJson<bool>(json['isHidden']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'dateImported': serializer.toJson<DateTime>(dateImported),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isHidden': serializer.toJson<bool>(isHidden),
    };
  }

  DictionaryMeta copyWith({
    int? id,
    String? name,
    bool? isEnabled,
    DateTime? dateImported,
    int? sortOrder,
    bool? isHidden,
  }) => DictionaryMeta(
    id: id ?? this.id,
    name: name ?? this.name,
    isEnabled: isEnabled ?? this.isEnabled,
    dateImported: dateImported ?? this.dateImported,
    sortOrder: sortOrder ?? this.sortOrder,
    isHidden: isHidden ?? this.isHidden,
  );
  DictionaryMeta copyWithCompanion(DictionaryMetasCompanion data) {
    return DictionaryMeta(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      dateImported: data.dateImported.present
          ? data.dateImported.value
          : this.dateImported,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isHidden: data.isHidden.present ? data.isHidden.value : this.isHidden,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DictionaryMeta(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('dateImported: $dateImported, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isHidden: $isHidden')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, isEnabled, dateImported, sortOrder, isHidden);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DictionaryMeta &&
          other.id == this.id &&
          other.name == this.name &&
          other.isEnabled == this.isEnabled &&
          other.dateImported == this.dateImported &&
          other.sortOrder == this.sortOrder &&
          other.isHidden == this.isHidden);
}

class DictionaryMetasCompanion extends UpdateCompanion<DictionaryMeta> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> isEnabled;
  final Value<DateTime> dateImported;
  final Value<int> sortOrder;
  final Value<bool> isHidden;
  const DictionaryMetasCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.dateImported = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isHidden = const Value.absent(),
  });
  DictionaryMetasCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.isEnabled = const Value.absent(),
    this.dateImported = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isHidden = const Value.absent(),
  }) : name = Value(name);
  static Insertable<DictionaryMeta> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? isEnabled,
    Expression<DateTime>? dateImported,
    Expression<int>? sortOrder,
    Expression<bool>? isHidden,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (dateImported != null) 'date_imported': dateImported,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isHidden != null) 'is_hidden': isHidden,
    });
  }

  DictionaryMetasCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<bool>? isEnabled,
    Value<DateTime>? dateImported,
    Value<int>? sortOrder,
    Value<bool>? isHidden,
  }) {
    return DictionaryMetasCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      dateImported: dateImported ?? this.dateImported,
      sortOrder: sortOrder ?? this.sortOrder,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (dateImported.present) {
      map['date_imported'] = Variable<DateTime>(dateImported.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isHidden.present) {
      map['is_hidden'] = Variable<bool>(isHidden.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DictionaryMetasCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('dateImported: $dateImported, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isHidden: $isHidden')
          ..write(')'))
        .toString();
  }
}

class $DictionaryEntriesTable extends DictionaryEntries
    with TableInfo<$DictionaryEntriesTable, DictionaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DictionaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _expressionMeta = const VerificationMeta(
    'expression',
  );
  @override
  late final GeneratedColumn<String> expression = GeneratedColumn<String>(
    'expression',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readingMeta = const VerificationMeta(
    'reading',
  );
  @override
  late final GeneratedColumn<String> reading = GeneratedColumn<String>(
    'reading',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _entryKindMeta = const VerificationMeta(
    'entryKind',
  );
  @override
  late final GeneratedColumn<String> entryKind = GeneratedColumn<String>(
    'entry_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(DictionaryEntryKinds.regular),
  );
  static const VerificationMeta _kanjiOnyomiMeta = const VerificationMeta(
    'kanjiOnyomi',
  );
  @override
  late final GeneratedColumn<String> kanjiOnyomi = GeneratedColumn<String>(
    'kanji_onyomi',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _kanjiKunyomiMeta = const VerificationMeta(
    'kanjiKunyomi',
  );
  @override
  late final GeneratedColumn<String> kanjiKunyomi = GeneratedColumn<String>(
    'kanji_kunyomi',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _definitionTagsMeta = const VerificationMeta(
    'definitionTags',
  );
  @override
  late final GeneratedColumn<String> definitionTags = GeneratedColumn<String>(
    'definition_tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _rulesMeta = const VerificationMeta('rules');
  @override
  late final GeneratedColumn<String> rules = GeneratedColumn<String>(
    'rules',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _termTagsMeta = const VerificationMeta(
    'termTags',
  );
  @override
  late final GeneratedColumn<String> termTags = GeneratedColumn<String>(
    'term_tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _glossariesMeta = const VerificationMeta(
    'glossaries',
  );
  @override
  late final GeneratedColumn<String> glossaries = GeneratedColumn<String>(
    'glossaries',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dictionaryIdMeta = const VerificationMeta(
    'dictionaryId',
  );
  @override
  late final GeneratedColumn<int> dictionaryId = GeneratedColumn<int>(
    'dictionary_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    expression,
    reading,
    entryKind,
    kanjiOnyomi,
    kanjiKunyomi,
    definitionTags,
    rules,
    termTags,
    glossaries,
    dictionaryId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dictionary_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DictionaryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('expression')) {
      context.handle(
        _expressionMeta,
        expression.isAcceptableOrUnknown(data['expression']!, _expressionMeta),
      );
    } else if (isInserting) {
      context.missing(_expressionMeta);
    }
    if (data.containsKey('reading')) {
      context.handle(
        _readingMeta,
        reading.isAcceptableOrUnknown(data['reading']!, _readingMeta),
      );
    }
    if (data.containsKey('entry_kind')) {
      context.handle(
        _entryKindMeta,
        entryKind.isAcceptableOrUnknown(data['entry_kind']!, _entryKindMeta),
      );
    }
    if (data.containsKey('kanji_onyomi')) {
      context.handle(
        _kanjiOnyomiMeta,
        kanjiOnyomi.isAcceptableOrUnknown(
          data['kanji_onyomi']!,
          _kanjiOnyomiMeta,
        ),
      );
    }
    if (data.containsKey('kanji_kunyomi')) {
      context.handle(
        _kanjiKunyomiMeta,
        kanjiKunyomi.isAcceptableOrUnknown(
          data['kanji_kunyomi']!,
          _kanjiKunyomiMeta,
        ),
      );
    }
    if (data.containsKey('definition_tags')) {
      context.handle(
        _definitionTagsMeta,
        definitionTags.isAcceptableOrUnknown(
          data['definition_tags']!,
          _definitionTagsMeta,
        ),
      );
    }
    if (data.containsKey('rules')) {
      context.handle(
        _rulesMeta,
        rules.isAcceptableOrUnknown(data['rules']!, _rulesMeta),
      );
    }
    if (data.containsKey('term_tags')) {
      context.handle(
        _termTagsMeta,
        termTags.isAcceptableOrUnknown(data['term_tags']!, _termTagsMeta),
      );
    }
    if (data.containsKey('glossaries')) {
      context.handle(
        _glossariesMeta,
        glossaries.isAcceptableOrUnknown(data['glossaries']!, _glossariesMeta),
      );
    } else if (isInserting) {
      context.missing(_glossariesMeta);
    }
    if (data.containsKey('dictionary_id')) {
      context.handle(
        _dictionaryIdMeta,
        dictionaryId.isAcceptableOrUnknown(
          data['dictionary_id']!,
          _dictionaryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dictionaryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DictionaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DictionaryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      expression: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expression'],
      )!,
      reading: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reading'],
      )!,
      entryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_kind'],
      )!,
      kanjiOnyomi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kanji_onyomi'],
      )!,
      kanjiKunyomi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kanji_kunyomi'],
      )!,
      definitionTags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definition_tags'],
      )!,
      rules: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rules'],
      )!,
      termTags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term_tags'],
      )!,
      glossaries: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}glossaries'],
      )!,
      dictionaryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dictionary_id'],
      )!,
    );
  }

  @override
  $DictionaryEntriesTable createAlias(String alias) {
    return $DictionaryEntriesTable(attachedDatabase, alias);
  }
}

class DictionaryEntry extends DataClass implements Insertable<DictionaryEntry> {
  final int id;
  final String expression;
  final String reading;
  final String entryKind;
  final String kanjiOnyomi;
  final String kanjiKunyomi;
  final String definitionTags;
  final String rules;
  final String termTags;
  final String glossaries;
  final int dictionaryId;
  const DictionaryEntry({
    required this.id,
    required this.expression,
    required this.reading,
    required this.entryKind,
    required this.kanjiOnyomi,
    required this.kanjiKunyomi,
    required this.definitionTags,
    required this.rules,
    required this.termTags,
    required this.glossaries,
    required this.dictionaryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['expression'] = Variable<String>(expression);
    map['reading'] = Variable<String>(reading);
    map['entry_kind'] = Variable<String>(entryKind);
    map['kanji_onyomi'] = Variable<String>(kanjiOnyomi);
    map['kanji_kunyomi'] = Variable<String>(kanjiKunyomi);
    map['definition_tags'] = Variable<String>(definitionTags);
    map['rules'] = Variable<String>(rules);
    map['term_tags'] = Variable<String>(termTags);
    map['glossaries'] = Variable<String>(glossaries);
    map['dictionary_id'] = Variable<int>(dictionaryId);
    return map;
  }

  DictionaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return DictionaryEntriesCompanion(
      id: Value(id),
      expression: Value(expression),
      reading: Value(reading),
      entryKind: Value(entryKind),
      kanjiOnyomi: Value(kanjiOnyomi),
      kanjiKunyomi: Value(kanjiKunyomi),
      definitionTags: Value(definitionTags),
      rules: Value(rules),
      termTags: Value(termTags),
      glossaries: Value(glossaries),
      dictionaryId: Value(dictionaryId),
    );
  }

  factory DictionaryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DictionaryEntry(
      id: serializer.fromJson<int>(json['id']),
      expression: serializer.fromJson<String>(json['expression']),
      reading: serializer.fromJson<String>(json['reading']),
      entryKind: serializer.fromJson<String>(json['entryKind']),
      kanjiOnyomi: serializer.fromJson<String>(json['kanjiOnyomi']),
      kanjiKunyomi: serializer.fromJson<String>(json['kanjiKunyomi']),
      definitionTags: serializer.fromJson<String>(json['definitionTags']),
      rules: serializer.fromJson<String>(json['rules']),
      termTags: serializer.fromJson<String>(json['termTags']),
      glossaries: serializer.fromJson<String>(json['glossaries']),
      dictionaryId: serializer.fromJson<int>(json['dictionaryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'expression': serializer.toJson<String>(expression),
      'reading': serializer.toJson<String>(reading),
      'entryKind': serializer.toJson<String>(entryKind),
      'kanjiOnyomi': serializer.toJson<String>(kanjiOnyomi),
      'kanjiKunyomi': serializer.toJson<String>(kanjiKunyomi),
      'definitionTags': serializer.toJson<String>(definitionTags),
      'rules': serializer.toJson<String>(rules),
      'termTags': serializer.toJson<String>(termTags),
      'glossaries': serializer.toJson<String>(glossaries),
      'dictionaryId': serializer.toJson<int>(dictionaryId),
    };
  }

  DictionaryEntry copyWith({
    int? id,
    String? expression,
    String? reading,
    String? entryKind,
    String? kanjiOnyomi,
    String? kanjiKunyomi,
    String? definitionTags,
    String? rules,
    String? termTags,
    String? glossaries,
    int? dictionaryId,
  }) => DictionaryEntry(
    id: id ?? this.id,
    expression: expression ?? this.expression,
    reading: reading ?? this.reading,
    entryKind: entryKind ?? this.entryKind,
    kanjiOnyomi: kanjiOnyomi ?? this.kanjiOnyomi,
    kanjiKunyomi: kanjiKunyomi ?? this.kanjiKunyomi,
    definitionTags: definitionTags ?? this.definitionTags,
    rules: rules ?? this.rules,
    termTags: termTags ?? this.termTags,
    glossaries: glossaries ?? this.glossaries,
    dictionaryId: dictionaryId ?? this.dictionaryId,
  );
  DictionaryEntry copyWithCompanion(DictionaryEntriesCompanion data) {
    return DictionaryEntry(
      id: data.id.present ? data.id.value : this.id,
      expression: data.expression.present
          ? data.expression.value
          : this.expression,
      reading: data.reading.present ? data.reading.value : this.reading,
      entryKind: data.entryKind.present ? data.entryKind.value : this.entryKind,
      kanjiOnyomi: data.kanjiOnyomi.present
          ? data.kanjiOnyomi.value
          : this.kanjiOnyomi,
      kanjiKunyomi: data.kanjiKunyomi.present
          ? data.kanjiKunyomi.value
          : this.kanjiKunyomi,
      definitionTags: data.definitionTags.present
          ? data.definitionTags.value
          : this.definitionTags,
      rules: data.rules.present ? data.rules.value : this.rules,
      termTags: data.termTags.present ? data.termTags.value : this.termTags,
      glossaries: data.glossaries.present
          ? data.glossaries.value
          : this.glossaries,
      dictionaryId: data.dictionaryId.present
          ? data.dictionaryId.value
          : this.dictionaryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DictionaryEntry(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('entryKind: $entryKind, ')
          ..write('kanjiOnyomi: $kanjiOnyomi, ')
          ..write('kanjiKunyomi: $kanjiKunyomi, ')
          ..write('definitionTags: $definitionTags, ')
          ..write('rules: $rules, ')
          ..write('termTags: $termTags, ')
          ..write('glossaries: $glossaries, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    expression,
    reading,
    entryKind,
    kanjiOnyomi,
    kanjiKunyomi,
    definitionTags,
    rules,
    termTags,
    glossaries,
    dictionaryId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DictionaryEntry &&
          other.id == this.id &&
          other.expression == this.expression &&
          other.reading == this.reading &&
          other.entryKind == this.entryKind &&
          other.kanjiOnyomi == this.kanjiOnyomi &&
          other.kanjiKunyomi == this.kanjiKunyomi &&
          other.definitionTags == this.definitionTags &&
          other.rules == this.rules &&
          other.termTags == this.termTags &&
          other.glossaries == this.glossaries &&
          other.dictionaryId == this.dictionaryId);
}

class DictionaryEntriesCompanion extends UpdateCompanion<DictionaryEntry> {
  final Value<int> id;
  final Value<String> expression;
  final Value<String> reading;
  final Value<String> entryKind;
  final Value<String> kanjiOnyomi;
  final Value<String> kanjiKunyomi;
  final Value<String> definitionTags;
  final Value<String> rules;
  final Value<String> termTags;
  final Value<String> glossaries;
  final Value<int> dictionaryId;
  const DictionaryEntriesCompanion({
    this.id = const Value.absent(),
    this.expression = const Value.absent(),
    this.reading = const Value.absent(),
    this.entryKind = const Value.absent(),
    this.kanjiOnyomi = const Value.absent(),
    this.kanjiKunyomi = const Value.absent(),
    this.definitionTags = const Value.absent(),
    this.rules = const Value.absent(),
    this.termTags = const Value.absent(),
    this.glossaries = const Value.absent(),
    this.dictionaryId = const Value.absent(),
  });
  DictionaryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String expression,
    this.reading = const Value.absent(),
    this.entryKind = const Value.absent(),
    this.kanjiOnyomi = const Value.absent(),
    this.kanjiKunyomi = const Value.absent(),
    this.definitionTags = const Value.absent(),
    this.rules = const Value.absent(),
    this.termTags = const Value.absent(),
    required String glossaries,
    required int dictionaryId,
  }) : expression = Value(expression),
       glossaries = Value(glossaries),
       dictionaryId = Value(dictionaryId);
  static Insertable<DictionaryEntry> custom({
    Expression<int>? id,
    Expression<String>? expression,
    Expression<String>? reading,
    Expression<String>? entryKind,
    Expression<String>? kanjiOnyomi,
    Expression<String>? kanjiKunyomi,
    Expression<String>? definitionTags,
    Expression<String>? rules,
    Expression<String>? termTags,
    Expression<String>? glossaries,
    Expression<int>? dictionaryId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expression != null) 'expression': expression,
      if (reading != null) 'reading': reading,
      if (entryKind != null) 'entry_kind': entryKind,
      if (kanjiOnyomi != null) 'kanji_onyomi': kanjiOnyomi,
      if (kanjiKunyomi != null) 'kanji_kunyomi': kanjiKunyomi,
      if (definitionTags != null) 'definition_tags': definitionTags,
      if (rules != null) 'rules': rules,
      if (termTags != null) 'term_tags': termTags,
      if (glossaries != null) 'glossaries': glossaries,
      if (dictionaryId != null) 'dictionary_id': dictionaryId,
    });
  }

  DictionaryEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? expression,
    Value<String>? reading,
    Value<String>? entryKind,
    Value<String>? kanjiOnyomi,
    Value<String>? kanjiKunyomi,
    Value<String>? definitionTags,
    Value<String>? rules,
    Value<String>? termTags,
    Value<String>? glossaries,
    Value<int>? dictionaryId,
  }) {
    return DictionaryEntriesCompanion(
      id: id ?? this.id,
      expression: expression ?? this.expression,
      reading: reading ?? this.reading,
      entryKind: entryKind ?? this.entryKind,
      kanjiOnyomi: kanjiOnyomi ?? this.kanjiOnyomi,
      kanjiKunyomi: kanjiKunyomi ?? this.kanjiKunyomi,
      definitionTags: definitionTags ?? this.definitionTags,
      rules: rules ?? this.rules,
      termTags: termTags ?? this.termTags,
      glossaries: glossaries ?? this.glossaries,
      dictionaryId: dictionaryId ?? this.dictionaryId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (expression.present) {
      map['expression'] = Variable<String>(expression.value);
    }
    if (reading.present) {
      map['reading'] = Variable<String>(reading.value);
    }
    if (entryKind.present) {
      map['entry_kind'] = Variable<String>(entryKind.value);
    }
    if (kanjiOnyomi.present) {
      map['kanji_onyomi'] = Variable<String>(kanjiOnyomi.value);
    }
    if (kanjiKunyomi.present) {
      map['kanji_kunyomi'] = Variable<String>(kanjiKunyomi.value);
    }
    if (definitionTags.present) {
      map['definition_tags'] = Variable<String>(definitionTags.value);
    }
    if (rules.present) {
      map['rules'] = Variable<String>(rules.value);
    }
    if (termTags.present) {
      map['term_tags'] = Variable<String>(termTags.value);
    }
    if (glossaries.present) {
      map['glossaries'] = Variable<String>(glossaries.value);
    }
    if (dictionaryId.present) {
      map['dictionary_id'] = Variable<int>(dictionaryId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DictionaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('entryKind: $entryKind, ')
          ..write('kanjiOnyomi: $kanjiOnyomi, ')
          ..write('kanjiKunyomi: $kanjiKunyomi, ')
          ..write('definitionTags: $definitionTags, ')
          ..write('rules: $rules, ')
          ..write('termTags: $termTags, ')
          ..write('glossaries: $glossaries, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }
}

class $PitchAccentsTable extends PitchAccents
    with TableInfo<$PitchAccentsTable, PitchAccent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PitchAccentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _expressionMeta = const VerificationMeta(
    'expression',
  );
  @override
  late final GeneratedColumn<String> expression = GeneratedColumn<String>(
    'expression',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readingMeta = const VerificationMeta(
    'reading',
  );
  @override
  late final GeneratedColumn<String> reading = GeneratedColumn<String>(
    'reading',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _downstepPositionMeta = const VerificationMeta(
    'downstepPosition',
  );
  @override
  late final GeneratedColumn<int> downstepPosition = GeneratedColumn<int>(
    'downstep_position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dictionaryIdMeta = const VerificationMeta(
    'dictionaryId',
  );
  @override
  late final GeneratedColumn<int> dictionaryId = GeneratedColumn<int>(
    'dictionary_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    expression,
    reading,
    downstepPosition,
    dictionaryId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pitch_accents';
  @override
  VerificationContext validateIntegrity(
    Insertable<PitchAccent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('expression')) {
      context.handle(
        _expressionMeta,
        expression.isAcceptableOrUnknown(data['expression']!, _expressionMeta),
      );
    } else if (isInserting) {
      context.missing(_expressionMeta);
    }
    if (data.containsKey('reading')) {
      context.handle(
        _readingMeta,
        reading.isAcceptableOrUnknown(data['reading']!, _readingMeta),
      );
    }
    if (data.containsKey('downstep_position')) {
      context.handle(
        _downstepPositionMeta,
        downstepPosition.isAcceptableOrUnknown(
          data['downstep_position']!,
          _downstepPositionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_downstepPositionMeta);
    }
    if (data.containsKey('dictionary_id')) {
      context.handle(
        _dictionaryIdMeta,
        dictionaryId.isAcceptableOrUnknown(
          data['dictionary_id']!,
          _dictionaryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dictionaryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PitchAccent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PitchAccent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      expression: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expression'],
      )!,
      reading: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reading'],
      )!,
      downstepPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}downstep_position'],
      )!,
      dictionaryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dictionary_id'],
      )!,
    );
  }

  @override
  $PitchAccentsTable createAlias(String alias) {
    return $PitchAccentsTable(attachedDatabase, alias);
  }
}

class PitchAccent extends DataClass implements Insertable<PitchAccent> {
  final int id;
  final String expression;
  final String reading;
  final int downstepPosition;
  final int dictionaryId;
  const PitchAccent({
    required this.id,
    required this.expression,
    required this.reading,
    required this.downstepPosition,
    required this.dictionaryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['expression'] = Variable<String>(expression);
    map['reading'] = Variable<String>(reading);
    map['downstep_position'] = Variable<int>(downstepPosition);
    map['dictionary_id'] = Variable<int>(dictionaryId);
    return map;
  }

  PitchAccentsCompanion toCompanion(bool nullToAbsent) {
    return PitchAccentsCompanion(
      id: Value(id),
      expression: Value(expression),
      reading: Value(reading),
      downstepPosition: Value(downstepPosition),
      dictionaryId: Value(dictionaryId),
    );
  }

  factory PitchAccent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PitchAccent(
      id: serializer.fromJson<int>(json['id']),
      expression: serializer.fromJson<String>(json['expression']),
      reading: serializer.fromJson<String>(json['reading']),
      downstepPosition: serializer.fromJson<int>(json['downstepPosition']),
      dictionaryId: serializer.fromJson<int>(json['dictionaryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'expression': serializer.toJson<String>(expression),
      'reading': serializer.toJson<String>(reading),
      'downstepPosition': serializer.toJson<int>(downstepPosition),
      'dictionaryId': serializer.toJson<int>(dictionaryId),
    };
  }

  PitchAccent copyWith({
    int? id,
    String? expression,
    String? reading,
    int? downstepPosition,
    int? dictionaryId,
  }) => PitchAccent(
    id: id ?? this.id,
    expression: expression ?? this.expression,
    reading: reading ?? this.reading,
    downstepPosition: downstepPosition ?? this.downstepPosition,
    dictionaryId: dictionaryId ?? this.dictionaryId,
  );
  PitchAccent copyWithCompanion(PitchAccentsCompanion data) {
    return PitchAccent(
      id: data.id.present ? data.id.value : this.id,
      expression: data.expression.present
          ? data.expression.value
          : this.expression,
      reading: data.reading.present ? data.reading.value : this.reading,
      downstepPosition: data.downstepPosition.present
          ? data.downstepPosition.value
          : this.downstepPosition,
      dictionaryId: data.dictionaryId.present
          ? data.dictionaryId.value
          : this.dictionaryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PitchAccent(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('downstepPosition: $downstepPosition, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, expression, reading, downstepPosition, dictionaryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PitchAccent &&
          other.id == this.id &&
          other.expression == this.expression &&
          other.reading == this.reading &&
          other.downstepPosition == this.downstepPosition &&
          other.dictionaryId == this.dictionaryId);
}

class PitchAccentsCompanion extends UpdateCompanion<PitchAccent> {
  final Value<int> id;
  final Value<String> expression;
  final Value<String> reading;
  final Value<int> downstepPosition;
  final Value<int> dictionaryId;
  const PitchAccentsCompanion({
    this.id = const Value.absent(),
    this.expression = const Value.absent(),
    this.reading = const Value.absent(),
    this.downstepPosition = const Value.absent(),
    this.dictionaryId = const Value.absent(),
  });
  PitchAccentsCompanion.insert({
    this.id = const Value.absent(),
    required String expression,
    this.reading = const Value.absent(),
    required int downstepPosition,
    required int dictionaryId,
  }) : expression = Value(expression),
       downstepPosition = Value(downstepPosition),
       dictionaryId = Value(dictionaryId);
  static Insertable<PitchAccent> custom({
    Expression<int>? id,
    Expression<String>? expression,
    Expression<String>? reading,
    Expression<int>? downstepPosition,
    Expression<int>? dictionaryId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expression != null) 'expression': expression,
      if (reading != null) 'reading': reading,
      if (downstepPosition != null) 'downstep_position': downstepPosition,
      if (dictionaryId != null) 'dictionary_id': dictionaryId,
    });
  }

  PitchAccentsCompanion copyWith({
    Value<int>? id,
    Value<String>? expression,
    Value<String>? reading,
    Value<int>? downstepPosition,
    Value<int>? dictionaryId,
  }) {
    return PitchAccentsCompanion(
      id: id ?? this.id,
      expression: expression ?? this.expression,
      reading: reading ?? this.reading,
      downstepPosition: downstepPosition ?? this.downstepPosition,
      dictionaryId: dictionaryId ?? this.dictionaryId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (expression.present) {
      map['expression'] = Variable<String>(expression.value);
    }
    if (reading.present) {
      map['reading'] = Variable<String>(reading.value);
    }
    if (downstepPosition.present) {
      map['downstep_position'] = Variable<int>(downstepPosition.value);
    }
    if (dictionaryId.present) {
      map['dictionary_id'] = Variable<int>(dictionaryId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PitchAccentsCompanion(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('downstepPosition: $downstepPosition, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }
}

class $FrequenciesTable extends Frequencies
    with TableInfo<$FrequenciesTable, Frequency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FrequenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _expressionMeta = const VerificationMeta(
    'expression',
  );
  @override
  late final GeneratedColumn<String> expression = GeneratedColumn<String>(
    'expression',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readingMeta = const VerificationMeta(
    'reading',
  );
  @override
  late final GeneratedColumn<String> reading = GeneratedColumn<String>(
    'reading',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _frequencyRankMeta = const VerificationMeta(
    'frequencyRank',
  );
  @override
  late final GeneratedColumn<int> frequencyRank = GeneratedColumn<int>(
    'frequency_rank',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dictionaryIdMeta = const VerificationMeta(
    'dictionaryId',
  );
  @override
  late final GeneratedColumn<int> dictionaryId = GeneratedColumn<int>(
    'dictionary_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    expression,
    reading,
    frequencyRank,
    dictionaryId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'frequencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<Frequency> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('expression')) {
      context.handle(
        _expressionMeta,
        expression.isAcceptableOrUnknown(data['expression']!, _expressionMeta),
      );
    } else if (isInserting) {
      context.missing(_expressionMeta);
    }
    if (data.containsKey('reading')) {
      context.handle(
        _readingMeta,
        reading.isAcceptableOrUnknown(data['reading']!, _readingMeta),
      );
    }
    if (data.containsKey('frequency_rank')) {
      context.handle(
        _frequencyRankMeta,
        frequencyRank.isAcceptableOrUnknown(
          data['frequency_rank']!,
          _frequencyRankMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_frequencyRankMeta);
    }
    if (data.containsKey('dictionary_id')) {
      context.handle(
        _dictionaryIdMeta,
        dictionaryId.isAcceptableOrUnknown(
          data['dictionary_id']!,
          _dictionaryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dictionaryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Frequency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Frequency(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      expression: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expression'],
      )!,
      reading: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reading'],
      )!,
      frequencyRank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frequency_rank'],
      )!,
      dictionaryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dictionary_id'],
      )!,
    );
  }

  @override
  $FrequenciesTable createAlias(String alias) {
    return $FrequenciesTable(attachedDatabase, alias);
  }
}

class Frequency extends DataClass implements Insertable<Frequency> {
  final int id;
  final String expression;
  final String reading;
  final int frequencyRank;
  final int dictionaryId;
  const Frequency({
    required this.id,
    required this.expression,
    required this.reading,
    required this.frequencyRank,
    required this.dictionaryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['expression'] = Variable<String>(expression);
    map['reading'] = Variable<String>(reading);
    map['frequency_rank'] = Variable<int>(frequencyRank);
    map['dictionary_id'] = Variable<int>(dictionaryId);
    return map;
  }

  FrequenciesCompanion toCompanion(bool nullToAbsent) {
    return FrequenciesCompanion(
      id: Value(id),
      expression: Value(expression),
      reading: Value(reading),
      frequencyRank: Value(frequencyRank),
      dictionaryId: Value(dictionaryId),
    );
  }

  factory Frequency.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Frequency(
      id: serializer.fromJson<int>(json['id']),
      expression: serializer.fromJson<String>(json['expression']),
      reading: serializer.fromJson<String>(json['reading']),
      frequencyRank: serializer.fromJson<int>(json['frequencyRank']),
      dictionaryId: serializer.fromJson<int>(json['dictionaryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'expression': serializer.toJson<String>(expression),
      'reading': serializer.toJson<String>(reading),
      'frequencyRank': serializer.toJson<int>(frequencyRank),
      'dictionaryId': serializer.toJson<int>(dictionaryId),
    };
  }

  Frequency copyWith({
    int? id,
    String? expression,
    String? reading,
    int? frequencyRank,
    int? dictionaryId,
  }) => Frequency(
    id: id ?? this.id,
    expression: expression ?? this.expression,
    reading: reading ?? this.reading,
    frequencyRank: frequencyRank ?? this.frequencyRank,
    dictionaryId: dictionaryId ?? this.dictionaryId,
  );
  Frequency copyWithCompanion(FrequenciesCompanion data) {
    return Frequency(
      id: data.id.present ? data.id.value : this.id,
      expression: data.expression.present
          ? data.expression.value
          : this.expression,
      reading: data.reading.present ? data.reading.value : this.reading,
      frequencyRank: data.frequencyRank.present
          ? data.frequencyRank.value
          : this.frequencyRank,
      dictionaryId: data.dictionaryId.present
          ? data.dictionaryId.value
          : this.dictionaryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Frequency(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('frequencyRank: $frequencyRank, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, expression, reading, frequencyRank, dictionaryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Frequency &&
          other.id == this.id &&
          other.expression == this.expression &&
          other.reading == this.reading &&
          other.frequencyRank == this.frequencyRank &&
          other.dictionaryId == this.dictionaryId);
}

class FrequenciesCompanion extends UpdateCompanion<Frequency> {
  final Value<int> id;
  final Value<String> expression;
  final Value<String> reading;
  final Value<int> frequencyRank;
  final Value<int> dictionaryId;
  const FrequenciesCompanion({
    this.id = const Value.absent(),
    this.expression = const Value.absent(),
    this.reading = const Value.absent(),
    this.frequencyRank = const Value.absent(),
    this.dictionaryId = const Value.absent(),
  });
  FrequenciesCompanion.insert({
    this.id = const Value.absent(),
    required String expression,
    this.reading = const Value.absent(),
    required int frequencyRank,
    required int dictionaryId,
  }) : expression = Value(expression),
       frequencyRank = Value(frequencyRank),
       dictionaryId = Value(dictionaryId);
  static Insertable<Frequency> custom({
    Expression<int>? id,
    Expression<String>? expression,
    Expression<String>? reading,
    Expression<int>? frequencyRank,
    Expression<int>? dictionaryId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expression != null) 'expression': expression,
      if (reading != null) 'reading': reading,
      if (frequencyRank != null) 'frequency_rank': frequencyRank,
      if (dictionaryId != null) 'dictionary_id': dictionaryId,
    });
  }

  FrequenciesCompanion copyWith({
    Value<int>? id,
    Value<String>? expression,
    Value<String>? reading,
    Value<int>? frequencyRank,
    Value<int>? dictionaryId,
  }) {
    return FrequenciesCompanion(
      id: id ?? this.id,
      expression: expression ?? this.expression,
      reading: reading ?? this.reading,
      frequencyRank: frequencyRank ?? this.frequencyRank,
      dictionaryId: dictionaryId ?? this.dictionaryId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (expression.present) {
      map['expression'] = Variable<String>(expression.value);
    }
    if (reading.present) {
      map['reading'] = Variable<String>(reading.value);
    }
    if (frequencyRank.present) {
      map['frequency_rank'] = Variable<int>(frequencyRank.value);
    }
    if (dictionaryId.present) {
      map['dictionary_id'] = Variable<int>(dictionaryId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FrequenciesCompanion(')
          ..write('id: $id, ')
          ..write('expression: $expression, ')
          ..write('reading: $reading, ')
          ..write('frequencyRank: $frequencyRank, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _cfiMeta = const VerificationMeta('cfi');
  @override
  late final GeneratedColumn<String> cfi = GeneratedColumn<String>(
    'cfi',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _userNoteMeta = const VerificationMeta(
    'userNote',
  );
  @override
  late final GeneratedColumn<String> userNote = GeneratedColumn<String>(
    'user_note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    cfi,
    progress,
    chapterTitle,
    userNote,
    dateAdded,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bookmark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('cfi')) {
      context.handle(
        _cfiMeta,
        cfi.isAcceptableOrUnknown(data['cfi']!, _cfiMeta),
      );
    } else if (isInserting) {
      context.missing(_cfiMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('user_note')) {
      context.handle(
        _userNoteMeta,
        userNote.isAcceptableOrUnknown(data['user_note']!, _userNoteMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      cfi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cfi'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      )!,
      userNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_note'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class Bookmark extends DataClass implements Insertable<Bookmark> {
  final int id;
  final int bookId;
  final String cfi;
  final double progress;
  final String chapterTitle;
  final String userNote;
  final DateTime dateAdded;
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.cfi,
    required this.progress,
    required this.chapterTitle,
    required this.userNote,
    required this.dateAdded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['cfi'] = Variable<String>(cfi);
    map['progress'] = Variable<double>(progress);
    map['chapter_title'] = Variable<String>(chapterTitle);
    map['user_note'] = Variable<String>(userNote);
    map['date_added'] = Variable<DateTime>(dateAdded);
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      bookId: Value(bookId),
      cfi: Value(cfi),
      progress: Value(progress),
      chapterTitle: Value(chapterTitle),
      userNote: Value(userNote),
      dateAdded: Value(dateAdded),
    );
  }

  factory Bookmark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bookmark(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      cfi: serializer.fromJson<String>(json['cfi']),
      progress: serializer.fromJson<double>(json['progress']),
      chapterTitle: serializer.fromJson<String>(json['chapterTitle']),
      userNote: serializer.fromJson<String>(json['userNote']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'cfi': serializer.toJson<String>(cfi),
      'progress': serializer.toJson<double>(progress),
      'chapterTitle': serializer.toJson<String>(chapterTitle),
      'userNote': serializer.toJson<String>(userNote),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
    };
  }

  Bookmark copyWith({
    int? id,
    int? bookId,
    String? cfi,
    double? progress,
    String? chapterTitle,
    String? userNote,
    DateTime? dateAdded,
  }) => Bookmark(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    cfi: cfi ?? this.cfi,
    progress: progress ?? this.progress,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    userNote: userNote ?? this.userNote,
    dateAdded: dateAdded ?? this.dateAdded,
  );
  Bookmark copyWithCompanion(BookmarksCompanion data) {
    return Bookmark(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      cfi: data.cfi.present ? data.cfi.value : this.cfi,
      progress: data.progress.present ? data.progress.value : this.progress,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      userNote: data.userNote.present ? data.userNote.value : this.userNote,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Bookmark(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('cfi: $cfi, ')
          ..write('progress: $progress, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('userNote: $userNote, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bookId, cfi, progress, chapterTitle, userNote, dateAdded);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bookmark &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.cfi == this.cfi &&
          other.progress == this.progress &&
          other.chapterTitle == this.chapterTitle &&
          other.userNote == this.userNote &&
          other.dateAdded == this.dateAdded);
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<String> cfi;
  final Value<double> progress;
  final Value<String> chapterTitle;
  final Value<String> userNote;
  final Value<DateTime> dateAdded;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.cfi = const Value.absent(),
    this.progress = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.userNote = const Value.absent(),
    this.dateAdded = const Value.absent(),
  });
  BookmarksCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required String cfi,
    this.progress = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.userNote = const Value.absent(),
    this.dateAdded = const Value.absent(),
  }) : bookId = Value(bookId),
       cfi = Value(cfi);
  static Insertable<Bookmark> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<String>? cfi,
    Expression<double>? progress,
    Expression<String>? chapterTitle,
    Expression<String>? userNote,
    Expression<DateTime>? dateAdded,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (cfi != null) 'cfi': cfi,
      if (progress != null) 'progress': progress,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (userNote != null) 'user_note': userNote,
      if (dateAdded != null) 'date_added': dateAdded,
    });
  }

  BookmarksCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<String>? cfi,
    Value<double>? progress,
    Value<String>? chapterTitle,
    Value<String>? userNote,
    Value<DateTime>? dateAdded,
  }) {
    return BookmarksCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      cfi: cfi ?? this.cfi,
      progress: progress ?? this.progress,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      userNote: userNote ?? this.userNote,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (cfi.present) {
      map['cfi'] = Variable<String>(cfi.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (userNote.present) {
      map['user_note'] = Variable<String>(userNote.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('cfi: $cfi, ')
          ..write('progress: $progress, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('userNote: $userNote, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }
}

class $HighlightsTable extends Highlights
    with TableInfo<$HighlightsTable, Highlight> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HighlightsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<int> bookId = GeneratedColumn<int>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _cfiRangeMeta = const VerificationMeta(
    'cfiRange',
  );
  @override
  late final GeneratedColumn<String> cfiRange = GeneratedColumn<String>(
    'cfi_range',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _selectedTextMeta = const VerificationMeta(
    'selectedText',
  );
  @override
  late final GeneratedColumn<String> selectedText = GeneratedColumn<String>(
    'selected_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('yellow'),
  );
  static const VerificationMeta _userNoteMeta = const VerificationMeta(
    'userNote',
  );
  @override
  late final GeneratedColumn<String> userNote = GeneratedColumn<String>(
    'user_note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    cfiRange,
    selectedText,
    color,
    userNote,
    dateAdded,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'highlights';
  @override
  VerificationContext validateIntegrity(
    Insertable<Highlight> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('cfi_range')) {
      context.handle(
        _cfiRangeMeta,
        cfiRange.isAcceptableOrUnknown(data['cfi_range']!, _cfiRangeMeta),
      );
    } else if (isInserting) {
      context.missing(_cfiRangeMeta);
    }
    if (data.containsKey('selected_text')) {
      context.handle(
        _selectedTextMeta,
        selectedText.isAcceptableOrUnknown(
          data['selected_text']!,
          _selectedTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectedTextMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('user_note')) {
      context.handle(
        _userNoteMeta,
        userNote.isAcceptableOrUnknown(data['user_note']!, _userNoteMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Highlight map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Highlight(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      cfiRange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cfi_range'],
      )!,
      selectedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_text'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      userNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_note'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
    );
  }

  @override
  $HighlightsTable createAlias(String alias) {
    return $HighlightsTable(attachedDatabase, alias);
  }
}

class Highlight extends DataClass implements Insertable<Highlight> {
  final int id;
  final int bookId;
  final String cfiRange;
  final String selectedText;
  final String color;
  final String userNote;
  final DateTime dateAdded;
  const Highlight({
    required this.id,
    required this.bookId,
    required this.cfiRange,
    required this.selectedText,
    required this.color,
    required this.userNote,
    required this.dateAdded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['cfi_range'] = Variable<String>(cfiRange);
    map['selected_text'] = Variable<String>(selectedText);
    map['color'] = Variable<String>(color);
    map['user_note'] = Variable<String>(userNote);
    map['date_added'] = Variable<DateTime>(dateAdded);
    return map;
  }

  HighlightsCompanion toCompanion(bool nullToAbsent) {
    return HighlightsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      cfiRange: Value(cfiRange),
      selectedText: Value(selectedText),
      color: Value(color),
      userNote: Value(userNote),
      dateAdded: Value(dateAdded),
    );
  }

  factory Highlight.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Highlight(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      cfiRange: serializer.fromJson<String>(json['cfiRange']),
      selectedText: serializer.fromJson<String>(json['selectedText']),
      color: serializer.fromJson<String>(json['color']),
      userNote: serializer.fromJson<String>(json['userNote']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'cfiRange': serializer.toJson<String>(cfiRange),
      'selectedText': serializer.toJson<String>(selectedText),
      'color': serializer.toJson<String>(color),
      'userNote': serializer.toJson<String>(userNote),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
    };
  }

  Highlight copyWith({
    int? id,
    int? bookId,
    String? cfiRange,
    String? selectedText,
    String? color,
    String? userNote,
    DateTime? dateAdded,
  }) => Highlight(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    cfiRange: cfiRange ?? this.cfiRange,
    selectedText: selectedText ?? this.selectedText,
    color: color ?? this.color,
    userNote: userNote ?? this.userNote,
    dateAdded: dateAdded ?? this.dateAdded,
  );
  Highlight copyWithCompanion(HighlightsCompanion data) {
    return Highlight(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      cfiRange: data.cfiRange.present ? data.cfiRange.value : this.cfiRange,
      selectedText: data.selectedText.present
          ? data.selectedText.value
          : this.selectedText,
      color: data.color.present ? data.color.value : this.color,
      userNote: data.userNote.present ? data.userNote.value : this.userNote,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Highlight(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('cfiRange: $cfiRange, ')
          ..write('selectedText: $selectedText, ')
          ..write('color: $color, ')
          ..write('userNote: $userNote, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    cfiRange,
    selectedText,
    color,
    userNote,
    dateAdded,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Highlight &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.cfiRange == this.cfiRange &&
          other.selectedText == this.selectedText &&
          other.color == this.color &&
          other.userNote == this.userNote &&
          other.dateAdded == this.dateAdded);
}

class HighlightsCompanion extends UpdateCompanion<Highlight> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<String> cfiRange;
  final Value<String> selectedText;
  final Value<String> color;
  final Value<String> userNote;
  final Value<DateTime> dateAdded;
  const HighlightsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.cfiRange = const Value.absent(),
    this.selectedText = const Value.absent(),
    this.color = const Value.absent(),
    this.userNote = const Value.absent(),
    this.dateAdded = const Value.absent(),
  });
  HighlightsCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required String cfiRange,
    required String selectedText,
    this.color = const Value.absent(),
    this.userNote = const Value.absent(),
    this.dateAdded = const Value.absent(),
  }) : bookId = Value(bookId),
       cfiRange = Value(cfiRange),
       selectedText = Value(selectedText);
  static Insertable<Highlight> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<String>? cfiRange,
    Expression<String>? selectedText,
    Expression<String>? color,
    Expression<String>? userNote,
    Expression<DateTime>? dateAdded,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (cfiRange != null) 'cfi_range': cfiRange,
      if (selectedText != null) 'selected_text': selectedText,
      if (color != null) 'color': color,
      if (userNote != null) 'user_note': userNote,
      if (dateAdded != null) 'date_added': dateAdded,
    });
  }

  HighlightsCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<String>? cfiRange,
    Value<String>? selectedText,
    Value<String>? color,
    Value<String>? userNote,
    Value<DateTime>? dateAdded,
  }) {
    return HighlightsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      cfiRange: cfiRange ?? this.cfiRange,
      selectedText: selectedText ?? this.selectedText,
      color: color ?? this.color,
      userNote: userNote ?? this.userNote,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<int>(bookId.value);
    }
    if (cfiRange.present) {
      map['cfi_range'] = Variable<String>(cfiRange.value);
    }
    if (selectedText.present) {
      map['selected_text'] = Variable<String>(selectedText.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (userNote.present) {
      map['user_note'] = Variable<String>(userNote.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HighlightsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('cfiRange: $cfiRange, ')
          ..write('selectedText: $selectedText, ')
          ..write('color: $color, ')
          ..write('userNote: $userNote, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }
}

class $PendingBookDatasTable extends PendingBookDatas
    with TableInfo<$PendingBookDatasTable, PendingBookData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingBookDatasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookKeyMeta = const VerificationMeta(
    'bookKey',
  );
  @override
  late final GeneratedColumn<String> bookKey = GeneratedColumn<String>(
    'book_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, bookKey, dataJson, dateAdded];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_book_datas';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingBookData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_key')) {
      context.handle(
        _bookKeyMeta,
        bookKey.isAcceptableOrUnknown(data['book_key']!, _bookKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_bookKeyMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingBookData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingBookData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_key'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
    );
  }

  @override
  $PendingBookDatasTable createAlias(String alias) {
    return $PendingBookDatasTable(attachedDatabase, alias);
  }
}

class PendingBookData extends DataClass implements Insertable<PendingBookData> {
  final int id;

  /// Book identity key: "{bookType}::{normalizedTitle}".
  final String bookKey;

  /// Full book entry JSON blob (bookmarks, highlights, progress, overrides).
  final String dataJson;
  final DateTime dateAdded;
  const PendingBookData({
    required this.id,
    required this.bookKey,
    required this.dataJson,
    required this.dateAdded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_key'] = Variable<String>(bookKey);
    map['data_json'] = Variable<String>(dataJson);
    map['date_added'] = Variable<DateTime>(dateAdded);
    return map;
  }

  PendingBookDatasCompanion toCompanion(bool nullToAbsent) {
    return PendingBookDatasCompanion(
      id: Value(id),
      bookKey: Value(bookKey),
      dataJson: Value(dataJson),
      dateAdded: Value(dateAdded),
    );
  }

  factory PendingBookData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingBookData(
      id: serializer.fromJson<int>(json['id']),
      bookKey: serializer.fromJson<String>(json['bookKey']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookKey': serializer.toJson<String>(bookKey),
      'dataJson': serializer.toJson<String>(dataJson),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
    };
  }

  PendingBookData copyWith({
    int? id,
    String? bookKey,
    String? dataJson,
    DateTime? dateAdded,
  }) => PendingBookData(
    id: id ?? this.id,
    bookKey: bookKey ?? this.bookKey,
    dataJson: dataJson ?? this.dataJson,
    dateAdded: dateAdded ?? this.dateAdded,
  );
  PendingBookData copyWithCompanion(PendingBookDatasCompanion data) {
    return PendingBookData(
      id: data.id.present ? data.id.value : this.id,
      bookKey: data.bookKey.present ? data.bookKey.value : this.bookKey,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingBookData(')
          ..write('id: $id, ')
          ..write('bookKey: $bookKey, ')
          ..write('dataJson: $dataJson, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, bookKey, dataJson, dateAdded);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingBookData &&
          other.id == this.id &&
          other.bookKey == this.bookKey &&
          other.dataJson == this.dataJson &&
          other.dateAdded == this.dateAdded);
}

class PendingBookDatasCompanion extends UpdateCompanion<PendingBookData> {
  final Value<int> id;
  final Value<String> bookKey;
  final Value<String> dataJson;
  final Value<DateTime> dateAdded;
  const PendingBookDatasCompanion({
    this.id = const Value.absent(),
    this.bookKey = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.dateAdded = const Value.absent(),
  });
  PendingBookDatasCompanion.insert({
    this.id = const Value.absent(),
    required String bookKey,
    required String dataJson,
    this.dateAdded = const Value.absent(),
  }) : bookKey = Value(bookKey),
       dataJson = Value(dataJson);
  static Insertable<PendingBookData> custom({
    Expression<int>? id,
    Expression<String>? bookKey,
    Expression<String>? dataJson,
    Expression<DateTime>? dateAdded,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookKey != null) 'book_key': bookKey,
      if (dataJson != null) 'data_json': dataJson,
      if (dateAdded != null) 'date_added': dateAdded,
    });
  }

  PendingBookDatasCompanion copyWith({
    Value<int>? id,
    Value<String>? bookKey,
    Value<String>? dataJson,
    Value<DateTime>? dateAdded,
  }) {
    return PendingBookDatasCompanion(
      id: id ?? this.id,
      bookKey: bookKey ?? this.bookKey,
      dataJson: dataJson ?? this.dataJson,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookKey.present) {
      map['book_key'] = Variable<String>(bookKey.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingBookDatasCompanion(')
          ..write('id: $id, ')
          ..write('bookKey: $bookKey, ')
          ..write('dataJson: $dataJson, ')
          ..write('dateAdded: $dateAdded')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $SavedWordsTable savedWords = $SavedWordsTable(this);
  late final $DictionaryMetasTable dictionaryMetas = $DictionaryMetasTable(
    this,
  );
  late final $DictionaryEntriesTable dictionaryEntries =
      $DictionaryEntriesTable(this);
  late final $PitchAccentsTable pitchAccents = $PitchAccentsTable(this);
  late final $FrequenciesTable frequencies = $FrequenciesTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $HighlightsTable highlights = $HighlightsTable(this);
  late final $PendingBookDatasTable pendingBookDatas = $PendingBookDatasTable(
    this,
  );
  late final Index idxExpression = Index(
    'idx_expression',
    'CREATE INDEX idx_expression ON dictionary_entries (expression)',
  );
  late final Index idxReading = Index(
    'idx_reading',
    'CREATE INDEX idx_reading ON dictionary_entries (reading)',
  );
  late final Index idxExprDictid = Index(
    'idx_expr_dictid',
    'CREATE INDEX idx_expr_dictid ON dictionary_entries (expression, dictionary_id)',
  );
  late final Index idxReadDictid = Index(
    'idx_read_dictid',
    'CREATE INDEX idx_read_dictid ON dictionary_entries (reading, dictionary_id)',
  );
  late final Index idxPitchExpression = Index(
    'idx_pitch_expression',
    'CREATE INDEX idx_pitch_expression ON pitch_accents (expression)',
  );
  late final Index idxPitchReading = Index(
    'idx_pitch_reading',
    'CREATE INDEX idx_pitch_reading ON pitch_accents (reading)',
  );
  late final Index idxPitchExprDictid = Index(
    'idx_pitch_expr_dictid',
    'CREATE INDEX idx_pitch_expr_dictid ON pitch_accents (expression, dictionary_id)',
  );
  late final Index idxFreqExpression = Index(
    'idx_freq_expression',
    'CREATE INDEX idx_freq_expression ON frequencies (expression)',
  );
  late final Index idxFreqReading = Index(
    'idx_freq_reading',
    'CREATE INDEX idx_freq_reading ON frequencies (reading)',
  );
  late final Index idxFreqExprRead = Index(
    'idx_freq_expr_read',
    'CREATE INDEX idx_freq_expr_read ON frequencies (expression, reading)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    savedWords,
    dictionaryMetas,
    dictionaryEntries,
    pitchAccents,
    frequencies,
    bookmarks,
    highlights,
    pendingBookDatas,
    idxExpression,
    idxReading,
    idxExprDictid,
    idxReadDictid,
    idxPitchExpression,
    idxPitchReading,
    idxPitchExprDictid,
    idxFreqExpression,
    idxFreqReading,
    idxFreqExprRead,
  ];
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      required String title,
      required String filePath,
      Value<String> bookType,
      Value<String?> coverImagePath,
      Value<int> totalPages,
      Value<String?> lastReadCfi,
      Value<double> readProgress,
      Value<DateTime> dateAdded,
      Value<DateTime?> lastReadAt,
      Value<String?> language,
      Value<String?> pageProgressionDirection,
      Value<String?> primaryWritingMode,
      Value<bool?> overrideVerticalText,
      Value<String?> overrideReadingDirection,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> filePath,
      Value<String> bookType,
      Value<String?> coverImagePath,
      Value<int> totalPages,
      Value<String?> lastReadCfi,
      Value<double> readProgress,
      Value<DateTime> dateAdded,
      Value<DateTime?> lastReadAt,
      Value<String?> language,
      Value<String?> pageProgressionDirection,
      Value<String?> primaryWritingMode,
      Value<bool?> overrideVerticalText,
      Value<String?> overrideReadingDirection,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: $_aliasNameGenerator(db.books.id, db.bookmarks.bookId),
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$HighlightsTable, List<Highlight>>
  _highlightsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.highlights,
    aliasName: $_aliasNameGenerator(db.books.id, db.highlights.bookId),
  );

  $$HighlightsTableProcessedTableManager get highlightsRefs {
    final manager = $$HighlightsTableTableManager(
      $_db,
      $_db.highlights,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_highlightsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookType => $composableBuilder(
    column: $table.bookType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastReadCfi => $composableBuilder(
    column: $table.lastReadCfi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get readProgress => $composableBuilder(
    column: $table.readProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageProgressionDirection => $composableBuilder(
    column: $table.pageProgressionDirection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get primaryWritingMode => $composableBuilder(
    column: $table.primaryWritingMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get overrideVerticalText => $composableBuilder(
    column: $table.overrideVerticalText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overrideReadingDirection => $composableBuilder(
    column: $table.overrideReadingDirection,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> highlightsRefs(
    Expression<bool> Function($$HighlightsTableFilterComposer f) f,
  ) {
    final $$HighlightsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.highlights,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HighlightsTableFilterComposer(
            $db: $db,
            $table: $db.highlights,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookType => $composableBuilder(
    column: $table.bookType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastReadCfi => $composableBuilder(
    column: $table.lastReadCfi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get readProgress => $composableBuilder(
    column: $table.readProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageProgressionDirection => $composableBuilder(
    column: $table.pageProgressionDirection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get primaryWritingMode => $composableBuilder(
    column: $table.primaryWritingMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get overrideVerticalText => $composableBuilder(
    column: $table.overrideVerticalText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overrideReadingDirection => $composableBuilder(
    column: $table.overrideReadingDirection,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get bookType =>
      $composableBuilder(column: $table.bookType, builder: (column) => column);

  GeneratedColumn<String> get coverImagePath => $composableBuilder(
    column: $table.coverImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastReadCfi => $composableBuilder(
    column: $table.lastReadCfi,
    builder: (column) => column,
  );

  GeneratedColumn<double> get readProgress => $composableBuilder(
    column: $table.readProgress,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get pageProgressionDirection => $composableBuilder(
    column: $table.pageProgressionDirection,
    builder: (column) => column,
  );

  GeneratedColumn<String> get primaryWritingMode => $composableBuilder(
    column: $table.primaryWritingMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get overrideVerticalText => $composableBuilder(
    column: $table.overrideVerticalText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get overrideReadingDirection => $composableBuilder(
    column: $table.overrideReadingDirection,
    builder: (column) => column,
  );

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> highlightsRefs<T extends Object>(
    Expression<T> Function($$HighlightsTableAnnotationComposer a) f,
  ) {
    final $$HighlightsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.highlights,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HighlightsTableAnnotationComposer(
            $db: $db,
            $table: $db.highlights,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          Book,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (Book, $$BooksTableReferences),
          Book,
          PrefetchHooks Function({bool bookmarksRefs, bool highlightsRefs})
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> bookType = const Value.absent(),
                Value<String?> coverImagePath = const Value.absent(),
                Value<int> totalPages = const Value.absent(),
                Value<String?> lastReadCfi = const Value.absent(),
                Value<double> readProgress = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> pageProgressionDirection = const Value.absent(),
                Value<String?> primaryWritingMode = const Value.absent(),
                Value<bool?> overrideVerticalText = const Value.absent(),
                Value<String?> overrideReadingDirection = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                filePath: filePath,
                bookType: bookType,
                coverImagePath: coverImagePath,
                totalPages: totalPages,
                lastReadCfi: lastReadCfi,
                readProgress: readProgress,
                dateAdded: dateAdded,
                lastReadAt: lastReadAt,
                language: language,
                pageProgressionDirection: pageProgressionDirection,
                primaryWritingMode: primaryWritingMode,
                overrideVerticalText: overrideVerticalText,
                overrideReadingDirection: overrideReadingDirection,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required String filePath,
                Value<String> bookType = const Value.absent(),
                Value<String?> coverImagePath = const Value.absent(),
                Value<int> totalPages = const Value.absent(),
                Value<String?> lastReadCfi = const Value.absent(),
                Value<double> readProgress = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> pageProgressionDirection = const Value.absent(),
                Value<String?> primaryWritingMode = const Value.absent(),
                Value<bool?> overrideVerticalText = const Value.absent(),
                Value<String?> overrideReadingDirection = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                filePath: filePath,
                bookType: bookType,
                coverImagePath: coverImagePath,
                totalPages: totalPages,
                lastReadCfi: lastReadCfi,
                readProgress: readProgress,
                dateAdded: dateAdded,
                lastReadAt: lastReadAt,
                language: language,
                pageProgressionDirection: pageProgressionDirection,
                primaryWritingMode: primaryWritingMode,
                overrideVerticalText: overrideVerticalText,
                overrideReadingDirection: overrideReadingDirection,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({bookmarksRefs = false, highlightsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bookmarksRefs) db.bookmarks,
                    if (highlightsRefs) db.highlights,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (bookmarksRefs)
                        await $_getPrefetchedData<Book, $BooksTable, Bookmark>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (highlightsRefs)
                        await $_getPrefetchedData<Book, $BooksTable, Highlight>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._highlightsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).highlightsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      Book,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (Book, $$BooksTableReferences),
      Book,
      PrefetchHooks Function({bool bookmarksRefs, bool highlightsRefs})
    >;
typedef $$SavedWordsTableCreateCompanionBuilder =
    SavedWordsCompanion Function({
      Value<int> id,
      required String expression,
      Value<String> reading,
      required String glossaries,
      Value<String> sentenceContext,
      Value<DateTime> dateAdded,
    });
typedef $$SavedWordsTableUpdateCompanionBuilder =
    SavedWordsCompanion Function({
      Value<int> id,
      Value<String> expression,
      Value<String> reading,
      Value<String> glossaries,
      Value<String> sentenceContext,
      Value<DateTime> dateAdded,
    });

class $$SavedWordsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedWordsTable> {
  $$SavedWordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get glossaries => $composableBuilder(
    column: $table.glossaries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sentenceContext => $composableBuilder(
    column: $table.sentenceContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedWordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedWordsTable> {
  $$SavedWordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get glossaries => $composableBuilder(
    column: $table.glossaries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sentenceContext => $composableBuilder(
    column: $table.sentenceContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedWordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedWordsTable> {
  $$SavedWordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reading =>
      $composableBuilder(column: $table.reading, builder: (column) => column);

  GeneratedColumn<String> get glossaries => $composableBuilder(
    column: $table.glossaries,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sentenceContext => $composableBuilder(
    column: $table.sentenceContext,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);
}

class $$SavedWordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedWordsTable,
          SavedWord,
          $$SavedWordsTableFilterComposer,
          $$SavedWordsTableOrderingComposer,
          $$SavedWordsTableAnnotationComposer,
          $$SavedWordsTableCreateCompanionBuilder,
          $$SavedWordsTableUpdateCompanionBuilder,
          (
            SavedWord,
            BaseReferences<_$AppDatabase, $SavedWordsTable, SavedWord>,
          ),
          SavedWord,
          PrefetchHooks Function()
        > {
  $$SavedWordsTableTableManager(_$AppDatabase db, $SavedWordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedWordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedWordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedWordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> expression = const Value.absent(),
                Value<String> reading = const Value.absent(),
                Value<String> glossaries = const Value.absent(),
                Value<String> sentenceContext = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => SavedWordsCompanion(
                id: id,
                expression: expression,
                reading: reading,
                glossaries: glossaries,
                sentenceContext: sentenceContext,
                dateAdded: dateAdded,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String expression,
                Value<String> reading = const Value.absent(),
                required String glossaries,
                Value<String> sentenceContext = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => SavedWordsCompanion.insert(
                id: id,
                expression: expression,
                reading: reading,
                glossaries: glossaries,
                sentenceContext: sentenceContext,
                dateAdded: dateAdded,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedWordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedWordsTable,
      SavedWord,
      $$SavedWordsTableFilterComposer,
      $$SavedWordsTableOrderingComposer,
      $$SavedWordsTableAnnotationComposer,
      $$SavedWordsTableCreateCompanionBuilder,
      $$SavedWordsTableUpdateCompanionBuilder,
      (SavedWord, BaseReferences<_$AppDatabase, $SavedWordsTable, SavedWord>),
      SavedWord,
      PrefetchHooks Function()
    >;
typedef $$DictionaryMetasTableCreateCompanionBuilder =
    DictionaryMetasCompanion Function({
      Value<int> id,
      required String name,
      Value<bool> isEnabled,
      Value<DateTime> dateImported,
      Value<int> sortOrder,
      Value<bool> isHidden,
    });
typedef $$DictionaryMetasTableUpdateCompanionBuilder =
    DictionaryMetasCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<bool> isEnabled,
      Value<DateTime> dateImported,
      Value<int> sortOrder,
      Value<bool> isHidden,
    });

class $$DictionaryMetasTableFilterComposer
    extends Composer<_$AppDatabase, $DictionaryMetasTable> {
  $$DictionaryMetasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateImported => $composableBuilder(
    column: $table.dateImported,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DictionaryMetasTableOrderingComposer
    extends Composer<_$AppDatabase, $DictionaryMetasTable> {
  $$DictionaryMetasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateImported => $composableBuilder(
    column: $table.dateImported,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DictionaryMetasTableAnnotationComposer
    extends Composer<_$AppDatabase, $DictionaryMetasTable> {
  $$DictionaryMetasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<DateTime> get dateImported => $composableBuilder(
    column: $table.dateImported,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isHidden =>
      $composableBuilder(column: $table.isHidden, builder: (column) => column);
}

class $$DictionaryMetasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DictionaryMetasTable,
          DictionaryMeta,
          $$DictionaryMetasTableFilterComposer,
          $$DictionaryMetasTableOrderingComposer,
          $$DictionaryMetasTableAnnotationComposer,
          $$DictionaryMetasTableCreateCompanionBuilder,
          $$DictionaryMetasTableUpdateCompanionBuilder,
          (
            DictionaryMeta,
            BaseReferences<
              _$AppDatabase,
              $DictionaryMetasTable,
              DictionaryMeta
            >,
          ),
          DictionaryMeta,
          PrefetchHooks Function()
        > {
  $$DictionaryMetasTableTableManager(
    _$AppDatabase db,
    $DictionaryMetasTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DictionaryMetasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DictionaryMetasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DictionaryMetasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<DateTime> dateImported = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
              }) => DictionaryMetasCompanion(
                id: id,
                name: name,
                isEnabled: isEnabled,
                dateImported: dateImported,
                sortOrder: sortOrder,
                isHidden: isHidden,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<bool> isEnabled = const Value.absent(),
                Value<DateTime> dateImported = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
              }) => DictionaryMetasCompanion.insert(
                id: id,
                name: name,
                isEnabled: isEnabled,
                dateImported: dateImported,
                sortOrder: sortOrder,
                isHidden: isHidden,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DictionaryMetasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DictionaryMetasTable,
      DictionaryMeta,
      $$DictionaryMetasTableFilterComposer,
      $$DictionaryMetasTableOrderingComposer,
      $$DictionaryMetasTableAnnotationComposer,
      $$DictionaryMetasTableCreateCompanionBuilder,
      $$DictionaryMetasTableUpdateCompanionBuilder,
      (
        DictionaryMeta,
        BaseReferences<_$AppDatabase, $DictionaryMetasTable, DictionaryMeta>,
      ),
      DictionaryMeta,
      PrefetchHooks Function()
    >;
typedef $$DictionaryEntriesTableCreateCompanionBuilder =
    DictionaryEntriesCompanion Function({
      Value<int> id,
      required String expression,
      Value<String> reading,
      Value<String> entryKind,
      Value<String> kanjiOnyomi,
      Value<String> kanjiKunyomi,
      Value<String> definitionTags,
      Value<String> rules,
      Value<String> termTags,
      required String glossaries,
      required int dictionaryId,
    });
typedef $$DictionaryEntriesTableUpdateCompanionBuilder =
    DictionaryEntriesCompanion Function({
      Value<int> id,
      Value<String> expression,
      Value<String> reading,
      Value<String> entryKind,
      Value<String> kanjiOnyomi,
      Value<String> kanjiKunyomi,
      Value<String> definitionTags,
      Value<String> rules,
      Value<String> termTags,
      Value<String> glossaries,
      Value<int> dictionaryId,
    });

class $$DictionaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DictionaryEntriesTable> {
  $$DictionaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryKind => $composableBuilder(
    column: $table.entryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kanjiOnyomi => $composableBuilder(
    column: $table.kanjiOnyomi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kanjiKunyomi => $composableBuilder(
    column: $table.kanjiKunyomi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get definitionTags => $composableBuilder(
    column: $table.definitionTags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rules => $composableBuilder(
    column: $table.rules,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get termTags => $composableBuilder(
    column: $table.termTags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get glossaries => $composableBuilder(
    column: $table.glossaries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DictionaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DictionaryEntriesTable> {
  $$DictionaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryKind => $composableBuilder(
    column: $table.entryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kanjiOnyomi => $composableBuilder(
    column: $table.kanjiOnyomi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kanjiKunyomi => $composableBuilder(
    column: $table.kanjiKunyomi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get definitionTags => $composableBuilder(
    column: $table.definitionTags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rules => $composableBuilder(
    column: $table.rules,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get termTags => $composableBuilder(
    column: $table.termTags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get glossaries => $composableBuilder(
    column: $table.glossaries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DictionaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DictionaryEntriesTable> {
  $$DictionaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reading =>
      $composableBuilder(column: $table.reading, builder: (column) => column);

  GeneratedColumn<String> get entryKind =>
      $composableBuilder(column: $table.entryKind, builder: (column) => column);

  GeneratedColumn<String> get kanjiOnyomi => $composableBuilder(
    column: $table.kanjiOnyomi,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kanjiKunyomi => $composableBuilder(
    column: $table.kanjiKunyomi,
    builder: (column) => column,
  );

  GeneratedColumn<String> get definitionTags => $composableBuilder(
    column: $table.definitionTags,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rules =>
      $composableBuilder(column: $table.rules, builder: (column) => column);

  GeneratedColumn<String> get termTags =>
      $composableBuilder(column: $table.termTags, builder: (column) => column);

  GeneratedColumn<String> get glossaries => $composableBuilder(
    column: $table.glossaries,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => column,
  );
}

class $$DictionaryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DictionaryEntriesTable,
          DictionaryEntry,
          $$DictionaryEntriesTableFilterComposer,
          $$DictionaryEntriesTableOrderingComposer,
          $$DictionaryEntriesTableAnnotationComposer,
          $$DictionaryEntriesTableCreateCompanionBuilder,
          $$DictionaryEntriesTableUpdateCompanionBuilder,
          (
            DictionaryEntry,
            BaseReferences<
              _$AppDatabase,
              $DictionaryEntriesTable,
              DictionaryEntry
            >,
          ),
          DictionaryEntry,
          PrefetchHooks Function()
        > {
  $$DictionaryEntriesTableTableManager(
    _$AppDatabase db,
    $DictionaryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DictionaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DictionaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DictionaryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> expression = const Value.absent(),
                Value<String> reading = const Value.absent(),
                Value<String> entryKind = const Value.absent(),
                Value<String> kanjiOnyomi = const Value.absent(),
                Value<String> kanjiKunyomi = const Value.absent(),
                Value<String> definitionTags = const Value.absent(),
                Value<String> rules = const Value.absent(),
                Value<String> termTags = const Value.absent(),
                Value<String> glossaries = const Value.absent(),
                Value<int> dictionaryId = const Value.absent(),
              }) => DictionaryEntriesCompanion(
                id: id,
                expression: expression,
                reading: reading,
                entryKind: entryKind,
                kanjiOnyomi: kanjiOnyomi,
                kanjiKunyomi: kanjiKunyomi,
                definitionTags: definitionTags,
                rules: rules,
                termTags: termTags,
                glossaries: glossaries,
                dictionaryId: dictionaryId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String expression,
                Value<String> reading = const Value.absent(),
                Value<String> entryKind = const Value.absent(),
                Value<String> kanjiOnyomi = const Value.absent(),
                Value<String> kanjiKunyomi = const Value.absent(),
                Value<String> definitionTags = const Value.absent(),
                Value<String> rules = const Value.absent(),
                Value<String> termTags = const Value.absent(),
                required String glossaries,
                required int dictionaryId,
              }) => DictionaryEntriesCompanion.insert(
                id: id,
                expression: expression,
                reading: reading,
                entryKind: entryKind,
                kanjiOnyomi: kanjiOnyomi,
                kanjiKunyomi: kanjiKunyomi,
                definitionTags: definitionTags,
                rules: rules,
                termTags: termTags,
                glossaries: glossaries,
                dictionaryId: dictionaryId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DictionaryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DictionaryEntriesTable,
      DictionaryEntry,
      $$DictionaryEntriesTableFilterComposer,
      $$DictionaryEntriesTableOrderingComposer,
      $$DictionaryEntriesTableAnnotationComposer,
      $$DictionaryEntriesTableCreateCompanionBuilder,
      $$DictionaryEntriesTableUpdateCompanionBuilder,
      (
        DictionaryEntry,
        BaseReferences<_$AppDatabase, $DictionaryEntriesTable, DictionaryEntry>,
      ),
      DictionaryEntry,
      PrefetchHooks Function()
    >;
typedef $$PitchAccentsTableCreateCompanionBuilder =
    PitchAccentsCompanion Function({
      Value<int> id,
      required String expression,
      Value<String> reading,
      required int downstepPosition,
      required int dictionaryId,
    });
typedef $$PitchAccentsTableUpdateCompanionBuilder =
    PitchAccentsCompanion Function({
      Value<int> id,
      Value<String> expression,
      Value<String> reading,
      Value<int> downstepPosition,
      Value<int> dictionaryId,
    });

class $$PitchAccentsTableFilterComposer
    extends Composer<_$AppDatabase, $PitchAccentsTable> {
  $$PitchAccentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get downstepPosition => $composableBuilder(
    column: $table.downstepPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PitchAccentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PitchAccentsTable> {
  $$PitchAccentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get downstepPosition => $composableBuilder(
    column: $table.downstepPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PitchAccentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PitchAccentsTable> {
  $$PitchAccentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reading =>
      $composableBuilder(column: $table.reading, builder: (column) => column);

  GeneratedColumn<int> get downstepPosition => $composableBuilder(
    column: $table.downstepPosition,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => column,
  );
}

class $$PitchAccentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PitchAccentsTable,
          PitchAccent,
          $$PitchAccentsTableFilterComposer,
          $$PitchAccentsTableOrderingComposer,
          $$PitchAccentsTableAnnotationComposer,
          $$PitchAccentsTableCreateCompanionBuilder,
          $$PitchAccentsTableUpdateCompanionBuilder,
          (
            PitchAccent,
            BaseReferences<_$AppDatabase, $PitchAccentsTable, PitchAccent>,
          ),
          PitchAccent,
          PrefetchHooks Function()
        > {
  $$PitchAccentsTableTableManager(_$AppDatabase db, $PitchAccentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PitchAccentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PitchAccentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PitchAccentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> expression = const Value.absent(),
                Value<String> reading = const Value.absent(),
                Value<int> downstepPosition = const Value.absent(),
                Value<int> dictionaryId = const Value.absent(),
              }) => PitchAccentsCompanion(
                id: id,
                expression: expression,
                reading: reading,
                downstepPosition: downstepPosition,
                dictionaryId: dictionaryId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String expression,
                Value<String> reading = const Value.absent(),
                required int downstepPosition,
                required int dictionaryId,
              }) => PitchAccentsCompanion.insert(
                id: id,
                expression: expression,
                reading: reading,
                downstepPosition: downstepPosition,
                dictionaryId: dictionaryId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PitchAccentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PitchAccentsTable,
      PitchAccent,
      $$PitchAccentsTableFilterComposer,
      $$PitchAccentsTableOrderingComposer,
      $$PitchAccentsTableAnnotationComposer,
      $$PitchAccentsTableCreateCompanionBuilder,
      $$PitchAccentsTableUpdateCompanionBuilder,
      (
        PitchAccent,
        BaseReferences<_$AppDatabase, $PitchAccentsTable, PitchAccent>,
      ),
      PitchAccent,
      PrefetchHooks Function()
    >;
typedef $$FrequenciesTableCreateCompanionBuilder =
    FrequenciesCompanion Function({
      Value<int> id,
      required String expression,
      Value<String> reading,
      required int frequencyRank,
      required int dictionaryId,
    });
typedef $$FrequenciesTableUpdateCompanionBuilder =
    FrequenciesCompanion Function({
      Value<int> id,
      Value<String> expression,
      Value<String> reading,
      Value<int> frequencyRank,
      Value<int> dictionaryId,
    });

class $$FrequenciesTableFilterComposer
    extends Composer<_$AppDatabase, $FrequenciesTable> {
  $$FrequenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frequencyRank => $composableBuilder(
    column: $table.frequencyRank,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FrequenciesTableOrderingComposer
    extends Composer<_$AppDatabase, $FrequenciesTable> {
  $$FrequenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frequencyRank => $composableBuilder(
    column: $table.frequencyRank,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FrequenciesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FrequenciesTable> {
  $$FrequenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get expression => $composableBuilder(
    column: $table.expression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reading =>
      $composableBuilder(column: $table.reading, builder: (column) => column);

  GeneratedColumn<int> get frequencyRank => $composableBuilder(
    column: $table.frequencyRank,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dictionaryId => $composableBuilder(
    column: $table.dictionaryId,
    builder: (column) => column,
  );
}

class $$FrequenciesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FrequenciesTable,
          Frequency,
          $$FrequenciesTableFilterComposer,
          $$FrequenciesTableOrderingComposer,
          $$FrequenciesTableAnnotationComposer,
          $$FrequenciesTableCreateCompanionBuilder,
          $$FrequenciesTableUpdateCompanionBuilder,
          (
            Frequency,
            BaseReferences<_$AppDatabase, $FrequenciesTable, Frequency>,
          ),
          Frequency,
          PrefetchHooks Function()
        > {
  $$FrequenciesTableTableManager(_$AppDatabase db, $FrequenciesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FrequenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FrequenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FrequenciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> expression = const Value.absent(),
                Value<String> reading = const Value.absent(),
                Value<int> frequencyRank = const Value.absent(),
                Value<int> dictionaryId = const Value.absent(),
              }) => FrequenciesCompanion(
                id: id,
                expression: expression,
                reading: reading,
                frequencyRank: frequencyRank,
                dictionaryId: dictionaryId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String expression,
                Value<String> reading = const Value.absent(),
                required int frequencyRank,
                required int dictionaryId,
              }) => FrequenciesCompanion.insert(
                id: id,
                expression: expression,
                reading: reading,
                frequencyRank: frequencyRank,
                dictionaryId: dictionaryId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FrequenciesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FrequenciesTable,
      Frequency,
      $$FrequenciesTableFilterComposer,
      $$FrequenciesTableOrderingComposer,
      $$FrequenciesTableAnnotationComposer,
      $$FrequenciesTableCreateCompanionBuilder,
      $$FrequenciesTableUpdateCompanionBuilder,
      (Frequency, BaseReferences<_$AppDatabase, $FrequenciesTable, Frequency>),
      Frequency,
      PrefetchHooks Function()
    >;
typedef $$BookmarksTableCreateCompanionBuilder =
    BookmarksCompanion Function({
      Value<int> id,
      required int bookId,
      required String cfi,
      Value<double> progress,
      Value<String> chapterTitle,
      Value<String> userNote,
      Value<DateTime> dateAdded,
    });
typedef $$BookmarksTableUpdateCompanionBuilder =
    BookmarksCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<String> cfi,
      Value<double> progress,
      Value<String> chapterTitle,
      Value<String> userNote,
      Value<DateTime> dateAdded,
    });

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) => db.books.createAlias(
    $_aliasNameGenerator(db.bookmarks.bookId, db.books.id),
  );

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cfi => $composableBuilder(
    column: $table.cfi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cfi => $composableBuilder(
    column: $table.cfi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cfi =>
      $composableBuilder(column: $table.cfi, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userNote =>
      $composableBuilder(column: $table.userNote, builder: (column) => column);

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          Bookmark,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (Bookmark, $$BookmarksTableReferences),
          Bookmark,
          PrefetchHooks Function({bool bookId})
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<String> cfi = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<String> userNote = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => BookmarksCompanion(
                id: id,
                bookId: bookId,
                cfi: cfi,
                progress: progress,
                chapterTitle: chapterTitle,
                userNote: userNote,
                dateAdded: dateAdded,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required String cfi,
                Value<double> progress = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<String> userNote = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => BookmarksCompanion.insert(
                id: id,
                bookId: bookId,
                cfi: cfi,
                progress: progress,
                chapterTitle: chapterTitle,
                userNote: userNote,
                dateAdded: dateAdded,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookmarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookmarksTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookmarksTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      Bookmark,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (Bookmark, $$BookmarksTableReferences),
      Bookmark,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$HighlightsTableCreateCompanionBuilder =
    HighlightsCompanion Function({
      Value<int> id,
      required int bookId,
      required String cfiRange,
      required String selectedText,
      Value<String> color,
      Value<String> userNote,
      Value<DateTime> dateAdded,
    });
typedef $$HighlightsTableUpdateCompanionBuilder =
    HighlightsCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<String> cfiRange,
      Value<String> selectedText,
      Value<String> color,
      Value<String> userNote,
      Value<DateTime> dateAdded,
    });

final class $$HighlightsTableReferences
    extends BaseReferences<_$AppDatabase, $HighlightsTable, Highlight> {
  $$HighlightsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) => db.books.createAlias(
    $_aliasNameGenerator(db.highlights.bookId, db.books.id),
  );

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<int>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HighlightsTableFilterComposer
    extends Composer<_$AppDatabase, $HighlightsTable> {
  $$HighlightsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cfiRange => $composableBuilder(
    column: $table.cfiRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HighlightsTableOrderingComposer
    extends Composer<_$AppDatabase, $HighlightsTable> {
  $$HighlightsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cfiRange => $composableBuilder(
    column: $table.cfiRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HighlightsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HighlightsTable> {
  $$HighlightsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cfiRange =>
      $composableBuilder(column: $table.cfiRange, builder: (column) => column);

  GeneratedColumn<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get userNote =>
      $composableBuilder(column: $table.userNote, builder: (column) => column);

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HighlightsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HighlightsTable,
          Highlight,
          $$HighlightsTableFilterComposer,
          $$HighlightsTableOrderingComposer,
          $$HighlightsTableAnnotationComposer,
          $$HighlightsTableCreateCompanionBuilder,
          $$HighlightsTableUpdateCompanionBuilder,
          (Highlight, $$HighlightsTableReferences),
          Highlight,
          PrefetchHooks Function({bool bookId})
        > {
  $$HighlightsTableTableManager(_$AppDatabase db, $HighlightsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HighlightsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HighlightsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HighlightsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<String> cfiRange = const Value.absent(),
                Value<String> selectedText = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> userNote = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => HighlightsCompanion(
                id: id,
                bookId: bookId,
                cfiRange: cfiRange,
                selectedText: selectedText,
                color: color,
                userNote: userNote,
                dateAdded: dateAdded,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required String cfiRange,
                required String selectedText,
                Value<String> color = const Value.absent(),
                Value<String> userNote = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => HighlightsCompanion.insert(
                id: id,
                bookId: bookId,
                cfiRange: cfiRange,
                selectedText: selectedText,
                color: color,
                userNote: userNote,
                dateAdded: dateAdded,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HighlightsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$HighlightsTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$HighlightsTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HighlightsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HighlightsTable,
      Highlight,
      $$HighlightsTableFilterComposer,
      $$HighlightsTableOrderingComposer,
      $$HighlightsTableAnnotationComposer,
      $$HighlightsTableCreateCompanionBuilder,
      $$HighlightsTableUpdateCompanionBuilder,
      (Highlight, $$HighlightsTableReferences),
      Highlight,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$PendingBookDatasTableCreateCompanionBuilder =
    PendingBookDatasCompanion Function({
      Value<int> id,
      required String bookKey,
      required String dataJson,
      Value<DateTime> dateAdded,
    });
typedef $$PendingBookDatasTableUpdateCompanionBuilder =
    PendingBookDatasCompanion Function({
      Value<int> id,
      Value<String> bookKey,
      Value<String> dataJson,
      Value<DateTime> dateAdded,
    });

class $$PendingBookDatasTableFilterComposer
    extends Composer<_$AppDatabase, $PendingBookDatasTable> {
  $$PendingBookDatasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookKey => $composableBuilder(
    column: $table.bookKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingBookDatasTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingBookDatasTable> {
  $$PendingBookDatasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookKey => $composableBuilder(
    column: $table.bookKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingBookDatasTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingBookDatasTable> {
  $$PendingBookDatasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookKey =>
      $composableBuilder(column: $table.bookKey, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);
}

class $$PendingBookDatasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingBookDatasTable,
          PendingBookData,
          $$PendingBookDatasTableFilterComposer,
          $$PendingBookDatasTableOrderingComposer,
          $$PendingBookDatasTableAnnotationComposer,
          $$PendingBookDatasTableCreateCompanionBuilder,
          $$PendingBookDatasTableUpdateCompanionBuilder,
          (
            PendingBookData,
            BaseReferences<
              _$AppDatabase,
              $PendingBookDatasTable,
              PendingBookData
            >,
          ),
          PendingBookData,
          PrefetchHooks Function()
        > {
  $$PendingBookDatasTableTableManager(
    _$AppDatabase db,
    $PendingBookDatasTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingBookDatasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingBookDatasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingBookDatasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookKey = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
              }) => PendingBookDatasCompanion(
                id: id,
                bookKey: bookKey,
                dataJson: dataJson,
                dateAdded: dateAdded,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bookKey,
                required String dataJson,
                Value<DateTime> dateAdded = const Value.absent(),
              }) => PendingBookDatasCompanion.insert(
                id: id,
                bookKey: bookKey,
                dataJson: dataJson,
                dateAdded: dateAdded,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingBookDatasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingBookDatasTable,
      PendingBookData,
      $$PendingBookDatasTableFilterComposer,
      $$PendingBookDatasTableOrderingComposer,
      $$PendingBookDatasTableAnnotationComposer,
      $$PendingBookDatasTableCreateCompanionBuilder,
      $$PendingBookDatasTableUpdateCompanionBuilder,
      (
        PendingBookData,
        BaseReferences<_$AppDatabase, $PendingBookDatasTable, PendingBookData>,
      ),
      PendingBookData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$SavedWordsTableTableManager get savedWords =>
      $$SavedWordsTableTableManager(_db, _db.savedWords);
  $$DictionaryMetasTableTableManager get dictionaryMetas =>
      $$DictionaryMetasTableTableManager(_db, _db.dictionaryMetas);
  $$DictionaryEntriesTableTableManager get dictionaryEntries =>
      $$DictionaryEntriesTableTableManager(_db, _db.dictionaryEntries);
  $$PitchAccentsTableTableManager get pitchAccents =>
      $$PitchAccentsTableTableManager(_db, _db.pitchAccents);
  $$FrequenciesTableTableManager get frequencies =>
      $$FrequenciesTableTableManager(_db, _db.frequencies);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$HighlightsTableTableManager get highlights =>
      $$HighlightsTableTableManager(_db, _db.highlights);
  $$PendingBookDatasTableTableManager get pendingBookDatas =>
      $$PendingBookDatasTableTableManager(_db, _db.pendingBookDatas);
}
