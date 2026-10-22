// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $HttpCacheTable extends HttpCache
    with TableInfo<$HttpCacheTable, HttpCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HttpCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parserVerMeta = const VerificationMeta(
    'parserVer',
  );
  @override
  late final GeneratedColumn<int> parserVer = GeneratedColumn<int>(
    'parser_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _softExpiryMeta = const VerificationMeta(
    'softExpiry',
  );
  @override
  late final GeneratedColumn<DateTime> softExpiry = GeneratedColumn<DateTime>(
    'soft_expiry',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hardExpiryMeta = const VerificationMeta(
    'hardExpiry',
  );
  @override
  late final GeneratedColumn<DateTime> hardExpiry = GeneratedColumn<DateTime>(
    'hard_expiry',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<Uint8List> body = GeneratedColumn<Uint8List>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    parserVer,
    etag,
    lastModified,
    fetchedAt,
    softExpiry,
    hardExpiry,
    body,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'http_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<HttpCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('parser_ver')) {
      context.handle(
        _parserVerMeta,
        parserVer.isAcceptableOrUnknown(data['parser_ver']!, _parserVerMeta),
      );
    } else if (isInserting) {
      context.missing(_parserVerMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('soft_expiry')) {
      context.handle(
        _softExpiryMeta,
        softExpiry.isAcceptableOrUnknown(data['soft_expiry']!, _softExpiryMeta),
      );
    } else if (isInserting) {
      context.missing(_softExpiryMeta);
    }
    if (data.containsKey('hard_expiry')) {
      context.handle(
        _hardExpiryMeta,
        hardExpiry.isAcceptableOrUnknown(data['hard_expiry']!, _hardExpiryMeta),
      );
    } else if (isInserting) {
      context.missing(_hardExpiryMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  HttpCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HttpCacheRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      parserVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_ver'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
      softExpiry: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}soft_expiry'],
      )!,
      hardExpiry: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hard_expiry'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $HttpCacheTable createAlias(String alias) {
    return $HttpCacheTable(attachedDatabase, alias);
  }
}

class HttpCacheRow extends DataClass implements Insertable<HttpCacheRow> {
  final String key;
  final int parserVer;
  final String? etag;
  final String? lastModified;
  final DateTime fetchedAt;
  final DateTime softExpiry;
  final DateTime hardExpiry;

  /// gzip.
  final Uint8List body;
  const HttpCacheRow({
    required this.key,
    required this.parserVer,
    this.etag,
    this.lastModified,
    required this.fetchedAt,
    required this.softExpiry,
    required this.hardExpiry,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['parser_ver'] = Variable<int>(parserVer);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<String>(lastModified);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    map['soft_expiry'] = Variable<DateTime>(softExpiry);
    map['hard_expiry'] = Variable<DateTime>(hardExpiry);
    map['body'] = Variable<Uint8List>(body);
    return map;
  }

  HttpCacheCompanion toCompanion(bool nullToAbsent) {
    return HttpCacheCompanion(
      key: Value(key),
      parserVer: Value(parserVer),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      fetchedAt: Value(fetchedAt),
      softExpiry: Value(softExpiry),
      hardExpiry: Value(hardExpiry),
      body: Value(body),
    );
  }

  factory HttpCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HttpCacheRow(
      key: serializer.fromJson<String>(json['key']),
      parserVer: serializer.fromJson<int>(json['parserVer']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
      softExpiry: serializer.fromJson<DateTime>(json['softExpiry']),
      hardExpiry: serializer.fromJson<DateTime>(json['hardExpiry']),
      body: serializer.fromJson<Uint8List>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'parserVer': serializer.toJson<int>(parserVer),
      'etag': serializer.toJson<String?>(etag),
      'lastModified': serializer.toJson<String?>(lastModified),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
      'softExpiry': serializer.toJson<DateTime>(softExpiry),
      'hardExpiry': serializer.toJson<DateTime>(hardExpiry),
      'body': serializer.toJson<Uint8List>(body),
    };
  }

  HttpCacheRow copyWith({
    String? key,
    int? parserVer,
    Value<String?> etag = const Value.absent(),
    Value<String?> lastModified = const Value.absent(),
    DateTime? fetchedAt,
    DateTime? softExpiry,
    DateTime? hardExpiry,
    Uint8List? body,
  }) => HttpCacheRow(
    key: key ?? this.key,
    parserVer: parserVer ?? this.parserVer,
    etag: etag.present ? etag.value : this.etag,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    softExpiry: softExpiry ?? this.softExpiry,
    hardExpiry: hardExpiry ?? this.hardExpiry,
    body: body ?? this.body,
  );
  HttpCacheRow copyWithCompanion(HttpCacheCompanion data) {
    return HttpCacheRow(
      key: data.key.present ? data.key.value : this.key,
      parserVer: data.parserVer.present ? data.parserVer.value : this.parserVer,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      softExpiry: data.softExpiry.present
          ? data.softExpiry.value
          : this.softExpiry,
      hardExpiry: data.hardExpiry.present
          ? data.hardExpiry.value
          : this.hardExpiry,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HttpCacheRow(')
          ..write('key: $key, ')
          ..write('parserVer: $parserVer, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('softExpiry: $softExpiry, ')
          ..write('hardExpiry: $hardExpiry, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    parserVer,
    etag,
    lastModified,
    fetchedAt,
    softExpiry,
    hardExpiry,
    $driftBlobEquality.hash(body),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HttpCacheRow &&
          other.key == this.key &&
          other.parserVer == this.parserVer &&
          other.etag == this.etag &&
          other.lastModified == this.lastModified &&
          other.fetchedAt == this.fetchedAt &&
          other.softExpiry == this.softExpiry &&
          other.hardExpiry == this.hardExpiry &&
          $driftBlobEquality.equals(other.body, this.body));
}

class HttpCacheCompanion extends UpdateCompanion<HttpCacheRow> {
  final Value<String> key;
  final Value<int> parserVer;
  final Value<String?> etag;
  final Value<String?> lastModified;
  final Value<DateTime> fetchedAt;
  final Value<DateTime> softExpiry;
  final Value<DateTime> hardExpiry;
  final Value<Uint8List> body;
  final Value<int> rowid;
  const HttpCacheCompanion({
    this.key = const Value.absent(),
    this.parserVer = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.softExpiry = const Value.absent(),
    this.hardExpiry = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HttpCacheCompanion.insert({
    required String key,
    required int parserVer,
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    required DateTime fetchedAt,
    required DateTime softExpiry,
    required DateTime hardExpiry,
    required Uint8List body,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       parserVer = Value(parserVer),
       fetchedAt = Value(fetchedAt),
       softExpiry = Value(softExpiry),
       hardExpiry = Value(hardExpiry),
       body = Value(body);
  static Insertable<HttpCacheRow> custom({
    Expression<String>? key,
    Expression<int>? parserVer,
    Expression<String>? etag,
    Expression<String>? lastModified,
    Expression<DateTime>? fetchedAt,
    Expression<DateTime>? softExpiry,
    Expression<DateTime>? hardExpiry,
    Expression<Uint8List>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (parserVer != null) 'parser_ver': parserVer,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'last_modified': lastModified,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (softExpiry != null) 'soft_expiry': softExpiry,
      if (hardExpiry != null) 'hard_expiry': hardExpiry,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HttpCacheCompanion copyWith({
    Value<String>? key,
    Value<int>? parserVer,
    Value<String?>? etag,
    Value<String?>? lastModified,
    Value<DateTime>? fetchedAt,
    Value<DateTime>? softExpiry,
    Value<DateTime>? hardExpiry,
    Value<Uint8List>? body,
    Value<int>? rowid,
  }) {
    return HttpCacheCompanion(
      key: key ?? this.key,
      parserVer: parserVer ?? this.parserVer,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      softExpiry: softExpiry ?? this.softExpiry,
      hardExpiry: hardExpiry ?? this.hardExpiry,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (parserVer.present) {
      map['parser_ver'] = Variable<int>(parserVer.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<String>(lastModified.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (softExpiry.present) {
      map['soft_expiry'] = Variable<DateTime>(softExpiry.value);
    }
    if (hardExpiry.present) {
      map['hard_expiry'] = Variable<DateTime>(hardExpiry.value);
    }
    if (body.present) {
      map['body'] = Variable<Uint8List>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HttpCacheCompanion(')
          ..write('key: $key, ')
          ..write('parserVer: $parserVer, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('softExpiry: $softExpiry, ')
          ..write('hardExpiry: $hardExpiry, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PluginReposTable extends PluginRepos
    with TableInfo<$PluginReposTable, PluginRepoRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PluginReposTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<String> keyId = GeneratedColumn<String>(
    'key_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedPubMeta = const VerificationMeta(
    'pinnedPub',
  );
  @override
  late final GeneratedColumn<String> pinnedPub = GeneratedColumn<String>(
    'pinned_pub',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCheckedAtMeta = const VerificationMeta(
    'lastCheckedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCheckedAt =
      GeneratedColumn<DateTime>(
        'last_checked_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    url,
    name,
    keyId,
    pinnedPub,
    etag,
    lastCheckedAt,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plugin_repos';
  @override
  VerificationContext validateIntegrity(
    Insertable<PluginRepoRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_keyIdMeta);
    }
    if (data.containsKey('pinned_pub')) {
      context.handle(
        _pinnedPubMeta,
        pinnedPub.isAcceptableOrUnknown(data['pinned_pub']!, _pinnedPubMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedPubMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('last_checked_at')) {
      context.handle(
        _lastCheckedAtMeta,
        lastCheckedAt.isAcceptableOrUnknown(
          data['last_checked_at']!,
          _lastCheckedAtMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PluginRepoRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PluginRepoRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_id'],
      )!,
      pinnedPub: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pinned_pub'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      lastCheckedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_checked_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $PluginReposTable createAlias(String alias) {
    return $PluginReposTable(attachedDatabase, alias);
  }
}

class PluginRepoRow extends DataClass implements Insertable<PluginRepoRow> {
  /// First 16 hex of sha256(url).
  final String id;
  final String url;
  final String name;
  final String keyId;
  final String pinnedPub;
  final String? etag;
  final DateTime? lastCheckedAt;
  final DateTime addedAt;
  const PluginRepoRow({
    required this.id,
    required this.url,
    required this.name,
    required this.keyId,
    required this.pinnedPub,
    this.etag,
    this.lastCheckedAt,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['url'] = Variable<String>(url);
    map['name'] = Variable<String>(name);
    map['key_id'] = Variable<String>(keyId);
    map['pinned_pub'] = Variable<String>(pinnedPub);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastCheckedAt != null) {
      map['last_checked_at'] = Variable<DateTime>(lastCheckedAt);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  PluginReposCompanion toCompanion(bool nullToAbsent) {
    return PluginReposCompanion(
      id: Value(id),
      url: Value(url),
      name: Value(name),
      keyId: Value(keyId),
      pinnedPub: Value(pinnedPub),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastCheckedAt: lastCheckedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckedAt),
      addedAt: Value(addedAt),
    );
  }

  factory PluginRepoRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PluginRepoRow(
      id: serializer.fromJson<String>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      name: serializer.fromJson<String>(json['name']),
      keyId: serializer.fromJson<String>(json['keyId']),
      pinnedPub: serializer.fromJson<String>(json['pinnedPub']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastCheckedAt: serializer.fromJson<DateTime?>(json['lastCheckedAt']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'url': serializer.toJson<String>(url),
      'name': serializer.toJson<String>(name),
      'keyId': serializer.toJson<String>(keyId),
      'pinnedPub': serializer.toJson<String>(pinnedPub),
      'etag': serializer.toJson<String?>(etag),
      'lastCheckedAt': serializer.toJson<DateTime?>(lastCheckedAt),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  PluginRepoRow copyWith({
    String? id,
    String? url,
    String? name,
    String? keyId,
    String? pinnedPub,
    Value<String?> etag = const Value.absent(),
    Value<DateTime?> lastCheckedAt = const Value.absent(),
    DateTime? addedAt,
  }) => PluginRepoRow(
    id: id ?? this.id,
    url: url ?? this.url,
    name: name ?? this.name,
    keyId: keyId ?? this.keyId,
    pinnedPub: pinnedPub ?? this.pinnedPub,
    etag: etag.present ? etag.value : this.etag,
    lastCheckedAt: lastCheckedAt.present
        ? lastCheckedAt.value
        : this.lastCheckedAt,
    addedAt: addedAt ?? this.addedAt,
  );
  PluginRepoRow copyWithCompanion(PluginReposCompanion data) {
    return PluginRepoRow(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      name: data.name.present ? data.name.value : this.name,
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      pinnedPub: data.pinnedPub.present ? data.pinnedPub.value : this.pinnedPub,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastCheckedAt: data.lastCheckedAt.present
          ? data.lastCheckedAt.value
          : this.lastCheckedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PluginRepoRow(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('keyId: $keyId, ')
          ..write('pinnedPub: $pinnedPub, ')
          ..write('etag: $etag, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    url,
    name,
    keyId,
    pinnedPub,
    etag,
    lastCheckedAt,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginRepoRow &&
          other.id == this.id &&
          other.url == this.url &&
          other.name == this.name &&
          other.keyId == this.keyId &&
          other.pinnedPub == this.pinnedPub &&
          other.etag == this.etag &&
          other.lastCheckedAt == this.lastCheckedAt &&
          other.addedAt == this.addedAt);
}

class PluginReposCompanion extends UpdateCompanion<PluginRepoRow> {
  final Value<String> id;
  final Value<String> url;
  final Value<String> name;
  final Value<String> keyId;
  final Value<String> pinnedPub;
  final Value<String?> etag;
  final Value<DateTime?> lastCheckedAt;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const PluginReposCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.name = const Value.absent(),
    this.keyId = const Value.absent(),
    this.pinnedPub = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PluginReposCompanion.insert({
    required String id,
    required String url,
    required String name,
    required String keyId,
    required String pinnedPub,
    this.etag = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       url = Value(url),
       name = Value(name),
       keyId = Value(keyId),
       pinnedPub = Value(pinnedPub),
       addedAt = Value(addedAt);
  static Insertable<PluginRepoRow> custom({
    Expression<String>? id,
    Expression<String>? url,
    Expression<String>? name,
    Expression<String>? keyId,
    Expression<String>? pinnedPub,
    Expression<String>? etag,
    Expression<DateTime>? lastCheckedAt,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (name != null) 'name': name,
      if (keyId != null) 'key_id': keyId,
      if (pinnedPub != null) 'pinned_pub': pinnedPub,
      if (etag != null) 'etag': etag,
      if (lastCheckedAt != null) 'last_checked_at': lastCheckedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PluginReposCompanion copyWith({
    Value<String>? id,
    Value<String>? url,
    Value<String>? name,
    Value<String>? keyId,
    Value<String>? pinnedPub,
    Value<String?>? etag,
    Value<DateTime?>? lastCheckedAt,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return PluginReposCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      keyId: keyId ?? this.keyId,
      pinnedPub: pinnedPub ?? this.pinnedPub,
      etag: etag ?? this.etag,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (keyId.present) {
      map['key_id'] = Variable<String>(keyId.value);
    }
    if (pinnedPub.present) {
      map['pinned_pub'] = Variable<String>(pinnedPub.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastCheckedAt.present) {
      map['last_checked_at'] = Variable<DateTime>(lastCheckedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PluginReposCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('keyId: $keyId, ')
          ..write('pinnedPub: $pinnedPub, ')
          ..write('etag: $etag, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PluginsTable extends Plugins with TableInfo<$PluginsTable, PluginRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PluginsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repoIdMeta = const VerificationMeta('repoId');
  @override
  late final GeneratedColumn<String> repoId = GeneratedColumn<String>(
    'repo_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _engineIdMeta = const VerificationMeta(
    'engineId',
  );
  @override
  late final GeneratedColumn<String> engineId = GeneratedColumn<String>(
    'engine_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _declaredUrlMeta = const VerificationMeta(
    'declaredUrl',
  );
  @override
  late final GeneratedColumn<String> declaredUrl = GeneratedColumn<String>(
    'declared_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  allowedHosts = GeneratedColumn<String>(
    'allowed_hosts',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<List<String>>($PluginsTable.$converterallowedHosts);
  static const VerificationMeta _signedMeta = const VerificationMeta('signed');
  @override
  late final GeneratedColumn<bool> signed = GeneratedColumn<bool>(
    'signed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("signed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updateShaMeta = const VerificationMeta(
    'updateSha',
  );
  @override
  late final GeneratedColumn<String> updateSha = GeneratedColumn<String>(
    'update_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    repoId,
    engineId,
    name,
    version,
    sha256,
    sourceUrl,
    declaredUrl,
    allowedHosts,
    signed,
    enabled,
    installedAt,
    updatedAt,
    updateSha,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plugins';
  @override
  VerificationContext validateIntegrity(
    Insertable<PluginRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('repo_id')) {
      context.handle(
        _repoIdMeta,
        repoId.isAcceptableOrUnknown(data['repo_id']!, _repoIdMeta),
      );
    }
    if (data.containsKey('engine_id')) {
      context.handle(
        _engineIdMeta,
        engineId.isAcceptableOrUnknown(data['engine_id']!, _engineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_engineIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceUrlMeta);
    }
    if (data.containsKey('declared_url')) {
      context.handle(
        _declaredUrlMeta,
        declaredUrl.isAcceptableOrUnknown(
          data['declared_url']!,
          _declaredUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_declaredUrlMeta);
    }
    if (data.containsKey('signed')) {
      context.handle(
        _signedMeta,
        signed.isAcceptableOrUnknown(data['signed']!, _signedMeta),
      );
    } else if (isInserting) {
      context.missing(_signedMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('update_sha')) {
      context.handle(
        _updateShaMeta,
        updateSha.isAcceptableOrUnknown(data['update_sha']!, _updateShaMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PluginRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PluginRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      repoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repo_id'],
      ),
      engineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      )!,
      declaredUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}declared_url'],
      )!,
      allowedHosts: $PluginsTable.$converterallowedHosts.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}allowed_hosts'],
        )!,
      ),
      signed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}signed'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updateSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}update_sha'],
      ),
    );
  }

  @override
  $PluginsTable createAlias(String alias) {
    return $PluginsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterallowedHosts =
      const StringListConverter();
}

class PluginRow extends DataClass implements Insertable<PluginRow> {
  /// `<repoId|single>:<engineId>`
  final String id;
  final String? repoId;
  final String engineId;
  final String name;
  final String? version;
  final String sha256;
  final String sourceUrl;
  final String declaredUrl;
  final List<String> allowedHosts;
  final bool signed;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;
  final String? updateSha;
  const PluginRow({
    required this.id,
    this.repoId,
    required this.engineId,
    required this.name,
    this.version,
    required this.sha256,
    required this.sourceUrl,
    required this.declaredUrl,
    required this.allowedHosts,
    required this.signed,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
    this.updateSha,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || repoId != null) {
      map['repo_id'] = Variable<String>(repoId);
    }
    map['engine_id'] = Variable<String>(engineId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || version != null) {
      map['version'] = Variable<String>(version);
    }
    map['sha256'] = Variable<String>(sha256);
    map['source_url'] = Variable<String>(sourceUrl);
    map['declared_url'] = Variable<String>(declaredUrl);
    {
      map['allowed_hosts'] = Variable<String>(
        $PluginsTable.$converterallowedHosts.toSql(allowedHosts),
      );
    }
    map['signed'] = Variable<bool>(signed);
    map['enabled'] = Variable<bool>(enabled);
    map['installed_at'] = Variable<DateTime>(installedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || updateSha != null) {
      map['update_sha'] = Variable<String>(updateSha);
    }
    return map;
  }

  PluginsCompanion toCompanion(bool nullToAbsent) {
    return PluginsCompanion(
      id: Value(id),
      repoId: repoId == null && nullToAbsent
          ? const Value.absent()
          : Value(repoId),
      engineId: Value(engineId),
      name: Value(name),
      version: version == null && nullToAbsent
          ? const Value.absent()
          : Value(version),
      sha256: Value(sha256),
      sourceUrl: Value(sourceUrl),
      declaredUrl: Value(declaredUrl),
      allowedHosts: Value(allowedHosts),
      signed: Value(signed),
      enabled: Value(enabled),
      installedAt: Value(installedAt),
      updatedAt: Value(updatedAt),
      updateSha: updateSha == null && nullToAbsent
          ? const Value.absent()
          : Value(updateSha),
    );
  }

  factory PluginRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PluginRow(
      id: serializer.fromJson<String>(json['id']),
      repoId: serializer.fromJson<String?>(json['repoId']),
      engineId: serializer.fromJson<String>(json['engineId']),
      name: serializer.fromJson<String>(json['name']),
      version: serializer.fromJson<String?>(json['version']),
      sha256: serializer.fromJson<String>(json['sha256']),
      sourceUrl: serializer.fromJson<String>(json['sourceUrl']),
      declaredUrl: serializer.fromJson<String>(json['declaredUrl']),
      allowedHosts: serializer.fromJson<List<String>>(json['allowedHosts']),
      signed: serializer.fromJson<bool>(json['signed']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updateSha: serializer.fromJson<String?>(json['updateSha']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'repoId': serializer.toJson<String?>(repoId),
      'engineId': serializer.toJson<String>(engineId),
      'name': serializer.toJson<String>(name),
      'version': serializer.toJson<String?>(version),
      'sha256': serializer.toJson<String>(sha256),
      'sourceUrl': serializer.toJson<String>(sourceUrl),
      'declaredUrl': serializer.toJson<String>(declaredUrl),
      'allowedHosts': serializer.toJson<List<String>>(allowedHosts),
      'signed': serializer.toJson<bool>(signed),
      'enabled': serializer.toJson<bool>(enabled),
      'installedAt': serializer.toJson<DateTime>(installedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updateSha': serializer.toJson<String?>(updateSha),
    };
  }

  PluginRow copyWith({
    String? id,
    Value<String?> repoId = const Value.absent(),
    String? engineId,
    String? name,
    Value<String?> version = const Value.absent(),
    String? sha256,
    String? sourceUrl,
    String? declaredUrl,
    List<String>? allowedHosts,
    bool? signed,
    bool? enabled,
    DateTime? installedAt,
    DateTime? updatedAt,
    Value<String?> updateSha = const Value.absent(),
  }) => PluginRow(
    id: id ?? this.id,
    repoId: repoId.present ? repoId.value : this.repoId,
    engineId: engineId ?? this.engineId,
    name: name ?? this.name,
    version: version.present ? version.value : this.version,
    sha256: sha256 ?? this.sha256,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    declaredUrl: declaredUrl ?? this.declaredUrl,
    allowedHosts: allowedHosts ?? this.allowedHosts,
    signed: signed ?? this.signed,
    enabled: enabled ?? this.enabled,
    installedAt: installedAt ?? this.installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updateSha: updateSha.present ? updateSha.value : this.updateSha,
  );
  PluginRow copyWithCompanion(PluginsCompanion data) {
    return PluginRow(
      id: data.id.present ? data.id.value : this.id,
      repoId: data.repoId.present ? data.repoId.value : this.repoId,
      engineId: data.engineId.present ? data.engineId.value : this.engineId,
      name: data.name.present ? data.name.value : this.name,
      version: data.version.present ? data.version.value : this.version,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      declaredUrl: data.declaredUrl.present
          ? data.declaredUrl.value
          : this.declaredUrl,
      allowedHosts: data.allowedHosts.present
          ? data.allowedHosts.value
          : this.allowedHosts,
      signed: data.signed.present ? data.signed.value : this.signed,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updateSha: data.updateSha.present ? data.updateSha.value : this.updateSha,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PluginRow(')
          ..write('id: $id, ')
          ..write('repoId: $repoId, ')
          ..write('engineId: $engineId, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('sha256: $sha256, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('declaredUrl: $declaredUrl, ')
          ..write('allowedHosts: $allowedHosts, ')
          ..write('signed: $signed, ')
          ..write('enabled: $enabled, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateSha: $updateSha')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    repoId,
    engineId,
    name,
    version,
    sha256,
    sourceUrl,
    declaredUrl,
    allowedHosts,
    signed,
    enabled,
    installedAt,
    updatedAt,
    updateSha,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginRow &&
          other.id == this.id &&
          other.repoId == this.repoId &&
          other.engineId == this.engineId &&
          other.name == this.name &&
          other.version == this.version &&
          other.sha256 == this.sha256 &&
          other.sourceUrl == this.sourceUrl &&
          other.declaredUrl == this.declaredUrl &&
          other.allowedHosts == this.allowedHosts &&
          other.signed == this.signed &&
          other.enabled == this.enabled &&
          other.installedAt == this.installedAt &&
          other.updatedAt == this.updatedAt &&
          other.updateSha == this.updateSha);
}

class PluginsCompanion extends UpdateCompanion<PluginRow> {
  final Value<String> id;
  final Value<String?> repoId;
  final Value<String> engineId;
  final Value<String> name;
  final Value<String?> version;
  final Value<String> sha256;
  final Value<String> sourceUrl;
  final Value<String> declaredUrl;
  final Value<List<String>> allowedHosts;
  final Value<bool> signed;
  final Value<bool> enabled;
  final Value<DateTime> installedAt;
  final Value<DateTime> updatedAt;
  final Value<String?> updateSha;
  final Value<int> rowid;
  const PluginsCompanion({
    this.id = const Value.absent(),
    this.repoId = const Value.absent(),
    this.engineId = const Value.absent(),
    this.name = const Value.absent(),
    this.version = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.declaredUrl = const Value.absent(),
    this.allowedHosts = const Value.absent(),
    this.signed = const Value.absent(),
    this.enabled = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updateSha = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PluginsCompanion.insert({
    required String id,
    this.repoId = const Value.absent(),
    required String engineId,
    required String name,
    this.version = const Value.absent(),
    required String sha256,
    required String sourceUrl,
    required String declaredUrl,
    required List<String> allowedHosts,
    required bool signed,
    this.enabled = const Value.absent(),
    required DateTime installedAt,
    required DateTime updatedAt,
    this.updateSha = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       engineId = Value(engineId),
       name = Value(name),
       sha256 = Value(sha256),
       sourceUrl = Value(sourceUrl),
       declaredUrl = Value(declaredUrl),
       allowedHosts = Value(allowedHosts),
       signed = Value(signed),
       installedAt = Value(installedAt),
       updatedAt = Value(updatedAt);
  static Insertable<PluginRow> custom({
    Expression<String>? id,
    Expression<String>? repoId,
    Expression<String>? engineId,
    Expression<String>? name,
    Expression<String>? version,
    Expression<String>? sha256,
    Expression<String>? sourceUrl,
    Expression<String>? declaredUrl,
    Expression<String>? allowedHosts,
    Expression<bool>? signed,
    Expression<bool>? enabled,
    Expression<DateTime>? installedAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? updateSha,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (repoId != null) 'repo_id': repoId,
      if (engineId != null) 'engine_id': engineId,
      if (name != null) 'name': name,
      if (version != null) 'version': version,
      if (sha256 != null) 'sha256': sha256,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (declaredUrl != null) 'declared_url': declaredUrl,
      if (allowedHosts != null) 'allowed_hosts': allowedHosts,
      if (signed != null) 'signed': signed,
      if (enabled != null) 'enabled': enabled,
      if (installedAt != null) 'installed_at': installedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updateSha != null) 'update_sha': updateSha,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PluginsCompanion copyWith({
    Value<String>? id,
    Value<String?>? repoId,
    Value<String>? engineId,
    Value<String>? name,
    Value<String?>? version,
    Value<String>? sha256,
    Value<String>? sourceUrl,
    Value<String>? declaredUrl,
    Value<List<String>>? allowedHosts,
    Value<bool>? signed,
    Value<bool>? enabled,
    Value<DateTime>? installedAt,
    Value<DateTime>? updatedAt,
    Value<String?>? updateSha,
    Value<int>? rowid,
  }) {
    return PluginsCompanion(
      id: id ?? this.id,
      repoId: repoId ?? this.repoId,
      engineId: engineId ?? this.engineId,
      name: name ?? this.name,
      version: version ?? this.version,
      sha256: sha256 ?? this.sha256,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      declaredUrl: declaredUrl ?? this.declaredUrl,
      allowedHosts: allowedHosts ?? this.allowedHosts,
      signed: signed ?? this.signed,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updateSha: updateSha ?? this.updateSha,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (repoId.present) {
      map['repo_id'] = Variable<String>(repoId.value);
    }
    if (engineId.present) {
      map['engine_id'] = Variable<String>(engineId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (declaredUrl.present) {
      map['declared_url'] = Variable<String>(declaredUrl.value);
    }
    if (allowedHosts.present) {
      map['allowed_hosts'] = Variable<String>(
        $PluginsTable.$converterallowedHosts.toSql(allowedHosts.value),
      );
    }
    if (signed.present) {
      map['signed'] = Variable<bool>(signed.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updateSha.present) {
      map['update_sha'] = Variable<String>(updateSha.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PluginsCompanion(')
          ..write('id: $id, ')
          ..write('repoId: $repoId, ')
          ..write('engineId: $engineId, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('sha256: $sha256, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('declaredUrl: $declaredUrl, ')
          ..write('allowedHosts: $allowedHosts, ')
          ..write('signed: $signed, ')
          ..write('enabled: $enabled, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updateSha: $updateSha, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TorznabEndpointsTable extends TorznabEndpoints
    with TableInfo<$TorznabEndpointsTable, TorznabEndpointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TorznabEndpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, Object?>?, String>
  caps =
      GeneratedColumn<String>(
        'caps',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Map<String, Object?>?>(
        $TorznabEndpointsTable.$convertercapsn,
      );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _capsAtMeta = const VerificationMeta('capsAt');
  @override
  late final GeneratedColumn<DateTime> capsAt = GeneratedColumn<DateTime>(
    'caps_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    baseUrl,
    caps,
    enabled,
    capsAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'torznab_endpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<TorznabEndpointRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('caps_at')) {
      context.handle(
        _capsAtMeta,
        capsAt.isAcceptableOrUnknown(data['caps_at']!, _capsAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TorznabEndpointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TorznabEndpointRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      caps: $TorznabEndpointsTable.$convertercapsn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}caps'],
        ),
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      capsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}caps_at'],
      ),
    );
  }

  @override
  $TorznabEndpointsTable createAlias(String alias) {
    return $TorznabEndpointsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, Object?>, String> $convertercaps =
      const JsonMapConverter();
  static TypeConverter<Map<String, Object?>?, String?> $convertercapsn =
      NullAwareTypeConverter.wrap($convertercaps);
}

class TorznabEndpointRow extends DataClass
    implements Insertable<TorznabEndpointRow> {
  final String id;
  final String name;
  final String baseUrl;
  final Map<String, Object?>? caps;
  final bool enabled;
  final DateTime? capsAt;
  const TorznabEndpointRow({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.caps,
    required this.enabled,
    this.capsAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['base_url'] = Variable<String>(baseUrl);
    if (!nullToAbsent || caps != null) {
      map['caps'] = Variable<String>(
        $TorznabEndpointsTable.$convertercapsn.toSql(caps),
      );
    }
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || capsAt != null) {
      map['caps_at'] = Variable<DateTime>(capsAt);
    }
    return map;
  }

  TorznabEndpointsCompanion toCompanion(bool nullToAbsent) {
    return TorznabEndpointsCompanion(
      id: Value(id),
      name: Value(name),
      baseUrl: Value(baseUrl),
      caps: caps == null && nullToAbsent ? const Value.absent() : Value(caps),
      enabled: Value(enabled),
      capsAt: capsAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capsAt),
    );
  }

  factory TorznabEndpointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TorznabEndpointRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      caps: serializer.fromJson<Map<String, Object?>?>(json['caps']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      capsAt: serializer.fromJson<DateTime?>(json['capsAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'caps': serializer.toJson<Map<String, Object?>?>(caps),
      'enabled': serializer.toJson<bool>(enabled),
      'capsAt': serializer.toJson<DateTime?>(capsAt),
    };
  }

  TorznabEndpointRow copyWith({
    String? id,
    String? name,
    String? baseUrl,
    Value<Map<String, Object?>?> caps = const Value.absent(),
    bool? enabled,
    Value<DateTime?> capsAt = const Value.absent(),
  }) => TorznabEndpointRow(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    caps: caps.present ? caps.value : this.caps,
    enabled: enabled ?? this.enabled,
    capsAt: capsAt.present ? capsAt.value : this.capsAt,
  );
  TorznabEndpointRow copyWithCompanion(TorznabEndpointsCompanion data) {
    return TorznabEndpointRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      caps: data.caps.present ? data.caps.value : this.caps,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      capsAt: data.capsAt.present ? data.capsAt.value : this.capsAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TorznabEndpointRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('caps: $caps, ')
          ..write('enabled: $enabled, ')
          ..write('capsAt: $capsAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, baseUrl, caps, enabled, capsAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TorznabEndpointRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.baseUrl == this.baseUrl &&
          other.caps == this.caps &&
          other.enabled == this.enabled &&
          other.capsAt == this.capsAt);
}

class TorznabEndpointsCompanion extends UpdateCompanion<TorznabEndpointRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> baseUrl;
  final Value<Map<String, Object?>?> caps;
  final Value<bool> enabled;
  final Value<DateTime?> capsAt;
  final Value<int> rowid;
  const TorznabEndpointsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.caps = const Value.absent(),
    this.enabled = const Value.absent(),
    this.capsAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TorznabEndpointsCompanion.insert({
    required String id,
    required String name,
    required String baseUrl,
    this.caps = const Value.absent(),
    this.enabled = const Value.absent(),
    this.capsAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       baseUrl = Value(baseUrl);
  static Insertable<TorznabEndpointRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? baseUrl,
    Expression<String>? caps,
    Expression<bool>? enabled,
    Expression<DateTime>? capsAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (baseUrl != null) 'base_url': baseUrl,
      if (caps != null) 'caps': caps,
      if (enabled != null) 'enabled': enabled,
      if (capsAt != null) 'caps_at': capsAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TorznabEndpointsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? baseUrl,
    Value<Map<String, Object?>?>? caps,
    Value<bool>? enabled,
    Value<DateTime?>? capsAt,
    Value<int>? rowid,
  }) {
    return TorznabEndpointsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      caps: caps ?? this.caps,
      enabled: enabled ?? this.enabled,
      capsAt: capsAt ?? this.capsAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (caps.present) {
      map['caps'] = Variable<String>(
        $TorznabEndpointsTable.$convertercapsn.toSql(caps.value),
      );
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (capsAt.present) {
      map['caps_at'] = Variable<DateTime>(capsAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TorznabEndpointsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('caps: $caps, ')
          ..write('enabled: $enabled, ')
          ..write('capsAt: $capsAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderRunsTable extends ProviderRuns
    with TableInfo<$ProviderRunsTable, ProviderRunRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _msMeta = const VerificationMeta('ms');
  @override
  late final GeneratedColumn<int> ms = GeneratedColumn<int>(
    'ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultsMeta = const VerificationMeta(
    'results',
  );
  @override
  late final GeneratedColumn<int> results = GeneratedColumn<int>(
    'results',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestsMeta = const VerificationMeta(
    'requests',
  );
  @override
  late final GeneratedColumn<int> requests = GeneratedColumn<int>(
    'requests',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  blockedHosts = GeneratedColumn<String>(
    'blocked_hosts',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<List<String>>($ProviderRunsTable.$converterblockedHosts);
  @override
  List<GeneratedColumn> get $columns => [
    providerId,
    at,
    status,
    reason,
    ms,
    results,
    requests,
    blockedHosts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderRunRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('ms')) {
      context.handle(_msMeta, ms.isAcceptableOrUnknown(data['ms']!, _msMeta));
    } else if (isInserting) {
      context.missing(_msMeta);
    }
    if (data.containsKey('results')) {
      context.handle(
        _resultsMeta,
        results.isAcceptableOrUnknown(data['results']!, _resultsMeta),
      );
    } else if (isInserting) {
      context.missing(_resultsMeta);
    }
    if (data.containsKey('requests')) {
      context.handle(
        _requestsMeta,
        requests.isAcceptableOrUnknown(data['requests']!, _requestsMeta),
      );
    } else if (isInserting) {
      context.missing(_requestsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  ProviderRunRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderRunRow(
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      ms: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ms'],
      )!,
      results: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}results'],
      )!,
      requests: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}requests'],
      )!,
      blockedHosts: $ProviderRunsTable.$converterblockedHosts.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}blocked_hosts'],
        )!,
      ),
    );
  }

  @override
  $ProviderRunsTable createAlias(String alias) {
    return $ProviderRunsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterblockedHosts =
      const StringListConverter();
}

class ProviderRunRow extends DataClass implements Insertable<ProviderRunRow> {
  final String providerId;
  final DateTime at;
  final String status;
  final String? reason;
  final int ms;
  final int results;
  final int requests;
  final List<String> blockedHosts;
  const ProviderRunRow({
    required this.providerId,
    required this.at,
    required this.status,
    this.reason,
    required this.ms,
    required this.results,
    required this.requests,
    required this.blockedHosts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider_id'] = Variable<String>(providerId);
    map['at'] = Variable<DateTime>(at);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['ms'] = Variable<int>(ms);
    map['results'] = Variable<int>(results);
    map['requests'] = Variable<int>(requests);
    {
      map['blocked_hosts'] = Variable<String>(
        $ProviderRunsTable.$converterblockedHosts.toSql(blockedHosts),
      );
    }
    return map;
  }

  ProviderRunsCompanion toCompanion(bool nullToAbsent) {
    return ProviderRunsCompanion(
      providerId: Value(providerId),
      at: Value(at),
      status: Value(status),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      ms: Value(ms),
      results: Value(results),
      requests: Value(requests),
      blockedHosts: Value(blockedHosts),
    );
  }

  factory ProviderRunRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderRunRow(
      providerId: serializer.fromJson<String>(json['providerId']),
      at: serializer.fromJson<DateTime>(json['at']),
      status: serializer.fromJson<String>(json['status']),
      reason: serializer.fromJson<String?>(json['reason']),
      ms: serializer.fromJson<int>(json['ms']),
      results: serializer.fromJson<int>(json['results']),
      requests: serializer.fromJson<int>(json['requests']),
      blockedHosts: serializer.fromJson<List<String>>(json['blockedHosts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'providerId': serializer.toJson<String>(providerId),
      'at': serializer.toJson<DateTime>(at),
      'status': serializer.toJson<String>(status),
      'reason': serializer.toJson<String?>(reason),
      'ms': serializer.toJson<int>(ms),
      'results': serializer.toJson<int>(results),
      'requests': serializer.toJson<int>(requests),
      'blockedHosts': serializer.toJson<List<String>>(blockedHosts),
    };
  }

  ProviderRunRow copyWith({
    String? providerId,
    DateTime? at,
    String? status,
    Value<String?> reason = const Value.absent(),
    int? ms,
    int? results,
    int? requests,
    List<String>? blockedHosts,
  }) => ProviderRunRow(
    providerId: providerId ?? this.providerId,
    at: at ?? this.at,
    status: status ?? this.status,
    reason: reason.present ? reason.value : this.reason,
    ms: ms ?? this.ms,
    results: results ?? this.results,
    requests: requests ?? this.requests,
    blockedHosts: blockedHosts ?? this.blockedHosts,
  );
  ProviderRunRow copyWithCompanion(ProviderRunsCompanion data) {
    return ProviderRunRow(
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      at: data.at.present ? data.at.value : this.at,
      status: data.status.present ? data.status.value : this.status,
      reason: data.reason.present ? data.reason.value : this.reason,
      ms: data.ms.present ? data.ms.value : this.ms,
      results: data.results.present ? data.results.value : this.results,
      requests: data.requests.present ? data.requests.value : this.requests,
      blockedHosts: data.blockedHosts.present
          ? data.blockedHosts.value
          : this.blockedHosts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderRunRow(')
          ..write('providerId: $providerId, ')
          ..write('at: $at, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('ms: $ms, ')
          ..write('results: $results, ')
          ..write('requests: $requests, ')
          ..write('blockedHosts: $blockedHosts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    at,
    status,
    reason,
    ms,
    results,
    requests,
    blockedHosts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderRunRow &&
          other.providerId == this.providerId &&
          other.at == this.at &&
          other.status == this.status &&
          other.reason == this.reason &&
          other.ms == this.ms &&
          other.results == this.results &&
          other.requests == this.requests &&
          other.blockedHosts == this.blockedHosts);
}

class ProviderRunsCompanion extends UpdateCompanion<ProviderRunRow> {
  final Value<String> providerId;
  final Value<DateTime> at;
  final Value<String> status;
  final Value<String?> reason;
  final Value<int> ms;
  final Value<int> results;
  final Value<int> requests;
  final Value<List<String>> blockedHosts;
  final Value<int> rowid;
  const ProviderRunsCompanion({
    this.providerId = const Value.absent(),
    this.at = const Value.absent(),
    this.status = const Value.absent(),
    this.reason = const Value.absent(),
    this.ms = const Value.absent(),
    this.results = const Value.absent(),
    this.requests = const Value.absent(),
    this.blockedHosts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderRunsCompanion.insert({
    required String providerId,
    required DateTime at,
    required String status,
    this.reason = const Value.absent(),
    required int ms,
    required int results,
    required int requests,
    required List<String> blockedHosts,
    this.rowid = const Value.absent(),
  }) : providerId = Value(providerId),
       at = Value(at),
       status = Value(status),
       ms = Value(ms),
       results = Value(results),
       requests = Value(requests),
       blockedHosts = Value(blockedHosts);
  static Insertable<ProviderRunRow> custom({
    Expression<String>? providerId,
    Expression<DateTime>? at,
    Expression<String>? status,
    Expression<String>? reason,
    Expression<int>? ms,
    Expression<int>? results,
    Expression<int>? requests,
    Expression<String>? blockedHosts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (providerId != null) 'provider_id': providerId,
      if (at != null) 'at': at,
      if (status != null) 'status': status,
      if (reason != null) 'reason': reason,
      if (ms != null) 'ms': ms,
      if (results != null) 'results': results,
      if (requests != null) 'requests': requests,
      if (blockedHosts != null) 'blocked_hosts': blockedHosts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderRunsCompanion copyWith({
    Value<String>? providerId,
    Value<DateTime>? at,
    Value<String>? status,
    Value<String?>? reason,
    Value<int>? ms,
    Value<int>? results,
    Value<int>? requests,
    Value<List<String>>? blockedHosts,
    Value<int>? rowid,
  }) {
    return ProviderRunsCompanion(
      providerId: providerId ?? this.providerId,
      at: at ?? this.at,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      ms: ms ?? this.ms,
      results: results ?? this.results,
      requests: requests ?? this.requests,
      blockedHosts: blockedHosts ?? this.blockedHosts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (ms.present) {
      map['ms'] = Variable<int>(ms.value);
    }
    if (results.present) {
      map['results'] = Variable<int>(results.value);
    }
    if (requests.present) {
      map['requests'] = Variable<int>(requests.value);
    }
    if (blockedHosts.present) {
      map['blocked_hosts'] = Variable<String>(
        $ProviderRunsTable.$converterblockedHosts.toSql(blockedHosts.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderRunsCompanion(')
          ..write('providerId: $providerId, ')
          ..write('at: $at, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('ms: $ms, ')
          ..write('results: $results, ')
          ..write('requests: $requests, ')
          ..write('blockedHosts: $blockedHosts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $HttpCacheTable httpCache = $HttpCacheTable(this);
  late final $PluginReposTable pluginRepos = $PluginReposTable(this);
  late final $PluginsTable plugins = $PluginsTable(this);
  late final $TorznabEndpointsTable torznabEndpoints = $TorznabEndpointsTable(
    this,
  );
  late final $ProviderRunsTable providerRuns = $ProviderRunsTable(this);
  late final Index httpCacheHardExpiry = Index(
    'http_cache_hard_expiry',
    'CREATE INDEX http_cache_hard_expiry ON http_cache (hard_expiry)',
  );
  late final Index providerRunsByProvider = Index(
    'provider_runs_by_provider',
    'CREATE INDEX provider_runs_by_provider ON provider_runs (provider_id, at)',
  );
  late final CacheDao cacheDao = CacheDao(this as AppDatabase);
  late final PluginDao pluginDao = PluginDao(this as AppDatabase);
  late final TorznabDao torznabDao = TorznabDao(this as AppDatabase);
  late final RunsDao runsDao = RunsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    httpCache,
    pluginRepos,
    plugins,
    torznabEndpoints,
    providerRuns,
    httpCacheHardExpiry,
    providerRunsByProvider,
  ];
}

typedef $$HttpCacheTableCreateCompanionBuilder = HttpCacheCompanion Function({
  required String key,
  required int parserVer,
  Value<String?> etag,
  Value<String?> lastModified,
  required DateTime fetchedAt,
  required DateTime softExpiry,
  required DateTime hardExpiry,
  required Uint8List body,
  Value<int> rowid,
});
typedef $$HttpCacheTableUpdateCompanionBuilder = HttpCacheCompanion Function({
  Value<String> key,
  Value<int> parserVer,
  Value<String?> etag,
  Value<String?> lastModified,
  Value<DateTime> fetchedAt,
  Value<DateTime> softExpiry,
  Value<DateTime> hardExpiry,
  Value<Uint8List> body,
  Value<int> rowid,
});

class $$HttpCacheTableFilterComposer
    extends Composer<_$AppDatabase, $HttpCacheTable> {
  $$HttpCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVer => $composableBuilder(
    column: $table.parserVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get softExpiry => $composableBuilder(
    column: $table.softExpiry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get hardExpiry => $composableBuilder(
    column: $table.hardExpiry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HttpCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $HttpCacheTable> {
  $$HttpCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVer => $composableBuilder(
    column: $table.parserVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get softExpiry => $composableBuilder(
    column: $table.softExpiry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get hardExpiry => $composableBuilder(
    column: $table.hardExpiry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HttpCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $HttpCacheTable> {
  $$HttpCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get parserVer =>
      $composableBuilder(column: $table.parserVer, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get softExpiry => $composableBuilder(
    column: $table.softExpiry,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get hardExpiry => $composableBuilder(
    column: $table.hardExpiry,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$HttpCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HttpCacheTable,
          HttpCacheRow,
          $$HttpCacheTableFilterComposer,
          $$HttpCacheTableOrderingComposer,
          $$HttpCacheTableAnnotationComposer,
          $$HttpCacheTableCreateCompanionBuilder,
          $$HttpCacheTableUpdateCompanionBuilder,
          (
            HttpCacheRow,
            BaseReferences<_$AppDatabase, $HttpCacheTable, HttpCacheRow>,
          ),
          HttpCacheRow,
          PrefetchHooks Function()
        > {
  $$HttpCacheTableTableManager(_$AppDatabase db, $HttpCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HttpCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HttpCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HttpCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<int> parserVer = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<DateTime> softExpiry = const Value.absent(),
                Value<DateTime> hardExpiry = const Value.absent(),
                Value<Uint8List> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HttpCacheCompanion(
                key: key,
                parserVer: parserVer,
                etag: etag,
                lastModified: lastModified,
                fetchedAt: fetchedAt,
                softExpiry: softExpiry,
                hardExpiry: hardExpiry,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required int parserVer,
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                required DateTime fetchedAt,
                required DateTime softExpiry,
                required DateTime hardExpiry,
                required Uint8List body,
                Value<int> rowid = const Value.absent(),
              }) => HttpCacheCompanion.insert(
                key: key,
                parserVer: parserVer,
                etag: etag,
                lastModified: lastModified,
                fetchedAt: fetchedAt,
                softExpiry: softExpiry,
                hardExpiry: hardExpiry,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HttpCacheTable, HttpCacheRow>(table),
                  BaseReferences<_$AppDatabase, $HttpCacheTable, HttpCacheRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HttpCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HttpCacheTable,
      HttpCacheRow,
      $$HttpCacheTableFilterComposer,
      $$HttpCacheTableOrderingComposer,
      $$HttpCacheTableAnnotationComposer,
      $$HttpCacheTableCreateCompanionBuilder,
      $$HttpCacheTableUpdateCompanionBuilder,
      (
        HttpCacheRow,
        BaseReferences<_$AppDatabase, $HttpCacheTable, HttpCacheRow>,
      ),
      HttpCacheRow,
      PrefetchHooks Function()
    >;
typedef $$PluginReposTableCreateCompanionBuilder =
    PluginReposCompanion Function({
      required String id,
      required String url,
      required String name,
      required String keyId,
      required String pinnedPub,
      Value<String?> etag,
      Value<DateTime?> lastCheckedAt,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$PluginReposTableUpdateCompanionBuilder =
    PluginReposCompanion Function({
      Value<String> id,
      Value<String> url,
      Value<String> name,
      Value<String> keyId,
      Value<String> pinnedPub,
      Value<String?> etag,
      Value<DateTime?> lastCheckedAt,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$PluginReposTableFilterComposer
    extends Composer<_$AppDatabase, $PluginReposTable> {
  $$PluginReposTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinnedPub => $composableBuilder(
    column: $table.pinnedPub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PluginReposTableOrderingComposer
    extends Composer<_$AppDatabase, $PluginReposTable> {
  $$PluginReposTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinnedPub => $composableBuilder(
    column: $table.pinnedPub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PluginReposTableAnnotationComposer
    extends Composer<_$AppDatabase, $PluginReposTable> {
  $$PluginReposTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<String> get pinnedPub =>
      $composableBuilder(column: $table.pinnedPub, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$PluginReposTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PluginReposTable,
          PluginRepoRow,
          $$PluginReposTableFilterComposer,
          $$PluginReposTableOrderingComposer,
          $$PluginReposTableAnnotationComposer,
          $$PluginReposTableCreateCompanionBuilder,
          $$PluginReposTableUpdateCompanionBuilder,
          (
            PluginRepoRow,
            BaseReferences<_$AppDatabase, $PluginReposTable, PluginRepoRow>,
          ),
          PluginRepoRow,
          PrefetchHooks Function()
        > {
  $$PluginReposTableTableManager(_$AppDatabase db, $PluginReposTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PluginReposTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PluginReposTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PluginReposTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> keyId = const Value.absent(),
                Value<String> pinnedPub = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<DateTime?> lastCheckedAt = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PluginReposCompanion(
                id: id,
                url: url,
                name: name,
                keyId: keyId,
                pinnedPub: pinnedPub,
                etag: etag,
                lastCheckedAt: lastCheckedAt,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String url,
                required String name,
                required String keyId,
                required String pinnedPub,
                Value<String?> etag = const Value.absent(),
                Value<DateTime?> lastCheckedAt = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => PluginReposCompanion.insert(
                id: id,
                url: url,
                name: name,
                keyId: keyId,
                pinnedPub: pinnedPub,
                etag: etag,
                lastCheckedAt: lastCheckedAt,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PluginReposTable, PluginRepoRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PluginReposTable,
                    PluginRepoRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PluginReposTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PluginReposTable,
      PluginRepoRow,
      $$PluginReposTableFilterComposer,
      $$PluginReposTableOrderingComposer,
      $$PluginReposTableAnnotationComposer,
      $$PluginReposTableCreateCompanionBuilder,
      $$PluginReposTableUpdateCompanionBuilder,
      (
        PluginRepoRow,
        BaseReferences<_$AppDatabase, $PluginReposTable, PluginRepoRow>,
      ),
      PluginRepoRow,
      PrefetchHooks Function()
    >;
typedef $$PluginsTableCreateCompanionBuilder = PluginsCompanion Function({
  required String id,
  Value<String?> repoId,
  required String engineId,
  required String name,
  Value<String?> version,
  required String sha256,
  required String sourceUrl,
  required String declaredUrl,
  required List<String> allowedHosts,
  required bool signed,
  Value<bool> enabled,
  required DateTime installedAt,
  required DateTime updatedAt,
  Value<String?> updateSha,
  Value<int> rowid,
});
typedef $$PluginsTableUpdateCompanionBuilder = PluginsCompanion Function({
  Value<String> id,
  Value<String?> repoId,
  Value<String> engineId,
  Value<String> name,
  Value<String?> version,
  Value<String> sha256,
  Value<String> sourceUrl,
  Value<String> declaredUrl,
  Value<List<String>> allowedHosts,
  Value<bool> signed,
  Value<bool> enabled,
  Value<DateTime> installedAt,
  Value<DateTime> updatedAt,
  Value<String?> updateSha,
  Value<int> rowid,
});

class $$PluginsTableFilterComposer
    extends Composer<_$AppDatabase, $PluginsTable> {
  $$PluginsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repoId => $composableBuilder(
    column: $table.repoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engineId => $composableBuilder(
    column: $table.engineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declaredUrl => $composableBuilder(
    column: $table.declaredUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get allowedHosts => $composableBuilder(
    column: $table.allowedHosts,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get signed => $composableBuilder(
    column: $table.signed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updateSha => $composableBuilder(
    column: $table.updateSha,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PluginsTableOrderingComposer
    extends Composer<_$AppDatabase, $PluginsTable> {
  $$PluginsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repoId => $composableBuilder(
    column: $table.repoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engineId => $composableBuilder(
    column: $table.engineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declaredUrl => $composableBuilder(
    column: $table.declaredUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get allowedHosts => $composableBuilder(
    column: $table.allowedHosts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get signed => $composableBuilder(
    column: $table.signed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updateSha => $composableBuilder(
    column: $table.updateSha,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PluginsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PluginsTable> {
  $$PluginsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get repoId =>
      $composableBuilder(column: $table.repoId, builder: (column) => column);

  GeneratedColumn<String> get engineId =>
      $composableBuilder(column: $table.engineId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<String> get declaredUrl => $composableBuilder(
    column: $table.declaredUrl,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get allowedHosts =>
      $composableBuilder(
        column: $table.allowedHosts,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get signed =>
      $composableBuilder(column: $table.signed, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updateSha =>
      $composableBuilder(column: $table.updateSha, builder: (column) => column);
}

class $$PluginsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PluginsTable,
          PluginRow,
          $$PluginsTableFilterComposer,
          $$PluginsTableOrderingComposer,
          $$PluginsTableAnnotationComposer,
          $$PluginsTableCreateCompanionBuilder,
          $$PluginsTableUpdateCompanionBuilder,
          (PluginRow, BaseReferences<_$AppDatabase, $PluginsTable, PluginRow>),
          PluginRow,
          PrefetchHooks Function()
        > {
  $$PluginsTableTableManager(_$AppDatabase db, $PluginsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PluginsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PluginsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PluginsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> repoId = const Value.absent(),
                Value<String> engineId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> version = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> sourceUrl = const Value.absent(),
                Value<String> declaredUrl = const Value.absent(),
                Value<List<String>> allowedHosts = const Value.absent(),
                Value<bool> signed = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> updateSha = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PluginsCompanion(
                id: id,
                repoId: repoId,
                engineId: engineId,
                name: name,
                version: version,
                sha256: sha256,
                sourceUrl: sourceUrl,
                declaredUrl: declaredUrl,
                allowedHosts: allowedHosts,
                signed: signed,
                enabled: enabled,
                installedAt: installedAt,
                updatedAt: updatedAt,
                updateSha: updateSha,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> repoId = const Value.absent(),
                required String engineId,
                required String name,
                Value<String?> version = const Value.absent(),
                required String sha256,
                required String sourceUrl,
                required String declaredUrl,
                required List<String> allowedHosts,
                required bool signed,
                Value<bool> enabled = const Value.absent(),
                required DateTime installedAt,
                required DateTime updatedAt,
                Value<String?> updateSha = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PluginsCompanion.insert(
                id: id,
                repoId: repoId,
                engineId: engineId,
                name: name,
                version: version,
                sha256: sha256,
                sourceUrl: sourceUrl,
                declaredUrl: declaredUrl,
                allowedHosts: allowedHosts,
                signed: signed,
                enabled: enabled,
                installedAt: installedAt,
                updatedAt: updatedAt,
                updateSha: updateSha,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PluginsTable, PluginRow>(table),
                  BaseReferences<_$AppDatabase, $PluginsTable, PluginRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PluginsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PluginsTable,
      PluginRow,
      $$PluginsTableFilterComposer,
      $$PluginsTableOrderingComposer,
      $$PluginsTableAnnotationComposer,
      $$PluginsTableCreateCompanionBuilder,
      $$PluginsTableUpdateCompanionBuilder,
      (PluginRow, BaseReferences<_$AppDatabase, $PluginsTable, PluginRow>),
      PluginRow,
      PrefetchHooks Function()
    >;
typedef $$TorznabEndpointsTableCreateCompanionBuilder =
    TorznabEndpointsCompanion Function({
      required String id,
      required String name,
      required String baseUrl,
      Value<Map<String, Object?>?> caps,
      Value<bool> enabled,
      Value<DateTime?> capsAt,
      Value<int> rowid,
    });
typedef $$TorznabEndpointsTableUpdateCompanionBuilder =
    TorznabEndpointsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> baseUrl,
      Value<Map<String, Object?>?> caps,
      Value<bool> enabled,
      Value<DateTime?> capsAt,
      Value<int> rowid,
    });

class $$TorznabEndpointsTableFilterComposer
    extends Composer<_$AppDatabase, $TorznabEndpointsTable> {
  $$TorznabEndpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, Object?>?,
    Map<String, Object>?,
    String
  >
  get caps => $composableBuilder(
    column: $table.caps,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capsAt => $composableBuilder(
    column: $table.capsAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TorznabEndpointsTableOrderingComposer
    extends Composer<_$AppDatabase, $TorznabEndpointsTable> {
  $$TorznabEndpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caps => $composableBuilder(
    column: $table.caps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capsAt => $composableBuilder(
    column: $table.capsAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TorznabEndpointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TorznabEndpointsTable> {
  $$TorznabEndpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, Object?>?, String> get caps =>
      $composableBuilder(column: $table.caps, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get capsAt =>
      $composableBuilder(column: $table.capsAt, builder: (column) => column);
}

class $$TorznabEndpointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TorznabEndpointsTable,
          TorznabEndpointRow,
          $$TorznabEndpointsTableFilterComposer,
          $$TorznabEndpointsTableOrderingComposer,
          $$TorznabEndpointsTableAnnotationComposer,
          $$TorznabEndpointsTableCreateCompanionBuilder,
          $$TorznabEndpointsTableUpdateCompanionBuilder,
          (
            TorznabEndpointRow,
            BaseReferences<
              _$AppDatabase,
              $TorznabEndpointsTable,
              TorznabEndpointRow
            >,
          ),
          TorznabEndpointRow,
          PrefetchHooks Function()
        > {
  $$TorznabEndpointsTableTableManager(
    _$AppDatabase db,
    $TorznabEndpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TorznabEndpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TorznabEndpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TorznabEndpointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<Map<String, Object?>?> caps = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> capsAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TorznabEndpointsCompanion(
                id: id,
                name: name,
                baseUrl: baseUrl,
                caps: caps,
                enabled: enabled,
                capsAt: capsAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String baseUrl,
                Value<Map<String, Object?>?> caps = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> capsAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TorznabEndpointsCompanion.insert(
                id: id,
                name: name,
                baseUrl: baseUrl,
                caps: caps,
                enabled: enabled,
                capsAt: capsAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TorznabEndpointsTable, TorznabEndpointRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $TorznabEndpointsTable,
                    TorznabEndpointRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TorznabEndpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TorznabEndpointsTable,
      TorznabEndpointRow,
      $$TorznabEndpointsTableFilterComposer,
      $$TorznabEndpointsTableOrderingComposer,
      $$TorznabEndpointsTableAnnotationComposer,
      $$TorznabEndpointsTableCreateCompanionBuilder,
      $$TorznabEndpointsTableUpdateCompanionBuilder,
      (
        TorznabEndpointRow,
        BaseReferences<
          _$AppDatabase,
          $TorznabEndpointsTable,
          TorznabEndpointRow
        >,
      ),
      TorznabEndpointRow,
      PrefetchHooks Function()
    >;
typedef $$ProviderRunsTableCreateCompanionBuilder =
    ProviderRunsCompanion Function({
      required String providerId,
      required DateTime at,
      required String status,
      Value<String?> reason,
      required int ms,
      required int results,
      required int requests,
      required List<String> blockedHosts,
      Value<int> rowid,
    });
typedef $$ProviderRunsTableUpdateCompanionBuilder =
    ProviderRunsCompanion Function({
      Value<String> providerId,
      Value<DateTime> at,
      Value<String> status,
      Value<String?> reason,
      Value<int> ms,
      Value<int> results,
      Value<int> requests,
      Value<List<String>> blockedHosts,
      Value<int> rowid,
    });

class $$ProviderRunsTableFilterComposer
    extends Composer<_$AppDatabase, $ProviderRunsTable> {
  $$ProviderRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ms => $composableBuilder(
    column: $table.ms,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get results => $composableBuilder(
    column: $table.results,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requests => $composableBuilder(
    column: $table.requests,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get blockedHosts => $composableBuilder(
    column: $table.blockedHosts,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$ProviderRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProviderRunsTable> {
  $$ProviderRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ms => $composableBuilder(
    column: $table.ms,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get results => $composableBuilder(
    column: $table.results,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requests => $composableBuilder(
    column: $table.requests,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedHosts => $composableBuilder(
    column: $table.blockedHosts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProviderRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProviderRunsTable> {
  $$ProviderRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get ms =>
      $composableBuilder(column: $table.ms, builder: (column) => column);

  GeneratedColumn<int> get results =>
      $composableBuilder(column: $table.results, builder: (column) => column);

  GeneratedColumn<int> get requests =>
      $composableBuilder(column: $table.requests, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get blockedHosts =>
      $composableBuilder(
        column: $table.blockedHosts,
        builder: (column) => column,
      );
}

class $$ProviderRunsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProviderRunsTable,
          ProviderRunRow,
          $$ProviderRunsTableFilterComposer,
          $$ProviderRunsTableOrderingComposer,
          $$ProviderRunsTableAnnotationComposer,
          $$ProviderRunsTableCreateCompanionBuilder,
          $$ProviderRunsTableUpdateCompanionBuilder,
          (
            ProviderRunRow,
            BaseReferences<_$AppDatabase, $ProviderRunsTable, ProviderRunRow>,
          ),
          ProviderRunRow,
          PrefetchHooks Function()
        > {
  $$ProviderRunsTableTableManager(_$AppDatabase db, $ProviderRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProviderRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProviderRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> providerId = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<int> ms = const Value.absent(),
                Value<int> results = const Value.absent(),
                Value<int> requests = const Value.absent(),
                Value<List<String>> blockedHosts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderRunsCompanion(
                providerId: providerId,
                at: at,
                status: status,
                reason: reason,
                ms: ms,
                results: results,
                requests: requests,
                blockedHosts: blockedHosts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String providerId,
                required DateTime at,
                required String status,
                Value<String?> reason = const Value.absent(),
                required int ms,
                required int results,
                required int requests,
                required List<String> blockedHosts,
                Value<int> rowid = const Value.absent(),
              }) => ProviderRunsCompanion.insert(
                providerId: providerId,
                at: at,
                status: status,
                reason: reason,
                ms: ms,
                results: results,
                requests: requests,
                blockedHosts: blockedHosts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProviderRunsTable, ProviderRunRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProviderRunsTable,
                    ProviderRunRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProviderRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProviderRunsTable,
      ProviderRunRow,
      $$ProviderRunsTableFilterComposer,
      $$ProviderRunsTableOrderingComposer,
      $$ProviderRunsTableAnnotationComposer,
      $$ProviderRunsTableCreateCompanionBuilder,
      $$ProviderRunsTableUpdateCompanionBuilder,
      (
        ProviderRunRow,
        BaseReferences<_$AppDatabase, $ProviderRunsTable, ProviderRunRow>,
      ),
      ProviderRunRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$HttpCacheTableTableManager get httpCache =>
      $$HttpCacheTableTableManager(_db, _db.httpCache);
  $$PluginReposTableTableManager get pluginRepos =>
      $$PluginReposTableTableManager(_db, _db.pluginRepos);
  $$PluginsTableTableManager get plugins =>
      $$PluginsTableTableManager(_db, _db.plugins);
  $$TorznabEndpointsTableTableManager get torznabEndpoints =>
      $$TorznabEndpointsTableTableManager(_db, _db.torznabEndpoints);
  $$ProviderRunsTableTableManager get providerRuns =>
      $$ProviderRunsTableTableManager(_db, _db.providerRuns);
}
