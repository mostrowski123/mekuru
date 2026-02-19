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
  final String glossaries;
  final int dictionaryId;
  const DictionaryEntry({
    required this.id,
    required this.expression,
    required this.reading,
    required this.glossaries,
    required this.dictionaryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['expression'] = Variable<String>(expression);
    map['reading'] = Variable<String>(reading);
    map['glossaries'] = Variable<String>(glossaries);
    map['dictionary_id'] = Variable<int>(dictionaryId);
    return map;
  }

  DictionaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return DictionaryEntriesCompanion(
      id: Value(id),
      expression: Value(expression),
      reading: Value(reading),
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
      'glossaries': serializer.toJson<String>(glossaries),
      'dictionaryId': serializer.toJson<int>(dictionaryId),
    };
  }

  DictionaryEntry copyWith({
    int? id,
    String? expression,
    String? reading,
    String? glossaries,
    int? dictionaryId,
  }) => DictionaryEntry(
    id: id ?? this.id,
    expression: expression ?? this.expression,
    reading: reading ?? this.reading,
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
          ..write('glossaries: $glossaries, ')
          ..write('dictionaryId: $dictionaryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, expression, reading, glossaries, dictionaryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DictionaryEntry &&
          other.id == this.id &&
          other.expression == this.expression &&
          other.reading == this.reading &&
          other.glossaries == this.glossaries &&
          other.dictionaryId == this.dictionaryId);
}

class DictionaryEntriesCompanion extends UpdateCompanion<DictionaryEntry> {
  final Value<int> id;
  final Value<String> expression;
  final Value<String> reading;
  final Value<String> glossaries;
  final Value<int> dictionaryId;
  const DictionaryEntriesCompanion({
    this.id = const Value.absent(),
    this.expression = const Value.absent(),
    this.reading = const Value.absent(),
    this.glossaries = const Value.absent(),
    this.dictionaryId = const Value.absent(),
  });
  DictionaryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String expression,
    this.reading = const Value.absent(),
    required String glossaries,
    required int dictionaryId,
  }) : expression = Value(expression),
       glossaries = Value(glossaries),
       dictionaryId = Value(dictionaryId);
  static Insertable<DictionaryEntry> custom({
    Expression<int>? id,
    Expression<String>? expression,
    Expression<String>? reading,
    Expression<String>? glossaries,
    Expression<int>? dictionaryId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expression != null) 'expression': expression,
      if (reading != null) 'reading': reading,
      if (glossaries != null) 'glossaries': glossaries,
      if (dictionaryId != null) 'dictionary_id': dictionaryId,
    });
  }

  DictionaryEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? expression,
    Value<String>? reading,
    Value<String>? glossaries,
    Value<int>? dictionaryId,
  }) {
    return DictionaryEntriesCompanion(
      id: id ?? this.id,
      expression: expression ?? this.expression,
      reading: reading ?? this.reading,
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
  late final Index idxExpression = Index(
    'idx_expression',
    'CREATE INDEX idx_expression ON dictionary_entries (expression)',
  );
  late final Index idxReading = Index(
    'idx_reading',
    'CREATE INDEX idx_reading ON dictionary_entries (reading)',
  );
  late final Index idxPitchExpression = Index(
    'idx_pitch_expression',
    'CREATE INDEX idx_pitch_expression ON pitch_accents (expression)',
  );
  late final Index idxPitchReading = Index(
    'idx_pitch_reading',
    'CREATE INDEX idx_pitch_reading ON pitch_accents (reading)',
  );
  late final Index idxFreqExpression = Index(
    'idx_freq_expression',
    'CREATE INDEX idx_freq_expression ON frequencies (expression)',
  );
  late final Index idxFreqReading = Index(
    'idx_freq_reading',
    'CREATE INDEX idx_freq_reading ON frequencies (reading)',
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
    idxExpression,
    idxReading,
    idxPitchExpression,
    idxPitchReading,
    idxFreqExpression,
    idxFreqReading,
  ];
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      required String title,
      required String filePath,
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
          (Book, BaseReferences<_$AppDatabase, $BooksTable, Book>),
          Book,
          PrefetchHooks Function()
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
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
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
      (Book, BaseReferences<_$AppDatabase, $BooksTable, Book>),
      Book,
      PrefetchHooks Function()
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
      required String glossaries,
      required int dictionaryId,
    });
typedef $$DictionaryEntriesTableUpdateCompanionBuilder =
    DictionaryEntriesCompanion Function({
      Value<int> id,
      Value<String> expression,
      Value<String> reading,
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
                Value<String> glossaries = const Value.absent(),
                Value<int> dictionaryId = const Value.absent(),
              }) => DictionaryEntriesCompanion(
                id: id,
                expression: expression,
                reading: reading,
                glossaries: glossaries,
                dictionaryId: dictionaryId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String expression,
                Value<String> reading = const Value.absent(),
                required String glossaries,
                required int dictionaryId,
              }) => DictionaryEntriesCompanion.insert(
                id: id,
                expression: expression,
                reading: reading,
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
}
