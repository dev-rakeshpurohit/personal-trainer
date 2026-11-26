// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $DocsTable extends Docs with TableInfo<$DocsTable, DocRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _storeMeta = const VerificationMeta('store');
  @override
  late final GeneratedColumn<String> store = GeneratedColumn<String>(
    'store',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _k1Meta = const VerificationMeta('k1');
  @override
  late final GeneratedColumn<String> k1 = GeneratedColumn<String>(
    'k1',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _k2Meta = const VerificationMeta('k2');
  @override
  late final GeneratedColumn<String> k2 = GeneratedColumn<String>(
    'k2',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [store, id, k1, k2, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'docs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('store')) {
      context.handle(
        _storeMeta,
        store.isAcceptableOrUnknown(data['store']!, _storeMeta),
      );
    } else if (isInserting) {
      context.missing(_storeMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('k1')) {
      context.handle(_k1Meta, k1.isAcceptableOrUnknown(data['k1']!, _k1Meta));
    }
    if (data.containsKey('k2')) {
      context.handle(_k2Meta, k2.isAcceptableOrUnknown(data['k2']!, _k2Meta));
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {store, id};
  @override
  DocRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocRow(
      store: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      k1: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}k1'],
      ),
      k2: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}k2'],
      ),
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $DocsTable createAlias(String alias) {
    return $DocsTable(attachedDatabase, alias);
  }
}

class DocRow extends DataClass implements Insertable<DocRow> {
  /// Store name, e.g. 'exercises', 'sets'.
  final String store;
  final String id;

  /// Secondary keys (store-specific, see [kStoreKeys]).
  final String? k1;
  final String? k2;

  /// The record as JSON.
  final String data;
  const DocRow({
    required this.store,
    required this.id,
    this.k1,
    this.k2,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['store'] = Variable<String>(store);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || k1 != null) {
      map['k1'] = Variable<String>(k1);
    }
    if (!nullToAbsent || k2 != null) {
      map['k2'] = Variable<String>(k2);
    }
    map['data'] = Variable<String>(data);
    return map;
  }

  DocsCompanion toCompanion(bool nullToAbsent) {
    return DocsCompanion(
      store: Value(store),
      id: Value(id),
      k1: k1 == null && nullToAbsent ? const Value.absent() : Value(k1),
      k2: k2 == null && nullToAbsent ? const Value.absent() : Value(k2),
      data: Value(data),
    );
  }

  factory DocRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocRow(
      store: serializer.fromJson<String>(json['store']),
      id: serializer.fromJson<String>(json['id']),
      k1: serializer.fromJson<String?>(json['k1']),
      k2: serializer.fromJson<String?>(json['k2']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'store': serializer.toJson<String>(store),
      'id': serializer.toJson<String>(id),
      'k1': serializer.toJson<String?>(k1),
      'k2': serializer.toJson<String?>(k2),
      'data': serializer.toJson<String>(data),
    };
  }

  DocRow copyWith({
    String? store,
    String? id,
    Value<String?> k1 = const Value.absent(),
    Value<String?> k2 = const Value.absent(),
    String? data,
  }) => DocRow(
    store: store ?? this.store,
    id: id ?? this.id,
    k1: k1.present ? k1.value : this.k1,
    k2: k2.present ? k2.value : this.k2,
    data: data ?? this.data,
  );
  DocRow copyWithCompanion(DocsCompanion data) {
    return DocRow(
      store: data.store.present ? data.store.value : this.store,
      id: data.id.present ? data.id.value : this.id,
      k1: data.k1.present ? data.k1.value : this.k1,
      k2: data.k2.present ? data.k2.value : this.k2,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocRow(')
          ..write('store: $store, ')
          ..write('id: $id, ')
          ..write('k1: $k1, ')
          ..write('k2: $k2, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(store, id, k1, k2, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocRow &&
          other.store == this.store &&
          other.id == this.id &&
          other.k1 == this.k1 &&
          other.k2 == this.k2 &&
          other.data == this.data);
}

class DocsCompanion extends UpdateCompanion<DocRow> {
  final Value<String> store;
  final Value<String> id;
  final Value<String?> k1;
  final Value<String?> k2;
  final Value<String> data;
  final Value<int> rowid;
  const DocsCompanion({
    this.store = const Value.absent(),
    this.id = const Value.absent(),
    this.k1 = const Value.absent(),
    this.k2 = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocsCompanion.insert({
    required String store,
    required String id,
    this.k1 = const Value.absent(),
    this.k2 = const Value.absent(),
    required String data,
    this.rowid = const Value.absent(),
  }) : store = Value(store),
       id = Value(id),
       data = Value(data);
  static Insertable<DocRow> custom({
    Expression<String>? store,
    Expression<String>? id,
    Expression<String>? k1,
    Expression<String>? k2,
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (store != null) 'store': store,
      if (id != null) 'id': id,
      if (k1 != null) 'k1': k1,
      if (k2 != null) 'k2': k2,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocsCompanion copyWith({
    Value<String>? store,
    Value<String>? id,
    Value<String?>? k1,
    Value<String?>? k2,
    Value<String>? data,
    Value<int>? rowid,
  }) {
    return DocsCompanion(
      store: store ?? this.store,
      id: id ?? this.id,
      k1: k1 ?? this.k1,
      k2: k2 ?? this.k2,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (store.present) {
      map['store'] = Variable<String>(store.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (k1.present) {
      map['k1'] = Variable<String>(k1.value);
    }
    if (k2.present) {
      map['k2'] = Variable<String>(k2.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocsCompanion(')
          ..write('store: $store, ')
          ..write('id: $id, ')
          ..write('k1: $k1, ')
          ..write('k2: $k2, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $DocsTable docs = $DocsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [docs];
}

typedef $$DocsTableCreateCompanionBuilder = DocsCompanion Function({
  required String store,
  required String id,
  Value<String?> k1,
  Value<String?> k2,
  required String data,
  Value<int> rowid,
});
typedef $$DocsTableUpdateCompanionBuilder = DocsCompanion Function({
  Value<String> store,
  Value<String> id,
  Value<String?> k1,
  Value<String?> k2,
  Value<String> data,
  Value<int> rowid,
});

class $$DocsTableFilterComposer extends Composer<_$AppDb, $DocsTable> {
  $$DocsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get store => $composableBuilder(
    column: $table.store,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get k1 => $composableBuilder(
    column: $table.k1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get k2 => $composableBuilder(
    column: $table.k2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DocsTableOrderingComposer extends Composer<_$AppDb, $DocsTable> {
  $$DocsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get store => $composableBuilder(
    column: $table.store,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get k1 => $composableBuilder(
    column: $table.k1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get k2 => $composableBuilder(
    column: $table.k2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocsTableAnnotationComposer extends Composer<_$AppDb, $DocsTable> {
  $$DocsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get store =>
      $composableBuilder(column: $table.store, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get k1 =>
      $composableBuilder(column: $table.k1, builder: (column) => column);

  GeneratedColumn<String> get k2 =>
      $composableBuilder(column: $table.k2, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$DocsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $DocsTable,
          DocRow,
          $$DocsTableFilterComposer,
          $$DocsTableOrderingComposer,
          $$DocsTableAnnotationComposer,
          $$DocsTableCreateCompanionBuilder,
          $$DocsTableUpdateCompanionBuilder,
          (DocRow, BaseReferences<_$AppDb, $DocsTable, DocRow>),
          DocRow,
          PrefetchHooks Function()
        > {
  $$DocsTableTableManager(_$AppDb db, $DocsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> store = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> k1 = const Value.absent(),
                Value<String?> k2 = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocsCompanion(
                store: store,
                id: id,
                k1: k1,
                k2: k2,
                data: data,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String store,
                required String id,
                Value<String?> k1 = const Value.absent(),
                Value<String?> k2 = const Value.absent(),
                required String data,
                Value<int> rowid = const Value.absent(),
              }) => DocsCompanion.insert(
                store: store,
                id: id,
                k1: k1,
                k2: k2,
                data: data,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocsTable, DocRow>(table),
                  BaseReferences<_$AppDb, $DocsTable, DocRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DocsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $DocsTable,
      DocRow,
      $$DocsTableFilterComposer,
      $$DocsTableOrderingComposer,
      $$DocsTableAnnotationComposer,
      $$DocsTableCreateCompanionBuilder,
      $$DocsTableUpdateCompanionBuilder,
      (DocRow, BaseReferences<_$AppDb, $DocsTable, DocRow>),
      DocRow,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$DocsTableTableManager get docs => $$DocsTableTableManager(_db, _db.docs);
}
