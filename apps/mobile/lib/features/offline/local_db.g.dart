// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $CachedProductsTable extends CachedProducts
    with TableInfo<$CachedProductsTable, CachedProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    data,
    name,
    barcode,
    sku,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProduct> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProduct(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      )!,
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedProductsTable createAlias(String alias) {
    return $CachedProductsTable(attachedDatabase, alias);
  }
}

class CachedProduct extends DataClass implements Insertable<CachedProduct> {
  final String id;
  final String data;
  final String name;
  final String barcode;
  final String sku;
  final DateTime updatedAt;
  const CachedProduct({
    required this.id,
    required this.data,
    required this.name,
    required this.barcode,
    required this.sku,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data'] = Variable<String>(data);
    map['name'] = Variable<String>(name);
    map['barcode'] = Variable<String>(barcode);
    map['sku'] = Variable<String>(sku);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedProductsCompanion toCompanion(bool nullToAbsent) {
    return CachedProductsCompanion(
      id: Value(id),
      data: Value(data),
      name: Value(name),
      barcode: Value(barcode),
      sku: Value(sku),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedProduct.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProduct(
      id: serializer.fromJson<String>(json['id']),
      data: serializer.fromJson<String>(json['data']),
      name: serializer.fromJson<String>(json['name']),
      barcode: serializer.fromJson<String>(json['barcode']),
      sku: serializer.fromJson<String>(json['sku']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'data': serializer.toJson<String>(data),
      'name': serializer.toJson<String>(name),
      'barcode': serializer.toJson<String>(barcode),
      'sku': serializer.toJson<String>(sku),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedProduct copyWith({
    String? id,
    String? data,
    String? name,
    String? barcode,
    String? sku,
    DateTime? updatedAt,
  }) => CachedProduct(
    id: id ?? this.id,
    data: data ?? this.data,
    name: name ?? this.name,
    barcode: barcode ?? this.barcode,
    sku: sku ?? this.sku,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedProduct copyWithCompanion(CachedProductsCompanion data) {
    return CachedProduct(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      name: data.name.present ? data.name.value : this.name,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      sku: data.sku.present ? data.sku.value : this.sku,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProduct(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('name: $name, ')
          ..write('barcode: $barcode, ')
          ..write('sku: $sku, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data, name, barcode, sku, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProduct &&
          other.id == this.id &&
          other.data == this.data &&
          other.name == this.name &&
          other.barcode == this.barcode &&
          other.sku == this.sku &&
          other.updatedAt == this.updatedAt);
}

class CachedProductsCompanion extends UpdateCompanion<CachedProduct> {
  final Value<String> id;
  final Value<String> data;
  final Value<String> name;
  final Value<String> barcode;
  final Value<String> sku;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedProductsCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.name = const Value.absent(),
    this.barcode = const Value.absent(),
    this.sku = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProductsCompanion.insert({
    required String id,
    required String data,
    required String name,
    this.barcode = const Value.absent(),
    this.sku = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       data = Value(data),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<CachedProduct> custom({
    Expression<String>? id,
    Expression<String>? data,
    Expression<String>? name,
    Expression<String>? barcode,
    Expression<String>? sku,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (name != null) 'name': name,
      if (barcode != null) 'barcode': barcode,
      if (sku != null) 'sku': sku,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? data,
    Value<String>? name,
    Value<String>? barcode,
    Value<String>? sku,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedProductsCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      sku: sku ?? this.sku,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProductsCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('name: $name, ')
          ..write('barcode: $barcode, ')
          ..write('sku: $sku, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCustomersTable extends CachedCustomers
    with TableInfo<$CachedCustomersTable, CachedCustomer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  @override
  List<GeneratedColumn> get $columns => [id, data, name, phone, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCustomer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedCustomer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCustomer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedCustomersTable createAlias(String alias) {
    return $CachedCustomersTable(attachedDatabase, alias);
  }
}

class CachedCustomer extends DataClass implements Insertable<CachedCustomer> {
  final String id;
  final String data;
  final String name;
  final String phone;
  final DateTime updatedAt;
  const CachedCustomer({
    required this.id,
    required this.data,
    required this.name,
    required this.phone,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data'] = Variable<String>(data);
    map['name'] = Variable<String>(name);
    map['phone'] = Variable<String>(phone);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedCustomersCompanion toCompanion(bool nullToAbsent) {
    return CachedCustomersCompanion(
      id: Value(id),
      data: Value(data),
      name: Value(name),
      phone: Value(phone),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedCustomer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCustomer(
      id: serializer.fromJson<String>(json['id']),
      data: serializer.fromJson<String>(json['data']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String>(json['phone']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'data': serializer.toJson<String>(data),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String>(phone),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedCustomer copyWith({
    String? id,
    String? data,
    String? name,
    String? phone,
    DateTime? updatedAt,
  }) => CachedCustomer(
    id: id ?? this.id,
    data: data ?? this.data,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedCustomer copyWithCompanion(CachedCustomersCompanion data) {
    return CachedCustomer(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomer(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data, name, phone, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCustomer &&
          other.id == this.id &&
          other.data == this.data &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.updatedAt == this.updatedAt);
}

class CachedCustomersCompanion extends UpdateCompanion<CachedCustomer> {
  final Value<String> id;
  final Value<String> data;
  final Value<String> name;
  final Value<String> phone;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedCustomersCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCustomersCompanion.insert({
    required String id,
    required String data,
    required String name,
    this.phone = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       data = Value(data),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<CachedCustomer> custom({
    Expression<String>? id,
    Expression<String>? data,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCustomersCompanion copyWith({
    Value<String>? id,
    Value<String>? data,
    Value<String>? name,
    Value<String>? phone,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedCustomersCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomersCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingBillsTable extends PendingBills
    with TableInfo<$PendingBillsTable, PendingBill> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingBillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNoMeta = const VerificationMeta(
    'displayNo',
  );
  @override
  late final GeneratedColumn<String> displayNo = GeneratedColumn<String>(
    'display_no',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
    'total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerNameMeta = const VerificationMeta(
    'customerName',
  );
  @override
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
    'customer_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    payload,
    displayNo,
    total,
    customerName,
    status,
    error,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_bills';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingBill> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('display_no')) {
      context.handle(
        _displayNoMeta,
        displayNo.isAcceptableOrUnknown(data['display_no']!, _displayNoMeta),
      );
    } else if (isInserting) {
      context.missing(_displayNoMeta);
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    if (data.containsKey('customer_name')) {
      context.handle(
        _customerNameMeta,
        customerName.isAcceptableOrUnknown(
          data['customer_name']!,
          _customerNameMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  PendingBill map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingBill(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      displayNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_no'],
      )!,
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total'],
      )!,
      customerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_name'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PendingBillsTable createAlias(String alias) {
    return $PendingBillsTable(attachedDatabase, alias);
  }
}

class PendingBill extends DataClass implements Insertable<PendingBill> {
  final String localId;
  final String payload;
  final String displayNo;
  final double total;
  final String customerName;
  final String status;
  final String error;
  final DateTime createdAt;
  const PendingBill({
    required this.localId,
    required this.payload,
    required this.displayNo,
    required this.total,
    required this.customerName,
    required this.status,
    required this.error,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['payload'] = Variable<String>(payload);
    map['display_no'] = Variable<String>(displayNo);
    map['total'] = Variable<double>(total);
    map['customer_name'] = Variable<String>(customerName);
    map['status'] = Variable<String>(status);
    map['error'] = Variable<String>(error);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingBillsCompanion toCompanion(bool nullToAbsent) {
    return PendingBillsCompanion(
      localId: Value(localId),
      payload: Value(payload),
      displayNo: Value(displayNo),
      total: Value(total),
      customerName: Value(customerName),
      status: Value(status),
      error: Value(error),
      createdAt: Value(createdAt),
    );
  }

  factory PendingBill.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingBill(
      localId: serializer.fromJson<String>(json['localId']),
      payload: serializer.fromJson<String>(json['payload']),
      displayNo: serializer.fromJson<String>(json['displayNo']),
      total: serializer.fromJson<double>(json['total']),
      customerName: serializer.fromJson<String>(json['customerName']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String>(json['error']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'payload': serializer.toJson<String>(payload),
      'displayNo': serializer.toJson<String>(displayNo),
      'total': serializer.toJson<double>(total),
      'customerName': serializer.toJson<String>(customerName),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String>(error),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingBill copyWith({
    String? localId,
    String? payload,
    String? displayNo,
    double? total,
    String? customerName,
    String? status,
    String? error,
    DateTime? createdAt,
  }) => PendingBill(
    localId: localId ?? this.localId,
    payload: payload ?? this.payload,
    displayNo: displayNo ?? this.displayNo,
    total: total ?? this.total,
    customerName: customerName ?? this.customerName,
    status: status ?? this.status,
    error: error ?? this.error,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingBill copyWithCompanion(PendingBillsCompanion data) {
    return PendingBill(
      localId: data.localId.present ? data.localId.value : this.localId,
      payload: data.payload.present ? data.payload.value : this.payload,
      displayNo: data.displayNo.present ? data.displayNo.value : this.displayNo,
      total: data.total.present ? data.total.value : this.total,
      customerName: data.customerName.present
          ? data.customerName.value
          : this.customerName,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingBill(')
          ..write('localId: $localId, ')
          ..write('payload: $payload, ')
          ..write('displayNo: $displayNo, ')
          ..write('total: $total, ')
          ..write('customerName: $customerName, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    payload,
    displayNo,
    total,
    customerName,
    status,
    error,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingBill &&
          other.localId == this.localId &&
          other.payload == this.payload &&
          other.displayNo == this.displayNo &&
          other.total == this.total &&
          other.customerName == this.customerName &&
          other.status == this.status &&
          other.error == this.error &&
          other.createdAt == this.createdAt);
}

class PendingBillsCompanion extends UpdateCompanion<PendingBill> {
  final Value<String> localId;
  final Value<String> payload;
  final Value<String> displayNo;
  final Value<double> total;
  final Value<String> customerName;
  final Value<String> status;
  final Value<String> error;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PendingBillsCompanion({
    this.localId = const Value.absent(),
    this.payload = const Value.absent(),
    this.displayNo = const Value.absent(),
    this.total = const Value.absent(),
    this.customerName = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingBillsCompanion.insert({
    required String localId,
    required String payload,
    required String displayNo,
    required double total,
    this.customerName = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       payload = Value(payload),
       displayNo = Value(displayNo),
       total = Value(total),
       createdAt = Value(createdAt);
  static Insertable<PendingBill> custom({
    Expression<String>? localId,
    Expression<String>? payload,
    Expression<String>? displayNo,
    Expression<double>? total,
    Expression<String>? customerName,
    Expression<String>? status,
    Expression<String>? error,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (payload != null) 'payload': payload,
      if (displayNo != null) 'display_no': displayNo,
      if (total != null) 'total': total,
      if (customerName != null) 'customer_name': customerName,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingBillsCompanion copyWith({
    Value<String>? localId,
    Value<String>? payload,
    Value<String>? displayNo,
    Value<double>? total,
    Value<String>? customerName,
    Value<String>? status,
    Value<String>? error,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PendingBillsCompanion(
      localId: localId ?? this.localId,
      payload: payload ?? this.payload,
      displayNo: displayNo ?? this.displayNo,
      total: total ?? this.total,
      customerName: customerName ?? this.customerName,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (displayNo.present) {
      map['display_no'] = Variable<String>(displayNo.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingBillsCompanion(')
          ..write('localId: $localId, ')
          ..write('payload: $payload, ')
          ..write('displayNo: $displayNo, ')
          ..write('total: $total, ')
          ..write('customerName: $customerName, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $CachedProductsTable cachedProducts = $CachedProductsTable(this);
  late final $CachedCustomersTable cachedCustomers = $CachedCustomersTable(
    this,
  );
  late final $PendingBillsTable pendingBills = $PendingBillsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedProducts,
    cachedCustomers,
    pendingBills,
  ];
}

typedef $$CachedProductsTableCreateCompanionBuilder =
    CachedProductsCompanion Function({
      required String id,
      required String data,
      required String name,
      Value<String> barcode,
      Value<String> sku,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedProductsTableUpdateCompanionBuilder =
    CachedProductsCompanion Function({
      Value<String> id,
      Value<String> data,
      Value<String> name,
      Value<String> barcode,
      Value<String> sku,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedProductsTableFilterComposer
    extends Composer<_$LocalDb, $CachedProductsTable> {
  $$CachedProductsTableFilterComposer({
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

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProductsTableOrderingComposer
    extends Composer<_$LocalDb, $CachedProductsTable> {
  $$CachedProductsTableOrderingComposer({
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

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProductsTableAnnotationComposer
    extends Composer<_$LocalDb, $CachedProductsTable> {
  $$CachedProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedProductsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $CachedProductsTable,
          CachedProduct,
          $$CachedProductsTableFilterComposer,
          $$CachedProductsTableOrderingComposer,
          $$CachedProductsTableAnnotationComposer,
          $$CachedProductsTableCreateCompanionBuilder,
          $$CachedProductsTableUpdateCompanionBuilder,
          (
            CachedProduct,
            BaseReferences<_$LocalDb, $CachedProductsTable, CachedProduct>,
          ),
          CachedProduct,
          PrefetchHooks Function()
        > {
  $$CachedProductsTableTableManager(_$LocalDb db, $CachedProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> barcode = const Value.absent(),
                Value<String> sku = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProductsCompanion(
                id: id,
                data: data,
                name: name,
                barcode: barcode,
                sku: sku,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String data,
                required String name,
                Value<String> barcode = const Value.absent(),
                Value<String> sku = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedProductsCompanion.insert(
                id: id,
                data: data,
                name: name,
                barcode: barcode,
                sku: sku,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $CachedProductsTable,
      CachedProduct,
      $$CachedProductsTableFilterComposer,
      $$CachedProductsTableOrderingComposer,
      $$CachedProductsTableAnnotationComposer,
      $$CachedProductsTableCreateCompanionBuilder,
      $$CachedProductsTableUpdateCompanionBuilder,
      (
        CachedProduct,
        BaseReferences<_$LocalDb, $CachedProductsTable, CachedProduct>,
      ),
      CachedProduct,
      PrefetchHooks Function()
    >;
typedef $$CachedCustomersTableCreateCompanionBuilder =
    CachedCustomersCompanion Function({
      required String id,
      required String data,
      required String name,
      Value<String> phone,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedCustomersTableUpdateCompanionBuilder =
    CachedCustomersCompanion Function({
      Value<String> id,
      Value<String> data,
      Value<String> name,
      Value<String> phone,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedCustomersTableFilterComposer
    extends Composer<_$LocalDb, $CachedCustomersTable> {
  $$CachedCustomersTableFilterComposer({
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

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCustomersTableOrderingComposer
    extends Composer<_$LocalDb, $CachedCustomersTable> {
  $$CachedCustomersTableOrderingComposer({
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

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCustomersTableAnnotationComposer
    extends Composer<_$LocalDb, $CachedCustomersTable> {
  $$CachedCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedCustomersTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $CachedCustomersTable,
          CachedCustomer,
          $$CachedCustomersTableFilterComposer,
          $$CachedCustomersTableOrderingComposer,
          $$CachedCustomersTableAnnotationComposer,
          $$CachedCustomersTableCreateCompanionBuilder,
          $$CachedCustomersTableUpdateCompanionBuilder,
          (
            CachedCustomer,
            BaseReferences<_$LocalDb, $CachedCustomersTable, CachedCustomer>,
          ),
          CachedCustomer,
          PrefetchHooks Function()
        > {
  $$CachedCustomersTableTableManager(_$LocalDb db, $CachedCustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCustomersCompanion(
                id: id,
                data: data,
                name: name,
                phone: phone,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String data,
                required String name,
                Value<String> phone = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedCustomersCompanion.insert(
                id: id,
                data: data,
                name: name,
                phone: phone,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $CachedCustomersTable,
      CachedCustomer,
      $$CachedCustomersTableFilterComposer,
      $$CachedCustomersTableOrderingComposer,
      $$CachedCustomersTableAnnotationComposer,
      $$CachedCustomersTableCreateCompanionBuilder,
      $$CachedCustomersTableUpdateCompanionBuilder,
      (
        CachedCustomer,
        BaseReferences<_$LocalDb, $CachedCustomersTable, CachedCustomer>,
      ),
      CachedCustomer,
      PrefetchHooks Function()
    >;
typedef $$PendingBillsTableCreateCompanionBuilder =
    PendingBillsCompanion Function({
      required String localId,
      required String payload,
      required String displayNo,
      required double total,
      Value<String> customerName,
      Value<String> status,
      Value<String> error,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$PendingBillsTableUpdateCompanionBuilder =
    PendingBillsCompanion Function({
      Value<String> localId,
      Value<String> payload,
      Value<String> displayNo,
      Value<double> total,
      Value<String> customerName,
      Value<String> status,
      Value<String> error,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PendingBillsTableFilterComposer
    extends Composer<_$LocalDb, $PendingBillsTable> {
  $$PendingBillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayNo => $composableBuilder(
    column: $table.displayNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingBillsTableOrderingComposer
    extends Composer<_$LocalDb, $PendingBillsTable> {
  $$PendingBillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayNo => $composableBuilder(
    column: $table.displayNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingBillsTableAnnotationComposer
    extends Composer<_$LocalDb, $PendingBillsTable> {
  $$PendingBillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get displayNo =>
      $composableBuilder(column: $table.displayNo, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingBillsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $PendingBillsTable,
          PendingBill,
          $$PendingBillsTableFilterComposer,
          $$PendingBillsTableOrderingComposer,
          $$PendingBillsTableAnnotationComposer,
          $$PendingBillsTableCreateCompanionBuilder,
          $$PendingBillsTableUpdateCompanionBuilder,
          (
            PendingBill,
            BaseReferences<_$LocalDb, $PendingBillsTable, PendingBill>,
          ),
          PendingBill,
          PrefetchHooks Function()
        > {
  $$PendingBillsTableTableManager(_$LocalDb db, $PendingBillsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingBillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingBillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingBillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> displayNo = const Value.absent(),
                Value<double> total = const Value.absent(),
                Value<String> customerName = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> error = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingBillsCompanion(
                localId: localId,
                payload: payload,
                displayNo: displayNo,
                total: total,
                customerName: customerName,
                status: status,
                error: error,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                required String payload,
                required String displayNo,
                required double total,
                Value<String> customerName = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> error = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingBillsCompanion.insert(
                localId: localId,
                payload: payload,
                displayNo: displayNo,
                total: total,
                customerName: customerName,
                status: status,
                error: error,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingBillsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $PendingBillsTable,
      PendingBill,
      $$PendingBillsTableFilterComposer,
      $$PendingBillsTableOrderingComposer,
      $$PendingBillsTableAnnotationComposer,
      $$PendingBillsTableCreateCompanionBuilder,
      $$PendingBillsTableUpdateCompanionBuilder,
      (PendingBill, BaseReferences<_$LocalDb, $PendingBillsTable, PendingBill>),
      PendingBill,
      PrefetchHooks Function()
    >;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$CachedProductsTableTableManager get cachedProducts =>
      $$CachedProductsTableTableManager(_db, _db.cachedProducts);
  $$CachedCustomersTableTableManager get cachedCustomers =>
      $$CachedCustomersTableTableManager(_db, _db.cachedCustomers);
  $$PendingBillsTableTableManager get pendingBills =>
      $$PendingBillsTableTableManager(_db, _db.pendingBills);
}
