// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CompaniesTable extends Companies
    with TableInfo<$CompaniesTable, Company> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CompaniesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
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
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _businessNumberMeta = const VerificationMeta(
    'businessNumber',
  );
  @override
  late final GeneratedColumn<String> businessNumber = GeneratedColumn<String>(
    'business_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logoUrlMeta = const VerificationMeta(
    'logoUrl',
  );
  @override
  late final GeneratedColumn<String> logoUrl = GeneratedColumn<String>(
    'logo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tradeTypesMeta = const VerificationMeta(
    'tradeTypes',
  );
  @override
  late final GeneratedColumn<String> tradeTypes = GeneratedColumn<String>(
    'trade_types',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    address,
    phone,
    businessNumber,
    logoUrl,
    tradeTypes,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'companies';
  @override
  VerificationContext validateIntegrity(
    Insertable<Company> instance, {
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
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('business_number')) {
      context.handle(
        _businessNumberMeta,
        businessNumber.isAcceptableOrUnknown(
          data['business_number']!,
          _businessNumberMeta,
        ),
      );
    }
    if (data.containsKey('logo_url')) {
      context.handle(
        _logoUrlMeta,
        logoUrl.isAcceptableOrUnknown(data['logo_url']!, _logoUrlMeta),
      );
    }
    if (data.containsKey('trade_types')) {
      context.handle(
        _tradeTypesMeta,
        tradeTypes.isAcceptableOrUnknown(data['trade_types']!, _tradeTypesMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Company map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Company(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      businessNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_number'],
      ),
      logoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_url'],
      ),
      tradeTypes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trade_types'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CompaniesTable createAlias(String alias) {
    return $CompaniesTable(attachedDatabase, alias);
  }
}

class Company extends DataClass implements Insertable<Company> {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final String? businessNumber;
  final String? logoUrl;
  final String? tradeTypes;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Company({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.businessNumber,
    this.logoUrl,
    this.tradeTypes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || businessNumber != null) {
      map['business_number'] = Variable<String>(businessNumber);
    }
    if (!nullToAbsent || logoUrl != null) {
      map['logo_url'] = Variable<String>(logoUrl);
    }
    if (!nullToAbsent || tradeTypes != null) {
      map['trade_types'] = Variable<String>(tradeTypes);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  CompaniesCompanion toCompanion(bool nullToAbsent) {
    return CompaniesCompanion(
      id: Value(id),
      name: Value(name),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      businessNumber: businessNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(businessNumber),
      logoUrl: logoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(logoUrl),
      tradeTypes: tradeTypes == null && nullToAbsent
          ? const Value.absent()
          : Value(tradeTypes),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Company.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Company(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String?>(json['address']),
      phone: serializer.fromJson<String?>(json['phone']),
      businessNumber: serializer.fromJson<String?>(json['businessNumber']),
      logoUrl: serializer.fromJson<String?>(json['logoUrl']),
      tradeTypes: serializer.fromJson<String?>(json['tradeTypes']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String?>(address),
      'phone': serializer.toJson<String?>(phone),
      'businessNumber': serializer.toJson<String?>(businessNumber),
      'logoUrl': serializer.toJson<String?>(logoUrl),
      'tradeTypes': serializer.toJson<String?>(tradeTypes),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Company copyWith({
    String? id,
    String? name,
    Value<String?> address = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<String?> businessNumber = const Value.absent(),
    Value<String?> logoUrl = const Value.absent(),
    Value<String?> tradeTypes = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Company(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address.present ? address.value : this.address,
    phone: phone.present ? phone.value : this.phone,
    businessNumber: businessNumber.present
        ? businessNumber.value
        : this.businessNumber,
    logoUrl: logoUrl.present ? logoUrl.value : this.logoUrl,
    tradeTypes: tradeTypes.present ? tradeTypes.value : this.tradeTypes,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Company copyWithCompanion(CompaniesCompanion data) {
    return Company(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      phone: data.phone.present ? data.phone.value : this.phone,
      businessNumber: data.businessNumber.present
          ? data.businessNumber.value
          : this.businessNumber,
      logoUrl: data.logoUrl.present ? data.logoUrl.value : this.logoUrl,
      tradeTypes: data.tradeTypes.present
          ? data.tradeTypes.value
          : this.tradeTypes,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Company(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('phone: $phone, ')
          ..write('businessNumber: $businessNumber, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('tradeTypes: $tradeTypes, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    address,
    phone,
    businessNumber,
    logoUrl,
    tradeTypes,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Company &&
          other.id == this.id &&
          other.name == this.name &&
          other.address == this.address &&
          other.phone == this.phone &&
          other.businessNumber == this.businessNumber &&
          other.logoUrl == this.logoUrl &&
          other.tradeTypes == this.tradeTypes &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CompaniesCompanion extends UpdateCompanion<Company> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> address;
  final Value<String?> phone;
  final Value<String?> businessNumber;
  final Value<String?> logoUrl;
  final Value<String?> tradeTypes;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const CompaniesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.phone = const Value.absent(),
    this.businessNumber = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.tradeTypes = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CompaniesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.address = const Value.absent(),
    this.phone = const Value.absent(),
    this.businessNumber = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.tradeTypes = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Company> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? address,
    Expression<String>? phone,
    Expression<String>? businessNumber,
    Expression<String>? logoUrl,
    Expression<String>? tradeTypes,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (businessNumber != null) 'business_number': businessNumber,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (tradeTypes != null) 'trade_types': tradeTypes,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CompaniesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? address,
    Value<String?>? phone,
    Value<String?>? businessNumber,
    Value<String?>? logoUrl,
    Value<String?>? tradeTypes,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CompaniesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      businessNumber: businessNumber ?? this.businessNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      tradeTypes: tradeTypes ?? this.tradeTypes,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
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
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (businessNumber.present) {
      map['business_number'] = Variable<String>(businessNumber.value);
    }
    if (logoUrl.present) {
      map['logo_url'] = Variable<String>(logoUrl.value);
    }
    if (tradeTypes.present) {
      map['trade_types'] = Variable<String>(tradeTypes.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CompaniesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('phone: $phone, ')
          ..write('businessNumber: $businessNumber, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('tradeTypes: $tradeTypes, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES companies (id)',
    ),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    email,
    firstName,
    lastName,
    phone,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      ),
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final String id;
  final String companyId;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const User({
    required this.id,
    required this.companyId,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || firstName != null) {
      map['first_name'] = Variable<String>(firstName);
    }
    if (!nullToAbsent || lastName != null) {
      map['last_name'] = Variable<String>(lastName);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      companyId: Value(companyId),
      email: Value(email),
      firstName: firstName == null && nullToAbsent
          ? const Value.absent()
          : Value(firstName),
      lastName: lastName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastName),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      email: serializer.fromJson<String>(json['email']),
      firstName: serializer.fromJson<String?>(json['firstName']),
      lastName: serializer.fromJson<String?>(json['lastName']),
      phone: serializer.fromJson<String?>(json['phone']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'email': serializer.toJson<String>(email),
      'firstName': serializer.toJson<String?>(firstName),
      'lastName': serializer.toJson<String?>(lastName),
      'phone': serializer.toJson<String?>(phone),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  User copyWith({
    String? id,
    String? companyId,
    String? email,
    Value<String?> firstName = const Value.absent(),
    Value<String?> lastName = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => User(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    email: email ?? this.email,
    firstName: firstName.present ? firstName.value : this.firstName,
    lastName: lastName.present ? lastName.value : this.lastName,
    phone: phone.present ? phone.value : this.phone,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      email: data.email.present ? data.email.value : this.email,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      phone: data.phone.present ? data.phone.value : this.phone,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('email: $email, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('phone: $phone, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    email,
    firstName,
    lastName,
    phone,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.email == this.email &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.phone == this.phone &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> email;
  final Value<String?> firstName;
  final Value<String?> lastName;
  final Value<String?> phone;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.email = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.phone = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String email,
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.phone = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       email = Value(email),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<User> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? email,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? phone,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (email != null) 'email': email,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? email,
    Value<String?>? firstName,
    Value<String?>? lastName,
    Value<String?>? phone,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('email: $email, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('phone: $phone, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserRolesTable extends UserRoles
    with TableInfo<$UserRolesTable, UserRole> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserRolesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES companies (id)',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    companyId,
    role,
    createdAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_roles';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserRole> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserRole map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserRole(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $UserRolesTable createAlias(String alias) {
    return $UserRolesTable(attachedDatabase, alias);
  }
}

class UserRole extends DataClass implements Insertable<UserRole> {
  final String id;
  final String userId;
  final String companyId;
  final String role;
  final DateTime createdAt;
  final DateTime? deletedAt;
  const UserRole({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.role,
    required this.createdAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['company_id'] = Variable<String>(companyId);
    map['role'] = Variable<String>(role);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  UserRolesCompanion toCompanion(bool nullToAbsent) {
    return UserRolesCompanion(
      id: Value(id),
      userId: Value(userId),
      companyId: Value(companyId),
      role: Value(role),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory UserRole.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserRole(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      companyId: serializer.fromJson<String>(json['companyId']),
      role: serializer.fromJson<String>(json['role']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'companyId': serializer.toJson<String>(companyId),
      'role': serializer.toJson<String>(role),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  UserRole copyWith({
    String? id,
    String? userId,
    String? companyId,
    String? role,
    DateTime? createdAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => UserRole(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    companyId: companyId ?? this.companyId,
    role: role ?? this.role,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  UserRole copyWithCompanion(UserRolesCompanion data) {
    return UserRole(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      role: data.role.present ? data.role.value : this.role,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserRole(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('companyId: $companyId, ')
          ..write('role: $role, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, companyId, role, createdAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserRole &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.companyId == this.companyId &&
          other.role == this.role &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt);
}

class UserRolesCompanion extends UpdateCompanion<UserRole> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> companyId;
  final Value<String> role;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const UserRolesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.companyId = const Value.absent(),
    this.role = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserRolesCompanion.insert({
    this.id = const Value.absent(),
    required String userId,
    required String companyId,
    required String role,
    required DateTime createdAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       companyId = Value(companyId),
       role = Value(role),
       createdAt = Value(createdAt);
  static Insertable<UserRole> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? companyId,
    Expression<String>? role,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (companyId != null) 'company_id': companyId,
      if (role != null) 'role': role,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserRolesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? companyId,
    Value<String>? role,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return UserRolesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      companyId: companyId ?? this.companyId,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserRolesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('companyId: $companyId, ')
          ..write('role: $role, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
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
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    id,
    entityType,
    entityId,
    operation,
    payload,
    status,
    attemptCount,
    errorMessage,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQueueData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueData extends DataClass implements Insertable<SyncQueueData> {
  /// Client-generated UUID v4 — serves as the idempotency key for server-side dedup.
  final String id;

  /// Entity type: 'company' | 'user' | 'user_role'
  final String entityType;

  /// UUID of the entity being synced.
  final String entityId;

  /// Operation type: 'CREATE' | 'UPDATE' | 'DELETE'
  final String operation;

  /// JSON-encoded entity data for the sync payload.
  final String payload;

  /// Sync status: 'pending' | 'synced' | 'parked'
  ///
  /// - pending: waiting to be sent
  /// - synced: successfully sent (row is deleted after confirmation)
  /// - parked: permanent failure (4xx), will not be retried automatically
  final String status;

  /// Number of upload attempts made for this item.
  final int attemptCount;

  /// Last error message, set when marking as parked or on retry.
  final String? errorMessage;

  /// Timestamp when this queue entry was created — used for FIFO ordering.
  final DateTime createdAt;
  const SyncQueueData({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.status,
    required this.attemptCount,
    this.errorMessage,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: Value(payload),
      status: Value(status),
      attemptCount: Value(attemptCount),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      createdAt: Value(createdAt),
    );
  }

  factory SyncQueueData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueData(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncQueueData copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? payload,
    String? status,
    int? attemptCount,
    Value<String?> errorMessage = const Value.absent(),
    DateTime? createdAt,
  }) => SyncQueueData(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncQueueData copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueData(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueData(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    operation,
    payload,
    status,
    attemptCount,
    errorMessage,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueData &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.errorMessage == this.errorMessage &&
          other.createdAt == this.createdAt);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueData> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<String?> errorMessage;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.errorMessage = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<SyncQueueData> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<String>? errorMessage,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (errorMessage != null) 'error_message': errorMessage,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payload,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<String?>? errorMessage,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
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
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorTable extends SyncCursor
    with TableInfo<$SyncCursorTable, SyncCursorData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('main'),
  );
  static const VerificationMeta _lastPulledAtMeta = const VerificationMeta(
    'lastPulledAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPulledAt = GeneratedColumn<DateTime>(
    'last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, lastPulledAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursor';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursorData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    }
    if (data.containsKey('last_pulled_at')) {
      context.handle(
        _lastPulledAtMeta,
        lastPulledAt.isAcceptableOrUnknown(
          data['last_pulled_at']!,
          _lastPulledAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncCursorData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursorData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      lastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pulled_at'],
      ),
    );
  }

  @override
  $SyncCursorTable createAlias(String alias) {
    return $SyncCursorTable(attachedDatabase, alias);
  }
}

class SyncCursorData extends DataClass implements Insertable<SyncCursorData> {
  /// Row key — always 'main' (single-row pattern).
  final String key;

  /// Timestamp of last successful delta pull. Null means never synced (first launch).
  final DateTime? lastPulledAt;
  const SyncCursorData({required this.key, this.lastPulledAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || lastPulledAt != null) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt);
    }
    return map;
  }

  SyncCursorCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorCompanion(
      key: Value(key),
      lastPulledAt: lastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAt),
    );
  }

  factory SyncCursorData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursorData(
      key: serializer.fromJson<String>(json['key']),
      lastPulledAt: serializer.fromJson<DateTime?>(json['lastPulledAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'lastPulledAt': serializer.toJson<DateTime?>(lastPulledAt),
    };
  }

  SyncCursorData copyWith({
    String? key,
    Value<DateTime?> lastPulledAt = const Value.absent(),
  }) => SyncCursorData(
    key: key ?? this.key,
    lastPulledAt: lastPulledAt.present ? lastPulledAt.value : this.lastPulledAt,
  );
  SyncCursorData copyWithCompanion(SyncCursorCompanion data) {
    return SyncCursorData(
      key: data.key.present ? data.key.value : this.key,
      lastPulledAt: data.lastPulledAt.present
          ? data.lastPulledAt.value
          : this.lastPulledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorData(')
          ..write('key: $key, ')
          ..write('lastPulledAt: $lastPulledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, lastPulledAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursorData &&
          other.key == this.key &&
          other.lastPulledAt == this.lastPulledAt);
}

class SyncCursorCompanion extends UpdateCompanion<SyncCursorData> {
  final Value<String> key;
  final Value<DateTime?> lastPulledAt;
  final Value<int> rowid;
  const SyncCursorCompanion({
    this.key = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorCompanion.insert({
    this.key = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  static Insertable<SyncCursorData> custom({
    Expression<String>? key,
    Expression<DateTime>? lastPulledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (lastPulledAt != null) 'last_pulled_at': lastPulledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorCompanion copyWith({
    Value<String>? key,
    Value<DateTime?>? lastPulledAt,
    Value<int>? rowid,
  }) {
    return SyncCursorCompanion(
      key: key ?? this.key,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (lastPulledAt.present) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorCompanion(')
          ..write('key: $key, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JobsTable extends Jobs with TableInfo<$JobsTable, Job> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES companies (id)',
    ),
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contractorIdMeta = const VerificationMeta(
    'contractorId',
  );
  @override
  late final GeneratedColumn<String> contractorId = GeneratedColumn<String>(
    'contractor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tradeTypeMeta = const VerificationMeta(
    'tradeType',
  );
  @override
  late final GeneratedColumn<String> tradeType = GeneratedColumn<String>(
    'trade_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('quote'),
  );
  static const VerificationMeta _statusHistoryMeta = const VerificationMeta(
    'statusHistory',
  );
  @override
  late final GeneratedColumn<String> statusHistory = GeneratedColumn<String>(
    'status_history',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('medium'),
  );
  static const VerificationMeta _purchaseOrderNumberMeta =
      const VerificationMeta('purchaseOrderNumber');
  @override
  late final GeneratedColumn<String> purchaseOrderNumber =
      GeneratedColumn<String>(
        'purchase_order_number',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _externalReferenceMeta = const VerificationMeta(
    'externalReference',
  );
  @override
  late final GeneratedColumn<String> externalReference =
      GeneratedColumn<String>(
        'external_reference',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedDurationMinutesMeta =
      const VerificationMeta('estimatedDurationMinutes');
  @override
  late final GeneratedColumn<int> estimatedDurationMinutes =
      GeneratedColumn<int>(
        'estimated_duration_minutes',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _scheduledCompletionDateMeta =
      const VerificationMeta('scheduledCompletionDate');
  @override
  late final GeneratedColumn<DateTime> scheduledCompletionDate =
      GeneratedColumn<DateTime>(
        'scheduled_completion_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<double> gpsLatitude = GeneratedColumn<double>(
    'gps_latitude', aliasedName, true,
    type: DriftSqlType.double, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<double> gpsLongitude = GeneratedColumn<double>(
    'gps_longitude', aliasedName, true,
    type: DriftSqlType.double, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> gpsAddress = GeneratedColumn<String>(
    'gps_address', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    clientId,
    contractorId,
    description,
    tradeType,
    status,
    statusHistory,
    priority,
    purchaseOrderNumber,
    externalReference,
    tags,
    notes,
    estimatedDurationMinutes,
    scheduledCompletionDate,
    gpsLatitude,
    gpsLongitude,
    gpsAddress,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Job> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    }
    if (data.containsKey('contractor_id')) {
      context.handle(
        _contractorIdMeta,
        contractorId.isAcceptableOrUnknown(
          data['contractor_id']!,
          _contractorIdMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('trade_type')) {
      context.handle(
        _tradeTypeMeta,
        tradeType.isAcceptableOrUnknown(data['trade_type']!, _tradeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_tradeTypeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('status_history')) {
      context.handle(
        _statusHistoryMeta,
        statusHistory.isAcceptableOrUnknown(
          data['status_history']!,
          _statusHistoryMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('purchase_order_number')) {
      context.handle(
        _purchaseOrderNumberMeta,
        purchaseOrderNumber.isAcceptableOrUnknown(
          data['purchase_order_number']!,
          _purchaseOrderNumberMeta,
        ),
      );
    }
    if (data.containsKey('external_reference')) {
      context.handle(
        _externalReferenceMeta,
        externalReference.isAcceptableOrUnknown(
          data['external_reference']!,
          _externalReferenceMeta,
        ),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('estimated_duration_minutes')) {
      context.handle(
        _estimatedDurationMinutesMeta,
        estimatedDurationMinutes.isAcceptableOrUnknown(
          data['estimated_duration_minutes']!,
          _estimatedDurationMinutesMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_completion_date')) {
      context.handle(
        _scheduledCompletionDateMeta,
        scheduledCompletionDate.isAcceptableOrUnknown(
          data['scheduled_completion_date']!,
          _scheduledCompletionDateMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Job map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Job(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      ),
      contractorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contractor_id'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      tradeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trade_type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      statusHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_history'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      purchaseOrderNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purchase_order_number'],
      ),
      externalReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_reference'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      estimatedDurationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_duration_minutes'],
      ),
      scheduledCompletionDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_completion_date'],
      ),
      gpsLatitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gps_latitude'],
      ),
      gpsLongitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gps_longitude'],
      ),
      gpsAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gps_address'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $JobsTable createAlias(String alias) {
    return $JobsTable(attachedDatabase, alias);
  }
}

class Job extends DataClass implements Insertable<Job> {
  final String id;
  final String companyId;

  /// FK to Users.id with client role. Nullable — a job may not be
  /// client-linked if created directly by admin.
  final String? clientId;

  /// FK to Users.id with contractor role. Nullable at Quote stage;
  /// required at Scheduled stage and beyond.
  final String? contractorId;
  final String description;

  /// Comma-separated trade type(s). Mirrors TradeType backend enum.
  final String tradeType;

  /// Lifecycle state. Matches [JobStatus] enum: quote | scheduled |
  /// in_progress | complete | invoiced | cancelled
  final String status;

  /// JSON-encoded audit trail: [{status, timestamp, userId, reason}]
  final String statusHistory;

  /// Priority level: low | medium | high | urgent
  final String priority;
  final String? purchaseOrderNumber;
  final String? externalReference;

  /// JSON-encoded list of string tags/labels.
  final String tags;
  final String? notes;
  final int? estimatedDurationMinutes;
  final DateTime? scheduledCompletionDate;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final String? gpsAddress;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete for sync tombstone propagation across devices.
  final DateTime? deletedAt;
  const Job({
    required this.id,
    required this.companyId,
    this.clientId,
    this.contractorId,
    required this.description,
    required this.tradeType,
    required this.status,
    required this.statusHistory,
    required this.priority,
    this.purchaseOrderNumber,
    this.externalReference,
    required this.tags,
    this.notes,
    this.estimatedDurationMinutes,
    this.scheduledCompletionDate,
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsAddress,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    if (!nullToAbsent || clientId != null) {
      map['client_id'] = Variable<String>(clientId);
    }
    if (!nullToAbsent || contractorId != null) {
      map['contractor_id'] = Variable<String>(contractorId);
    }
    map['description'] = Variable<String>(description);
    map['trade_type'] = Variable<String>(tradeType);
    map['status'] = Variable<String>(status);
    map['status_history'] = Variable<String>(statusHistory);
    map['priority'] = Variable<String>(priority);
    if (!nullToAbsent || purchaseOrderNumber != null) {
      map['purchase_order_number'] = Variable<String>(purchaseOrderNumber);
    }
    if (!nullToAbsent || externalReference != null) {
      map['external_reference'] = Variable<String>(externalReference);
    }
    map['tags'] = Variable<String>(tags);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || estimatedDurationMinutes != null) {
      map['estimated_duration_minutes'] = Variable<int>(
        estimatedDurationMinutes,
      );
    }
    if (!nullToAbsent || scheduledCompletionDate != null) {
      map['scheduled_completion_date'] = Variable<DateTime>(
        scheduledCompletionDate,
      );
    }
    if (!nullToAbsent || gpsLatitude != null) {
      map['gps_latitude'] = Variable<double>(gpsLatitude);
    }
    if (!nullToAbsent || gpsLongitude != null) {
      map['gps_longitude'] = Variable<double>(gpsLongitude);
    }
    if (!nullToAbsent || gpsAddress != null) {
      map['gps_address'] = Variable<String>(gpsAddress);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  JobsCompanion toCompanion(bool nullToAbsent) {
    return JobsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      clientId: clientId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientId),
      contractorId: contractorId == null && nullToAbsent
          ? const Value.absent()
          : Value(contractorId),
      description: Value(description),
      tradeType: Value(tradeType),
      status: Value(status),
      statusHistory: Value(statusHistory),
      priority: Value(priority),
      purchaseOrderNumber: purchaseOrderNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(purchaseOrderNumber),
      externalReference: externalReference == null && nullToAbsent
          ? const Value.absent()
          : Value(externalReference),
      tags: Value(tags),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      estimatedDurationMinutes: estimatedDurationMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedDurationMinutes),
      scheduledCompletionDate: scheduledCompletionDate == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledCompletionDate),
      gpsLatitude: gpsLatitude == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsLatitude),
      gpsLongitude: gpsLongitude == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsLongitude),
      gpsAddress: gpsAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsAddress),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Job.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Job(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      clientId: serializer.fromJson<String?>(json['clientId']),
      contractorId: serializer.fromJson<String?>(json['contractorId']),
      description: serializer.fromJson<String>(json['description']),
      tradeType: serializer.fromJson<String>(json['tradeType']),
      status: serializer.fromJson<String>(json['status']),
      statusHistory: serializer.fromJson<String>(json['statusHistory']),
      priority: serializer.fromJson<String>(json['priority']),
      purchaseOrderNumber: serializer.fromJson<String?>(
        json['purchaseOrderNumber'],
      ),
      externalReference: serializer.fromJson<String?>(
        json['externalReference'],
      ),
      tags: serializer.fromJson<String>(json['tags']),
      notes: serializer.fromJson<String?>(json['notes']),
      estimatedDurationMinutes: serializer.fromJson<int?>(
        json['estimatedDurationMinutes'],
      ),
      scheduledCompletionDate: serializer.fromJson<DateTime?>(
        json['scheduledCompletionDate'],
      ),
      gpsLatitude: serializer.fromJson<double?>(json['gpsLatitude']),
      gpsLongitude: serializer.fromJson<double?>(json['gpsLongitude']),
      gpsAddress: serializer.fromJson<String?>(json['gpsAddress']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'clientId': serializer.toJson<String?>(clientId),
      'contractorId': serializer.toJson<String?>(contractorId),
      'description': serializer.toJson<String>(description),
      'tradeType': serializer.toJson<String>(tradeType),
      'status': serializer.toJson<String>(status),
      'statusHistory': serializer.toJson<String>(statusHistory),
      'priority': serializer.toJson<String>(priority),
      'purchaseOrderNumber': serializer.toJson<String?>(purchaseOrderNumber),
      'externalReference': serializer.toJson<String?>(externalReference),
      'tags': serializer.toJson<String>(tags),
      'notes': serializer.toJson<String?>(notes),
      'estimatedDurationMinutes': serializer.toJson<int?>(
        estimatedDurationMinutes,
      ),
      'scheduledCompletionDate': serializer.toJson<DateTime?>(
        scheduledCompletionDate,
      ),
      'gpsLatitude': serializer.toJson<double?>(gpsLatitude),
      'gpsLongitude': serializer.toJson<double?>(gpsLongitude),
      'gpsAddress': serializer.toJson<String?>(gpsAddress),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Job copyWith({
    String? id,
    String? companyId,
    Value<String?> clientId = const Value.absent(),
    Value<String?> contractorId = const Value.absent(),
    String? description,
    String? tradeType,
    String? status,
    String? statusHistory,
    String? priority,
    Value<String?> purchaseOrderNumber = const Value.absent(),
    Value<String?> externalReference = const Value.absent(),
    String? tags,
    Value<String?> notes = const Value.absent(),
    Value<int?> estimatedDurationMinutes = const Value.absent(),
    Value<DateTime?> scheduledCompletionDate = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<double?> gpsLatitude = const Value.absent(),
    Value<double?> gpsLongitude = const Value.absent(),
    Value<String?> gpsAddress = const Value.absent(),
  }) => Job(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    clientId: clientId.present ? clientId.value : this.clientId,
    contractorId: contractorId.present ? contractorId.value : this.contractorId,
    description: description ?? this.description,
    tradeType: tradeType ?? this.tradeType,
    status: status ?? this.status,
    statusHistory: statusHistory ?? this.statusHistory,
    priority: priority ?? this.priority,
    purchaseOrderNumber: purchaseOrderNumber.present
        ? purchaseOrderNumber.value
        : this.purchaseOrderNumber,
    externalReference: externalReference.present
        ? externalReference.value
        : this.externalReference,
    tags: tags ?? this.tags,
    notes: notes.present ? notes.value : this.notes,
    estimatedDurationMinutes: estimatedDurationMinutes.present
        ? estimatedDurationMinutes.value
        : this.estimatedDurationMinutes,
    scheduledCompletionDate: scheduledCompletionDate.present
        ? scheduledCompletionDate.value
        : this.scheduledCompletionDate,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    gpsLatitude: gpsLatitude.present ? gpsLatitude.value : this.gpsLatitude,
    gpsLongitude: gpsLongitude.present ? gpsLongitude.value : this.gpsLongitude,
    gpsAddress: gpsAddress.present ? gpsAddress.value : this.gpsAddress,
  );
  Job copyWithCompanion(JobsCompanion data) {
    return Job(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      contractorId: data.contractorId.present
          ? data.contractorId.value
          : this.contractorId,
      description: data.description.present
          ? data.description.value
          : this.description,
      tradeType: data.tradeType.present ? data.tradeType.value : this.tradeType,
      status: data.status.present ? data.status.value : this.status,
      statusHistory: data.statusHistory.present
          ? data.statusHistory.value
          : this.statusHistory,
      priority: data.priority.present ? data.priority.value : this.priority,
      purchaseOrderNumber: data.purchaseOrderNumber.present
          ? data.purchaseOrderNumber.value
          : this.purchaseOrderNumber,
      externalReference: data.externalReference.present
          ? data.externalReference.value
          : this.externalReference,
      tags: data.tags.present ? data.tags.value : this.tags,
      notes: data.notes.present ? data.notes.value : this.notes,
      estimatedDurationMinutes: data.estimatedDurationMinutes.present
          ? data.estimatedDurationMinutes.value
          : this.estimatedDurationMinutes,
      scheduledCompletionDate: data.scheduledCompletionDate.present
          ? data.scheduledCompletionDate.value
          : this.scheduledCompletionDate,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      gpsLatitude: data.gpsLatitude.present
          ? data.gpsLatitude.value
          : this.gpsLatitude,
      gpsLongitude: data.gpsLongitude.present
          ? data.gpsLongitude.value
          : this.gpsLongitude,
      gpsAddress: data.gpsAddress.present
          ? data.gpsAddress.value
          : this.gpsAddress,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Job(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('clientId: $clientId, ')
          ..write('contractorId: $contractorId, ')
          ..write('description: $description, ')
          ..write('tradeType: $tradeType, ')
          ..write('status: $status, ')
          ..write('statusHistory: $statusHistory, ')
          ..write('priority: $priority, ')
          ..write('purchaseOrderNumber: $purchaseOrderNumber, ')
          ..write('externalReference: $externalReference, ')
          ..write('tags: $tags, ')
          ..write('notes: $notes, ')
          ..write('estimatedDurationMinutes: $estimatedDurationMinutes, ')
          ..write('scheduledCompletionDate: $scheduledCompletionDate, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('gpsLatitude: $gpsLatitude, ')
          ..write('gpsLongitude: $gpsLongitude, ')
          ..write('gpsAddress: $gpsAddress')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    companyId,
    clientId,
    contractorId,
    description,
    tradeType,
    status,
    statusHistory,
    priority,
    purchaseOrderNumber,
    externalReference,
    tags,
    notes,
    estimatedDurationMinutes,
    scheduledCompletionDate,
    version,
    createdAt,
    updatedAt,
    deletedAt,
    gpsLatitude,
    gpsLongitude,
    gpsAddress,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Job &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.clientId == this.clientId &&
          other.contractorId == this.contractorId &&
          other.description == this.description &&
          other.tradeType == this.tradeType &&
          other.status == this.status &&
          other.statusHistory == this.statusHistory &&
          other.priority == this.priority &&
          other.purchaseOrderNumber == this.purchaseOrderNumber &&
          other.externalReference == this.externalReference &&
          other.tags == this.tags &&
          other.notes == this.notes &&
          other.estimatedDurationMinutes == this.estimatedDurationMinutes &&
          other.scheduledCompletionDate == this.scheduledCompletionDate &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.gpsLatitude == this.gpsLatitude &&
          other.gpsLongitude == this.gpsLongitude &&
          other.gpsAddress == this.gpsAddress);
}

class JobsCompanion extends UpdateCompanion<Job> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String?> clientId;
  final Value<String?> contractorId;
  final Value<String> description;
  final Value<String> tradeType;
  final Value<String> status;
  final Value<String> statusHistory;
  final Value<String> priority;
  final Value<String?> purchaseOrderNumber;
  final Value<String?> externalReference;
  final Value<String> tags;
  final Value<String?> notes;
  final Value<int?> estimatedDurationMinutes;
  final Value<DateTime?> scheduledCompletionDate;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<double?> gpsLatitude;
  final Value<double?> gpsLongitude;
  final Value<String?> gpsAddress;
  final Value<int> rowid;
  const JobsCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.contractorId = const Value.absent(),
    this.description = const Value.absent(),
    this.tradeType = const Value.absent(),
    this.status = const Value.absent(),
    this.statusHistory = const Value.absent(),
    this.priority = const Value.absent(),
    this.purchaseOrderNumber = const Value.absent(),
    this.externalReference = const Value.absent(),
    this.tags = const Value.absent(),
    this.notes = const Value.absent(),
    this.estimatedDurationMinutes = const Value.absent(),
    this.scheduledCompletionDate = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.gpsLatitude = const Value.absent(),
    this.gpsLongitude = const Value.absent(),
    this.gpsAddress = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JobsCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    this.clientId = const Value.absent(),
    this.contractorId = const Value.absent(),
    required String description,
    required String tradeType,
    this.status = const Value.absent(),
    this.statusHistory = const Value.absent(),
    this.priority = const Value.absent(),
    this.purchaseOrderNumber = const Value.absent(),
    this.externalReference = const Value.absent(),
    this.tags = const Value.absent(),
    this.notes = const Value.absent(),
    this.estimatedDurationMinutes = const Value.absent(),
    this.scheduledCompletionDate = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.gpsLatitude = const Value.absent(),
    this.gpsLongitude = const Value.absent(),
    this.gpsAddress = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       description = Value(description),
       tradeType = Value(tradeType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Job> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? clientId,
    Expression<String>? contractorId,
    Expression<String>? description,
    Expression<String>? tradeType,
    Expression<String>? status,
    Expression<String>? statusHistory,
    Expression<String>? priority,
    Expression<String>? purchaseOrderNumber,
    Expression<String>? externalReference,
    Expression<String>? tags,
    Expression<String>? notes,
    Expression<int>? estimatedDurationMinutes,
    Expression<DateTime>? scheduledCompletionDate,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<double>? gpsLatitude,
    Expression<double>? gpsLongitude,
    Expression<String>? gpsAddress,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (clientId != null) 'client_id': clientId,
      if (contractorId != null) 'contractor_id': contractorId,
      if (description != null) 'description': description,
      if (tradeType != null) 'trade_type': tradeType,
      if (status != null) 'status': status,
      if (statusHistory != null) 'status_history': statusHistory,
      if (priority != null) 'priority': priority,
      if (purchaseOrderNumber != null)
        'purchase_order_number': purchaseOrderNumber,
      if (externalReference != null) 'external_reference': externalReference,
      if (tags != null) 'tags': tags,
      if (notes != null) 'notes': notes,
      if (estimatedDurationMinutes != null)
        'estimated_duration_minutes': estimatedDurationMinutes,
      if (scheduledCompletionDate != null)
        'scheduled_completion_date': scheduledCompletionDate,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (gpsLatitude != null) 'gps_latitude': gpsLatitude,
      if (gpsLongitude != null) 'gps_longitude': gpsLongitude,
      if (gpsAddress != null) 'gps_address': gpsAddress,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JobsCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String?>? clientId,
    Value<String?>? contractorId,
    Value<String>? description,
    Value<String>? tradeType,
    Value<String>? status,
    Value<String>? statusHistory,
    Value<String>? priority,
    Value<String?>? purchaseOrderNumber,
    Value<String?>? externalReference,
    Value<String>? tags,
    Value<String?>? notes,
    Value<int?>? estimatedDurationMinutes,
    Value<DateTime?>? scheduledCompletionDate,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<double?>? gpsLatitude,
    Value<double?>? gpsLongitude,
    Value<String?>? gpsAddress,
    Value<int>? rowid,
  }) {
    return JobsCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      clientId: clientId ?? this.clientId,
      contractorId: contractorId ?? this.contractorId,
      description: description ?? this.description,
      tradeType: tradeType ?? this.tradeType,
      status: status ?? this.status,
      statusHistory: statusHistory ?? this.statusHistory,
      priority: priority ?? this.priority,
      purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
      externalReference: externalReference ?? this.externalReference,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      scheduledCompletionDate:
          scheduledCompletionDate ?? this.scheduledCompletionDate,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      gpsLatitude: gpsLatitude ?? this.gpsLatitude,
      gpsLongitude: gpsLongitude ?? this.gpsLongitude,
      gpsAddress: gpsAddress ?? this.gpsAddress,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (contractorId.present) {
      map['contractor_id'] = Variable<String>(contractorId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (tradeType.present) {
      map['trade_type'] = Variable<String>(tradeType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (statusHistory.present) {
      map['status_history'] = Variable<String>(statusHistory.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (purchaseOrderNumber.present) {
      map['purchase_order_number'] = Variable<String>(
        purchaseOrderNumber.value,
      );
    }
    if (externalReference.present) {
      map['external_reference'] = Variable<String>(externalReference.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (estimatedDurationMinutes.present) {
      map['estimated_duration_minutes'] = Variable<int>(
        estimatedDurationMinutes.value,
      );
    }
    if (scheduledCompletionDate.present) {
      map['scheduled_completion_date'] = Variable<DateTime>(
        scheduledCompletionDate.value,
      );
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (gpsLatitude.present) {
      map['gps_latitude'] = Variable<double>(gpsLatitude.value);
    }
    if (gpsLongitude.present) {
      map['gps_longitude'] = Variable<double>(gpsLongitude.value);
    }
    if (gpsAddress.present) {
      map['gps_address'] = Variable<String>(gpsAddress.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobsCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('clientId: $clientId, ')
          ..write('contractorId: $contractorId, ')
          ..write('description: $description, ')
          ..write('tradeType: $tradeType, ')
          ..write('status: $status, ')
          ..write('statusHistory: $statusHistory, ')
          ..write('priority: $priority, ')
          ..write('purchaseOrderNumber: $purchaseOrderNumber, ')
          ..write('externalReference: $externalReference, ')
          ..write('tags: $tags, ')
          ..write('notes: $notes, ')
          ..write('estimatedDurationMinutes: $estimatedDurationMinutes, ')
          ..write('scheduledCompletionDate: $scheduledCompletionDate, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('gpsLatitude: $gpsLatitude, ')
          ..write('gpsLongitude: $gpsLongitude, ')
          ..write('gpsAddress: $gpsAddress, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientProfilesTable extends ClientProfiles
    with TableInfo<$ClientProfilesTable, ClientProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES companies (id)',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _billingAddressMeta = const VerificationMeta(
    'billingAddress',
  );
  @override
  late final GeneratedColumn<String> billingAddress = GeneratedColumn<String>(
    'billing_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _adminNotesMeta = const VerificationMeta(
    'adminNotes',
  );
  @override
  late final GeneratedColumn<String> adminNotes = GeneratedColumn<String>(
    'admin_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referralSourceMeta = const VerificationMeta(
    'referralSource',
  );
  @override
  late final GeneratedColumn<String> referralSource = GeneratedColumn<String>(
    'referral_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preferredContractorIdMeta =
      const VerificationMeta('preferredContractorId');
  @override
  late final GeneratedColumn<String> preferredContractorId =
      GeneratedColumn<String>(
        'preferred_contractor_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _preferredContactMethodMeta =
      const VerificationMeta('preferredContactMethod');
  @override
  late final GeneratedColumn<String> preferredContactMethod =
      GeneratedColumn<String>(
        'preferred_contact_method',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _averageRatingMeta = const VerificationMeta(
    'averageRating',
  );
  @override
  late final GeneratedColumn<double> averageRating = GeneratedColumn<double>(
    'average_rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    userId,
    billingAddress,
    tags,
    adminNotes,
    referralSource,
    preferredContractorId,
    preferredContactMethod,
    averageRating,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('billing_address')) {
      context.handle(
        _billingAddressMeta,
        billingAddress.isAcceptableOrUnknown(
          data['billing_address']!,
          _billingAddressMeta,
        ),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('admin_notes')) {
      context.handle(
        _adminNotesMeta,
        adminNotes.isAcceptableOrUnknown(data['admin_notes']!, _adminNotesMeta),
      );
    }
    if (data.containsKey('referral_source')) {
      context.handle(
        _referralSourceMeta,
        referralSource.isAcceptableOrUnknown(
          data['referral_source']!,
          _referralSourceMeta,
        ),
      );
    }
    if (data.containsKey('preferred_contractor_id')) {
      context.handle(
        _preferredContractorIdMeta,
        preferredContractorId.isAcceptableOrUnknown(
          data['preferred_contractor_id']!,
          _preferredContractorIdMeta,
        ),
      );
    }
    if (data.containsKey('preferred_contact_method')) {
      context.handle(
        _preferredContactMethodMeta,
        preferredContactMethod.isAcceptableOrUnknown(
          data['preferred_contact_method']!,
          _preferredContactMethodMeta,
        ),
      );
    }
    if (data.containsKey('average_rating')) {
      context.handle(
        _averageRatingMeta,
        averageRating.isAcceptableOrUnknown(
          data['average_rating']!,
          _averageRatingMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClientProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      billingAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}billing_address'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      adminNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}admin_notes'],
      ),
      referralSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}referral_source'],
      ),
      preferredContractorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferred_contractor_id'],
      ),
      preferredContactMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferred_contact_method'],
      ),
      averageRating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_rating'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ClientProfilesTable createAlias(String alias) {
    return $ClientProfilesTable(attachedDatabase, alias);
  }
}

class ClientProfile extends DataClass implements Insertable<ClientProfile> {
  final String id;
  final String companyId;

  /// FK to Users.id — the user who has the 'client' role.
  final String userId;

  /// Full billing address as a plain text block (street, city, state, postcode).
  final String? billingAddress;

  /// JSON-encoded list of string labels for client segmentation.
  final String tags;

  /// Internal admin notes not visible to the client.
  final String? adminNotes;

  /// How the client was referred to the company (e.g., 'word_of_mouth', 'google').
  final String? referralSource;

  /// FK to Users.id with contractor role — preferred contractor for this client.
  final String? preferredContractorId;

  /// Preferred contact method: 'email' | 'phone' | 'sms' | 'app'
  final String? preferredContactMethod;

  /// Cached average rating (1.0–5.0) from mutual ratings. Recomputed on sync.
  final double? averageRating;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete for sync tombstone propagation across devices.
  final DateTime? deletedAt;
  const ClientProfile({
    required this.id,
    required this.companyId,
    required this.userId,
    this.billingAddress,
    required this.tags,
    this.adminNotes,
    this.referralSource,
    this.preferredContractorId,
    this.preferredContactMethod,
    this.averageRating,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || billingAddress != null) {
      map['billing_address'] = Variable<String>(billingAddress);
    }
    map['tags'] = Variable<String>(tags);
    if (!nullToAbsent || adminNotes != null) {
      map['admin_notes'] = Variable<String>(adminNotes);
    }
    if (!nullToAbsent || referralSource != null) {
      map['referral_source'] = Variable<String>(referralSource);
    }
    if (!nullToAbsent || preferredContractorId != null) {
      map['preferred_contractor_id'] = Variable<String>(preferredContractorId);
    }
    if (!nullToAbsent || preferredContactMethod != null) {
      map['preferred_contact_method'] = Variable<String>(
        preferredContactMethod,
      );
    }
    if (!nullToAbsent || averageRating != null) {
      map['average_rating'] = Variable<double>(averageRating);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ClientProfilesCompanion toCompanion(bool nullToAbsent) {
    return ClientProfilesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      userId: Value(userId),
      billingAddress: billingAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(billingAddress),
      tags: Value(tags),
      adminNotes: adminNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(adminNotes),
      referralSource: referralSource == null && nullToAbsent
          ? const Value.absent()
          : Value(referralSource),
      preferredContractorId: preferredContractorId == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredContractorId),
      preferredContactMethod: preferredContactMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredContactMethod),
      averageRating: averageRating == null && nullToAbsent
          ? const Value.absent()
          : Value(averageRating),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ClientProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientProfile(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      userId: serializer.fromJson<String>(json['userId']),
      billingAddress: serializer.fromJson<String?>(json['billingAddress']),
      tags: serializer.fromJson<String>(json['tags']),
      adminNotes: serializer.fromJson<String?>(json['adminNotes']),
      referralSource: serializer.fromJson<String?>(json['referralSource']),
      preferredContractorId: serializer.fromJson<String?>(
        json['preferredContractorId'],
      ),
      preferredContactMethod: serializer.fromJson<String?>(
        json['preferredContactMethod'],
      ),
      averageRating: serializer.fromJson<double?>(json['averageRating']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'userId': serializer.toJson<String>(userId),
      'billingAddress': serializer.toJson<String?>(billingAddress),
      'tags': serializer.toJson<String>(tags),
      'adminNotes': serializer.toJson<String?>(adminNotes),
      'referralSource': serializer.toJson<String?>(referralSource),
      'preferredContractorId': serializer.toJson<String?>(
        preferredContractorId,
      ),
      'preferredContactMethod': serializer.toJson<String?>(
        preferredContactMethod,
      ),
      'averageRating': serializer.toJson<double?>(averageRating),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ClientProfile copyWith({
    String? id,
    String? companyId,
    String? userId,
    Value<String?> billingAddress = const Value.absent(),
    String? tags,
    Value<String?> adminNotes = const Value.absent(),
    Value<String?> referralSource = const Value.absent(),
    Value<String?> preferredContractorId = const Value.absent(),
    Value<String?> preferredContactMethod = const Value.absent(),
    Value<double?> averageRating = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ClientProfile(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    userId: userId ?? this.userId,
    billingAddress: billingAddress.present
        ? billingAddress.value
        : this.billingAddress,
    tags: tags ?? this.tags,
    adminNotes: adminNotes.present ? adminNotes.value : this.adminNotes,
    referralSource: referralSource.present
        ? referralSource.value
        : this.referralSource,
    preferredContractorId: preferredContractorId.present
        ? preferredContractorId.value
        : this.preferredContractorId,
    preferredContactMethod: preferredContactMethod.present
        ? preferredContactMethod.value
        : this.preferredContactMethod,
    averageRating: averageRating.present
        ? averageRating.value
        : this.averageRating,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ClientProfile copyWithCompanion(ClientProfilesCompanion data) {
    return ClientProfile(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      userId: data.userId.present ? data.userId.value : this.userId,
      billingAddress: data.billingAddress.present
          ? data.billingAddress.value
          : this.billingAddress,
      tags: data.tags.present ? data.tags.value : this.tags,
      adminNotes: data.adminNotes.present
          ? data.adminNotes.value
          : this.adminNotes,
      referralSource: data.referralSource.present
          ? data.referralSource.value
          : this.referralSource,
      preferredContractorId: data.preferredContractorId.present
          ? data.preferredContractorId.value
          : this.preferredContractorId,
      preferredContactMethod: data.preferredContactMethod.present
          ? data.preferredContactMethod.value
          : this.preferredContactMethod,
      averageRating: data.averageRating.present
          ? data.averageRating.value
          : this.averageRating,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientProfile(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('userId: $userId, ')
          ..write('billingAddress: $billingAddress, ')
          ..write('tags: $tags, ')
          ..write('adminNotes: $adminNotes, ')
          ..write('referralSource: $referralSource, ')
          ..write('preferredContractorId: $preferredContractorId, ')
          ..write('preferredContactMethod: $preferredContactMethod, ')
          ..write('averageRating: $averageRating, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    userId,
    billingAddress,
    tags,
    adminNotes,
    referralSource,
    preferredContractorId,
    preferredContactMethod,
    averageRating,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientProfile &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.userId == this.userId &&
          other.billingAddress == this.billingAddress &&
          other.tags == this.tags &&
          other.adminNotes == this.adminNotes &&
          other.referralSource == this.referralSource &&
          other.preferredContractorId == this.preferredContractorId &&
          other.preferredContactMethod == this.preferredContactMethod &&
          other.averageRating == this.averageRating &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ClientProfilesCompanion extends UpdateCompanion<ClientProfile> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> userId;
  final Value<String?> billingAddress;
  final Value<String> tags;
  final Value<String?> adminNotes;
  final Value<String?> referralSource;
  final Value<String?> preferredContractorId;
  final Value<String?> preferredContactMethod;
  final Value<double?> averageRating;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ClientProfilesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.userId = const Value.absent(),
    this.billingAddress = const Value.absent(),
    this.tags = const Value.absent(),
    this.adminNotes = const Value.absent(),
    this.referralSource = const Value.absent(),
    this.preferredContractorId = const Value.absent(),
    this.preferredContactMethod = const Value.absent(),
    this.averageRating = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String userId,
    this.billingAddress = const Value.absent(),
    this.tags = const Value.absent(),
    this.adminNotes = const Value.absent(),
    this.referralSource = const Value.absent(),
    this.preferredContractorId = const Value.absent(),
    this.preferredContactMethod = const Value.absent(),
    this.averageRating = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       userId = Value(userId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ClientProfile> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? userId,
    Expression<String>? billingAddress,
    Expression<String>? tags,
    Expression<String>? adminNotes,
    Expression<String>? referralSource,
    Expression<String>? preferredContractorId,
    Expression<String>? preferredContactMethod,
    Expression<double>? averageRating,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (userId != null) 'user_id': userId,
      if (billingAddress != null) 'billing_address': billingAddress,
      if (tags != null) 'tags': tags,
      if (adminNotes != null) 'admin_notes': adminNotes,
      if (referralSource != null) 'referral_source': referralSource,
      if (preferredContractorId != null)
        'preferred_contractor_id': preferredContractorId,
      if (preferredContactMethod != null)
        'preferred_contact_method': preferredContactMethod,
      if (averageRating != null) 'average_rating': averageRating,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? userId,
    Value<String?>? billingAddress,
    Value<String>? tags,
    Value<String?>? adminNotes,
    Value<String?>? referralSource,
    Value<String?>? preferredContractorId,
    Value<String?>? preferredContactMethod,
    Value<double?>? averageRating,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ClientProfilesCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      userId: userId ?? this.userId,
      billingAddress: billingAddress ?? this.billingAddress,
      tags: tags ?? this.tags,
      adminNotes: adminNotes ?? this.adminNotes,
      referralSource: referralSource ?? this.referralSource,
      preferredContractorId:
          preferredContractorId ?? this.preferredContractorId,
      preferredContactMethod:
          preferredContactMethod ?? this.preferredContactMethod,
      averageRating: averageRating ?? this.averageRating,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (billingAddress.present) {
      map['billing_address'] = Variable<String>(billingAddress.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (adminNotes.present) {
      map['admin_notes'] = Variable<String>(adminNotes.value);
    }
    if (referralSource.present) {
      map['referral_source'] = Variable<String>(referralSource.value);
    }
    if (preferredContractorId.present) {
      map['preferred_contractor_id'] = Variable<String>(
        preferredContractorId.value,
      );
    }
    if (preferredContactMethod.present) {
      map['preferred_contact_method'] = Variable<String>(
        preferredContactMethod.value,
      );
    }
    if (averageRating.present) {
      map['average_rating'] = Variable<double>(averageRating.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientProfilesCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('userId: $userId, ')
          ..write('billingAddress: $billingAddress, ')
          ..write('tags: $tags, ')
          ..write('adminNotes: $adminNotes, ')
          ..write('referralSource: $referralSource, ')
          ..write('preferredContractorId: $preferredContractorId, ')
          ..write('preferredContactMethod: $preferredContactMethod, ')
          ..write('averageRating: $averageRating, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientPropertiesTable extends ClientProperties
    with TableInfo<$ClientPropertiesTable, ClientProperty> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientPropertiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES companies (id)',
    ),
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobSiteIdMeta = const VerificationMeta(
    'jobSiteId',
  );
  @override
  late final GeneratedColumn<String> jobSiteId = GeneratedColumn<String>(
    'job_site_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    clientId,
    jobSiteId,
    nickname,
    isDefault,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_properties';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientProperty> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('job_site_id')) {
      context.handle(
        _jobSiteIdMeta,
        jobSiteId.isAcceptableOrUnknown(data['job_site_id']!, _jobSiteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobSiteIdMeta);
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClientProperty map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientProperty(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      jobSiteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_site_id'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ClientPropertiesTable createAlias(String alias) {
    return $ClientPropertiesTable(attachedDatabase, alias);
  }
}

class ClientProperty extends DataClass implements Insertable<ClientProperty> {
  final String id;
  final String companyId;

  /// FK to the client (Users.id with client role).
  final String clientId;

  /// UUID of the corresponding JobSite record (Phase 3 scheduling engine).
  /// Stored as plain text — JobSite table is not present in mobile Drift schema.
  final String jobSiteId;

  /// User-friendly label for this saved address (e.g., 'Home', 'Office').
  final String? nickname;

  /// Whether this is the client's primary/default property.
  final bool isDefault;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete for sync tombstone propagation across devices.
  final DateTime? deletedAt;
  const ClientProperty({
    required this.id,
    required this.companyId,
    required this.clientId,
    required this.jobSiteId,
    this.nickname,
    required this.isDefault,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['client_id'] = Variable<String>(clientId);
    map['job_site_id'] = Variable<String>(jobSiteId);
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    map['is_default'] = Variable<bool>(isDefault);
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ClientPropertiesCompanion toCompanion(bool nullToAbsent) {
    return ClientPropertiesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      clientId: Value(clientId),
      jobSiteId: Value(jobSiteId),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      isDefault: Value(isDefault),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ClientProperty.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientProperty(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      clientId: serializer.fromJson<String>(json['clientId']),
      jobSiteId: serializer.fromJson<String>(json['jobSiteId']),
      nickname: serializer.fromJson<String?>(json['nickname']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'clientId': serializer.toJson<String>(clientId),
      'jobSiteId': serializer.toJson<String>(jobSiteId),
      'nickname': serializer.toJson<String?>(nickname),
      'isDefault': serializer.toJson<bool>(isDefault),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ClientProperty copyWith({
    String? id,
    String? companyId,
    String? clientId,
    String? jobSiteId,
    Value<String?> nickname = const Value.absent(),
    bool? isDefault,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ClientProperty(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    clientId: clientId ?? this.clientId,
    jobSiteId: jobSiteId ?? this.jobSiteId,
    nickname: nickname.present ? nickname.value : this.nickname,
    isDefault: isDefault ?? this.isDefault,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ClientProperty copyWithCompanion(ClientPropertiesCompanion data) {
    return ClientProperty(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      jobSiteId: data.jobSiteId.present ? data.jobSiteId.value : this.jobSiteId,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientProperty(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('clientId: $clientId, ')
          ..write('jobSiteId: $jobSiteId, ')
          ..write('nickname: $nickname, ')
          ..write('isDefault: $isDefault, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    clientId,
    jobSiteId,
    nickname,
    isDefault,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientProperty &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.clientId == this.clientId &&
          other.jobSiteId == this.jobSiteId &&
          other.nickname == this.nickname &&
          other.isDefault == this.isDefault &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ClientPropertiesCompanion extends UpdateCompanion<ClientProperty> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> clientId;
  final Value<String> jobSiteId;
  final Value<String?> nickname;
  final Value<bool> isDefault;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ClientPropertiesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.jobSiteId = const Value.absent(),
    this.nickname = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientPropertiesCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String clientId,
    required String jobSiteId,
    this.nickname = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       clientId = Value(clientId),
       jobSiteId = Value(jobSiteId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ClientProperty> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? clientId,
    Expression<String>? jobSiteId,
    Expression<String>? nickname,
    Expression<bool>? isDefault,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (clientId != null) 'client_id': clientId,
      if (jobSiteId != null) 'job_site_id': jobSiteId,
      if (nickname != null) 'nickname': nickname,
      if (isDefault != null) 'is_default': isDefault,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientPropertiesCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? clientId,
    Value<String>? jobSiteId,
    Value<String?>? nickname,
    Value<bool>? isDefault,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ClientPropertiesCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      clientId: clientId ?? this.clientId,
      jobSiteId: jobSiteId ?? this.jobSiteId,
      nickname: nickname ?? this.nickname,
      isDefault: isDefault ?? this.isDefault,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (jobSiteId.present) {
      map['job_site_id'] = Variable<String>(jobSiteId.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientPropertiesCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('clientId: $clientId, ')
          ..write('jobSiteId: $jobSiteId, ')
          ..write('nickname: $nickname, ')
          ..write('isDefault: $isDefault, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JobRequestsTable extends JobRequests
    with TableInfo<$JobRequestsTable, JobRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES companies (id)',
    ),
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tradeTypeMeta = const VerificationMeta(
    'tradeType',
  );
  @override
  late final GeneratedColumn<String> tradeType = GeneratedColumn<String>(
    'trade_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urgencyMeta = const VerificationMeta(
    'urgency',
  );
  @override
  late final GeneratedColumn<String> urgency = GeneratedColumn<String>(
    'urgency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('normal'),
  );
  static const VerificationMeta _preferredDateStartMeta =
      const VerificationMeta('preferredDateStart');
  @override
  late final GeneratedColumn<DateTime> preferredDateStart =
      GeneratedColumn<DateTime>(
        'preferred_date_start',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _preferredDateEndMeta = const VerificationMeta(
    'preferredDateEnd',
  );
  @override
  late final GeneratedColumn<DateTime> preferredDateEnd =
      GeneratedColumn<DateTime>(
        'preferred_date_end',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _budgetMinMeta = const VerificationMeta(
    'budgetMin',
  );
  @override
  late final GeneratedColumn<double> budgetMin = GeneratedColumn<double>(
    'budget_min',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _budgetMaxMeta = const VerificationMeta(
    'budgetMax',
  );
  @override
  late final GeneratedColumn<double> budgetMax = GeneratedColumn<double>(
    'budget_max',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photosMeta = const VerificationMeta('photos');
  @override
  late final GeneratedColumn<String> photos = GeneratedColumn<String>(
    'photos',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _requestStatusMeta = const VerificationMeta(
    'requestStatus',
  );
  @override
  late final GeneratedColumn<String> requestStatus = GeneratedColumn<String>(
    'request_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _declineReasonMeta = const VerificationMeta(
    'declineReason',
  );
  @override
  late final GeneratedColumn<String> declineReason = GeneratedColumn<String>(
    'decline_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _declineMessageMeta = const VerificationMeta(
    'declineMessage',
  );
  @override
  late final GeneratedColumn<String> declineMessage = GeneratedColumn<String>(
    'decline_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _convertedJobIdMeta = const VerificationMeta(
    'convertedJobId',
  );
  @override
  late final GeneratedColumn<String> convertedJobId = GeneratedColumn<String>(
    'converted_job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _submittedNameMeta = const VerificationMeta(
    'submittedName',
  );
  @override
  late final GeneratedColumn<String> submittedName = GeneratedColumn<String>(
    'submitted_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _submittedEmailMeta = const VerificationMeta(
    'submittedEmail',
  );
  @override
  late final GeneratedColumn<String> submittedEmail = GeneratedColumn<String>(
    'submitted_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _submittedPhoneMeta = const VerificationMeta(
    'submittedPhone',
  );
  @override
  late final GeneratedColumn<String> submittedPhone = GeneratedColumn<String>(
    'submitted_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    clientId,
    description,
    tradeType,
    urgency,
    preferredDateStart,
    preferredDateEnd,
    budgetMin,
    budgetMax,
    photos,
    requestStatus,
    declineReason,
    declineMessage,
    convertedJobId,
    submittedName,
    submittedEmail,
    submittedPhone,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'job_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<JobRequest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('trade_type')) {
      context.handle(
        _tradeTypeMeta,
        tradeType.isAcceptableOrUnknown(data['trade_type']!, _tradeTypeMeta),
      );
    }
    if (data.containsKey('urgency')) {
      context.handle(
        _urgencyMeta,
        urgency.isAcceptableOrUnknown(data['urgency']!, _urgencyMeta),
      );
    }
    if (data.containsKey('preferred_date_start')) {
      context.handle(
        _preferredDateStartMeta,
        preferredDateStart.isAcceptableOrUnknown(
          data['preferred_date_start']!,
          _preferredDateStartMeta,
        ),
      );
    }
    if (data.containsKey('preferred_date_end')) {
      context.handle(
        _preferredDateEndMeta,
        preferredDateEnd.isAcceptableOrUnknown(
          data['preferred_date_end']!,
          _preferredDateEndMeta,
        ),
      );
    }
    if (data.containsKey('budget_min')) {
      context.handle(
        _budgetMinMeta,
        budgetMin.isAcceptableOrUnknown(data['budget_min']!, _budgetMinMeta),
      );
    }
    if (data.containsKey('budget_max')) {
      context.handle(
        _budgetMaxMeta,
        budgetMax.isAcceptableOrUnknown(data['budget_max']!, _budgetMaxMeta),
      );
    }
    if (data.containsKey('photos')) {
      context.handle(
        _photosMeta,
        photos.isAcceptableOrUnknown(data['photos']!, _photosMeta),
      );
    }
    if (data.containsKey('request_status')) {
      context.handle(
        _requestStatusMeta,
        requestStatus.isAcceptableOrUnknown(
          data['request_status']!,
          _requestStatusMeta,
        ),
      );
    }
    if (data.containsKey('decline_reason')) {
      context.handle(
        _declineReasonMeta,
        declineReason.isAcceptableOrUnknown(
          data['decline_reason']!,
          _declineReasonMeta,
        ),
      );
    }
    if (data.containsKey('decline_message')) {
      context.handle(
        _declineMessageMeta,
        declineMessage.isAcceptableOrUnknown(
          data['decline_message']!,
          _declineMessageMeta,
        ),
      );
    }
    if (data.containsKey('converted_job_id')) {
      context.handle(
        _convertedJobIdMeta,
        convertedJobId.isAcceptableOrUnknown(
          data['converted_job_id']!,
          _convertedJobIdMeta,
        ),
      );
    }
    if (data.containsKey('submitted_name')) {
      context.handle(
        _submittedNameMeta,
        submittedName.isAcceptableOrUnknown(
          data['submitted_name']!,
          _submittedNameMeta,
        ),
      );
    }
    if (data.containsKey('submitted_email')) {
      context.handle(
        _submittedEmailMeta,
        submittedEmail.isAcceptableOrUnknown(
          data['submitted_email']!,
          _submittedEmailMeta,
        ),
      );
    }
    if (data.containsKey('submitted_phone')) {
      context.handle(
        _submittedPhoneMeta,
        submittedPhone.isAcceptableOrUnknown(
          data['submitted_phone']!,
          _submittedPhoneMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JobRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JobRequest(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      tradeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trade_type'],
      ),
      urgency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}urgency'],
      )!,
      preferredDateStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}preferred_date_start'],
      ),
      preferredDateEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}preferred_date_end'],
      ),
      budgetMin: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}budget_min'],
      ),
      budgetMax: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}budget_max'],
      ),
      photos: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photos'],
      )!,
      requestStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_status'],
      )!,
      declineReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decline_reason'],
      ),
      declineMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decline_message'],
      ),
      convertedJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}converted_job_id'],
      ),
      submittedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}submitted_name'],
      ),
      submittedEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}submitted_email'],
      ),
      submittedPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}submitted_phone'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $JobRequestsTable createAlias(String alias) {
    return $JobRequestsTable(attachedDatabase, alias);
  }
}

class JobRequest extends DataClass implements Insertable<JobRequest> {
  final String id;
  final String companyId;

  /// FK to Users.id (client role). Null for anonymous web form submissions
  /// until a User account is created/matched on the backend.
  final String? clientId;
  final String description;

  /// Requested trade type (may be null if client is unsure).
  final String? tradeType;

  /// Urgency level: normal | urgent | emergency
  final String urgency;
  final DateTime? preferredDateStart;
  final DateTime? preferredDateEnd;
  final double? budgetMin;
  final double? budgetMax;

  /// JSON-encoded list of photo file paths or URLs (1–5 photos).
  final String photos;

  /// Request status: pending | accepted | declined
  final String requestStatus;

  /// Short reason code for decline (required when status = 'declined').
  final String? declineReason;

  /// Optional longer decline message shown to the client.
  final String? declineMessage;

  /// UUID of the Job created when this request is accepted. Null until accepted.
  final String? convertedJobId;
  final String? submittedName;
  final String? submittedEmail;
  final String? submittedPhone;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete for sync tombstone propagation across devices.
  final DateTime? deletedAt;
  const JobRequest({
    required this.id,
    required this.companyId,
    this.clientId,
    required this.description,
    this.tradeType,
    required this.urgency,
    this.preferredDateStart,
    this.preferredDateEnd,
    this.budgetMin,
    this.budgetMax,
    required this.photos,
    required this.requestStatus,
    this.declineReason,
    this.declineMessage,
    this.convertedJobId,
    this.submittedName,
    this.submittedEmail,
    this.submittedPhone,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    if (!nullToAbsent || clientId != null) {
      map['client_id'] = Variable<String>(clientId);
    }
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || tradeType != null) {
      map['trade_type'] = Variable<String>(tradeType);
    }
    map['urgency'] = Variable<String>(urgency);
    if (!nullToAbsent || preferredDateStart != null) {
      map['preferred_date_start'] = Variable<DateTime>(preferredDateStart);
    }
    if (!nullToAbsent || preferredDateEnd != null) {
      map['preferred_date_end'] = Variable<DateTime>(preferredDateEnd);
    }
    if (!nullToAbsent || budgetMin != null) {
      map['budget_min'] = Variable<double>(budgetMin);
    }
    if (!nullToAbsent || budgetMax != null) {
      map['budget_max'] = Variable<double>(budgetMax);
    }
    map['photos'] = Variable<String>(photos);
    map['request_status'] = Variable<String>(requestStatus);
    if (!nullToAbsent || declineReason != null) {
      map['decline_reason'] = Variable<String>(declineReason);
    }
    if (!nullToAbsent || declineMessage != null) {
      map['decline_message'] = Variable<String>(declineMessage);
    }
    if (!nullToAbsent || convertedJobId != null) {
      map['converted_job_id'] = Variable<String>(convertedJobId);
    }
    if (!nullToAbsent || submittedName != null) {
      map['submitted_name'] = Variable<String>(submittedName);
    }
    if (!nullToAbsent || submittedEmail != null) {
      map['submitted_email'] = Variable<String>(submittedEmail);
    }
    if (!nullToAbsent || submittedPhone != null) {
      map['submitted_phone'] = Variable<String>(submittedPhone);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  JobRequestsCompanion toCompanion(bool nullToAbsent) {
    return JobRequestsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      clientId: clientId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientId),
      description: Value(description),
      tradeType: tradeType == null && nullToAbsent
          ? const Value.absent()
          : Value(tradeType),
      urgency: Value(urgency),
      preferredDateStart: preferredDateStart == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredDateStart),
      preferredDateEnd: preferredDateEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredDateEnd),
      budgetMin: budgetMin == null && nullToAbsent
          ? const Value.absent()
          : Value(budgetMin),
      budgetMax: budgetMax == null && nullToAbsent
          ? const Value.absent()
          : Value(budgetMax),
      photos: Value(photos),
      requestStatus: Value(requestStatus),
      declineReason: declineReason == null && nullToAbsent
          ? const Value.absent()
          : Value(declineReason),
      declineMessage: declineMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(declineMessage),
      convertedJobId: convertedJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(convertedJobId),
      submittedName: submittedName == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedName),
      submittedEmail: submittedEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedEmail),
      submittedPhone: submittedPhone == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedPhone),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory JobRequest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JobRequest(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      clientId: serializer.fromJson<String?>(json['clientId']),
      description: serializer.fromJson<String>(json['description']),
      tradeType: serializer.fromJson<String?>(json['tradeType']),
      urgency: serializer.fromJson<String>(json['urgency']),
      preferredDateStart: serializer.fromJson<DateTime?>(
        json['preferredDateStart'],
      ),
      preferredDateEnd: serializer.fromJson<DateTime?>(
        json['preferredDateEnd'],
      ),
      budgetMin: serializer.fromJson<double?>(json['budgetMin']),
      budgetMax: serializer.fromJson<double?>(json['budgetMax']),
      photos: serializer.fromJson<String>(json['photos']),
      requestStatus: serializer.fromJson<String>(json['requestStatus']),
      declineReason: serializer.fromJson<String?>(json['declineReason']),
      declineMessage: serializer.fromJson<String?>(json['declineMessage']),
      convertedJobId: serializer.fromJson<String?>(json['convertedJobId']),
      submittedName: serializer.fromJson<String?>(json['submittedName']),
      submittedEmail: serializer.fromJson<String?>(json['submittedEmail']),
      submittedPhone: serializer.fromJson<String?>(json['submittedPhone']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'clientId': serializer.toJson<String?>(clientId),
      'description': serializer.toJson<String>(description),
      'tradeType': serializer.toJson<String?>(tradeType),
      'urgency': serializer.toJson<String>(urgency),
      'preferredDateStart': serializer.toJson<DateTime?>(preferredDateStart),
      'preferredDateEnd': serializer.toJson<DateTime?>(preferredDateEnd),
      'budgetMin': serializer.toJson<double?>(budgetMin),
      'budgetMax': serializer.toJson<double?>(budgetMax),
      'photos': serializer.toJson<String>(photos),
      'requestStatus': serializer.toJson<String>(requestStatus),
      'declineReason': serializer.toJson<String?>(declineReason),
      'declineMessage': serializer.toJson<String?>(declineMessage),
      'convertedJobId': serializer.toJson<String?>(convertedJobId),
      'submittedName': serializer.toJson<String?>(submittedName),
      'submittedEmail': serializer.toJson<String?>(submittedEmail),
      'submittedPhone': serializer.toJson<String?>(submittedPhone),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  JobRequest copyWith({
    String? id,
    String? companyId,
    Value<String?> clientId = const Value.absent(),
    String? description,
    Value<String?> tradeType = const Value.absent(),
    String? urgency,
    Value<DateTime?> preferredDateStart = const Value.absent(),
    Value<DateTime?> preferredDateEnd = const Value.absent(),
    Value<double?> budgetMin = const Value.absent(),
    Value<double?> budgetMax = const Value.absent(),
    String? photos,
    String? requestStatus,
    Value<String?> declineReason = const Value.absent(),
    Value<String?> declineMessage = const Value.absent(),
    Value<String?> convertedJobId = const Value.absent(),
    Value<String?> submittedName = const Value.absent(),
    Value<String?> submittedEmail = const Value.absent(),
    Value<String?> submittedPhone = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => JobRequest(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    clientId: clientId.present ? clientId.value : this.clientId,
    description: description ?? this.description,
    tradeType: tradeType.present ? tradeType.value : this.tradeType,
    urgency: urgency ?? this.urgency,
    preferredDateStart: preferredDateStart.present
        ? preferredDateStart.value
        : this.preferredDateStart,
    preferredDateEnd: preferredDateEnd.present
        ? preferredDateEnd.value
        : this.preferredDateEnd,
    budgetMin: budgetMin.present ? budgetMin.value : this.budgetMin,
    budgetMax: budgetMax.present ? budgetMax.value : this.budgetMax,
    photos: photos ?? this.photos,
    requestStatus: requestStatus ?? this.requestStatus,
    declineReason: declineReason.present
        ? declineReason.value
        : this.declineReason,
    declineMessage: declineMessage.present
        ? declineMessage.value
        : this.declineMessage,
    convertedJobId: convertedJobId.present
        ? convertedJobId.value
        : this.convertedJobId,
    submittedName: submittedName.present
        ? submittedName.value
        : this.submittedName,
    submittedEmail: submittedEmail.present
        ? submittedEmail.value
        : this.submittedEmail,
    submittedPhone: submittedPhone.present
        ? submittedPhone.value
        : this.submittedPhone,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  JobRequest copyWithCompanion(JobRequestsCompanion data) {
    return JobRequest(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      description: data.description.present
          ? data.description.value
          : this.description,
      tradeType: data.tradeType.present ? data.tradeType.value : this.tradeType,
      urgency: data.urgency.present ? data.urgency.value : this.urgency,
      preferredDateStart: data.preferredDateStart.present
          ? data.preferredDateStart.value
          : this.preferredDateStart,
      preferredDateEnd: data.preferredDateEnd.present
          ? data.preferredDateEnd.value
          : this.preferredDateEnd,
      budgetMin: data.budgetMin.present ? data.budgetMin.value : this.budgetMin,
      budgetMax: data.budgetMax.present ? data.budgetMax.value : this.budgetMax,
      photos: data.photos.present ? data.photos.value : this.photos,
      requestStatus: data.requestStatus.present
          ? data.requestStatus.value
          : this.requestStatus,
      declineReason: data.declineReason.present
          ? data.declineReason.value
          : this.declineReason,
      declineMessage: data.declineMessage.present
          ? data.declineMessage.value
          : this.declineMessage,
      convertedJobId: data.convertedJobId.present
          ? data.convertedJobId.value
          : this.convertedJobId,
      submittedName: data.submittedName.present
          ? data.submittedName.value
          : this.submittedName,
      submittedEmail: data.submittedEmail.present
          ? data.submittedEmail.value
          : this.submittedEmail,
      submittedPhone: data.submittedPhone.present
          ? data.submittedPhone.value
          : this.submittedPhone,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JobRequest(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('clientId: $clientId, ')
          ..write('description: $description, ')
          ..write('tradeType: $tradeType, ')
          ..write('urgency: $urgency, ')
          ..write('preferredDateStart: $preferredDateStart, ')
          ..write('preferredDateEnd: $preferredDateEnd, ')
          ..write('budgetMin: $budgetMin, ')
          ..write('budgetMax: $budgetMax, ')
          ..write('photos: $photos, ')
          ..write('requestStatus: $requestStatus, ')
          ..write('declineReason: $declineReason, ')
          ..write('declineMessage: $declineMessage, ')
          ..write('convertedJobId: $convertedJobId, ')
          ..write('submittedName: $submittedName, ')
          ..write('submittedEmail: $submittedEmail, ')
          ..write('submittedPhone: $submittedPhone, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    companyId,
    clientId,
    description,
    tradeType,
    urgency,
    preferredDateStart,
    preferredDateEnd,
    budgetMin,
    budgetMax,
    photos,
    requestStatus,
    declineReason,
    declineMessage,
    convertedJobId,
    submittedName,
    submittedEmail,
    submittedPhone,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobRequest &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.clientId == this.clientId &&
          other.description == this.description &&
          other.tradeType == this.tradeType &&
          other.urgency == this.urgency &&
          other.preferredDateStart == this.preferredDateStart &&
          other.preferredDateEnd == this.preferredDateEnd &&
          other.budgetMin == this.budgetMin &&
          other.budgetMax == this.budgetMax &&
          other.photos == this.photos &&
          other.requestStatus == this.requestStatus &&
          other.declineReason == this.declineReason &&
          other.declineMessage == this.declineMessage &&
          other.convertedJobId == this.convertedJobId &&
          other.submittedName == this.submittedName &&
          other.submittedEmail == this.submittedEmail &&
          other.submittedPhone == this.submittedPhone &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class JobRequestsCompanion extends UpdateCompanion<JobRequest> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String?> clientId;
  final Value<String> description;
  final Value<String?> tradeType;
  final Value<String> urgency;
  final Value<DateTime?> preferredDateStart;
  final Value<DateTime?> preferredDateEnd;
  final Value<double?> budgetMin;
  final Value<double?> budgetMax;
  final Value<String> photos;
  final Value<String> requestStatus;
  final Value<String?> declineReason;
  final Value<String?> declineMessage;
  final Value<String?> convertedJobId;
  final Value<String?> submittedName;
  final Value<String?> submittedEmail;
  final Value<String?> submittedPhone;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const JobRequestsCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.description = const Value.absent(),
    this.tradeType = const Value.absent(),
    this.urgency = const Value.absent(),
    this.preferredDateStart = const Value.absent(),
    this.preferredDateEnd = const Value.absent(),
    this.budgetMin = const Value.absent(),
    this.budgetMax = const Value.absent(),
    this.photos = const Value.absent(),
    this.requestStatus = const Value.absent(),
    this.declineReason = const Value.absent(),
    this.declineMessage = const Value.absent(),
    this.convertedJobId = const Value.absent(),
    this.submittedName = const Value.absent(),
    this.submittedEmail = const Value.absent(),
    this.submittedPhone = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JobRequestsCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    this.clientId = const Value.absent(),
    required String description,
    this.tradeType = const Value.absent(),
    this.urgency = const Value.absent(),
    this.preferredDateStart = const Value.absent(),
    this.preferredDateEnd = const Value.absent(),
    this.budgetMin = const Value.absent(),
    this.budgetMax = const Value.absent(),
    this.photos = const Value.absent(),
    this.requestStatus = const Value.absent(),
    this.declineReason = const Value.absent(),
    this.declineMessage = const Value.absent(),
    this.convertedJobId = const Value.absent(),
    this.submittedName = const Value.absent(),
    this.submittedEmail = const Value.absent(),
    this.submittedPhone = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       description = Value(description),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<JobRequest> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? clientId,
    Expression<String>? description,
    Expression<String>? tradeType,
    Expression<String>? urgency,
    Expression<DateTime>? preferredDateStart,
    Expression<DateTime>? preferredDateEnd,
    Expression<double>? budgetMin,
    Expression<double>? budgetMax,
    Expression<String>? photos,
    Expression<String>? requestStatus,
    Expression<String>? declineReason,
    Expression<String>? declineMessage,
    Expression<String>? convertedJobId,
    Expression<String>? submittedName,
    Expression<String>? submittedEmail,
    Expression<String>? submittedPhone,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (clientId != null) 'client_id': clientId,
      if (description != null) 'description': description,
      if (tradeType != null) 'trade_type': tradeType,
      if (urgency != null) 'urgency': urgency,
      if (preferredDateStart != null)
        'preferred_date_start': preferredDateStart,
      if (preferredDateEnd != null) 'preferred_date_end': preferredDateEnd,
      if (budgetMin != null) 'budget_min': budgetMin,
      if (budgetMax != null) 'budget_max': budgetMax,
      if (photos != null) 'photos': photos,
      if (requestStatus != null) 'request_status': requestStatus,
      if (declineReason != null) 'decline_reason': declineReason,
      if (declineMessage != null) 'decline_message': declineMessage,
      if (convertedJobId != null) 'converted_job_id': convertedJobId,
      if (submittedName != null) 'submitted_name': submittedName,
      if (submittedEmail != null) 'submitted_email': submittedEmail,
      if (submittedPhone != null) 'submitted_phone': submittedPhone,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JobRequestsCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String?>? clientId,
    Value<String>? description,
    Value<String?>? tradeType,
    Value<String>? urgency,
    Value<DateTime?>? preferredDateStart,
    Value<DateTime?>? preferredDateEnd,
    Value<double?>? budgetMin,
    Value<double?>? budgetMax,
    Value<String>? photos,
    Value<String>? requestStatus,
    Value<String?>? declineReason,
    Value<String?>? declineMessage,
    Value<String?>? convertedJobId,
    Value<String?>? submittedName,
    Value<String?>? submittedEmail,
    Value<String?>? submittedPhone,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return JobRequestsCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      clientId: clientId ?? this.clientId,
      description: description ?? this.description,
      tradeType: tradeType ?? this.tradeType,
      urgency: urgency ?? this.urgency,
      preferredDateStart: preferredDateStart ?? this.preferredDateStart,
      preferredDateEnd: preferredDateEnd ?? this.preferredDateEnd,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      photos: photos ?? this.photos,
      requestStatus: requestStatus ?? this.requestStatus,
      declineReason: declineReason ?? this.declineReason,
      declineMessage: declineMessage ?? this.declineMessage,
      convertedJobId: convertedJobId ?? this.convertedJobId,
      submittedName: submittedName ?? this.submittedName,
      submittedEmail: submittedEmail ?? this.submittedEmail,
      submittedPhone: submittedPhone ?? this.submittedPhone,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (tradeType.present) {
      map['trade_type'] = Variable<String>(tradeType.value);
    }
    if (urgency.present) {
      map['urgency'] = Variable<String>(urgency.value);
    }
    if (preferredDateStart.present) {
      map['preferred_date_start'] = Variable<DateTime>(
        preferredDateStart.value,
      );
    }
    if (preferredDateEnd.present) {
      map['preferred_date_end'] = Variable<DateTime>(preferredDateEnd.value);
    }
    if (budgetMin.present) {
      map['budget_min'] = Variable<double>(budgetMin.value);
    }
    if (budgetMax.present) {
      map['budget_max'] = Variable<double>(budgetMax.value);
    }
    if (photos.present) {
      map['photos'] = Variable<String>(photos.value);
    }
    if (requestStatus.present) {
      map['request_status'] = Variable<String>(requestStatus.value);
    }
    if (declineReason.present) {
      map['decline_reason'] = Variable<String>(declineReason.value);
    }
    if (declineMessage.present) {
      map['decline_message'] = Variable<String>(declineMessage.value);
    }
    if (convertedJobId.present) {
      map['converted_job_id'] = Variable<String>(convertedJobId.value);
    }
    if (submittedName.present) {
      map['submitted_name'] = Variable<String>(submittedName.value);
    }
    if (submittedEmail.present) {
      map['submitted_email'] = Variable<String>(submittedEmail.value);
    }
    if (submittedPhone.present) {
      map['submitted_phone'] = Variable<String>(submittedPhone.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobRequestsCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('clientId: $clientId, ')
          ..write('description: $description, ')
          ..write('tradeType: $tradeType, ')
          ..write('urgency: $urgency, ')
          ..write('preferredDateStart: $preferredDateStart, ')
          ..write('preferredDateEnd: $preferredDateEnd, ')
          ..write('budgetMin: $budgetMin, ')
          ..write('budgetMax: $budgetMax, ')
          ..write('photos: $photos, ')
          ..write('requestStatus: $requestStatus, ')
          ..write('declineReason: $declineReason, ')
          ..write('declineMessage: $declineMessage, ')
          ..write('convertedJobId: $convertedJobId, ')
          ..write('submittedName: $submittedName, ')
          ..write('submittedEmail: $submittedEmail, ')
          ..write('submittedPhone: $submittedPhone, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookingsTable extends Bookings with TableInfo<$BookingsTable, Booking> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contractorIdMeta = const VerificationMeta(
    'contractorId',
  );
  @override
  late final GeneratedColumn<String> contractorId = GeneratedColumn<String>(
    'contractor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobSiteIdMeta = const VerificationMeta(
    'jobSiteId',
  );
  @override
  late final GeneratedColumn<String> jobSiteId = GeneratedColumn<String>(
    'job_site_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeRangeStartMeta = const VerificationMeta(
    'timeRangeStart',
  );
  @override
  late final GeneratedColumn<DateTime> timeRangeStart =
      GeneratedColumn<DateTime>(
        'time_range_start',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _timeRangeEndMeta = const VerificationMeta(
    'timeRangeEnd',
  );
  @override
  late final GeneratedColumn<DateTime> timeRangeEnd = GeneratedColumn<DateTime>(
    'time_range_end',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayIndexMeta = const VerificationMeta(
    'dayIndex',
  );
  @override
  late final GeneratedColumn<int> dayIndex = GeneratedColumn<int>(
    'day_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentBookingIdMeta = const VerificationMeta(
    'parentBookingId',
  );
  @override
  late final GeneratedColumn<String> parentBookingId = GeneratedColumn<String>(
    'parent_booking_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    contractorId,
    jobId,
    jobSiteId,
    timeRangeStart,
    timeRangeEnd,
    dayIndex,
    parentBookingId,
    notes,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Booking> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('contractor_id')) {
      context.handle(
        _contractorIdMeta,
        contractorId.isAcceptableOrUnknown(
          data['contractor_id']!,
          _contractorIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contractorIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('job_site_id')) {
      context.handle(
        _jobSiteIdMeta,
        jobSiteId.isAcceptableOrUnknown(data['job_site_id']!, _jobSiteIdMeta),
      );
    }
    if (data.containsKey('time_range_start')) {
      context.handle(
        _timeRangeStartMeta,
        timeRangeStart.isAcceptableOrUnknown(
          data['time_range_start']!,
          _timeRangeStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timeRangeStartMeta);
    }
    if (data.containsKey('time_range_end')) {
      context.handle(
        _timeRangeEndMeta,
        timeRangeEnd.isAcceptableOrUnknown(
          data['time_range_end']!,
          _timeRangeEndMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timeRangeEndMeta);
    }
    if (data.containsKey('day_index')) {
      context.handle(
        _dayIndexMeta,
        dayIndex.isAcceptableOrUnknown(data['day_index']!, _dayIndexMeta),
      );
    }
    if (data.containsKey('parent_booking_id')) {
      context.handle(
        _parentBookingIdMeta,
        parentBookingId.isAcceptableOrUnknown(
          data['parent_booking_id']!,
          _parentBookingIdMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Booking map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Booking(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      contractorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contractor_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      jobSiteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_site_id'],
      ),
      timeRangeStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time_range_start'],
      )!,
      timeRangeEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time_range_end'],
      )!,
      dayIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_index'],
      ),
      parentBookingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_booking_id'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $BookingsTable createAlias(String alias) {
    return $BookingsTable(attachedDatabase, alias);
  }
}

class Booking extends DataClass implements Insertable<Booking> {
  final String id;

  /// FK to Companies.id — tenant scope.
  final String companyId;

  /// FK to Users.id (contractor role) — the contractor this booking is for.
  final String contractorId;

  /// FK to Jobs.id — the job this booking is associated with.
  final String jobId;

  /// FK to JobSites.id — nullable (job site may not be set at booking time).
  final String? jobSiteId;

  /// Start of the scheduled time block (UTC).
  final DateTime timeRangeStart;

  /// End of the scheduled time block (UTC).
  final DateTime timeRangeEnd;

  /// 0-based index for multi-day bookings. Null for single-day bookings.
  final int? dayIndex;

  /// Links all booking records for the same multi-day job.
  /// Null for single-day bookings or the first day of a multi-day job.
  final String? parentBookingId;

  /// Optional notes/instructions for this booking.
  final String? notes;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete for sync tombstone propagation across devices.
  final DateTime? deletedAt;
  const Booking({
    required this.id,
    required this.companyId,
    required this.contractorId,
    required this.jobId,
    this.jobSiteId,
    required this.timeRangeStart,
    required this.timeRangeEnd,
    this.dayIndex,
    this.parentBookingId,
    this.notes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['contractor_id'] = Variable<String>(contractorId);
    map['job_id'] = Variable<String>(jobId);
    if (!nullToAbsent || jobSiteId != null) {
      map['job_site_id'] = Variable<String>(jobSiteId);
    }
    map['time_range_start'] = Variable<DateTime>(timeRangeStart);
    map['time_range_end'] = Variable<DateTime>(timeRangeEnd);
    if (!nullToAbsent || dayIndex != null) {
      map['day_index'] = Variable<int>(dayIndex);
    }
    if (!nullToAbsent || parentBookingId != null) {
      map['parent_booking_id'] = Variable<String>(parentBookingId);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  BookingsCompanion toCompanion(bool nullToAbsent) {
    return BookingsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      contractorId: Value(contractorId),
      jobId: Value(jobId),
      jobSiteId: jobSiteId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobSiteId),
      timeRangeStart: Value(timeRangeStart),
      timeRangeEnd: Value(timeRangeEnd),
      dayIndex: dayIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(dayIndex),
      parentBookingId: parentBookingId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentBookingId),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Booking.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Booking(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      contractorId: serializer.fromJson<String>(json['contractorId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      jobSiteId: serializer.fromJson<String?>(json['jobSiteId']),
      timeRangeStart: serializer.fromJson<DateTime>(json['timeRangeStart']),
      timeRangeEnd: serializer.fromJson<DateTime>(json['timeRangeEnd']),
      dayIndex: serializer.fromJson<int?>(json['dayIndex']),
      parentBookingId: serializer.fromJson<String?>(json['parentBookingId']),
      notes: serializer.fromJson<String?>(json['notes']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'contractorId': serializer.toJson<String>(contractorId),
      'jobId': serializer.toJson<String>(jobId),
      'jobSiteId': serializer.toJson<String?>(jobSiteId),
      'timeRangeStart': serializer.toJson<DateTime>(timeRangeStart),
      'timeRangeEnd': serializer.toJson<DateTime>(timeRangeEnd),
      'dayIndex': serializer.toJson<int?>(dayIndex),
      'parentBookingId': serializer.toJson<String?>(parentBookingId),
      'notes': serializer.toJson<String?>(notes),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Booking copyWith({
    String? id,
    String? companyId,
    String? contractorId,
    String? jobId,
    Value<String?> jobSiteId = const Value.absent(),
    DateTime? timeRangeStart,
    DateTime? timeRangeEnd,
    Value<int?> dayIndex = const Value.absent(),
    Value<String?> parentBookingId = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Booking(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    contractorId: contractorId ?? this.contractorId,
    jobId: jobId ?? this.jobId,
    jobSiteId: jobSiteId.present ? jobSiteId.value : this.jobSiteId,
    timeRangeStart: timeRangeStart ?? this.timeRangeStart,
    timeRangeEnd: timeRangeEnd ?? this.timeRangeEnd,
    dayIndex: dayIndex.present ? dayIndex.value : this.dayIndex,
    parentBookingId: parentBookingId.present
        ? parentBookingId.value
        : this.parentBookingId,
    notes: notes.present ? notes.value : this.notes,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Booking copyWithCompanion(BookingsCompanion data) {
    return Booking(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      contractorId: data.contractorId.present
          ? data.contractorId.value
          : this.contractorId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      jobSiteId: data.jobSiteId.present ? data.jobSiteId.value : this.jobSiteId,
      timeRangeStart: data.timeRangeStart.present
          ? data.timeRangeStart.value
          : this.timeRangeStart,
      timeRangeEnd: data.timeRangeEnd.present
          ? data.timeRangeEnd.value
          : this.timeRangeEnd,
      dayIndex: data.dayIndex.present ? data.dayIndex.value : this.dayIndex,
      parentBookingId: data.parentBookingId.present
          ? data.parentBookingId.value
          : this.parentBookingId,
      notes: data.notes.present ? data.notes.value : this.notes,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Booking(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('contractorId: $contractorId, ')
          ..write('jobId: $jobId, ')
          ..write('jobSiteId: $jobSiteId, ')
          ..write('timeRangeStart: $timeRangeStart, ')
          ..write('timeRangeEnd: $timeRangeEnd, ')
          ..write('dayIndex: $dayIndex, ')
          ..write('parentBookingId: $parentBookingId, ')
          ..write('notes: $notes, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    contractorId,
    jobId,
    jobSiteId,
    timeRangeStart,
    timeRangeEnd,
    dayIndex,
    parentBookingId,
    notes,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Booking &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.contractorId == this.contractorId &&
          other.jobId == this.jobId &&
          other.jobSiteId == this.jobSiteId &&
          other.timeRangeStart == this.timeRangeStart &&
          other.timeRangeEnd == this.timeRangeEnd &&
          other.dayIndex == this.dayIndex &&
          other.parentBookingId == this.parentBookingId &&
          other.notes == this.notes &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class BookingsCompanion extends UpdateCompanion<Booking> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> contractorId;
  final Value<String> jobId;
  final Value<String?> jobSiteId;
  final Value<DateTime> timeRangeStart;
  final Value<DateTime> timeRangeEnd;
  final Value<int?> dayIndex;
  final Value<String?> parentBookingId;
  final Value<String?> notes;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const BookingsCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.contractorId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.jobSiteId = const Value.absent(),
    this.timeRangeStart = const Value.absent(),
    this.timeRangeEnd = const Value.absent(),
    this.dayIndex = const Value.absent(),
    this.parentBookingId = const Value.absent(),
    this.notes = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookingsCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String contractorId,
    required String jobId,
    this.jobSiteId = const Value.absent(),
    required DateTime timeRangeStart,
    required DateTime timeRangeEnd,
    this.dayIndex = const Value.absent(),
    this.parentBookingId = const Value.absent(),
    this.notes = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       contractorId = Value(contractorId),
       jobId = Value(jobId),
       timeRangeStart = Value(timeRangeStart),
       timeRangeEnd = Value(timeRangeEnd),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Booking> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? contractorId,
    Expression<String>? jobId,
    Expression<String>? jobSiteId,
    Expression<DateTime>? timeRangeStart,
    Expression<DateTime>? timeRangeEnd,
    Expression<int>? dayIndex,
    Expression<String>? parentBookingId,
    Expression<String>? notes,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (contractorId != null) 'contractor_id': contractorId,
      if (jobId != null) 'job_id': jobId,
      if (jobSiteId != null) 'job_site_id': jobSiteId,
      if (timeRangeStart != null) 'time_range_start': timeRangeStart,
      if (timeRangeEnd != null) 'time_range_end': timeRangeEnd,
      if (dayIndex != null) 'day_index': dayIndex,
      if (parentBookingId != null) 'parent_booking_id': parentBookingId,
      if (notes != null) 'notes': notes,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookingsCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? contractorId,
    Value<String>? jobId,
    Value<String?>? jobSiteId,
    Value<DateTime>? timeRangeStart,
    Value<DateTime>? timeRangeEnd,
    Value<int?>? dayIndex,
    Value<String?>? parentBookingId,
    Value<String?>? notes,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return BookingsCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      contractorId: contractorId ?? this.contractorId,
      jobId: jobId ?? this.jobId,
      jobSiteId: jobSiteId ?? this.jobSiteId,
      timeRangeStart: timeRangeStart ?? this.timeRangeStart,
      timeRangeEnd: timeRangeEnd ?? this.timeRangeEnd,
      dayIndex: dayIndex ?? this.dayIndex,
      parentBookingId: parentBookingId ?? this.parentBookingId,
      notes: notes ?? this.notes,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (contractorId.present) {
      map['contractor_id'] = Variable<String>(contractorId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (jobSiteId.present) {
      map['job_site_id'] = Variable<String>(jobSiteId.value);
    }
    if (timeRangeStart.present) {
      map['time_range_start'] = Variable<DateTime>(timeRangeStart.value);
    }
    if (timeRangeEnd.present) {
      map['time_range_end'] = Variable<DateTime>(timeRangeEnd.value);
    }
    if (dayIndex.present) {
      map['day_index'] = Variable<int>(dayIndex.value);
    }
    if (parentBookingId.present) {
      map['parent_booking_id'] = Variable<String>(parentBookingId.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookingsCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('contractorId: $contractorId, ')
          ..write('jobId: $jobId, ')
          ..write('jobSiteId: $jobSiteId, ')
          ..write('timeRangeStart: $timeRangeStart, ')
          ..write('timeRangeEnd: $timeRangeEnd, ')
          ..write('dayIndex: $dayIndex, ')
          ..write('parentBookingId: $parentBookingId, ')
          ..write('notes: $notes, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JobSitesTable extends JobSites with TableInfo<$JobSitesTable, JobSite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobSitesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formattedAddressMeta = const VerificationMeta(
    'formattedAddress',
  );
  @override
  late final GeneratedColumn<String> formattedAddress = GeneratedColumn<String>(
    'formatted_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    address,
    lat,
    lng,
    formattedAddress,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'job_sites';
  @override
  VerificationContext validateIntegrity(
    Insertable<JobSite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('formatted_address')) {
      context.handle(
        _formattedAddressMeta,
        formattedAddress.isAcceptableOrUnknown(
          data['formatted_address']!,
          _formattedAddressMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JobSite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JobSite(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      formattedAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}formatted_address'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $JobSitesTable createAlias(String alias) {
    return $JobSitesTable(attachedDatabase, alias);
  }
}

class JobSite extends DataClass implements Insertable<JobSite> {
  final String id;

  /// FK to Companies.id — tenant scope.
  final String companyId;

  /// Raw address string submitted for geocoding.
  final String address;

  /// Geocoded latitude in WGS84. Nullable — geocoding may fail.
  final double? lat;

  /// Geocoded longitude in WGS84. Nullable — geocoding may fail.
  final double? lng;

  /// Geocoder's canonical formatted address for display.
  final String? formattedAddress;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete for sync tombstone propagation across devices.
  final DateTime? deletedAt;
  const JobSite({
    required this.id,
    required this.companyId,
    required this.address,
    this.lat,
    this.lng,
    this.formattedAddress,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['address'] = Variable<String>(address);
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    if (!nullToAbsent || formattedAddress != null) {
      map['formatted_address'] = Variable<String>(formattedAddress);
    }
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  JobSitesCompanion toCompanion(bool nullToAbsent) {
    return JobSitesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      address: Value(address),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      formattedAddress: formattedAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(formattedAddress),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory JobSite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JobSite(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      address: serializer.fromJson<String>(json['address']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      formattedAddress: serializer.fromJson<String?>(json['formattedAddress']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'address': serializer.toJson<String>(address),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'formattedAddress': serializer.toJson<String?>(formattedAddress),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  JobSite copyWith({
    String? id,
    String? companyId,
    String? address,
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    Value<String?> formattedAddress = const Value.absent(),
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => JobSite(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    address: address ?? this.address,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    formattedAddress: formattedAddress.present
        ? formattedAddress.value
        : this.formattedAddress,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  JobSite copyWithCompanion(JobSitesCompanion data) {
    return JobSite(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      address: data.address.present ? data.address.value : this.address,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      formattedAddress: data.formattedAddress.present
          ? data.formattedAddress.value
          : this.formattedAddress,
      version: data.version.present ? data.version.value : this.version,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JobSite(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('address: $address, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('formattedAddress: $formattedAddress, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    address,
    lat,
    lng,
    formattedAddress,
    version,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobSite &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.address == this.address &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.formattedAddress == this.formattedAddress &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class JobSitesCompanion extends UpdateCompanion<JobSite> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> address;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<String?> formattedAddress;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const JobSitesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.address = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.formattedAddress = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JobSitesCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String address,
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.formattedAddress = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       address = Value(address),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<JobSite> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? address,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? formattedAddress,
    Expression<int>? version,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (address != null) 'address': address,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (formattedAddress != null) 'formatted_address': formattedAddress,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JobSitesCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? address,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<String?>? formattedAddress,
    Value<int>? version,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return JobSitesCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (formattedAddress.present) {
      map['formatted_address'] = Variable<String>(formattedAddress.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobSitesCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('address: $address, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('formattedAddress: $formattedAddress, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CompaniesTable companies = $CompaniesTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $UserRolesTable userRoles = $UserRolesTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $SyncCursorTable syncCursor = $SyncCursorTable(this);
  late final $JobsTable jobs = $JobsTable(this);
  late final $ClientProfilesTable clientProfiles = $ClientProfilesTable(this);
  late final $ClientPropertiesTable clientProperties = $ClientPropertiesTable(
    this,
  );
  late final $JobRequestsTable jobRequests = $JobRequestsTable(this);
  late final $BookingsTable bookings = $BookingsTable(this);
  late final $JobSitesTable jobSites = $JobSitesTable(this);
  late final $JobNotesTable jobNotes = $JobNotesTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $TimeEntriesTable timeEntries = $TimeEntriesTable(this);
  late final CompanyDao companyDao = CompanyDao(this as AppDatabase);
  late final UserDao userDao = UserDao(this as AppDatabase);
  late final SyncQueueDao syncQueueDao = SyncQueueDao(this as AppDatabase);
  late final SyncCursorDao syncCursorDao = SyncCursorDao(this as AppDatabase);
  late final JobDao jobDao = JobDao(this as AppDatabase);
  late final BookingDao bookingDao = BookingDao(this as AppDatabase);
  late final NoteDao noteDao = NoteDao(this as AppDatabase);
  late final AttachmentDao attachmentDao = AttachmentDao(this as AppDatabase);
  late final TimeEntryDao timeEntryDao = TimeEntryDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    companies,
    users,
    userRoles,
    syncQueue,
    syncCursor,
    jobs,
    clientProfiles,
    clientProperties,
    jobRequests,
    bookings,
    jobSites,
    jobNotes,
    attachments,
    timeEntries,
  ];
}

typedef $$CompaniesTableCreateCompanionBuilder =
    CompaniesCompanion Function({
      Value<String> id,
      required String name,
      Value<String?> address,
      Value<String?> phone,
      Value<String?> businessNumber,
      Value<String?> logoUrl,
      Value<String?> tradeTypes,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$CompaniesTableUpdateCompanionBuilder =
    CompaniesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> address,
      Value<String?> phone,
      Value<String?> businessNumber,
      Value<String?> logoUrl,
      Value<String?> tradeTypes,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$CompaniesTableReferences
    extends BaseReferences<_$AppDatabase, $CompaniesTable, Company> {
  $$CompaniesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$UsersTable, List<User>> _usersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.users,
    aliasName: $_aliasNameGenerator(db.companies.id, db.users.companyId),
  );

  $$UsersTableProcessedTableManager get usersRefs {
    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.companyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_usersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$UserRolesTable, List<UserRole>>
  _userRolesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.userRoles,
    aliasName: $_aliasNameGenerator(db.companies.id, db.userRoles.companyId),
  );

  $$UserRolesTableProcessedTableManager get userRolesRefs {
    final manager = $$UserRolesTableTableManager(
      $_db,
      $_db.userRoles,
    ).filter((f) => f.companyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_userRolesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$JobsTable, List<Job>> _jobsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.jobs,
    aliasName: $_aliasNameGenerator(db.companies.id, db.jobs.companyId),
  );

  $$JobsTableProcessedTableManager get jobsRefs {
    final manager = $$JobsTableTableManager(
      $_db,
      $_db.jobs,
    ).filter((f) => f.companyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_jobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ClientProfilesTable, List<ClientProfile>>
  _clientProfilesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.clientProfiles,
    aliasName: $_aliasNameGenerator(
      db.companies.id,
      db.clientProfiles.companyId,
    ),
  );

  $$ClientProfilesTableProcessedTableManager get clientProfilesRefs {
    final manager = $$ClientProfilesTableTableManager(
      $_db,
      $_db.clientProfiles,
    ).filter((f) => f.companyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_clientProfilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ClientPropertiesTable, List<ClientProperty>>
  _clientPropertiesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.clientProperties,
    aliasName: $_aliasNameGenerator(
      db.companies.id,
      db.clientProperties.companyId,
    ),
  );

  $$ClientPropertiesTableProcessedTableManager get clientPropertiesRefs {
    final manager = $$ClientPropertiesTableTableManager(
      $_db,
      $_db.clientProperties,
    ).filter((f) => f.companyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _clientPropertiesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$JobRequestsTable, List<JobRequest>>
  _jobRequestsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.jobRequests,
    aliasName: $_aliasNameGenerator(db.companies.id, db.jobRequests.companyId),
  );

  $$JobRequestsTableProcessedTableManager get jobRequestsRefs {
    final manager = $$JobRequestsTableTableManager(
      $_db,
      $_db.jobRequests,
    ).filter((f) => f.companyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_jobRequestsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CompaniesTableFilterComposer
    extends Composer<_$AppDatabase, $CompaniesTable> {
  $$CompaniesTableFilterComposer({
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

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessNumber => $composableBuilder(
    column: $table.businessNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tradeTypes => $composableBuilder(
    column: $table.tradeTypes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> usersRefs(
    Expression<bool> Function($$UsersTableFilterComposer f) f,
  ) {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> userRolesRefs(
    Expression<bool> Function($$UserRolesTableFilterComposer f) f,
  ) {
    final $$UserRolesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.userRoles,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UserRolesTableFilterComposer(
            $db: $db,
            $table: $db.userRoles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> jobsRefs(
    Expression<bool> Function($$JobsTableFilterComposer f) f,
  ) {
    final $$JobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableFilterComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> clientProfilesRefs(
    Expression<bool> Function($$ClientProfilesTableFilterComposer f) f,
  ) {
    final $$ClientProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clientProfiles,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientProfilesTableFilterComposer(
            $db: $db,
            $table: $db.clientProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> clientPropertiesRefs(
    Expression<bool> Function($$ClientPropertiesTableFilterComposer f) f,
  ) {
    final $$ClientPropertiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clientProperties,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientPropertiesTableFilterComposer(
            $db: $db,
            $table: $db.clientProperties,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> jobRequestsRefs(
    Expression<bool> Function($$JobRequestsTableFilterComposer f) f,
  ) {
    final $$JobRequestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobRequests,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobRequestsTableFilterComposer(
            $db: $db,
            $table: $db.jobRequests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CompaniesTableOrderingComposer
    extends Composer<_$AppDatabase, $CompaniesTable> {
  $$CompaniesTableOrderingComposer({
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

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessNumber => $composableBuilder(
    column: $table.businessNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tradeTypes => $composableBuilder(
    column: $table.tradeTypes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CompaniesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CompaniesTable> {
  $$CompaniesTableAnnotationComposer({
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

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get businessNumber => $composableBuilder(
    column: $table.businessNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get logoUrl =>
      $composableBuilder(column: $table.logoUrl, builder: (column) => column);

  GeneratedColumn<String> get tradeTypes => $composableBuilder(
    column: $table.tradeTypes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> usersRefs<T extends Object>(
    Expression<T> Function($$UsersTableAnnotationComposer a) f,
  ) {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> userRolesRefs<T extends Object>(
    Expression<T> Function($$UserRolesTableAnnotationComposer a) f,
  ) {
    final $$UserRolesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.userRoles,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UserRolesTableAnnotationComposer(
            $db: $db,
            $table: $db.userRoles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> jobsRefs<T extends Object>(
    Expression<T> Function($$JobsTableAnnotationComposer a) f,
  ) {
    final $$JobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableAnnotationComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> clientProfilesRefs<T extends Object>(
    Expression<T> Function($$ClientProfilesTableAnnotationComposer a) f,
  ) {
    final $$ClientProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clientProfiles,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.clientProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> clientPropertiesRefs<T extends Object>(
    Expression<T> Function($$ClientPropertiesTableAnnotationComposer a) f,
  ) {
    final $$ClientPropertiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clientProperties,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientPropertiesTableAnnotationComposer(
            $db: $db,
            $table: $db.clientProperties,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> jobRequestsRefs<T extends Object>(
    Expression<T> Function($$JobRequestsTableAnnotationComposer a) f,
  ) {
    final $$JobRequestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobRequests,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobRequestsTableAnnotationComposer(
            $db: $db,
            $table: $db.jobRequests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CompaniesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CompaniesTable,
          Company,
          $$CompaniesTableFilterComposer,
          $$CompaniesTableOrderingComposer,
          $$CompaniesTableAnnotationComposer,
          $$CompaniesTableCreateCompanionBuilder,
          $$CompaniesTableUpdateCompanionBuilder,
          (Company, $$CompaniesTableReferences),
          Company,
          PrefetchHooks Function({
            bool usersRefs,
            bool userRolesRefs,
            bool jobsRefs,
            bool clientProfilesRefs,
            bool clientPropertiesRefs,
            bool jobRequestsRefs,
          })
        > {
  $$CompaniesTableTableManager(_$AppDatabase db, $CompaniesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CompaniesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CompaniesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CompaniesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> businessNumber = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String?> tradeTypes = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompaniesCompanion(
                id: id,
                name: name,
                address: address,
                phone: phone,
                businessNumber: businessNumber,
                logoUrl: logoUrl,
                tradeTypes: tradeTypes,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String name,
                Value<String?> address = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> businessNumber = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String?> tradeTypes = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompaniesCompanion.insert(
                id: id,
                name: name,
                address: address,
                phone: phone,
                businessNumber: businessNumber,
                logoUrl: logoUrl,
                tradeTypes: tradeTypes,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CompaniesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                usersRefs = false,
                userRolesRefs = false,
                jobsRefs = false,
                clientProfilesRefs = false,
                clientPropertiesRefs = false,
                jobRequestsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (usersRefs) db.users,
                    if (userRolesRefs) db.userRoles,
                    if (jobsRefs) db.jobs,
                    if (clientProfilesRefs) db.clientProfiles,
                    if (clientPropertiesRefs) db.clientProperties,
                    if (jobRequestsRefs) db.jobRequests,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (usersRefs)
                        await $_getPrefetchedData<
                          Company,
                          $CompaniesTable,
                          User
                        >(
                          currentTable: table,
                          referencedTable: $$CompaniesTableReferences
                              ._usersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompaniesTableReferences(
                                db,
                                table,
                                p0,
                              ).usersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (userRolesRefs)
                        await $_getPrefetchedData<
                          Company,
                          $CompaniesTable,
                          UserRole
                        >(
                          currentTable: table,
                          referencedTable: $$CompaniesTableReferences
                              ._userRolesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompaniesTableReferences(
                                db,
                                table,
                                p0,
                              ).userRolesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (jobsRefs)
                        await $_getPrefetchedData<
                          Company,
                          $CompaniesTable,
                          Job
                        >(
                          currentTable: table,
                          referencedTable: $$CompaniesTableReferences
                              ._jobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompaniesTableReferences(
                                db,
                                table,
                                p0,
                              ).jobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (clientProfilesRefs)
                        await $_getPrefetchedData<
                          Company,
                          $CompaniesTable,
                          ClientProfile
                        >(
                          currentTable: table,
                          referencedTable: $$CompaniesTableReferences
                              ._clientProfilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompaniesTableReferences(
                                db,
                                table,
                                p0,
                              ).clientProfilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (clientPropertiesRefs)
                        await $_getPrefetchedData<
                          Company,
                          $CompaniesTable,
                          ClientProperty
                        >(
                          currentTable: table,
                          referencedTable: $$CompaniesTableReferences
                              ._clientPropertiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompaniesTableReferences(
                                db,
                                table,
                                p0,
                              ).clientPropertiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (jobRequestsRefs)
                        await $_getPrefetchedData<
                          Company,
                          $CompaniesTable,
                          JobRequest
                        >(
                          currentTable: table,
                          referencedTable: $$CompaniesTableReferences
                              ._jobRequestsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompaniesTableReferences(
                                db,
                                table,
                                p0,
                              ).jobRequestsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.id,
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

typedef $$CompaniesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CompaniesTable,
      Company,
      $$CompaniesTableFilterComposer,
      $$CompaniesTableOrderingComposer,
      $$CompaniesTableAnnotationComposer,
      $$CompaniesTableCreateCompanionBuilder,
      $$CompaniesTableUpdateCompanionBuilder,
      (Company, $$CompaniesTableReferences),
      Company,
      PrefetchHooks Function({
        bool usersRefs,
        bool userRolesRefs,
        bool jobsRefs,
        bool clientProfilesRefs,
        bool clientPropertiesRefs,
        bool jobRequestsRefs,
      })
    >;
typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      Value<String> id,
      required String companyId,
      required String email,
      Value<String?> firstName,
      Value<String?> lastName,
      Value<String?> phone,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> email,
      Value<String?> firstName,
      Value<String?> lastName,
      Value<String?> phone,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$UsersTableReferences
    extends BaseReferences<_$AppDatabase, $UsersTable, User> {
  $$UsersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CompaniesTable _companyIdTable(_$AppDatabase db) => db.companies
      .createAlias($_aliasNameGenerator(db.users.companyId, db.companies.id));

  $$CompaniesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompaniesTableTableManager(
      $_db,
      $_db.companies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$UserRolesTable, List<UserRole>>
  _userRolesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.userRoles,
    aliasName: $_aliasNameGenerator(db.users.id, db.userRoles.userId),
  );

  $$UserRolesTableProcessedTableManager get userRolesRefs {
    final manager = $$UserRolesTableTableManager(
      $_db,
      $_db.userRoles,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_userRolesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ClientProfilesTable, List<ClientProfile>>
  _clientProfilesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.clientProfiles,
    aliasName: $_aliasNameGenerator(db.users.id, db.clientProfiles.userId),
  );

  $$ClientProfilesTableProcessedTableManager get clientProfilesRefs {
    final manager = $$ClientProfilesTableTableManager(
      $_db,
      $_db.clientProfiles,
    ).filter((f) => f.userId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_clientProfilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
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

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CompaniesTableFilterComposer get companyId {
    final $$CompaniesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableFilterComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> userRolesRefs(
    Expression<bool> Function($$UserRolesTableFilterComposer f) f,
  ) {
    final $$UserRolesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.userRoles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UserRolesTableFilterComposer(
            $db: $db,
            $table: $db.userRoles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> clientProfilesRefs(
    Expression<bool> Function($$ClientProfilesTableFilterComposer f) f,
  ) {
    final $$ClientProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clientProfiles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientProfilesTableFilterComposer(
            $db: $db,
            $table: $db.clientProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
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

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompaniesTableOrderingComposer get companyId {
    final $$CompaniesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableOrderingComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CompaniesTableAnnotationComposer get companyId {
    final $$CompaniesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableAnnotationComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> userRolesRefs<T extends Object>(
    Expression<T> Function($$UserRolesTableAnnotationComposer a) f,
  ) {
    final $$UserRolesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.userRoles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UserRolesTableAnnotationComposer(
            $db: $db,
            $table: $db.userRoles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> clientProfilesRefs<T extends Object>(
    Expression<T> Function($$ClientProfilesTableAnnotationComposer a) f,
  ) {
    final $$ClientProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.clientProfiles,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.clientProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, $$UsersTableReferences),
          User,
          PrefetchHooks Function({
            bool companyId,
            bool userRolesRefs,
            bool clientProfilesRefs,
          })
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String?> firstName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                companyId: companyId,
                email: email,
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                required String email,
                Value<String?> firstName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                id: id,
                companyId: companyId,
                email: email,
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UsersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                companyId = false,
                userRolesRefs = false,
                clientProfilesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (userRolesRefs) db.userRoles,
                    if (clientProfilesRefs) db.clientProfiles,
                  ],
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
                        if (companyId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.companyId,
                                    referencedTable: $$UsersTableReferences
                                        ._companyIdTable(db),
                                    referencedColumn: $$UsersTableReferences
                                        ._companyIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (userRolesRefs)
                        await $_getPrefetchedData<User, $UsersTable, UserRole>(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._userRolesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).userRolesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (clientProfilesRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          ClientProfile
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._clientProfilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).clientProfilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.id,
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

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, $$UsersTableReferences),
      User,
      PrefetchHooks Function({
        bool companyId,
        bool userRolesRefs,
        bool clientProfilesRefs,
      })
    >;
typedef $$UserRolesTableCreateCompanionBuilder =
    UserRolesCompanion Function({
      Value<String> id,
      required String userId,
      required String companyId,
      required String role,
      required DateTime createdAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$UserRolesTableUpdateCompanionBuilder =
    UserRolesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> companyId,
      Value<String> role,
      Value<DateTime> createdAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$UserRolesTableReferences
    extends BaseReferences<_$AppDatabase, $UserRolesTable, UserRole> {
  $$UserRolesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UsersTable _userIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.userRoles.userId, db.users.id),
  );

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CompaniesTable _companyIdTable(_$AppDatabase db) =>
      db.companies.createAlias(
        $_aliasNameGenerator(db.userRoles.companyId, db.companies.id),
      );

  $$CompaniesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompaniesTableTableManager(
      $_db,
      $_db.companies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$UserRolesTableFilterComposer
    extends Composer<_$AppDatabase, $UserRolesTable> {
  $$UserRolesTableFilterComposer({
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

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CompaniesTableFilterComposer get companyId {
    final $$CompaniesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableFilterComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UserRolesTableOrderingComposer
    extends Composer<_$AppDatabase, $UserRolesTable> {
  $$UserRolesTableOrderingComposer({
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

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CompaniesTableOrderingComposer get companyId {
    final $$CompaniesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableOrderingComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UserRolesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserRolesTable> {
  $$UserRolesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CompaniesTableAnnotationComposer get companyId {
    final $$CompaniesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableAnnotationComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UserRolesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserRolesTable,
          UserRole,
          $$UserRolesTableFilterComposer,
          $$UserRolesTableOrderingComposer,
          $$UserRolesTableAnnotationComposer,
          $$UserRolesTableCreateCompanionBuilder,
          $$UserRolesTableUpdateCompanionBuilder,
          (UserRole, $$UserRolesTableReferences),
          UserRole,
          PrefetchHooks Function({bool userId, bool companyId})
        > {
  $$UserRolesTableTableManager(_$AppDatabase db, $UserRolesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserRolesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserRolesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserRolesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserRolesCompanion(
                id: id,
                userId: userId,
                companyId: companyId,
                role: role,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String userId,
                required String companyId,
                required String role,
                required DateTime createdAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserRolesCompanion.insert(
                id: id,
                userId: userId,
                companyId: companyId,
                role: role,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$UserRolesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false, companyId = false}) {
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
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$UserRolesTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$UserRolesTableReferences
                                    ._userIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable: $$UserRolesTableReferences
                                    ._companyIdTable(db),
                                referencedColumn: $$UserRolesTableReferences
                                    ._companyIdTable(db)
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

typedef $$UserRolesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserRolesTable,
      UserRole,
      $$UserRolesTableFilterComposer,
      $$UserRolesTableOrderingComposer,
      $$UserRolesTableAnnotationComposer,
      $$UserRolesTableCreateCompanionBuilder,
      $$UserRolesTableUpdateCompanionBuilder,
      (UserRole, $$UserRolesTableReferences),
      UserRole,
      PrefetchHooks Function({bool userId, bool companyId})
    >;
typedef $$SyncQueueTableCreateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<String> id,
      required String entityType,
      required String entityId,
      required String operation,
      required String payload,
      Value<String> status,
      Value<int> attemptCount,
      Value<String?> errorMessage,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SyncQueueTableUpdateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<String> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payload,
      Value<String> status,
      Value<int> attemptCount,
      Value<String?> errorMessage,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
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

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
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

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncQueueTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQueueTable,
          SyncQueueData,
          $$SyncQueueTableFilterComposer,
          $$SyncQueueTableOrderingComposer,
          $$SyncQueueTableAnnotationComposer,
          $$SyncQueueTableCreateCompanionBuilder,
          $$SyncQueueTableUpdateCompanionBuilder,
          (
            SyncQueueData,
            BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>,
          ),
          SyncQueueData,
          PrefetchHooks Function()
        > {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                status: status,
                attemptCount: attemptCount,
                errorMessage: errorMessage,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String entityType,
                required String entityId,
                required String operation,
                required String payload,
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                status: status,
                attemptCount: attemptCount,
                errorMessage: errorMessage,
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

typedef $$SyncQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQueueTable,
      SyncQueueData,
      $$SyncQueueTableFilterComposer,
      $$SyncQueueTableOrderingComposer,
      $$SyncQueueTableAnnotationComposer,
      $$SyncQueueTableCreateCompanionBuilder,
      $$SyncQueueTableUpdateCompanionBuilder,
      (
        SyncQueueData,
        BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>,
      ),
      SyncQueueData,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorTableCreateCompanionBuilder =
    SyncCursorCompanion Function({
      Value<String> key,
      Value<DateTime?> lastPulledAt,
      Value<int> rowid,
    });
typedef $$SyncCursorTableUpdateCompanionBuilder =
    SyncCursorCompanion Function({
      Value<String> key,
      Value<DateTime?> lastPulledAt,
      Value<int> rowid,
    });

class $$SyncCursorTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorTable> {
  $$SyncCursorTableFilterComposer({
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

  ColumnFilters<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorTable> {
  $$SyncCursorTableOrderingComposer({
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

  ColumnOrderings<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorTable> {
  $$SyncCursorTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => column,
  );
}

class $$SyncCursorTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorTable,
          SyncCursorData,
          $$SyncCursorTableFilterComposer,
          $$SyncCursorTableOrderingComposer,
          $$SyncCursorTableAnnotationComposer,
          $$SyncCursorTableCreateCompanionBuilder,
          $$SyncCursorTableUpdateCompanionBuilder,
          (
            SyncCursorData,
            BaseReferences<_$AppDatabase, $SyncCursorTable, SyncCursorData>,
          ),
          SyncCursorData,
          PrefetchHooks Function()
        > {
  $$SyncCursorTableTableManager(_$AppDatabase db, $SyncCursorTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorCompanion(
                key: key,
                lastPulledAt: lastPulledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorCompanion.insert(
                key: key,
                lastPulledAt: lastPulledAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorTable,
      SyncCursorData,
      $$SyncCursorTableFilterComposer,
      $$SyncCursorTableOrderingComposer,
      $$SyncCursorTableAnnotationComposer,
      $$SyncCursorTableCreateCompanionBuilder,
      $$SyncCursorTableUpdateCompanionBuilder,
      (
        SyncCursorData,
        BaseReferences<_$AppDatabase, $SyncCursorTable, SyncCursorData>,
      ),
      SyncCursorData,
      PrefetchHooks Function()
    >;
typedef $$JobsTableCreateCompanionBuilder =
    JobsCompanion Function({
      Value<String> id,
      required String companyId,
      Value<String?> clientId,
      Value<String?> contractorId,
      required String description,
      required String tradeType,
      Value<String> status,
      Value<String> statusHistory,
      Value<String> priority,
      Value<String?> purchaseOrderNumber,
      Value<String?> externalReference,
      Value<String> tags,
      Value<String?> notes,
      Value<int?> estimatedDurationMinutes,
      Value<DateTime?> scheduledCompletionDate,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<double?> gpsLatitude,
      Value<double?> gpsLongitude,
      Value<String?> gpsAddress,
      Value<int> rowid,
    });
typedef $$JobsTableUpdateCompanionBuilder =
    JobsCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String?> clientId,
      Value<String?> contractorId,
      Value<String> description,
      Value<String> tradeType,
      Value<String> status,
      Value<String> statusHistory,
      Value<String> priority,
      Value<String?> purchaseOrderNumber,
      Value<String?> externalReference,
      Value<String> tags,
      Value<String?> notes,
      Value<int?> estimatedDurationMinutes,
      Value<DateTime?> scheduledCompletionDate,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<double?> gpsLatitude,
      Value<double?> gpsLongitude,
      Value<String?> gpsAddress,
      Value<int> rowid,
    });

final class $$JobsTableReferences
    extends BaseReferences<_$AppDatabase, $JobsTable, Job> {
  $$JobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CompaniesTable _companyIdTable(_$AppDatabase db) => db.companies
      .createAlias($_aliasNameGenerator(db.jobs.companyId, db.companies.id));

  $$CompaniesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompaniesTableTableManager(
      $_db,
      $_db.companies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$JobsTableFilterComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableFilterComposer({
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

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contractorId => $composableBuilder(
    column: $table.contractorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tradeType => $composableBuilder(
    column: $table.tradeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusHistory => $composableBuilder(
    column: $table.statusHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purchaseOrderNumber => $composableBuilder(
    column: $table.purchaseOrderNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalReference => $composableBuilder(
    column: $table.externalReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedDurationMinutes => $composableBuilder(
    column: $table.estimatedDurationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledCompletionDate => $composableBuilder(
    column: $table.scheduledCompletionDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CompaniesTableFilterComposer get companyId {
    final $$CompaniesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableFilterComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobsTableOrderingComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableOrderingComposer({
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

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contractorId => $composableBuilder(
    column: $table.contractorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tradeType => $composableBuilder(
    column: $table.tradeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusHistory => $composableBuilder(
    column: $table.statusHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purchaseOrderNumber => $composableBuilder(
    column: $table.purchaseOrderNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalReference => $composableBuilder(
    column: $table.externalReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedDurationMinutes => $composableBuilder(
    column: $table.estimatedDurationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledCompletionDate => $composableBuilder(
    column: $table.scheduledCompletionDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompaniesTableOrderingComposer get companyId {
    final $$CompaniesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableOrderingComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get contractorId => $composableBuilder(
    column: $table.contractorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tradeType =>
      $composableBuilder(column: $table.tradeType, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get statusHistory => $composableBuilder(
    column: $table.statusHistory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get purchaseOrderNumber => $composableBuilder(
    column: $table.purchaseOrderNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get externalReference => $composableBuilder(
    column: $table.externalReference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get estimatedDurationMinutes => $composableBuilder(
    column: $table.estimatedDurationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledCompletionDate => $composableBuilder(
    column: $table.scheduledCompletionDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CompaniesTableAnnotationComposer get companyId {
    final $$CompaniesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableAnnotationComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JobsTable,
          Job,
          $$JobsTableFilterComposer,
          $$JobsTableOrderingComposer,
          $$JobsTableAnnotationComposer,
          $$JobsTableCreateCompanionBuilder,
          $$JobsTableUpdateCompanionBuilder,
          (Job, $$JobsTableReferences),
          Job,
          PrefetchHooks Function({bool companyId})
        > {
  $$JobsTableTableManager(_$AppDatabase db, $JobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String?> clientId = const Value.absent(),
                Value<String?> contractorId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> tradeType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> statusHistory = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String?> purchaseOrderNumber = const Value.absent(),
                Value<String?> externalReference = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int?> estimatedDurationMinutes = const Value.absent(),
                Value<DateTime?> scheduledCompletionDate = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<double?> gpsLatitude = const Value.absent(),
                Value<double?> gpsLongitude = const Value.absent(),
                Value<String?> gpsAddress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobsCompanion(
                id: id,
                companyId: companyId,
                clientId: clientId,
                contractorId: contractorId,
                description: description,
                tradeType: tradeType,
                status: status,
                statusHistory: statusHistory,
                priority: priority,
                purchaseOrderNumber: purchaseOrderNumber,
                externalReference: externalReference,
                tags: tags,
                notes: notes,
                estimatedDurationMinutes: estimatedDurationMinutes,
                scheduledCompletionDate: scheduledCompletionDate,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                gpsLatitude: gpsLatitude,
                gpsLongitude: gpsLongitude,
                gpsAddress: gpsAddress,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                Value<String?> clientId = const Value.absent(),
                Value<String?> contractorId = const Value.absent(),
                required String description,
                required String tradeType,
                Value<String> status = const Value.absent(),
                Value<String> statusHistory = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String?> purchaseOrderNumber = const Value.absent(),
                Value<String?> externalReference = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int?> estimatedDurationMinutes = const Value.absent(),
                Value<DateTime?> scheduledCompletionDate = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<double?> gpsLatitude = const Value.absent(),
                Value<double?> gpsLongitude = const Value.absent(),
                Value<String?> gpsAddress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobsCompanion.insert(
                id: id,
                companyId: companyId,
                clientId: clientId,
                contractorId: contractorId,
                description: description,
                tradeType: tradeType,
                status: status,
                statusHistory: statusHistory,
                priority: priority,
                purchaseOrderNumber: purchaseOrderNumber,
                externalReference: externalReference,
                tags: tags,
                notes: notes,
                estimatedDurationMinutes: estimatedDurationMinutes,
                scheduledCompletionDate: scheduledCompletionDate,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                gpsLatitude: gpsLatitude,
                gpsLongitude: gpsLongitude,
                gpsAddress: gpsAddress,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$JobsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({companyId = false}) {
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
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable: $$JobsTableReferences
                                    ._companyIdTable(db),
                                referencedColumn: $$JobsTableReferences
                                    ._companyIdTable(db)
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

typedef $$JobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JobsTable,
      Job,
      $$JobsTableFilterComposer,
      $$JobsTableOrderingComposer,
      $$JobsTableAnnotationComposer,
      $$JobsTableCreateCompanionBuilder,
      $$JobsTableUpdateCompanionBuilder,
      (Job, $$JobsTableReferences),
      Job,
      PrefetchHooks Function({bool companyId})
    >;
typedef $$ClientProfilesTableCreateCompanionBuilder =
    ClientProfilesCompanion Function({
      Value<String> id,
      required String companyId,
      required String userId,
      Value<String?> billingAddress,
      Value<String> tags,
      Value<String?> adminNotes,
      Value<String?> referralSource,
      Value<String?> preferredContractorId,
      Value<String?> preferredContactMethod,
      Value<double?> averageRating,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ClientProfilesTableUpdateCompanionBuilder =
    ClientProfilesCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> userId,
      Value<String?> billingAddress,
      Value<String> tags,
      Value<String?> adminNotes,
      Value<String?> referralSource,
      Value<String?> preferredContractorId,
      Value<String?> preferredContactMethod,
      Value<double?> averageRating,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$ClientProfilesTableReferences
    extends BaseReferences<_$AppDatabase, $ClientProfilesTable, ClientProfile> {
  $$ClientProfilesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CompaniesTable _companyIdTable(_$AppDatabase db) =>
      db.companies.createAlias(
        $_aliasNameGenerator(db.clientProfiles.companyId, db.companies.id),
      );

  $$CompaniesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompaniesTableTableManager(
      $_db,
      $_db.companies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _userIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.clientProfiles.userId, db.users.id),
  );

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ClientProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ClientProfilesTable> {
  $$ClientProfilesTableFilterComposer({
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

  ColumnFilters<String> get billingAddress => $composableBuilder(
    column: $table.billingAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get adminNotes => $composableBuilder(
    column: $table.adminNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referralSource => $composableBuilder(
    column: $table.referralSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferredContractorId => $composableBuilder(
    column: $table.preferredContractorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferredContactMethod => $composableBuilder(
    column: $table.preferredContactMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageRating => $composableBuilder(
    column: $table.averageRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CompaniesTableFilterComposer get companyId {
    final $$CompaniesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableFilterComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClientProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientProfilesTable> {
  $$ClientProfilesTableOrderingComposer({
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

  ColumnOrderings<String> get billingAddress => $composableBuilder(
    column: $table.billingAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get adminNotes => $composableBuilder(
    column: $table.adminNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referralSource => $composableBuilder(
    column: $table.referralSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferredContractorId => $composableBuilder(
    column: $table.preferredContractorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferredContactMethod => $composableBuilder(
    column: $table.preferredContactMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageRating => $composableBuilder(
    column: $table.averageRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompaniesTableOrderingComposer get companyId {
    final $$CompaniesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableOrderingComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClientProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientProfilesTable> {
  $$ClientProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get billingAddress => $composableBuilder(
    column: $table.billingAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get adminNotes => $composableBuilder(
    column: $table.adminNotes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referralSource => $composableBuilder(
    column: $table.referralSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preferredContractorId => $composableBuilder(
    column: $table.preferredContractorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preferredContactMethod => $composableBuilder(
    column: $table.preferredContactMethod,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageRating => $composableBuilder(
    column: $table.averageRating,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CompaniesTableAnnotationComposer get companyId {
    final $$CompaniesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableAnnotationComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClientProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientProfilesTable,
          ClientProfile,
          $$ClientProfilesTableFilterComposer,
          $$ClientProfilesTableOrderingComposer,
          $$ClientProfilesTableAnnotationComposer,
          $$ClientProfilesTableCreateCompanionBuilder,
          $$ClientProfilesTableUpdateCompanionBuilder,
          (ClientProfile, $$ClientProfilesTableReferences),
          ClientProfile,
          PrefetchHooks Function({bool companyId, bool userId})
        > {
  $$ClientProfilesTableTableManager(
    _$AppDatabase db,
    $ClientProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> billingAddress = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> adminNotes = const Value.absent(),
                Value<String?> referralSource = const Value.absent(),
                Value<String?> preferredContractorId = const Value.absent(),
                Value<String?> preferredContactMethod = const Value.absent(),
                Value<double?> averageRating = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientProfilesCompanion(
                id: id,
                companyId: companyId,
                userId: userId,
                billingAddress: billingAddress,
                tags: tags,
                adminNotes: adminNotes,
                referralSource: referralSource,
                preferredContractorId: preferredContractorId,
                preferredContactMethod: preferredContactMethod,
                averageRating: averageRating,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                required String userId,
                Value<String?> billingAddress = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> adminNotes = const Value.absent(),
                Value<String?> referralSource = const Value.absent(),
                Value<String?> preferredContractorId = const Value.absent(),
                Value<String?> preferredContactMethod = const Value.absent(),
                Value<double?> averageRating = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientProfilesCompanion.insert(
                id: id,
                companyId: companyId,
                userId: userId,
                billingAddress: billingAddress,
                tags: tags,
                adminNotes: adminNotes,
                referralSource: referralSource,
                preferredContractorId: preferredContractorId,
                preferredContactMethod: preferredContactMethod,
                averageRating: averageRating,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ClientProfilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({companyId = false, userId = false}) {
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
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable: $$ClientProfilesTableReferences
                                    ._companyIdTable(db),
                                referencedColumn:
                                    $$ClientProfilesTableReferences
                                        ._companyIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$ClientProfilesTableReferences
                                    ._userIdTable(db),
                                referencedColumn:
                                    $$ClientProfilesTableReferences
                                        ._userIdTable(db)
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

typedef $$ClientProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientProfilesTable,
      ClientProfile,
      $$ClientProfilesTableFilterComposer,
      $$ClientProfilesTableOrderingComposer,
      $$ClientProfilesTableAnnotationComposer,
      $$ClientProfilesTableCreateCompanionBuilder,
      $$ClientProfilesTableUpdateCompanionBuilder,
      (ClientProfile, $$ClientProfilesTableReferences),
      ClientProfile,
      PrefetchHooks Function({bool companyId, bool userId})
    >;
typedef $$ClientPropertiesTableCreateCompanionBuilder =
    ClientPropertiesCompanion Function({
      Value<String> id,
      required String companyId,
      required String clientId,
      required String jobSiteId,
      Value<String?> nickname,
      Value<bool> isDefault,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ClientPropertiesTableUpdateCompanionBuilder =
    ClientPropertiesCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> clientId,
      Value<String> jobSiteId,
      Value<String?> nickname,
      Value<bool> isDefault,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$ClientPropertiesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ClientPropertiesTable, ClientProperty> {
  $$ClientPropertiesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CompaniesTable _companyIdTable(_$AppDatabase db) =>
      db.companies.createAlias(
        $_aliasNameGenerator(db.clientProperties.companyId, db.companies.id),
      );

  $$CompaniesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompaniesTableTableManager(
      $_db,
      $_db.companies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ClientPropertiesTableFilterComposer
    extends Composer<_$AppDatabase, $ClientPropertiesTable> {
  $$ClientPropertiesTableFilterComposer({
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

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobSiteId => $composableBuilder(
    column: $table.jobSiteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CompaniesTableFilterComposer get companyId {
    final $$CompaniesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableFilterComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClientPropertiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientPropertiesTable> {
  $$ClientPropertiesTableOrderingComposer({
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

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobSiteId => $composableBuilder(
    column: $table.jobSiteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompaniesTableOrderingComposer get companyId {
    final $$CompaniesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableOrderingComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClientPropertiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientPropertiesTable> {
  $$ClientPropertiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get jobSiteId =>
      $composableBuilder(column: $table.jobSiteId, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CompaniesTableAnnotationComposer get companyId {
    final $$CompaniesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableAnnotationComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ClientPropertiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientPropertiesTable,
          ClientProperty,
          $$ClientPropertiesTableFilterComposer,
          $$ClientPropertiesTableOrderingComposer,
          $$ClientPropertiesTableAnnotationComposer,
          $$ClientPropertiesTableCreateCompanionBuilder,
          $$ClientPropertiesTableUpdateCompanionBuilder,
          (ClientProperty, $$ClientPropertiesTableReferences),
          ClientProperty,
          PrefetchHooks Function({bool companyId})
        > {
  $$ClientPropertiesTableTableManager(
    _$AppDatabase db,
    $ClientPropertiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientPropertiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientPropertiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientPropertiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> jobSiteId = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientPropertiesCompanion(
                id: id,
                companyId: companyId,
                clientId: clientId,
                jobSiteId: jobSiteId,
                nickname: nickname,
                isDefault: isDefault,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                required String clientId,
                required String jobSiteId,
                Value<String?> nickname = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientPropertiesCompanion.insert(
                id: id,
                companyId: companyId,
                clientId: clientId,
                jobSiteId: jobSiteId,
                nickname: nickname,
                isDefault: isDefault,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ClientPropertiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({companyId = false}) {
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
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable:
                                    $$ClientPropertiesTableReferences
                                        ._companyIdTable(db),
                                referencedColumn:
                                    $$ClientPropertiesTableReferences
                                        ._companyIdTable(db)
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

typedef $$ClientPropertiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientPropertiesTable,
      ClientProperty,
      $$ClientPropertiesTableFilterComposer,
      $$ClientPropertiesTableOrderingComposer,
      $$ClientPropertiesTableAnnotationComposer,
      $$ClientPropertiesTableCreateCompanionBuilder,
      $$ClientPropertiesTableUpdateCompanionBuilder,
      (ClientProperty, $$ClientPropertiesTableReferences),
      ClientProperty,
      PrefetchHooks Function({bool companyId})
    >;
typedef $$JobRequestsTableCreateCompanionBuilder =
    JobRequestsCompanion Function({
      Value<String> id,
      required String companyId,
      Value<String?> clientId,
      required String description,
      Value<String?> tradeType,
      Value<String> urgency,
      Value<DateTime?> preferredDateStart,
      Value<DateTime?> preferredDateEnd,
      Value<double?> budgetMin,
      Value<double?> budgetMax,
      Value<String> photos,
      Value<String> requestStatus,
      Value<String?> declineReason,
      Value<String?> declineMessage,
      Value<String?> convertedJobId,
      Value<String?> submittedName,
      Value<String?> submittedEmail,
      Value<String?> submittedPhone,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$JobRequestsTableUpdateCompanionBuilder =
    JobRequestsCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String?> clientId,
      Value<String> description,
      Value<String?> tradeType,
      Value<String> urgency,
      Value<DateTime?> preferredDateStart,
      Value<DateTime?> preferredDateEnd,
      Value<double?> budgetMin,
      Value<double?> budgetMax,
      Value<String> photos,
      Value<String> requestStatus,
      Value<String?> declineReason,
      Value<String?> declineMessage,
      Value<String?> convertedJobId,
      Value<String?> submittedName,
      Value<String?> submittedEmail,
      Value<String?> submittedPhone,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$JobRequestsTableReferences
    extends BaseReferences<_$AppDatabase, $JobRequestsTable, JobRequest> {
  $$JobRequestsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CompaniesTable _companyIdTable(_$AppDatabase db) =>
      db.companies.createAlias(
        $_aliasNameGenerator(db.jobRequests.companyId, db.companies.id),
      );

  $$CompaniesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompaniesTableTableManager(
      $_db,
      $_db.companies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$JobRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $JobRequestsTable> {
  $$JobRequestsTableFilterComposer({
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

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tradeType => $composableBuilder(
    column: $table.tradeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urgency => $composableBuilder(
    column: $table.urgency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get preferredDateStart => $composableBuilder(
    column: $table.preferredDateStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get preferredDateEnd => $composableBuilder(
    column: $table.preferredDateEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get budgetMin => $composableBuilder(
    column: $table.budgetMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get budgetMax => $composableBuilder(
    column: $table.budgetMax,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photos => $composableBuilder(
    column: $table.photos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestStatus => $composableBuilder(
    column: $table.requestStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declineReason => $composableBuilder(
    column: $table.declineReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declineMessage => $composableBuilder(
    column: $table.declineMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get convertedJobId => $composableBuilder(
    column: $table.convertedJobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get submittedName => $composableBuilder(
    column: $table.submittedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get submittedEmail => $composableBuilder(
    column: $table.submittedEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get submittedPhone => $composableBuilder(
    column: $table.submittedPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CompaniesTableFilterComposer get companyId {
    final $$CompaniesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableFilterComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $JobRequestsTable> {
  $$JobRequestsTableOrderingComposer({
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

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tradeType => $composableBuilder(
    column: $table.tradeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urgency => $composableBuilder(
    column: $table.urgency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get preferredDateStart => $composableBuilder(
    column: $table.preferredDateStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get preferredDateEnd => $composableBuilder(
    column: $table.preferredDateEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get budgetMin => $composableBuilder(
    column: $table.budgetMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get budgetMax => $composableBuilder(
    column: $table.budgetMax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photos => $composableBuilder(
    column: $table.photos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestStatus => $composableBuilder(
    column: $table.requestStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declineReason => $composableBuilder(
    column: $table.declineReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declineMessage => $composableBuilder(
    column: $table.declineMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get convertedJobId => $composableBuilder(
    column: $table.convertedJobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get submittedName => $composableBuilder(
    column: $table.submittedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get submittedEmail => $composableBuilder(
    column: $table.submittedEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get submittedPhone => $composableBuilder(
    column: $table.submittedPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompaniesTableOrderingComposer get companyId {
    final $$CompaniesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableOrderingComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobRequestsTable> {
  $$JobRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tradeType =>
      $composableBuilder(column: $table.tradeType, builder: (column) => column);

  GeneratedColumn<String> get urgency =>
      $composableBuilder(column: $table.urgency, builder: (column) => column);

  GeneratedColumn<DateTime> get preferredDateStart => $composableBuilder(
    column: $table.preferredDateStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get preferredDateEnd => $composableBuilder(
    column: $table.preferredDateEnd,
    builder: (column) => column,
  );

  GeneratedColumn<double> get budgetMin =>
      $composableBuilder(column: $table.budgetMin, builder: (column) => column);

  GeneratedColumn<double> get budgetMax =>
      $composableBuilder(column: $table.budgetMax, builder: (column) => column);

  GeneratedColumn<String> get photos =>
      $composableBuilder(column: $table.photos, builder: (column) => column);

  GeneratedColumn<String> get requestStatus => $composableBuilder(
    column: $table.requestStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get declineReason => $composableBuilder(
    column: $table.declineReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get declineMessage => $composableBuilder(
    column: $table.declineMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get convertedJobId => $composableBuilder(
    column: $table.convertedJobId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get submittedName => $composableBuilder(
    column: $table.submittedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get submittedEmail => $composableBuilder(
    column: $table.submittedEmail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get submittedPhone => $composableBuilder(
    column: $table.submittedPhone,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CompaniesTableAnnotationComposer get companyId {
    final $$CompaniesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompaniesTableAnnotationComposer(
            $db: $db,
            $table: $db.companies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobRequestsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JobRequestsTable,
          JobRequest,
          $$JobRequestsTableFilterComposer,
          $$JobRequestsTableOrderingComposer,
          $$JobRequestsTableAnnotationComposer,
          $$JobRequestsTableCreateCompanionBuilder,
          $$JobRequestsTableUpdateCompanionBuilder,
          (JobRequest, $$JobRequestsTableReferences),
          JobRequest,
          PrefetchHooks Function({bool companyId})
        > {
  $$JobRequestsTableTableManager(_$AppDatabase db, $JobRequestsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobRequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobRequestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobRequestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String?> clientId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> tradeType = const Value.absent(),
                Value<String> urgency = const Value.absent(),
                Value<DateTime?> preferredDateStart = const Value.absent(),
                Value<DateTime?> preferredDateEnd = const Value.absent(),
                Value<double?> budgetMin = const Value.absent(),
                Value<double?> budgetMax = const Value.absent(),
                Value<String> photos = const Value.absent(),
                Value<String> requestStatus = const Value.absent(),
                Value<String?> declineReason = const Value.absent(),
                Value<String?> declineMessage = const Value.absent(),
                Value<String?> convertedJobId = const Value.absent(),
                Value<String?> submittedName = const Value.absent(),
                Value<String?> submittedEmail = const Value.absent(),
                Value<String?> submittedPhone = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobRequestsCompanion(
                id: id,
                companyId: companyId,
                clientId: clientId,
                description: description,
                tradeType: tradeType,
                urgency: urgency,
                preferredDateStart: preferredDateStart,
                preferredDateEnd: preferredDateEnd,
                budgetMin: budgetMin,
                budgetMax: budgetMax,
                photos: photos,
                requestStatus: requestStatus,
                declineReason: declineReason,
                declineMessage: declineMessage,
                convertedJobId: convertedJobId,
                submittedName: submittedName,
                submittedEmail: submittedEmail,
                submittedPhone: submittedPhone,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                Value<String?> clientId = const Value.absent(),
                required String description,
                Value<String?> tradeType = const Value.absent(),
                Value<String> urgency = const Value.absent(),
                Value<DateTime?> preferredDateStart = const Value.absent(),
                Value<DateTime?> preferredDateEnd = const Value.absent(),
                Value<double?> budgetMin = const Value.absent(),
                Value<double?> budgetMax = const Value.absent(),
                Value<String> photos = const Value.absent(),
                Value<String> requestStatus = const Value.absent(),
                Value<String?> declineReason = const Value.absent(),
                Value<String?> declineMessage = const Value.absent(),
                Value<String?> convertedJobId = const Value.absent(),
                Value<String?> submittedName = const Value.absent(),
                Value<String?> submittedEmail = const Value.absent(),
                Value<String?> submittedPhone = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobRequestsCompanion.insert(
                id: id,
                companyId: companyId,
                clientId: clientId,
                description: description,
                tradeType: tradeType,
                urgency: urgency,
                preferredDateStart: preferredDateStart,
                preferredDateEnd: preferredDateEnd,
                budgetMin: budgetMin,
                budgetMax: budgetMax,
                photos: photos,
                requestStatus: requestStatus,
                declineReason: declineReason,
                declineMessage: declineMessage,
                convertedJobId: convertedJobId,
                submittedName: submittedName,
                submittedEmail: submittedEmail,
                submittedPhone: submittedPhone,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$JobRequestsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({companyId = false}) {
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
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable: $$JobRequestsTableReferences
                                    ._companyIdTable(db),
                                referencedColumn: $$JobRequestsTableReferences
                                    ._companyIdTable(db)
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

typedef $$JobRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JobRequestsTable,
      JobRequest,
      $$JobRequestsTableFilterComposer,
      $$JobRequestsTableOrderingComposer,
      $$JobRequestsTableAnnotationComposer,
      $$JobRequestsTableCreateCompanionBuilder,
      $$JobRequestsTableUpdateCompanionBuilder,
      (JobRequest, $$JobRequestsTableReferences),
      JobRequest,
      PrefetchHooks Function({bool companyId})
    >;
typedef $$BookingsTableCreateCompanionBuilder =
    BookingsCompanion Function({
      Value<String> id,
      required String companyId,
      required String contractorId,
      required String jobId,
      Value<String?> jobSiteId,
      required DateTime timeRangeStart,
      required DateTime timeRangeEnd,
      Value<int?> dayIndex,
      Value<String?> parentBookingId,
      Value<String?> notes,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$BookingsTableUpdateCompanionBuilder =
    BookingsCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> contractorId,
      Value<String> jobId,
      Value<String?> jobSiteId,
      Value<DateTime> timeRangeStart,
      Value<DateTime> timeRangeEnd,
      Value<int?> dayIndex,
      Value<String?> parentBookingId,
      Value<String?> notes,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$BookingsTableFilterComposer
    extends Composer<_$AppDatabase, $BookingsTable> {
  $$BookingsTableFilterComposer({
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

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contractorId => $composableBuilder(
    column: $table.contractorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobSiteId => $composableBuilder(
    column: $table.jobSiteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timeRangeStart => $composableBuilder(
    column: $table.timeRangeStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timeRangeEnd => $composableBuilder(
    column: $table.timeRangeEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayIndex => $composableBuilder(
    column: $table.dayIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentBookingId => $composableBuilder(
    column: $table.parentBookingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BookingsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookingsTable> {
  $$BookingsTableOrderingComposer({
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

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contractorId => $composableBuilder(
    column: $table.contractorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobSiteId => $composableBuilder(
    column: $table.jobSiteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timeRangeStart => $composableBuilder(
    column: $table.timeRangeStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timeRangeEnd => $composableBuilder(
    column: $table.timeRangeEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayIndex => $composableBuilder(
    column: $table.dayIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentBookingId => $composableBuilder(
    column: $table.parentBookingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookingsTable> {
  $$BookingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get contractorId => $composableBuilder(
    column: $table.contractorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get jobSiteId =>
      $composableBuilder(column: $table.jobSiteId, builder: (column) => column);

  GeneratedColumn<DateTime> get timeRangeStart => $composableBuilder(
    column: $table.timeRangeStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timeRangeEnd => $composableBuilder(
    column: $table.timeRangeEnd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dayIndex =>
      $composableBuilder(column: $table.dayIndex, builder: (column) => column);

  GeneratedColumn<String> get parentBookingId => $composableBuilder(
    column: $table.parentBookingId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$BookingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookingsTable,
          Booking,
          $$BookingsTableFilterComposer,
          $$BookingsTableOrderingComposer,
          $$BookingsTableAnnotationComposer,
          $$BookingsTableCreateCompanionBuilder,
          $$BookingsTableUpdateCompanionBuilder,
          (Booking, BaseReferences<_$AppDatabase, $BookingsTable, Booking>),
          Booking,
          PrefetchHooks Function()
        > {
  $$BookingsTableTableManager(_$AppDatabase db, $BookingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> contractorId = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String?> jobSiteId = const Value.absent(),
                Value<DateTime> timeRangeStart = const Value.absent(),
                Value<DateTime> timeRangeEnd = const Value.absent(),
                Value<int?> dayIndex = const Value.absent(),
                Value<String?> parentBookingId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookingsCompanion(
                id: id,
                companyId: companyId,
                contractorId: contractorId,
                jobId: jobId,
                jobSiteId: jobSiteId,
                timeRangeStart: timeRangeStart,
                timeRangeEnd: timeRangeEnd,
                dayIndex: dayIndex,
                parentBookingId: parentBookingId,
                notes: notes,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                required String contractorId,
                required String jobId,
                Value<String?> jobSiteId = const Value.absent(),
                required DateTime timeRangeStart,
                required DateTime timeRangeEnd,
                Value<int?> dayIndex = const Value.absent(),
                Value<String?> parentBookingId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookingsCompanion.insert(
                id: id,
                companyId: companyId,
                contractorId: contractorId,
                jobId: jobId,
                jobSiteId: jobSiteId,
                timeRangeStart: timeRangeStart,
                timeRangeEnd: timeRangeEnd,
                dayIndex: dayIndex,
                parentBookingId: parentBookingId,
                notes: notes,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookingsTable,
      Booking,
      $$BookingsTableFilterComposer,
      $$BookingsTableOrderingComposer,
      $$BookingsTableAnnotationComposer,
      $$BookingsTableCreateCompanionBuilder,
      $$BookingsTableUpdateCompanionBuilder,
      (Booking, BaseReferences<_$AppDatabase, $BookingsTable, Booking>),
      Booking,
      PrefetchHooks Function()
    >;
typedef $$JobSitesTableCreateCompanionBuilder =
    JobSitesCompanion Function({
      Value<String> id,
      required String companyId,
      required String address,
      Value<double?> lat,
      Value<double?> lng,
      Value<String?> formattedAddress,
      Value<int> version,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$JobSitesTableUpdateCompanionBuilder =
    JobSitesCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> address,
      Value<double?> lat,
      Value<double?> lng,
      Value<String?> formattedAddress,
      Value<int> version,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$JobSitesTableFilterComposer
    extends Composer<_$AppDatabase, $JobSitesTable> {
  $$JobSitesTableFilterComposer({
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

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formattedAddress => $composableBuilder(
    column: $table.formattedAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JobSitesTableOrderingComposer
    extends Composer<_$AppDatabase, $JobSitesTable> {
  $$JobSitesTableOrderingComposer({
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

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formattedAddress => $composableBuilder(
    column: $table.formattedAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JobSitesTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobSitesTable> {
  $$JobSitesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get formattedAddress => $composableBuilder(
    column: $table.formattedAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$JobSitesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JobSitesTable,
          JobSite,
          $$JobSitesTableFilterComposer,
          $$JobSitesTableOrderingComposer,
          $$JobSitesTableAnnotationComposer,
          $$JobSitesTableCreateCompanionBuilder,
          $$JobSitesTableUpdateCompanionBuilder,
          (JobSite, BaseReferences<_$AppDatabase, $JobSitesTable, JobSite>),
          JobSite,
          PrefetchHooks Function()
        > {
  $$JobSitesTableTableManager(_$AppDatabase db, $JobSitesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobSitesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobSitesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobSitesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<String?> formattedAddress = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobSitesCompanion(
                id: id,
                companyId: companyId,
                address: address,
                lat: lat,
                lng: lng,
                formattedAddress: formattedAddress,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String companyId,
                required String address,
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<String?> formattedAddress = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobSitesCompanion.insert(
                id: id,
                companyId: companyId,
                address: address,
                lat: lat,
                lng: lng,
                formattedAddress: formattedAddress,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JobSitesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JobSitesTable,
      JobSite,
      $$JobSitesTableFilterComposer,
      $$JobSitesTableOrderingComposer,
      $$JobSitesTableAnnotationComposer,
      $$JobSitesTableCreateCompanionBuilder,
      $$JobSitesTableUpdateCompanionBuilder,
      (JobSite, BaseReferences<_$AppDatabase, $JobSitesTable, JobSite>),
      JobSite,
      PrefetchHooks Function()
    >;

// ---------------------------------------------------------------------------
// Phase 6 — JobNotes table
// ---------------------------------------------------------------------------

class $JobNotesTable extends JobNotes with TableInfo<$JobNotesTable, JobNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version', aliasedName, false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at', aliasedName, true,
    type: DriftSqlType.dateTime, requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns =>
      [id, companyId, jobId, authorId, body, version, createdAt, updatedAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'job_notes';
  @override
  VerificationContext validateIntegrity(Insertable<JobNote> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JobNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JobNote(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      companyId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}company_id'])!,
      jobId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}job_id'])!,
      authorId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}author_id'])!,
      body: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      version: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }
  @override
  $JobNotesTable createAlias(String alias) => $JobNotesTable(attachedDatabase, alias);
}

class JobNote extends DataClass implements Insertable<JobNote> {
  final String id;
  final String companyId;
  final String jobId;
  final String authorId;
  final String body;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const JobNote({
    required this.id,
    required this.companyId,
    required this.jobId,
    required this.authorId,
    required this.body,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['job_id'] = Variable<String>(jobId);
    map['author_id'] = Variable<String>(authorId);
    map['body'] = Variable<String>(body);
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }
  JobNotesCompanion toCompanion(bool nullToAbsent) {
    return JobNotesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      jobId: Value(jobId),
      authorId: Value(authorId),
      body: Value(body),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    );
  }
  factory JobNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JobNote(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      authorId: serializer.fromJson<String>(json['authorId']),
      body: serializer.fromJson<String>(json['body']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'jobId': serializer.toJson<String>(jobId),
      'authorId': serializer.toJson<String>(authorId),
      'body': serializer.toJson<String>(body),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobNote &&
          runtimeType == other.runtimeType &&
          id == other.id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'JobNote(id: $id, jobId: $jobId, body: $body)';
}

class JobNotesCompanion extends UpdateCompanion<JobNote> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> jobId;
  final Value<String> authorId;
  final Value<String> body;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const JobNotesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.authorId = const Value.absent(),
    this.body = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JobNotesCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String jobId,
    required String authorId,
    required String body,
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : companyId = Value(companyId),
        jobId = Value(jobId),
        authorId = Value(authorId),
        body = Value(body),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<String>(id.value);
    if (companyId.present) map['company_id'] = Variable<String>(companyId.value);
    if (jobId.present) map['job_id'] = Variable<String>(jobId.value);
    if (authorId.present) map['author_id'] = Variable<String>(authorId.value);
    if (body.present) map['body'] = Variable<String>(body.value);
    if (version.present) map['version'] = Variable<int>(version.value);
    if (createdAt.present) map['created_at'] = Variable<DateTime>(createdAt.value);
    if (updatedAt.present) map['updated_at'] = Variable<DateTime>(updatedAt.value);
    if (deletedAt.present) map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    if (rowid.present) map['rowid'] = Variable<int>(rowid.value);
    return map;
  }
  @override
  String toString() => 'JobNotesCompanion(id: $id, jobId: $jobId, body: $body)';
}

// ---------------------------------------------------------------------------
// Phase 6 — Attachments table
// ---------------------------------------------------------------------------

class $AttachmentsTable extends Attachments with TableInfo<$AttachmentsTable, Attachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> attachmentType = GeneratedColumn<String>(
    'attachment_type', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> uploadStatus = GeneratedColumn<String>(
    'upload_status', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending_upload'),
  );
  @override
  late final GeneratedColumn<String> remoteUrl = GeneratedColumn<String>(
    'remote_url', aliasedName, true,
    type: DriftSqlType.string, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order', aliasedName, false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at', aliasedName, true,
    type: DriftSqlType.dateTime, requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id, companyId, noteId, attachmentType, localPath, thumbnailPath,
    caption, uploadStatus, remoteUrl, sortOrder, createdAt, updatedAt, deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(Insertable<Attachment> instance,
      {bool isInserting = false}) {
    return VerificationContext();
  }
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      companyId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}company_id'])!,
      noteId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}note_id'])!,
      attachmentType: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}attachment_type'])!,
      localPath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}local_path'])!,
      thumbnailPath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}thumbnail_path']),
      caption: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}caption']),
      uploadStatus: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}upload_status'])!,
      remoteUrl: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}remote_url']),
      sortOrder: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }
  @override
  $AttachmentsTable createAlias(String alias) => $AttachmentsTable(attachedDatabase, alias);
}

class Attachment extends DataClass implements Insertable<Attachment> {
  final String id;
  final String companyId;
  final String noteId;
  final String attachmentType;
  final String localPath;
  final String? thumbnailPath;
  final String? caption;
  final String uploadStatus;
  final String? remoteUrl;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Attachment({
    required this.id,
    required this.companyId,
    required this.noteId,
    required this.attachmentType,
    required this.localPath,
    this.thumbnailPath,
    this.caption,
    required this.uploadStatus,
    this.remoteUrl,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['note_id'] = Variable<String>(noteId);
    map['attachment_type'] = Variable<String>(attachmentType);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || caption != null) {
      map['caption'] = Variable<String>(caption);
    }
    map['upload_status'] = Variable<String>(uploadStatus);
    if (!nullToAbsent || remoteUrl != null) {
      map['remote_url'] = Variable<String>(remoteUrl);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }
  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      noteId: Value(noteId),
      attachmentType: Value(attachmentType),
      localPath: Value(localPath),
      thumbnailPath: Value(thumbnailPath),
      caption: Value(caption),
      uploadStatus: Value(uploadStatus),
      remoteUrl: Value(remoteUrl),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    );
  }
  factory Attachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      attachmentType: serializer.fromJson<String>(json['attachmentType']),
      localPath: serializer.fromJson<String>(json['localPath']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      caption: serializer.fromJson<String?>(json['caption']),
      uploadStatus: serializer.fromJson<String>(json['uploadStatus']),
      remoteUrl: serializer.fromJson<String?>(json['remoteUrl']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'noteId': serializer.toJson<String>(noteId),
      'attachmentType': serializer.toJson<String>(attachmentType),
      'localPath': serializer.toJson<String>(localPath),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'caption': serializer.toJson<String?>(caption),
      'uploadStatus': serializer.toJson<String>(uploadStatus),
      'remoteUrl': serializer.toJson<String?>(remoteUrl),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Attachment && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'Attachment(id: $id, noteId: $noteId, attachmentType: $attachmentType)';
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> noteId;
  final Value<String> attachmentType;
  final Value<String> localPath;
  final Value<String?> thumbnailPath;
  final Value<String?> caption;
  final Value<String> uploadStatus;
  final Value<String?> remoteUrl;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.attachmentType = const Value.absent(),
    this.localPath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.caption = const Value.absent(),
    this.uploadStatus = const Value.absent(),
    this.remoteUrl = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String noteId,
    required String attachmentType,
    required String localPath,
    this.thumbnailPath = const Value.absent(),
    this.caption = const Value.absent(),
    this.uploadStatus = const Value.absent(),
    this.remoteUrl = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : companyId = Value(companyId),
        noteId = Value(noteId),
        attachmentType = Value(attachmentType),
        localPath = Value(localPath),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<String>(id.value);
    if (companyId.present) map['company_id'] = Variable<String>(companyId.value);
    if (noteId.present) map['note_id'] = Variable<String>(noteId.value);
    if (attachmentType.present) map['attachment_type'] = Variable<String>(attachmentType.value);
    if (localPath.present) map['local_path'] = Variable<String>(localPath.value);
    if (thumbnailPath.present) map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    if (caption.present) map['caption'] = Variable<String>(caption.value);
    if (uploadStatus.present) map['upload_status'] = Variable<String>(uploadStatus.value);
    if (remoteUrl.present) map['remote_url'] = Variable<String>(remoteUrl.value);
    if (sortOrder.present) map['sort_order'] = Variable<int>(sortOrder.value);
    if (createdAt.present) map['created_at'] = Variable<DateTime>(createdAt.value);
    if (updatedAt.present) map['updated_at'] = Variable<DateTime>(updatedAt.value);
    if (deletedAt.present) map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    if (rowid.present) map['rowid'] = Variable<int>(rowid.value);
    return map;
  }
  @override
  String toString() => 'AttachmentsCompanion(id: $id, noteId: $noteId)';
}

// ---------------------------------------------------------------------------
// Phase 6 — TimeEntries table
// ---------------------------------------------------------------------------

class $TimeEntriesTable extends TimeEntries with TableInfo<$TimeEntriesTable, TimeEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeEntriesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => const Uuid().v4(),
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<String> contractorId = GeneratedColumn<String>(
    'contractor_id', aliasedName, false,
    type: DriftSqlType.string, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> clockedInAt = GeneratedColumn<DateTime>(
    'clocked_in_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> clockedOutAt = GeneratedColumn<DateTime>(
    'clocked_out_at', aliasedName, true,
    type: DriftSqlType.dateTime, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds', aliasedName, true,
    type: DriftSqlType.int, requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumn<String> sessionStatus = GeneratedColumn<String>(
    'session_status', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  @override
  late final GeneratedColumn<String> adjustmentLog = GeneratedColumn<String>(
    'adjustment_log', aliasedName, false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version', aliasedName, false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at', aliasedName, true,
    type: DriftSqlType.dateTime, requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id, companyId, jobId, contractorId, clockedInAt, clockedOutAt,
    durationSeconds, sessionStatus, adjustmentLog, version,
    createdAt, updatedAt, deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'time_entries';
  @override
  VerificationContext validateIntegrity(Insertable<TimeEntry> instance,
      {bool isInserting = false}) {
    return VerificationContext();
  }
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimeEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimeEntry(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      companyId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}company_id'])!,
      jobId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}job_id'])!,
      contractorId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}contractor_id'])!,
      clockedInAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}clocked_in_at'])!,
      clockedOutAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}clocked_out_at']),
      durationSeconds: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}duration_seconds']),
      sessionStatus: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}session_status'])!,
      adjustmentLog: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}adjustment_log'])!,
      version: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }
  @override
  $TimeEntriesTable createAlias(String alias) => $TimeEntriesTable(attachedDatabase, alias);
}

class TimeEntry extends DataClass implements Insertable<TimeEntry> {
  final String id;
  final String companyId;
  final String jobId;
  final String contractorId;
  final DateTime clockedInAt;
  final DateTime? clockedOutAt;
  final int? durationSeconds;
  final String sessionStatus;
  final String adjustmentLog;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const TimeEntry({
    required this.id,
    required this.companyId,
    required this.jobId,
    required this.contractorId,
    required this.clockedInAt,
    this.clockedOutAt,
    this.durationSeconds,
    required this.sessionStatus,
    required this.adjustmentLog,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['job_id'] = Variable<String>(jobId);
    map['contractor_id'] = Variable<String>(contractorId);
    map['clocked_in_at'] = Variable<DateTime>(clockedInAt);
    if (!nullToAbsent || clockedOutAt != null) {
      map['clocked_out_at'] = Variable<DateTime>(clockedOutAt);
    }
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    map['session_status'] = Variable<String>(sessionStatus);
    map['adjustment_log'] = Variable<String>(adjustmentLog);
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }
  TimeEntriesCompanion toCompanion(bool nullToAbsent) {
    return TimeEntriesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      jobId: Value(jobId),
      contractorId: Value(contractorId),
      clockedInAt: Value(clockedInAt),
      clockedOutAt: Value(clockedOutAt),
      durationSeconds: Value(durationSeconds),
      sessionStatus: Value(sessionStatus),
      adjustmentLog: Value(adjustmentLog),
      version: Value(version),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    );
  }
  factory TimeEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimeEntry(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      contractorId: serializer.fromJson<String>(json['contractorId']),
      clockedInAt: serializer.fromJson<DateTime>(json['clockedInAt']),
      clockedOutAt: serializer.fromJson<DateTime?>(json['clockedOutAt']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      sessionStatus: serializer.fromJson<String>(json['sessionStatus']),
      adjustmentLog: serializer.fromJson<String>(json['adjustmentLog']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'jobId': serializer.toJson<String>(jobId),
      'contractorId': serializer.toJson<String>(contractorId),
      'clockedInAt': serializer.toJson<DateTime>(clockedInAt),
      'clockedOutAt': serializer.toJson<DateTime?>(clockedOutAt),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'sessionStatus': serializer.toJson<String>(sessionStatus),
      'adjustmentLog': serializer.toJson<String>(adjustmentLog),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TimeEntry && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'TimeEntry(id: $id, jobId: $jobId, sessionStatus: $sessionStatus)';
}

class TimeEntriesCompanion extends UpdateCompanion<TimeEntry> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> jobId;
  final Value<String> contractorId;
  final Value<DateTime> clockedInAt;
  final Value<DateTime?> clockedOutAt;
  final Value<int?> durationSeconds;
  final Value<String> sessionStatus;
  final Value<String> adjustmentLog;
  final Value<int> version;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const TimeEntriesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.contractorId = const Value.absent(),
    this.clockedInAt = const Value.absent(),
    this.clockedOutAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.sessionStatus = const Value.absent(),
    this.adjustmentLog = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimeEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String companyId,
    required String jobId,
    required String contractorId,
    required DateTime clockedInAt,
    this.clockedOutAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.sessionStatus = const Value.absent(),
    this.adjustmentLog = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : companyId = Value(companyId),
        jobId = Value(jobId),
        contractorId = Value(contractorId),
        clockedInAt = Value(clockedInAt),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<String>(id.value);
    if (companyId.present) map['company_id'] = Variable<String>(companyId.value);
    if (jobId.present) map['job_id'] = Variable<String>(jobId.value);
    if (contractorId.present) map['contractor_id'] = Variable<String>(contractorId.value);
    if (clockedInAt.present) map['clocked_in_at'] = Variable<DateTime>(clockedInAt.value);
    if (clockedOutAt.present) map['clocked_out_at'] = Variable<DateTime>(clockedOutAt.value);
    if (durationSeconds.present) map['duration_seconds'] = Variable<int>(durationSeconds.value);
    if (sessionStatus.present) map['session_status'] = Variable<String>(sessionStatus.value);
    if (adjustmentLog.present) map['adjustment_log'] = Variable<String>(adjustmentLog.value);
    if (version.present) map['version'] = Variable<int>(version.value);
    if (createdAt.present) map['created_at'] = Variable<DateTime>(createdAt.value);
    if (updatedAt.present) map['updated_at'] = Variable<DateTime>(updatedAt.value);
    if (deletedAt.present) map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    if (rowid.present) map['rowid'] = Variable<int>(rowid.value);
    return map;
  }
  @override
  String toString() => 'TimeEntriesCompanion(id: $id, jobId: $jobId, sessionStatus: $sessionStatus)';
}

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CompaniesTableTableManager get companies =>
      $$CompaniesTableTableManager(_db, _db.companies);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$UserRolesTableTableManager get userRoles =>
      $$UserRolesTableTableManager(_db, _db.userRoles);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$SyncCursorTableTableManager get syncCursor =>
      $$SyncCursorTableTableManager(_db, _db.syncCursor);
  $$JobsTableTableManager get jobs => $$JobsTableTableManager(_db, _db.jobs);
  $$ClientProfilesTableTableManager get clientProfiles =>
      $$ClientProfilesTableTableManager(_db, _db.clientProfiles);
  $$ClientPropertiesTableTableManager get clientProperties =>
      $$ClientPropertiesTableTableManager(_db, _db.clientProperties);
  $$JobRequestsTableTableManager get jobRequests =>
      $$JobRequestsTableTableManager(_db, _db.jobRequests);
  $$BookingsTableTableManager get bookings =>
      $$BookingsTableTableManager(_db, _db.bookings);
  $$JobSitesTableTableManager get jobSites =>
      $$JobSitesTableTableManager(_db, _db.jobSites);
}
