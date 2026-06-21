// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

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
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _streamPathMeta = const VerificationMeta(
    'streamPath',
  );
  @override
  late final GeneratedColumn<String> streamPath = GeneratedColumn<String>(
    'stream_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalWordsMeta = const VerificationMeta(
    'totalWords',
  );
  @override
  late final GeneratedColumn<int> totalWords = GeneratedColumn<int>(
    'total_words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalBonusMsMeta = const VerificationMeta(
    'totalBonusMs',
  );
  @override
  late final GeneratedColumn<int> totalBonusMs = GeneratedColumn<int>(
    'total_bonus_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtEpochSMeta = const VerificationMeta(
    'createdAtEpochS',
  );
  @override
  late final GeneratedColumn<int> createdAtEpochS = GeneratedColumn<int>(
    'created_at_epoch_s',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadEpochSMeta = const VerificationMeta(
    'lastReadEpochS',
  );
  @override
  late final GeneratedColumn<int> lastReadEpochS = GeneratedColumn<int>(
    'last_read_epoch_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    author,
    coverPath,
    streamPath,
    fingerprint,
    contentHash,
    totalWords,
    totalBonusMs,
    createdAtEpochS,
    lastReadEpochS,
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
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('stream_path')) {
      context.handle(
        _streamPathMeta,
        streamPath.isAcceptableOrUnknown(data['stream_path']!, _streamPathMeta),
      );
    } else if (isInserting) {
      context.missing(_streamPathMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('total_words')) {
      context.handle(
        _totalWordsMeta,
        totalWords.isAcceptableOrUnknown(data['total_words']!, _totalWordsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalWordsMeta);
    }
    if (data.containsKey('total_bonus_ms')) {
      context.handle(
        _totalBonusMsMeta,
        totalBonusMs.isAcceptableOrUnknown(
          data['total_bonus_ms']!,
          _totalBonusMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalBonusMsMeta);
    }
    if (data.containsKey('created_at_epoch_s')) {
      context.handle(
        _createdAtEpochSMeta,
        createdAtEpochS.isAcceptableOrUnknown(
          data['created_at_epoch_s']!,
          _createdAtEpochSMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtEpochSMeta);
    }
    if (data.containsKey('last_read_epoch_s')) {
      context.handle(
        _lastReadEpochSMeta,
        lastReadEpochS.isAcceptableOrUnknown(
          data['last_read_epoch_s']!,
          _lastReadEpochSMeta,
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
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      streamPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_path'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      totalWords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_words'],
      )!,
      totalBonusMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bonus_ms'],
      )!,
      createdAtEpochS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_epoch_s'],
      )!,
      lastReadEpochS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_epoch_s'],
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

  /// Null for txt/md (Story 2.3); 2.4 fills it from the EPUB OPF.
  final String? author;

  /// Null here; 2.4 sets it when it extracts a cover.
  final String? coverPath;

  /// Path to the flat-file word stream (`stream_store`).
  final String streamPath;
  final String fingerprint;

  /// SHA-256 (hex) of the raw imported file bytes — the content-identity key for
  /// re-import dedup (Story 2.7). Distinct from [fingerprint], which is salted by
  /// import time and so differs on every import of the same file. Nullable: rows
  /// imported before schema v2 stay null and coexist under the partial unique
  /// index (`content_hash IS NOT NULL`).
  final String? contentHash;
  final int totalWords;
  final int totalBonusMs;
  final int createdAtEpochS;

  /// AC2 last-read placeholder; stays null until Epic 4 wires reading progress.
  final int? lastReadEpochS;
  const Book({
    required this.id,
    required this.title,
    this.author,
    this.coverPath,
    required this.streamPath,
    required this.fingerprint,
    this.contentHash,
    required this.totalWords,
    required this.totalBonusMs,
    required this.createdAtEpochS,
    this.lastReadEpochS,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['stream_path'] = Variable<String>(streamPath);
    map['fingerprint'] = Variable<String>(fingerprint);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    map['total_words'] = Variable<int>(totalWords);
    map['total_bonus_ms'] = Variable<int>(totalBonusMs);
    map['created_at_epoch_s'] = Variable<int>(createdAtEpochS);
    if (!nullToAbsent || lastReadEpochS != null) {
      map['last_read_epoch_s'] = Variable<int>(lastReadEpochS);
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      streamPath: Value(streamPath),
      fingerprint: Value(fingerprint),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      totalWords: Value(totalWords),
      totalBonusMs: Value(totalBonusMs),
      createdAtEpochS: Value(createdAtEpochS),
      lastReadEpochS: lastReadEpochS == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadEpochS),
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
      author: serializer.fromJson<String?>(json['author']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      streamPath: serializer.fromJson<String>(json['streamPath']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      totalWords: serializer.fromJson<int>(json['totalWords']),
      totalBonusMs: serializer.fromJson<int>(json['totalBonusMs']),
      createdAtEpochS: serializer.fromJson<int>(json['createdAtEpochS']),
      lastReadEpochS: serializer.fromJson<int?>(json['lastReadEpochS']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'coverPath': serializer.toJson<String?>(coverPath),
      'streamPath': serializer.toJson<String>(streamPath),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'contentHash': serializer.toJson<String?>(contentHash),
      'totalWords': serializer.toJson<int>(totalWords),
      'totalBonusMs': serializer.toJson<int>(totalBonusMs),
      'createdAtEpochS': serializer.toJson<int>(createdAtEpochS),
      'lastReadEpochS': serializer.toJson<int?>(lastReadEpochS),
    };
  }

  Book copyWith({
    int? id,
    String? title,
    Value<String?> author = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    String? streamPath,
    String? fingerprint,
    Value<String?> contentHash = const Value.absent(),
    int? totalWords,
    int? totalBonusMs,
    int? createdAtEpochS,
    Value<int?> lastReadEpochS = const Value.absent(),
  }) => Book(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    streamPath: streamPath ?? this.streamPath,
    fingerprint: fingerprint ?? this.fingerprint,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    totalWords: totalWords ?? this.totalWords,
    totalBonusMs: totalBonusMs ?? this.totalBonusMs,
    createdAtEpochS: createdAtEpochS ?? this.createdAtEpochS,
    lastReadEpochS: lastReadEpochS.present
        ? lastReadEpochS.value
        : this.lastReadEpochS,
  );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      streamPath: data.streamPath.present
          ? data.streamPath.value
          : this.streamPath,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      totalWords: data.totalWords.present
          ? data.totalWords.value
          : this.totalWords,
      totalBonusMs: data.totalBonusMs.present
          ? data.totalBonusMs.value
          : this.totalBonusMs,
      createdAtEpochS: data.createdAtEpochS.present
          ? data.createdAtEpochS.value
          : this.createdAtEpochS,
      lastReadEpochS: data.lastReadEpochS.present
          ? data.lastReadEpochS.value
          : this.lastReadEpochS,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('coverPath: $coverPath, ')
          ..write('streamPath: $streamPath, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('contentHash: $contentHash, ')
          ..write('totalWords: $totalWords, ')
          ..write('totalBonusMs: $totalBonusMs, ')
          ..write('createdAtEpochS: $createdAtEpochS, ')
          ..write('lastReadEpochS: $lastReadEpochS')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    author,
    coverPath,
    streamPath,
    fingerprint,
    contentHash,
    totalWords,
    totalBonusMs,
    createdAtEpochS,
    lastReadEpochS,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.coverPath == this.coverPath &&
          other.streamPath == this.streamPath &&
          other.fingerprint == this.fingerprint &&
          other.contentHash == this.contentHash &&
          other.totalWords == this.totalWords &&
          other.totalBonusMs == this.totalBonusMs &&
          other.createdAtEpochS == this.createdAtEpochS &&
          other.lastReadEpochS == this.lastReadEpochS);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> coverPath;
  final Value<String> streamPath;
  final Value<String> fingerprint;
  final Value<String?> contentHash;
  final Value<int> totalWords;
  final Value<int> totalBonusMs;
  final Value<int> createdAtEpochS;
  final Value<int?> lastReadEpochS;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.streamPath = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.totalWords = const Value.absent(),
    this.totalBonusMs = const Value.absent(),
    this.createdAtEpochS = const Value.absent(),
    this.lastReadEpochS = const Value.absent(),
  });
  BooksCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.author = const Value.absent(),
    this.coverPath = const Value.absent(),
    required String streamPath,
    required String fingerprint,
    this.contentHash = const Value.absent(),
    required int totalWords,
    required int totalBonusMs,
    required int createdAtEpochS,
    this.lastReadEpochS = const Value.absent(),
  }) : title = Value(title),
       streamPath = Value(streamPath),
       fingerprint = Value(fingerprint),
       totalWords = Value(totalWords),
       totalBonusMs = Value(totalBonusMs),
       createdAtEpochS = Value(createdAtEpochS);
  static Insertable<Book> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? coverPath,
    Expression<String>? streamPath,
    Expression<String>? fingerprint,
    Expression<String>? contentHash,
    Expression<int>? totalWords,
    Expression<int>? totalBonusMs,
    Expression<int>? createdAtEpochS,
    Expression<int>? lastReadEpochS,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (coverPath != null) 'cover_path': coverPath,
      if (streamPath != null) 'stream_path': streamPath,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (contentHash != null) 'content_hash': contentHash,
      if (totalWords != null) 'total_words': totalWords,
      if (totalBonusMs != null) 'total_bonus_ms': totalBonusMs,
      if (createdAtEpochS != null) 'created_at_epoch_s': createdAtEpochS,
      if (lastReadEpochS != null) 'last_read_epoch_s': lastReadEpochS,
    });
  }

  BooksCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? author,
    Value<String?>? coverPath,
    Value<String>? streamPath,
    Value<String>? fingerprint,
    Value<String?>? contentHash,
    Value<int>? totalWords,
    Value<int>? totalBonusMs,
    Value<int>? createdAtEpochS,
    Value<int?>? lastReadEpochS,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      streamPath: streamPath ?? this.streamPath,
      fingerprint: fingerprint ?? this.fingerprint,
      contentHash: contentHash ?? this.contentHash,
      totalWords: totalWords ?? this.totalWords,
      totalBonusMs: totalBonusMs ?? this.totalBonusMs,
      createdAtEpochS: createdAtEpochS ?? this.createdAtEpochS,
      lastReadEpochS: lastReadEpochS ?? this.lastReadEpochS,
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
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (streamPath.present) {
      map['stream_path'] = Variable<String>(streamPath.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (totalWords.present) {
      map['total_words'] = Variable<int>(totalWords.value);
    }
    if (totalBonusMs.present) {
      map['total_bonus_ms'] = Variable<int>(totalBonusMs.value);
    }
    if (createdAtEpochS.present) {
      map['created_at_epoch_s'] = Variable<int>(createdAtEpochS.value);
    }
    if (lastReadEpochS.present) {
      map['last_read_epoch_s'] = Variable<int>(lastReadEpochS.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('coverPath: $coverPath, ')
          ..write('streamPath: $streamPath, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('contentHash: $contentHash, ')
          ..write('totalWords: $totalWords, ')
          ..write('totalBonusMs: $totalBonusMs, ')
          ..write('createdAtEpochS: $createdAtEpochS, ')
          ..write('lastReadEpochS: $lastReadEpochS')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters with TableInfo<$ChaptersTable, Chapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  static const VerificationMeta _wordOffsetMeta = const VerificationMeta(
    'wordOffset',
  );
  @override
  late final GeneratedColumn<int> wordOffset = GeneratedColumn<int>(
    'word_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cumulativeBonusMsMeta = const VerificationMeta(
    'cumulativeBonusMs',
  );
  @override
  late final GeneratedColumn<int> cumulativeBonusMs = GeneratedColumn<int>(
    'cumulative_bonus_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    chapterIndex,
    title,
    wordOffset,
    cumulativeBonusMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chapter> instance, {
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
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('word_offset')) {
      context.handle(
        _wordOffsetMeta,
        wordOffset.isAcceptableOrUnknown(data['word_offset']!, _wordOffsetMeta),
      );
    } else if (isInserting) {
      context.missing(_wordOffsetMeta);
    }
    if (data.containsKey('cumulative_bonus_ms')) {
      context.handle(
        _cumulativeBonusMsMeta,
        cumulativeBonusMs.isAcceptableOrUnknown(
          data['cumulative_bonus_ms']!,
          _cumulativeBonusMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cumulativeBonusMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chapter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}book_id'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      wordOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_offset'],
      )!,
      cumulativeBonusMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cumulative_bonus_ms'],
      )!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class Chapter extends DataClass implements Insertable<Chapter> {
  final int id;
  final int bookId;
  final int chapterIndex;
  final String title;

  /// Absolute first-word index — mirrors `ChapterEntry.offset`.
  final int wordOffset;
  final int cumulativeBonusMs;
  const Chapter({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    required this.wordOffset,
    required this.cumulativeBonusMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<int>(bookId);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['title'] = Variable<String>(title);
    map['word_offset'] = Variable<int>(wordOffset);
    map['cumulative_bonus_ms'] = Variable<int>(cumulativeBonusMs);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      bookId: Value(bookId),
      chapterIndex: Value(chapterIndex),
      title: Value(title),
      wordOffset: Value(wordOffset),
      cumulativeBonusMs: Value(cumulativeBonusMs),
    );
  }

  factory Chapter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chapter(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<int>(json['bookId']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      title: serializer.fromJson<String>(json['title']),
      wordOffset: serializer.fromJson<int>(json['wordOffset']),
      cumulativeBonusMs: serializer.fromJson<int>(json['cumulativeBonusMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<int>(bookId),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'title': serializer.toJson<String>(title),
      'wordOffset': serializer.toJson<int>(wordOffset),
      'cumulativeBonusMs': serializer.toJson<int>(cumulativeBonusMs),
    };
  }

  Chapter copyWith({
    int? id,
    int? bookId,
    int? chapterIndex,
    String? title,
    int? wordOffset,
    int? cumulativeBonusMs,
  }) => Chapter(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    title: title ?? this.title,
    wordOffset: wordOffset ?? this.wordOffset,
    cumulativeBonusMs: cumulativeBonusMs ?? this.cumulativeBonusMs,
  );
  Chapter copyWithCompanion(ChaptersCompanion data) {
    return Chapter(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      title: data.title.present ? data.title.value : this.title,
      wordOffset: data.wordOffset.present
          ? data.wordOffset.value
          : this.wordOffset,
      cumulativeBonusMs: data.cumulativeBonusMs.present
          ? data.cumulativeBonusMs.value
          : this.cumulativeBonusMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chapter(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('title: $title, ')
          ..write('wordOffset: $wordOffset, ')
          ..write('cumulativeBonusMs: $cumulativeBonusMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    chapterIndex,
    title,
    wordOffset,
    cumulativeBonusMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.chapterIndex == this.chapterIndex &&
          other.title == this.title &&
          other.wordOffset == this.wordOffset &&
          other.cumulativeBonusMs == this.cumulativeBonusMs);
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<int> id;
  final Value<int> bookId;
  final Value<int> chapterIndex;
  final Value<String> title;
  final Value<int> wordOffset;
  final Value<int> cumulativeBonusMs;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.title = const Value.absent(),
    this.wordOffset = const Value.absent(),
    this.cumulativeBonusMs = const Value.absent(),
  });
  ChaptersCompanion.insert({
    this.id = const Value.absent(),
    required int bookId,
    required int chapterIndex,
    required String title,
    required int wordOffset,
    required int cumulativeBonusMs,
  }) : bookId = Value(bookId),
       chapterIndex = Value(chapterIndex),
       title = Value(title),
       wordOffset = Value(wordOffset),
       cumulativeBonusMs = Value(cumulativeBonusMs);
  static Insertable<Chapter> custom({
    Expression<int>? id,
    Expression<int>? bookId,
    Expression<int>? chapterIndex,
    Expression<String>? title,
    Expression<int>? wordOffset,
    Expression<int>? cumulativeBonusMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (title != null) 'title': title,
      if (wordOffset != null) 'word_offset': wordOffset,
      if (cumulativeBonusMs != null) 'cumulative_bonus_ms': cumulativeBonusMs,
    });
  }

  ChaptersCompanion copyWith({
    Value<int>? id,
    Value<int>? bookId,
    Value<int>? chapterIndex,
    Value<String>? title,
    Value<int>? wordOffset,
    Value<int>? cumulativeBonusMs,
  }) {
    return ChaptersCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      title: title ?? this.title,
      wordOffset: wordOffset ?? this.wordOffset,
      cumulativeBonusMs: cumulativeBonusMs ?? this.cumulativeBonusMs,
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
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (wordOffset.present) {
      map['word_offset'] = Variable<int>(wordOffset.value);
    }
    if (cumulativeBonusMs.present) {
      map['cumulative_bonus_ms'] = Variable<int>(cumulativeBonusMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('title: $title, ')
          ..write('wordOffset: $wordOffset, ')
          ..write('cumulativeBonusMs: $cumulativeBonusMs')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [books, chapters];
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      required String title,
      Value<String?> author,
      Value<String?> coverPath,
      required String streamPath,
      required String fingerprint,
      Value<String?> contentHash,
      required int totalWords,
      required int totalBonusMs,
      required int createdAtEpochS,
      Value<int?> lastReadEpochS,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String?> author,
      Value<String?> coverPath,
      Value<String> streamPath,
      Value<String> fingerprint,
      Value<String?> contentHash,
      Value<int> totalWords,
      Value<int> totalBonusMs,
      Value<int> createdAtEpochS,
      Value<int?> lastReadEpochS,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ChaptersTable, List<Chapter>> _chaptersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chapters,
    aliasName: 'books__id__chapters__book_id',
  );

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
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

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamPath => $composableBuilder(
    column: $table.streamPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalWords => $composableBuilder(
    column: $table.totalWords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBonusMs => $composableBuilder(
    column: $table.totalBonusMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtEpochS => $composableBuilder(
    column: $table.createdAtEpochS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadEpochS => $composableBuilder(
    column: $table.lastReadEpochS,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> chaptersRefs(
    Expression<bool> Function($$ChaptersTableFilterComposer f) f,
  ) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
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

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamPath => $composableBuilder(
    column: $table.streamPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalWords => $composableBuilder(
    column: $table.totalWords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBonusMs => $composableBuilder(
    column: $table.totalBonusMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtEpochS => $composableBuilder(
    column: $table.createdAtEpochS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadEpochS => $composableBuilder(
    column: $table.lastReadEpochS,
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

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get streamPath => $composableBuilder(
    column: $table.streamPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalWords => $composableBuilder(
    column: $table.totalWords,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBonusMs => $composableBuilder(
    column: $table.totalBonusMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtEpochS => $composableBuilder(
    column: $table.createdAtEpochS,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReadEpochS => $composableBuilder(
    column: $table.lastReadEpochS,
    builder: (column) => column,
  );

  Expression<T> chaptersRefs<T extends Object>(
    Expression<T> Function($$ChaptersTableAnnotationComposer a) f,
  ) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
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
          PrefetchHooks Function({bool chaptersRefs})
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
                Value<String?> author = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> streamPath = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> totalWords = const Value.absent(),
                Value<int> totalBonusMs = const Value.absent(),
                Value<int> createdAtEpochS = const Value.absent(),
                Value<int?> lastReadEpochS = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                author: author,
                coverPath: coverPath,
                streamPath: streamPath,
                fingerprint: fingerprint,
                contentHash: contentHash,
                totalWords: totalWords,
                totalBonusMs: totalBonusMs,
                createdAtEpochS: createdAtEpochS,
                lastReadEpochS: lastReadEpochS,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String?> author = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                required String streamPath,
                required String fingerprint,
                Value<String?> contentHash = const Value.absent(),
                required int totalWords,
                required int totalBonusMs,
                required int createdAtEpochS,
                Value<int?> lastReadEpochS = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                author: author,
                coverPath: coverPath,
                streamPath: streamPath,
                fingerprint: fingerprint,
                contentHash: contentHash,
                totalWords: totalWords,
                totalBonusMs: totalBonusMs,
                createdAtEpochS: createdAtEpochS,
                lastReadEpochS: lastReadEpochS,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({chaptersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (chaptersRefs) db.chapters],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chaptersRefs)
                    await $_getPrefetchedData<Book, $BooksTable, Chapter>(
                      currentTable: table,
                      referencedTable: $$BooksTableReferences
                          ._chaptersRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$BooksTableReferences(db, table, p0).chaptersRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.bookId == item.id),
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
      PrefetchHooks Function({bool chaptersRefs})
    >;
typedef $$ChaptersTableCreateCompanionBuilder =
    ChaptersCompanion Function({
      Value<int> id,
      required int bookId,
      required int chapterIndex,
      required String title,
      required int wordOffset,
      required int cumulativeBonusMs,
    });
typedef $$ChaptersTableUpdateCompanionBuilder =
    ChaptersCompanion Function({
      Value<int> id,
      Value<int> bookId,
      Value<int> chapterIndex,
      Value<String> title,
      Value<int> wordOffset,
      Value<int> cumulativeBonusMs,
    });

final class $$ChaptersTableReferences
    extends BaseReferences<_$AppDatabase, $ChaptersTable, Chapter> {
  $$ChaptersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('chapters__book_id__books__id');

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

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
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

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wordOffset => $composableBuilder(
    column: $table.wordOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cumulativeBonusMs => $composableBuilder(
    column: $table.cumulativeBonusMs,
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

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
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

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wordOffset => $composableBuilder(
    column: $table.wordOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cumulativeBonusMs => $composableBuilder(
    column: $table.cumulativeBonusMs,
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

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get wordOffset => $composableBuilder(
    column: $table.wordOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cumulativeBonusMs => $composableBuilder(
    column: $table.cumulativeBonusMs,
    builder: (column) => column,
  );

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

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          Chapter,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (Chapter, $$ChaptersTableReferences),
          Chapter,
          PrefetchHooks Function({bool bookId})
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bookId = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> wordOffset = const Value.absent(),
                Value<int> cumulativeBonusMs = const Value.absent(),
              }) => ChaptersCompanion(
                id: id,
                bookId: bookId,
                chapterIndex: chapterIndex,
                title: title,
                wordOffset: wordOffset,
                cumulativeBonusMs: cumulativeBonusMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bookId,
                required int chapterIndex,
                required String title,
                required int wordOffset,
                required int cumulativeBonusMs,
              }) => ChaptersCompanion.insert(
                id: id,
                bookId: bookId,
                chapterIndex: chapterIndex,
                title: title,
                wordOffset: wordOffset,
                cumulativeBonusMs: cumulativeBonusMs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChaptersTableReferences(db, table, e),
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
                                referencedTable: $$ChaptersTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$ChaptersTableReferences
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

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      Chapter,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (Chapter, $$ChaptersTableReferences),
      Chapter,
      PrefetchHooks Function({bool bookId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
}
