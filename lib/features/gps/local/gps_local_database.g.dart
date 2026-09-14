// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gps_local_database.dart';

// ignore_for_file: type=lint
class $LocalRecordedRoutesTable extends LocalRecordedRoutes
    with TableInfo<$LocalRecordedRoutesTable, LocalRecordedRoute> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRecordedRoutesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tripIdMeta = const VerificationMeta('tripId');
  @override
  late final GeneratedColumn<String> tripId = GeneratedColumn<String>(
      'trip_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _transportModeMeta =
      const VerificationMeta('transportMode');
  @override
  late final GeneratedColumn<String> transportMode = GeneratedColumn<String>(
      'transport_mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('walking'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(RecordedRouteStatus.recording));
  static const VerificationMeta _visibilityMeta =
      const VerificationMeta('visibility');
  @override
  late final GeneratedColumn<String> visibility = GeneratedColumn<String>(
      'visibility', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('private'));
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(RouteSyncStatus.notSynced));
  static const VerificationMeta _lastSyncedPointSeqMeta =
      const VerificationMeta('lastSyncedPointSeq');
  @override
  late final GeneratedColumn<int> lastSyncedPointSeq = GeneratedColumn<int>(
      'last_synced_point_seq', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastSyncedEventSeqMeta =
      const VerificationMeta('lastSyncedEventSeq');
  @override
  late final GeneratedColumn<int> lastSyncedEventSeq = GeneratedColumn<int>(
      'last_synced_event_seq', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastSyncAttemptAtMeta =
      const VerificationMeta('lastSyncAttemptAt');
  @override
  late final GeneratedColumn<DateTime> lastSyncAttemptAt =
      GeneratedColumn<DateTime>('last_sync_attempt_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastSyncErrorMeta =
      const VerificationMeta('lastSyncError');
  @override
  late final GeneratedColumn<String> lastSyncError = GeneratedColumn<String>(
      'last_sync_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ownerId,
        tripId,
        title,
        transportMode,
        status,
        visibility,
        startedAt,
        endedAt,
        createdAt,
        updatedAt,
        syncStatus,
        lastSyncedPointSeq,
        lastSyncedEventSeq,
        lastSyncAttemptAt,
        lastSyncError
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_recorded_routes';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRecordedRoute> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('trip_id')) {
      context.handle(_tripIdMeta,
          tripId.isAcceptableOrUnknown(data['trip_id']!, _tripIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('transport_mode')) {
      context.handle(
          _transportModeMeta,
          transportMode.isAcceptableOrUnknown(
              data['transport_mode']!, _transportModeMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('visibility')) {
      context.handle(
          _visibilityMeta,
          visibility.isAcceptableOrUnknown(
              data['visibility']!, _visibilityMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    }
    if (data.containsKey('last_synced_point_seq')) {
      context.handle(
          _lastSyncedPointSeqMeta,
          lastSyncedPointSeq.isAcceptableOrUnknown(
              data['last_synced_point_seq']!, _lastSyncedPointSeqMeta));
    }
    if (data.containsKey('last_synced_event_seq')) {
      context.handle(
          _lastSyncedEventSeqMeta,
          lastSyncedEventSeq.isAcceptableOrUnknown(
              data['last_synced_event_seq']!, _lastSyncedEventSeqMeta));
    }
    if (data.containsKey('last_sync_attempt_at')) {
      context.handle(
          _lastSyncAttemptAtMeta,
          lastSyncAttemptAt.isAcceptableOrUnknown(
              data['last_sync_attempt_at']!, _lastSyncAttemptAtMeta));
    }
    if (data.containsKey('last_sync_error')) {
      context.handle(
          _lastSyncErrorMeta,
          lastSyncError.isAcceptableOrUnknown(
              data['last_sync_error']!, _lastSyncErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalRecordedRoute map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRecordedRoute(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      tripId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}trip_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      transportMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}transport_mode'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      visibility: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}visibility'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
      lastSyncedPointSeq: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_synced_point_seq']),
      lastSyncedEventSeq: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_synced_event_seq']),
      lastSyncAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_sync_attempt_at']),
      lastSyncError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_sync_error']),
    );
  }

  @override
  $LocalRecordedRoutesTable createAlias(String alias) {
    return $LocalRecordedRoutesTable(attachedDatabase, alias);
  }
}

class LocalRecordedRoute extends DataClass
    implements Insertable<LocalRecordedRoute> {
  final String id;
  final String ownerId;
  final String? tripId;
  final String? title;
  final String transportMode;
  final String status;
  final String visibility;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final int? lastSyncedPointSeq;
  final int? lastSyncedEventSeq;
  final DateTime? lastSyncAttemptAt;
  final String? lastSyncError;
  const LocalRecordedRoute(
      {required this.id,
      required this.ownerId,
      this.tripId,
      this.title,
      required this.transportMode,
      required this.status,
      required this.visibility,
      required this.startedAt,
      this.endedAt,
      required this.createdAt,
      required this.updatedAt,
      required this.syncStatus,
      this.lastSyncedPointSeq,
      this.lastSyncedEventSeq,
      this.lastSyncAttemptAt,
      this.lastSyncError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    if (!nullToAbsent || tripId != null) {
      map['trip_id'] = Variable<String>(tripId);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['transport_mode'] = Variable<String>(transportMode);
    map['status'] = Variable<String>(status);
    map['visibility'] = Variable<String>(visibility);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || lastSyncedPointSeq != null) {
      map['last_synced_point_seq'] = Variable<int>(lastSyncedPointSeq);
    }
    if (!nullToAbsent || lastSyncedEventSeq != null) {
      map['last_synced_event_seq'] = Variable<int>(lastSyncedEventSeq);
    }
    if (!nullToAbsent || lastSyncAttemptAt != null) {
      map['last_sync_attempt_at'] = Variable<DateTime>(lastSyncAttemptAt);
    }
    if (!nullToAbsent || lastSyncError != null) {
      map['last_sync_error'] = Variable<String>(lastSyncError);
    }
    return map;
  }

  LocalRecordedRoutesCompanion toCompanion(bool nullToAbsent) {
    return LocalRecordedRoutesCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      tripId:
          tripId == null && nullToAbsent ? const Value.absent() : Value(tripId),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      transportMode: Value(transportMode),
      status: Value(status),
      visibility: Value(visibility),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      syncStatus: Value(syncStatus),
      lastSyncedPointSeq: lastSyncedPointSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedPointSeq),
      lastSyncedEventSeq: lastSyncedEventSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedEventSeq),
      lastSyncAttemptAt: lastSyncAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAttemptAt),
      lastSyncError: lastSyncError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncError),
    );
  }

  factory LocalRecordedRoute.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRecordedRoute(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      tripId: serializer.fromJson<String?>(json['tripId']),
      title: serializer.fromJson<String?>(json['title']),
      transportMode: serializer.fromJson<String>(json['transportMode']),
      status: serializer.fromJson<String>(json['status']),
      visibility: serializer.fromJson<String>(json['visibility']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      lastSyncedPointSeq: serializer.fromJson<int?>(json['lastSyncedPointSeq']),
      lastSyncedEventSeq: serializer.fromJson<int?>(json['lastSyncedEventSeq']),
      lastSyncAttemptAt:
          serializer.fromJson<DateTime?>(json['lastSyncAttemptAt']),
      lastSyncError: serializer.fromJson<String?>(json['lastSyncError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'tripId': serializer.toJson<String?>(tripId),
      'title': serializer.toJson<String?>(title),
      'transportMode': serializer.toJson<String>(transportMode),
      'status': serializer.toJson<String>(status),
      'visibility': serializer.toJson<String>(visibility),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'lastSyncedPointSeq': serializer.toJson<int?>(lastSyncedPointSeq),
      'lastSyncedEventSeq': serializer.toJson<int?>(lastSyncedEventSeq),
      'lastSyncAttemptAt': serializer.toJson<DateTime?>(lastSyncAttemptAt),
      'lastSyncError': serializer.toJson<String?>(lastSyncError),
    };
  }

  LocalRecordedRoute copyWith(
          {String? id,
          String? ownerId,
          Value<String?> tripId = const Value.absent(),
          Value<String?> title = const Value.absent(),
          String? transportMode,
          String? status,
          String? visibility,
          DateTime? startedAt,
          Value<DateTime?> endedAt = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          String? syncStatus,
          Value<int?> lastSyncedPointSeq = const Value.absent(),
          Value<int?> lastSyncedEventSeq = const Value.absent(),
          Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
          Value<String?> lastSyncError = const Value.absent()}) =>
      LocalRecordedRoute(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        tripId: tripId.present ? tripId.value : this.tripId,
        title: title.present ? title.value : this.title,
        transportMode: transportMode ?? this.transportMode,
        status: status ?? this.status,
        visibility: visibility ?? this.visibility,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        lastSyncedPointSeq: lastSyncedPointSeq.present
            ? lastSyncedPointSeq.value
            : this.lastSyncedPointSeq,
        lastSyncedEventSeq: lastSyncedEventSeq.present
            ? lastSyncedEventSeq.value
            : this.lastSyncedEventSeq,
        lastSyncAttemptAt: lastSyncAttemptAt.present
            ? lastSyncAttemptAt.value
            : this.lastSyncAttemptAt,
        lastSyncError:
            lastSyncError.present ? lastSyncError.value : this.lastSyncError,
      );
  LocalRecordedRoute copyWithCompanion(LocalRecordedRoutesCompanion data) {
    return LocalRecordedRoute(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      tripId: data.tripId.present ? data.tripId.value : this.tripId,
      title: data.title.present ? data.title.value : this.title,
      transportMode: data.transportMode.present
          ? data.transportMode.value
          : this.transportMode,
      status: data.status.present ? data.status.value : this.status,
      visibility:
          data.visibility.present ? data.visibility.value : this.visibility,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
      lastSyncedPointSeq: data.lastSyncedPointSeq.present
          ? data.lastSyncedPointSeq.value
          : this.lastSyncedPointSeq,
      lastSyncedEventSeq: data.lastSyncedEventSeq.present
          ? data.lastSyncedEventSeq.value
          : this.lastSyncedEventSeq,
      lastSyncAttemptAt: data.lastSyncAttemptAt.present
          ? data.lastSyncAttemptAt.value
          : this.lastSyncAttemptAt,
      lastSyncError: data.lastSyncError.present
          ? data.lastSyncError.value
          : this.lastSyncError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordedRoute(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('tripId: $tripId, ')
          ..write('title: $title, ')
          ..write('transportMode: $transportMode, ')
          ..write('status: $status, ')
          ..write('visibility: $visibility, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastSyncedPointSeq: $lastSyncedPointSeq, ')
          ..write('lastSyncedEventSeq: $lastSyncedEventSeq, ')
          ..write('lastSyncAttemptAt: $lastSyncAttemptAt, ')
          ..write('lastSyncError: $lastSyncError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      ownerId,
      tripId,
      title,
      transportMode,
      status,
      visibility,
      startedAt,
      endedAt,
      createdAt,
      updatedAt,
      syncStatus,
      lastSyncedPointSeq,
      lastSyncedEventSeq,
      lastSyncAttemptAt,
      lastSyncError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRecordedRoute &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.tripId == this.tripId &&
          other.title == this.title &&
          other.transportMode == this.transportMode &&
          other.status == this.status &&
          other.visibility == this.visibility &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.syncStatus == this.syncStatus &&
          other.lastSyncedPointSeq == this.lastSyncedPointSeq &&
          other.lastSyncedEventSeq == this.lastSyncedEventSeq &&
          other.lastSyncAttemptAt == this.lastSyncAttemptAt &&
          other.lastSyncError == this.lastSyncError);
}

class LocalRecordedRoutesCompanion extends UpdateCompanion<LocalRecordedRoute> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String?> tripId;
  final Value<String?> title;
  final Value<String> transportMode;
  final Value<String> status;
  final Value<String> visibility;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> syncStatus;
  final Value<int?> lastSyncedPointSeq;
  final Value<int?> lastSyncedEventSeq;
  final Value<DateTime?> lastSyncAttemptAt;
  final Value<String?> lastSyncError;
  final Value<int> rowid;
  const LocalRecordedRoutesCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.tripId = const Value.absent(),
    this.title = const Value.absent(),
    this.transportMode = const Value.absent(),
    this.status = const Value.absent(),
    this.visibility = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.lastSyncedPointSeq = const Value.absent(),
    this.lastSyncedEventSeq = const Value.absent(),
    this.lastSyncAttemptAt = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRecordedRoutesCompanion.insert({
    required String id,
    required String ownerId,
    this.tripId = const Value.absent(),
    this.title = const Value.absent(),
    this.transportMode = const Value.absent(),
    this.status = const Value.absent(),
    this.visibility = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.syncStatus = const Value.absent(),
    this.lastSyncedPointSeq = const Value.absent(),
    this.lastSyncedEventSeq = const Value.absent(),
    this.lastSyncAttemptAt = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ownerId = Value(ownerId),
        startedAt = Value(startedAt),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<LocalRecordedRoute> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? tripId,
    Expression<String>? title,
    Expression<String>? transportMode,
    Expression<String>? status,
    Expression<String>? visibility,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? syncStatus,
    Expression<int>? lastSyncedPointSeq,
    Expression<int>? lastSyncedEventSeq,
    Expression<DateTime>? lastSyncAttemptAt,
    Expression<String>? lastSyncError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (tripId != null) 'trip_id': tripId,
      if (title != null) 'title': title,
      if (transportMode != null) 'transport_mode': transportMode,
      if (status != null) 'status': status,
      if (visibility != null) 'visibility': visibility,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (lastSyncedPointSeq != null)
        'last_synced_point_seq': lastSyncedPointSeq,
      if (lastSyncedEventSeq != null)
        'last_synced_event_seq': lastSyncedEventSeq,
      if (lastSyncAttemptAt != null) 'last_sync_attempt_at': lastSyncAttemptAt,
      if (lastSyncError != null) 'last_sync_error': lastSyncError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRecordedRoutesCompanion copyWith(
      {Value<String>? id,
      Value<String>? ownerId,
      Value<String?>? tripId,
      Value<String?>? title,
      Value<String>? transportMode,
      Value<String>? status,
      Value<String>? visibility,
      Value<DateTime>? startedAt,
      Value<DateTime?>? endedAt,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<String>? syncStatus,
      Value<int?>? lastSyncedPointSeq,
      Value<int?>? lastSyncedEventSeq,
      Value<DateTime?>? lastSyncAttemptAt,
      Value<String?>? lastSyncError,
      Value<int>? rowid}) {
    return LocalRecordedRoutesCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      tripId: tripId ?? this.tripId,
      title: title ?? this.title,
      transportMode: transportMode ?? this.transportMode,
      status: status ?? this.status,
      visibility: visibility ?? this.visibility,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedPointSeq: lastSyncedPointSeq ?? this.lastSyncedPointSeq,
      lastSyncedEventSeq: lastSyncedEventSeq ?? this.lastSyncedEventSeq,
      lastSyncAttemptAt: lastSyncAttemptAt ?? this.lastSyncAttemptAt,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (tripId.present) {
      map['trip_id'] = Variable<String>(tripId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (transportMode.present) {
      map['transport_mode'] = Variable<String>(transportMode.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (visibility.present) {
      map['visibility'] = Variable<String>(visibility.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (lastSyncedPointSeq.present) {
      map['last_synced_point_seq'] = Variable<int>(lastSyncedPointSeq.value);
    }
    if (lastSyncedEventSeq.present) {
      map['last_synced_event_seq'] = Variable<int>(lastSyncedEventSeq.value);
    }
    if (lastSyncAttemptAt.present) {
      map['last_sync_attempt_at'] = Variable<DateTime>(lastSyncAttemptAt.value);
    }
    if (lastSyncError.present) {
      map['last_sync_error'] = Variable<String>(lastSyncError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordedRoutesCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('tripId: $tripId, ')
          ..write('title: $title, ')
          ..write('transportMode: $transportMode, ')
          ..write('status: $status, ')
          ..write('visibility: $visibility, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastSyncedPointSeq: $lastSyncedPointSeq, ')
          ..write('lastSyncedEventSeq: $lastSyncedEventSeq, ')
          ..write('lastSyncAttemptAt: $lastSyncAttemptAt, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalRoutePointsTable extends LocalRoutePoints
    with TableInfo<$LocalRoutePointsTable, LocalRoutePoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRoutePointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordedRouteIdMeta =
      const VerificationMeta('recordedRouteId');
  @override
  late final GeneratedColumn<String> recordedRouteId = GeneratedColumn<String>(
      'recorded_route_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _altitudeMeta =
      const VerificationMeta('altitude');
  @override
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
      'altitude', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _horizontalAccuracyMeta =
      const VerificationMeta('horizontalAccuracy');
  @override
  late final GeneratedColumn<double> horizontalAccuracy =
      GeneratedColumn<double>('horizontal_accuracy', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _verticalAccuracyMeta =
      const VerificationMeta('verticalAccuracy');
  @override
  late final GeneratedColumn<double> verticalAccuracy = GeneratedColumn<double>(
      'vertical_accuracy', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
      'speed', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _speedAccuracyMeta =
      const VerificationMeta('speedAccuracy');
  @override
  late final GeneratedColumn<double> speedAccuracy = GeneratedColumn<double>(
      'speed_accuracy', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _headingMeta =
      const VerificationMeta('heading');
  @override
  late final GeneratedColumn<double> heading = GeneratedColumn<double>(
      'heading', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _headingAccuracyMeta =
      const VerificationMeta('headingAccuracy');
  @override
  late final GeneratedColumn<double> headingAccuracy = GeneratedColumn<double>(
      'heading_accuracy', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _recordedAtMeta =
      const VerificationMeta('recordedAt');
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
      'recorded_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        recordedRouteId,
        seq,
        ownerId,
        latitude,
        longitude,
        altitude,
        horizontalAccuracy,
        verticalAccuracy,
        speed,
        speedAccuracy,
        heading,
        headingAccuracy,
        recordedAt,
        provider
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_route_points';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRoutePoint> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recorded_route_id')) {
      context.handle(
          _recordedRouteIdMeta,
          recordedRouteId.isAcceptableOrUnknown(
              data['recorded_route_id']!, _recordedRouteIdMeta));
    } else if (isInserting) {
      context.missing(_recordedRouteIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('altitude')) {
      context.handle(_altitudeMeta,
          altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta));
    }
    if (data.containsKey('horizontal_accuracy')) {
      context.handle(
          _horizontalAccuracyMeta,
          horizontalAccuracy.isAcceptableOrUnknown(
              data['horizontal_accuracy']!, _horizontalAccuracyMeta));
    }
    if (data.containsKey('vertical_accuracy')) {
      context.handle(
          _verticalAccuracyMeta,
          verticalAccuracy.isAcceptableOrUnknown(
              data['vertical_accuracy']!, _verticalAccuracyMeta));
    }
    if (data.containsKey('speed')) {
      context.handle(
          _speedMeta, speed.isAcceptableOrUnknown(data['speed']!, _speedMeta));
    }
    if (data.containsKey('speed_accuracy')) {
      context.handle(
          _speedAccuracyMeta,
          speedAccuracy.isAcceptableOrUnknown(
              data['speed_accuracy']!, _speedAccuracyMeta));
    }
    if (data.containsKey('heading')) {
      context.handle(_headingMeta,
          heading.isAcceptableOrUnknown(data['heading']!, _headingMeta));
    }
    if (data.containsKey('heading_accuracy')) {
      context.handle(
          _headingAccuracyMeta,
          headingAccuracy.isAcceptableOrUnknown(
              data['heading_accuracy']!, _headingAccuracyMeta));
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
          _recordedAtMeta,
          recordedAt.isAcceptableOrUnknown(
              data['recorded_at']!, _recordedAtMeta));
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordedRouteId, seq};
  @override
  LocalRoutePoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRoutePoint(
      recordedRouteId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recorded_route_id'])!,
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      altitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}altitude']),
      horizontalAccuracy: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}horizontal_accuracy']),
      verticalAccuracy: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}vertical_accuracy']),
      speed: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}speed']),
      speedAccuracy: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}speed_accuracy']),
      heading: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}heading']),
      headingAccuracy: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}heading_accuracy']),
      recordedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}recorded_at'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider']),
    );
  }

  @override
  $LocalRoutePointsTable createAlias(String alias) {
    return $LocalRoutePointsTable(attachedDatabase, alias);
  }
}

class LocalRoutePoint extends DataClass implements Insertable<LocalRoutePoint> {
  final String recordedRouteId;
  final int seq;
  final String ownerId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? horizontalAccuracy;
  final double? verticalAccuracy;
  final double? speed;
  final double? speedAccuracy;
  final double? heading;
  final double? headingAccuracy;
  final DateTime recordedAt;
  final String? provider;
  const LocalRoutePoint(
      {required this.recordedRouteId,
      required this.seq,
      required this.ownerId,
      required this.latitude,
      required this.longitude,
      this.altitude,
      this.horizontalAccuracy,
      this.verticalAccuracy,
      this.speed,
      this.speedAccuracy,
      this.heading,
      this.headingAccuracy,
      required this.recordedAt,
      this.provider});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recorded_route_id'] = Variable<String>(recordedRouteId);
    map['seq'] = Variable<int>(seq);
    map['owner_id'] = Variable<String>(ownerId);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    if (!nullToAbsent || horizontalAccuracy != null) {
      map['horizontal_accuracy'] = Variable<double>(horizontalAccuracy);
    }
    if (!nullToAbsent || verticalAccuracy != null) {
      map['vertical_accuracy'] = Variable<double>(verticalAccuracy);
    }
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    if (!nullToAbsent || speedAccuracy != null) {
      map['speed_accuracy'] = Variable<double>(speedAccuracy);
    }
    if (!nullToAbsent || heading != null) {
      map['heading'] = Variable<double>(heading);
    }
    if (!nullToAbsent || headingAccuracy != null) {
      map['heading_accuracy'] = Variable<double>(headingAccuracy);
    }
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    return map;
  }

  LocalRoutePointsCompanion toCompanion(bool nullToAbsent) {
    return LocalRoutePointsCompanion(
      recordedRouteId: Value(recordedRouteId),
      seq: Value(seq),
      ownerId: Value(ownerId),
      latitude: Value(latitude),
      longitude: Value(longitude),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      horizontalAccuracy: horizontalAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(horizontalAccuracy),
      verticalAccuracy: verticalAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(verticalAccuracy),
      speed:
          speed == null && nullToAbsent ? const Value.absent() : Value(speed),
      speedAccuracy: speedAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(speedAccuracy),
      heading: heading == null && nullToAbsent
          ? const Value.absent()
          : Value(heading),
      headingAccuracy: headingAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(headingAccuracy),
      recordedAt: Value(recordedAt),
      provider: provider == null && nullToAbsent
          ? const Value.absent()
          : Value(provider),
    );
  }

  factory LocalRoutePoint.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRoutePoint(
      recordedRouteId: serializer.fromJson<String>(json['recordedRouteId']),
      seq: serializer.fromJson<int>(json['seq']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      altitude: serializer.fromJson<double?>(json['altitude']),
      horizontalAccuracy:
          serializer.fromJson<double?>(json['horizontalAccuracy']),
      verticalAccuracy: serializer.fromJson<double?>(json['verticalAccuracy']),
      speed: serializer.fromJson<double?>(json['speed']),
      speedAccuracy: serializer.fromJson<double?>(json['speedAccuracy']),
      heading: serializer.fromJson<double?>(json['heading']),
      headingAccuracy: serializer.fromJson<double?>(json['headingAccuracy']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
      provider: serializer.fromJson<String?>(json['provider']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordedRouteId': serializer.toJson<String>(recordedRouteId),
      'seq': serializer.toJson<int>(seq),
      'ownerId': serializer.toJson<String>(ownerId),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'altitude': serializer.toJson<double?>(altitude),
      'horizontalAccuracy': serializer.toJson<double?>(horizontalAccuracy),
      'verticalAccuracy': serializer.toJson<double?>(verticalAccuracy),
      'speed': serializer.toJson<double?>(speed),
      'speedAccuracy': serializer.toJson<double?>(speedAccuracy),
      'heading': serializer.toJson<double?>(heading),
      'headingAccuracy': serializer.toJson<double?>(headingAccuracy),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
      'provider': serializer.toJson<String?>(provider),
    };
  }

  LocalRoutePoint copyWith(
          {String? recordedRouteId,
          int? seq,
          String? ownerId,
          double? latitude,
          double? longitude,
          Value<double?> altitude = const Value.absent(),
          Value<double?> horizontalAccuracy = const Value.absent(),
          Value<double?> verticalAccuracy = const Value.absent(),
          Value<double?> speed = const Value.absent(),
          Value<double?> speedAccuracy = const Value.absent(),
          Value<double?> heading = const Value.absent(),
          Value<double?> headingAccuracy = const Value.absent(),
          DateTime? recordedAt,
          Value<String?> provider = const Value.absent()}) =>
      LocalRoutePoint(
        recordedRouteId: recordedRouteId ?? this.recordedRouteId,
        seq: seq ?? this.seq,
        ownerId: ownerId ?? this.ownerId,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        altitude: altitude.present ? altitude.value : this.altitude,
        horizontalAccuracy: horizontalAccuracy.present
            ? horizontalAccuracy.value
            : this.horizontalAccuracy,
        verticalAccuracy: verticalAccuracy.present
            ? verticalAccuracy.value
            : this.verticalAccuracy,
        speed: speed.present ? speed.value : this.speed,
        speedAccuracy:
            speedAccuracy.present ? speedAccuracy.value : this.speedAccuracy,
        heading: heading.present ? heading.value : this.heading,
        headingAccuracy: headingAccuracy.present
            ? headingAccuracy.value
            : this.headingAccuracy,
        recordedAt: recordedAt ?? this.recordedAt,
        provider: provider.present ? provider.value : this.provider,
      );
  LocalRoutePoint copyWithCompanion(LocalRoutePointsCompanion data) {
    return LocalRoutePoint(
      recordedRouteId: data.recordedRouteId.present
          ? data.recordedRouteId.value
          : this.recordedRouteId,
      seq: data.seq.present ? data.seq.value : this.seq,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      horizontalAccuracy: data.horizontalAccuracy.present
          ? data.horizontalAccuracy.value
          : this.horizontalAccuracy,
      verticalAccuracy: data.verticalAccuracy.present
          ? data.verticalAccuracy.value
          : this.verticalAccuracy,
      speed: data.speed.present ? data.speed.value : this.speed,
      speedAccuracy: data.speedAccuracy.present
          ? data.speedAccuracy.value
          : this.speedAccuracy,
      heading: data.heading.present ? data.heading.value : this.heading,
      headingAccuracy: data.headingAccuracy.present
          ? data.headingAccuracy.value
          : this.headingAccuracy,
      recordedAt:
          data.recordedAt.present ? data.recordedAt.value : this.recordedAt,
      provider: data.provider.present ? data.provider.value : this.provider,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRoutePoint(')
          ..write('recordedRouteId: $recordedRouteId, ')
          ..write('seq: $seq, ')
          ..write('ownerId: $ownerId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('horizontalAccuracy: $horizontalAccuracy, ')
          ..write('verticalAccuracy: $verticalAccuracy, ')
          ..write('speed: $speed, ')
          ..write('speedAccuracy: $speedAccuracy, ')
          ..write('heading: $heading, ')
          ..write('headingAccuracy: $headingAccuracy, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('provider: $provider')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      recordedRouteId,
      seq,
      ownerId,
      latitude,
      longitude,
      altitude,
      horizontalAccuracy,
      verticalAccuracy,
      speed,
      speedAccuracy,
      heading,
      headingAccuracy,
      recordedAt,
      provider);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRoutePoint &&
          other.recordedRouteId == this.recordedRouteId &&
          other.seq == this.seq &&
          other.ownerId == this.ownerId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitude == this.altitude &&
          other.horizontalAccuracy == this.horizontalAccuracy &&
          other.verticalAccuracy == this.verticalAccuracy &&
          other.speed == this.speed &&
          other.speedAccuracy == this.speedAccuracy &&
          other.heading == this.heading &&
          other.headingAccuracy == this.headingAccuracy &&
          other.recordedAt == this.recordedAt &&
          other.provider == this.provider);
}

class LocalRoutePointsCompanion extends UpdateCompanion<LocalRoutePoint> {
  final Value<String> recordedRouteId;
  final Value<int> seq;
  final Value<String> ownerId;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> altitude;
  final Value<double?> horizontalAccuracy;
  final Value<double?> verticalAccuracy;
  final Value<double?> speed;
  final Value<double?> speedAccuracy;
  final Value<double?> heading;
  final Value<double?> headingAccuracy;
  final Value<DateTime> recordedAt;
  final Value<String?> provider;
  final Value<int> rowid;
  const LocalRoutePointsCompanion({
    this.recordedRouteId = const Value.absent(),
    this.seq = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.horizontalAccuracy = const Value.absent(),
    this.verticalAccuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.speedAccuracy = const Value.absent(),
    this.heading = const Value.absent(),
    this.headingAccuracy = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.provider = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRoutePointsCompanion.insert({
    required String recordedRouteId,
    required int seq,
    required String ownerId,
    required double latitude,
    required double longitude,
    this.altitude = const Value.absent(),
    this.horizontalAccuracy = const Value.absent(),
    this.verticalAccuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.speedAccuracy = const Value.absent(),
    this.heading = const Value.absent(),
    this.headingAccuracy = const Value.absent(),
    required DateTime recordedAt,
    this.provider = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : recordedRouteId = Value(recordedRouteId),
        seq = Value(seq),
        ownerId = Value(ownerId),
        latitude = Value(latitude),
        longitude = Value(longitude),
        recordedAt = Value(recordedAt);
  static Insertable<LocalRoutePoint> custom({
    Expression<String>? recordedRouteId,
    Expression<int>? seq,
    Expression<String>? ownerId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitude,
    Expression<double>? horizontalAccuracy,
    Expression<double>? verticalAccuracy,
    Expression<double>? speed,
    Expression<double>? speedAccuracy,
    Expression<double>? heading,
    Expression<double>? headingAccuracy,
    Expression<DateTime>? recordedAt,
    Expression<String>? provider,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordedRouteId != null) 'recorded_route_id': recordedRouteId,
      if (seq != null) 'seq': seq,
      if (ownerId != null) 'owner_id': ownerId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (horizontalAccuracy != null) 'horizontal_accuracy': horizontalAccuracy,
      if (verticalAccuracy != null) 'vertical_accuracy': verticalAccuracy,
      if (speed != null) 'speed': speed,
      if (speedAccuracy != null) 'speed_accuracy': speedAccuracy,
      if (heading != null) 'heading': heading,
      if (headingAccuracy != null) 'heading_accuracy': headingAccuracy,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (provider != null) 'provider': provider,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRoutePointsCompanion copyWith(
      {Value<String>? recordedRouteId,
      Value<int>? seq,
      Value<String>? ownerId,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<double?>? altitude,
      Value<double?>? horizontalAccuracy,
      Value<double?>? verticalAccuracy,
      Value<double?>? speed,
      Value<double?>? speedAccuracy,
      Value<double?>? heading,
      Value<double?>? headingAccuracy,
      Value<DateTime>? recordedAt,
      Value<String?>? provider,
      Value<int>? rowid}) {
    return LocalRoutePointsCompanion(
      recordedRouteId: recordedRouteId ?? this.recordedRouteId,
      seq: seq ?? this.seq,
      ownerId: ownerId ?? this.ownerId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      horizontalAccuracy: horizontalAccuracy ?? this.horizontalAccuracy,
      verticalAccuracy: verticalAccuracy ?? this.verticalAccuracy,
      speed: speed ?? this.speed,
      speedAccuracy: speedAccuracy ?? this.speedAccuracy,
      heading: heading ?? this.heading,
      headingAccuracy: headingAccuracy ?? this.headingAccuracy,
      recordedAt: recordedAt ?? this.recordedAt,
      provider: provider ?? this.provider,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordedRouteId.present) {
      map['recorded_route_id'] = Variable<String>(recordedRouteId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (horizontalAccuracy.present) {
      map['horizontal_accuracy'] = Variable<double>(horizontalAccuracy.value);
    }
    if (verticalAccuracy.present) {
      map['vertical_accuracy'] = Variable<double>(verticalAccuracy.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (speedAccuracy.present) {
      map['speed_accuracy'] = Variable<double>(speedAccuracy.value);
    }
    if (heading.present) {
      map['heading'] = Variable<double>(heading.value);
    }
    if (headingAccuracy.present) {
      map['heading_accuracy'] = Variable<double>(headingAccuracy.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRoutePointsCompanion(')
          ..write('recordedRouteId: $recordedRouteId, ')
          ..write('seq: $seq, ')
          ..write('ownerId: $ownerId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('horizontalAccuracy: $horizontalAccuracy, ')
          ..write('verticalAccuracy: $verticalAccuracy, ')
          ..write('speed: $speed, ')
          ..write('speedAccuracy: $speedAccuracy, ')
          ..write('heading: $heading, ')
          ..write('headingAccuracy: $headingAccuracy, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('provider: $provider, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalWaypointsTable extends LocalWaypoints
    with TableInfo<$LocalWaypointsTable, LocalWaypoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalWaypointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordedRouteIdMeta =
      const VerificationMeta('recordedRouteId');
  @override
  late final GeneratedColumn<String> recordedRouteId = GeneratedColumn<String>(
      'recorded_route_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _waypointTypeMeta =
      const VerificationMeta('waypointType');
  @override
  late final GeneratedColumn<String> waypointType = GeneratedColumn<String>(
      'waypoint_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _altitudeMeta =
      const VerificationMeta('altitude');
  @override
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
      'altitude', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _recordedAtMeta =
      const VerificationMeta('recordedAt');
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
      'recorded_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _photoRefMeta =
      const VerificationMeta('photoRef');
  @override
  late final GeneratedColumn<String> photoRef = GeneratedColumn<String>(
      'photo_ref', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(WaypointSyncStatus.pending));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        recordedRouteId,
        ownerId,
        waypointType,
        title,
        note,
        latitude,
        longitude,
        altitude,
        recordedAt,
        photoRef,
        createdAt,
        updatedAt,
        syncStatus
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_waypoints';
  @override
  VerificationContext validateIntegrity(Insertable<LocalWaypoint> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recorded_route_id')) {
      context.handle(
          _recordedRouteIdMeta,
          recordedRouteId.isAcceptableOrUnknown(
              data['recorded_route_id']!, _recordedRouteIdMeta));
    } else if (isInserting) {
      context.missing(_recordedRouteIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('waypoint_type')) {
      context.handle(
          _waypointTypeMeta,
          waypointType.isAcceptableOrUnknown(
              data['waypoint_type']!, _waypointTypeMeta));
    } else if (isInserting) {
      context.missing(_waypointTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('altitude')) {
      context.handle(_altitudeMeta,
          altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta));
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
          _recordedAtMeta,
          recordedAt.isAcceptableOrUnknown(
              data['recorded_at']!, _recordedAtMeta));
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('photo_ref')) {
      context.handle(_photoRefMeta,
          photoRef.isAcceptableOrUnknown(data['photo_ref']!, _photoRefMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalWaypoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalWaypoint(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      recordedRouteId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recorded_route_id'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      waypointType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}waypoint_type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      altitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}altitude']),
      recordedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}recorded_at'])!,
      photoRef: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}photo_ref']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
    );
  }

  @override
  $LocalWaypointsTable createAlias(String alias) {
    return $LocalWaypointsTable(attachedDatabase, alias);
  }
}

class LocalWaypoint extends DataClass implements Insertable<LocalWaypoint> {
  final String id;
  final String recordedRouteId;
  final String ownerId;
  final String waypointType;
  final String? title;
  final String? note;
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime recordedAt;
  final String? photoRef;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  const LocalWaypoint(
      {required this.id,
      required this.recordedRouteId,
      required this.ownerId,
      required this.waypointType,
      this.title,
      this.note,
      required this.latitude,
      required this.longitude,
      this.altitude,
      required this.recordedAt,
      this.photoRef,
      required this.createdAt,
      required this.updatedAt,
      required this.syncStatus});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recorded_route_id'] = Variable<String>(recordedRouteId);
    map['owner_id'] = Variable<String>(ownerId);
    map['waypoint_type'] = Variable<String>(waypointType);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    if (!nullToAbsent || photoRef != null) {
      map['photo_ref'] = Variable<String>(photoRef);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalWaypointsCompanion toCompanion(bool nullToAbsent) {
    return LocalWaypointsCompanion(
      id: Value(id),
      recordedRouteId: Value(recordedRouteId),
      ownerId: Value(ownerId),
      waypointType: Value(waypointType),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      latitude: Value(latitude),
      longitude: Value(longitude),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      recordedAt: Value(recordedAt),
      photoRef: photoRef == null && nullToAbsent
          ? const Value.absent()
          : Value(photoRef),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalWaypoint.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalWaypoint(
      id: serializer.fromJson<String>(json['id']),
      recordedRouteId: serializer.fromJson<String>(json['recordedRouteId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      waypointType: serializer.fromJson<String>(json['waypointType']),
      title: serializer.fromJson<String?>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      altitude: serializer.fromJson<double?>(json['altitude']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
      photoRef: serializer.fromJson<String?>(json['photoRef']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recordedRouteId': serializer.toJson<String>(recordedRouteId),
      'ownerId': serializer.toJson<String>(ownerId),
      'waypointType': serializer.toJson<String>(waypointType),
      'title': serializer.toJson<String?>(title),
      'note': serializer.toJson<String?>(note),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'altitude': serializer.toJson<double?>(altitude),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
      'photoRef': serializer.toJson<String?>(photoRef),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalWaypoint copyWith(
          {String? id,
          String? recordedRouteId,
          String? ownerId,
          String? waypointType,
          Value<String?> title = const Value.absent(),
          Value<String?> note = const Value.absent(),
          double? latitude,
          double? longitude,
          Value<double?> altitude = const Value.absent(),
          DateTime? recordedAt,
          Value<String?> photoRef = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          String? syncStatus}) =>
      LocalWaypoint(
        id: id ?? this.id,
        recordedRouteId: recordedRouteId ?? this.recordedRouteId,
        ownerId: ownerId ?? this.ownerId,
        waypointType: waypointType ?? this.waypointType,
        title: title.present ? title.value : this.title,
        note: note.present ? note.value : this.note,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        altitude: altitude.present ? altitude.value : this.altitude,
        recordedAt: recordedAt ?? this.recordedAt,
        photoRef: photoRef.present ? photoRef.value : this.photoRef,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
  LocalWaypoint copyWithCompanion(LocalWaypointsCompanion data) {
    return LocalWaypoint(
      id: data.id.present ? data.id.value : this.id,
      recordedRouteId: data.recordedRouteId.present
          ? data.recordedRouteId.value
          : this.recordedRouteId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      waypointType: data.waypointType.present
          ? data.waypointType.value
          : this.waypointType,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      recordedAt:
          data.recordedAt.present ? data.recordedAt.value : this.recordedAt,
      photoRef: data.photoRef.present ? data.photoRef.value : this.photoRef,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalWaypoint(')
          ..write('id: $id, ')
          ..write('recordedRouteId: $recordedRouteId, ')
          ..write('ownerId: $ownerId, ')
          ..write('waypointType: $waypointType, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('photoRef: $photoRef, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      recordedRouteId,
      ownerId,
      waypointType,
      title,
      note,
      latitude,
      longitude,
      altitude,
      recordedAt,
      photoRef,
      createdAt,
      updatedAt,
      syncStatus);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalWaypoint &&
          other.id == this.id &&
          other.recordedRouteId == this.recordedRouteId &&
          other.ownerId == this.ownerId &&
          other.waypointType == this.waypointType &&
          other.title == this.title &&
          other.note == this.note &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitude == this.altitude &&
          other.recordedAt == this.recordedAt &&
          other.photoRef == this.photoRef &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalWaypointsCompanion extends UpdateCompanion<LocalWaypoint> {
  final Value<String> id;
  final Value<String> recordedRouteId;
  final Value<String> ownerId;
  final Value<String> waypointType;
  final Value<String?> title;
  final Value<String?> note;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> altitude;
  final Value<DateTime> recordedAt;
  final Value<String?> photoRef;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalWaypointsCompanion({
    this.id = const Value.absent(),
    this.recordedRouteId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.waypointType = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.photoRef = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalWaypointsCompanion.insert({
    required String id,
    required String recordedRouteId,
    required String ownerId,
    required String waypointType,
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    required double latitude,
    required double longitude,
    this.altitude = const Value.absent(),
    required DateTime recordedAt,
    this.photoRef = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        recordedRouteId = Value(recordedRouteId),
        ownerId = Value(ownerId),
        waypointType = Value(waypointType),
        latitude = Value(latitude),
        longitude = Value(longitude),
        recordedAt = Value(recordedAt),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<LocalWaypoint> custom({
    Expression<String>? id,
    Expression<String>? recordedRouteId,
    Expression<String>? ownerId,
    Expression<String>? waypointType,
    Expression<String>? title,
    Expression<String>? note,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitude,
    Expression<DateTime>? recordedAt,
    Expression<String>? photoRef,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordedRouteId != null) 'recorded_route_id': recordedRouteId,
      if (ownerId != null) 'owner_id': ownerId,
      if (waypointType != null) 'waypoint_type': waypointType,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (photoRef != null) 'photo_ref': photoRef,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalWaypointsCompanion copyWith(
      {Value<String>? id,
      Value<String>? recordedRouteId,
      Value<String>? ownerId,
      Value<String>? waypointType,
      Value<String?>? title,
      Value<String?>? note,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<double?>? altitude,
      Value<DateTime>? recordedAt,
      Value<String?>? photoRef,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<String>? syncStatus,
      Value<int>? rowid}) {
    return LocalWaypointsCompanion(
      id: id ?? this.id,
      recordedRouteId: recordedRouteId ?? this.recordedRouteId,
      ownerId: ownerId ?? this.ownerId,
      waypointType: waypointType ?? this.waypointType,
      title: title ?? this.title,
      note: note ?? this.note,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      recordedAt: recordedAt ?? this.recordedAt,
      photoRef: photoRef ?? this.photoRef,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recordedRouteId.present) {
      map['recorded_route_id'] = Variable<String>(recordedRouteId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (waypointType.present) {
      map['waypoint_type'] = Variable<String>(waypointType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    if (photoRef.present) {
      map['photo_ref'] = Variable<String>(photoRef.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalWaypointsCompanion(')
          ..write('id: $id, ')
          ..write('recordedRouteId: $recordedRouteId, ')
          ..write('ownerId: $ownerId, ')
          ..write('waypointType: $waypointType, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('photoRef: $photoRef, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalRouteEventsTable extends LocalRouteEvents
    with TableInfo<$LocalRouteEventsTable, LocalRouteEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRouteEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordedRouteIdMeta =
      const VerificationMeta('recordedRouteId');
  @override
  late final GeneratedColumn<String> recordedRouteId = GeneratedColumn<String>(
      'recorded_route_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _eventTypeMeta =
      const VerificationMeta('eventType');
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
      'event_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _occurredAtMeta =
      const VerificationMeta('occurredAt');
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
      'occurred_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [recordedRouteId, seq, ownerId, eventType, occurredAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_route_events';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRouteEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recorded_route_id')) {
      context.handle(
          _recordedRouteIdMeta,
          recordedRouteId.isAcceptableOrUnknown(
              data['recorded_route_id']!, _recordedRouteIdMeta));
    } else if (isInserting) {
      context.missing(_recordedRouteIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(_eventTypeMeta,
          eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta));
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
          _occurredAtMeta,
          occurredAt.isAcceptableOrUnknown(
              data['occurred_at']!, _occurredAtMeta));
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordedRouteId, seq};
  @override
  LocalRouteEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRouteEvent(
      recordedRouteId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recorded_route_id'])!,
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      eventType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}event_type'])!,
      occurredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}occurred_at'])!,
    );
  }

  @override
  $LocalRouteEventsTable createAlias(String alias) {
    return $LocalRouteEventsTable(attachedDatabase, alias);
  }
}

class LocalRouteEvent extends DataClass implements Insertable<LocalRouteEvent> {
  final String recordedRouteId;
  final int seq;
  final String ownerId;
  final String eventType;
  final DateTime occurredAt;
  const LocalRouteEvent(
      {required this.recordedRouteId,
      required this.seq,
      required this.ownerId,
      required this.eventType,
      required this.occurredAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recorded_route_id'] = Variable<String>(recordedRouteId);
    map['seq'] = Variable<int>(seq);
    map['owner_id'] = Variable<String>(ownerId);
    map['event_type'] = Variable<String>(eventType);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  LocalRouteEventsCompanion toCompanion(bool nullToAbsent) {
    return LocalRouteEventsCompanion(
      recordedRouteId: Value(recordedRouteId),
      seq: Value(seq),
      ownerId: Value(ownerId),
      eventType: Value(eventType),
      occurredAt: Value(occurredAt),
    );
  }

  factory LocalRouteEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRouteEvent(
      recordedRouteId: serializer.fromJson<String>(json['recordedRouteId']),
      seq: serializer.fromJson<int>(json['seq']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordedRouteId': serializer.toJson<String>(recordedRouteId),
      'seq': serializer.toJson<int>(seq),
      'ownerId': serializer.toJson<String>(ownerId),
      'eventType': serializer.toJson<String>(eventType),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  LocalRouteEvent copyWith(
          {String? recordedRouteId,
          int? seq,
          String? ownerId,
          String? eventType,
          DateTime? occurredAt}) =>
      LocalRouteEvent(
        recordedRouteId: recordedRouteId ?? this.recordedRouteId,
        seq: seq ?? this.seq,
        ownerId: ownerId ?? this.ownerId,
        eventType: eventType ?? this.eventType,
        occurredAt: occurredAt ?? this.occurredAt,
      );
  LocalRouteEvent copyWithCompanion(LocalRouteEventsCompanion data) {
    return LocalRouteEvent(
      recordedRouteId: data.recordedRouteId.present
          ? data.recordedRouteId.value
          : this.recordedRouteId,
      seq: data.seq.present ? data.seq.value : this.seq,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      occurredAt:
          data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRouteEvent(')
          ..write('recordedRouteId: $recordedRouteId, ')
          ..write('seq: $seq, ')
          ..write('ownerId: $ownerId, ')
          ..write('eventType: $eventType, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(recordedRouteId, seq, ownerId, eventType, occurredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRouteEvent &&
          other.recordedRouteId == this.recordedRouteId &&
          other.seq == this.seq &&
          other.ownerId == this.ownerId &&
          other.eventType == this.eventType &&
          other.occurredAt == this.occurredAt);
}

class LocalRouteEventsCompanion extends UpdateCompanion<LocalRouteEvent> {
  final Value<String> recordedRouteId;
  final Value<int> seq;
  final Value<String> ownerId;
  final Value<String> eventType;
  final Value<DateTime> occurredAt;
  final Value<int> rowid;
  const LocalRouteEventsCompanion({
    this.recordedRouteId = const Value.absent(),
    this.seq = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRouteEventsCompanion.insert({
    required String recordedRouteId,
    required int seq,
    required String ownerId,
    required String eventType,
    required DateTime occurredAt,
    this.rowid = const Value.absent(),
  })  : recordedRouteId = Value(recordedRouteId),
        seq = Value(seq),
        ownerId = Value(ownerId),
        eventType = Value(eventType),
        occurredAt = Value(occurredAt);
  static Insertable<LocalRouteEvent> custom({
    Expression<String>? recordedRouteId,
    Expression<int>? seq,
    Expression<String>? ownerId,
    Expression<String>? eventType,
    Expression<DateTime>? occurredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordedRouteId != null) 'recorded_route_id': recordedRouteId,
      if (seq != null) 'seq': seq,
      if (ownerId != null) 'owner_id': ownerId,
      if (eventType != null) 'event_type': eventType,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRouteEventsCompanion copyWith(
      {Value<String>? recordedRouteId,
      Value<int>? seq,
      Value<String>? ownerId,
      Value<String>? eventType,
      Value<DateTime>? occurredAt,
      Value<int>? rowid}) {
    return LocalRouteEventsCompanion(
      recordedRouteId: recordedRouteId ?? this.recordedRouteId,
      seq: seq ?? this.seq,
      ownerId: ownerId ?? this.ownerId,
      eventType: eventType ?? this.eventType,
      occurredAt: occurredAt ?? this.occurredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordedRouteId.present) {
      map['recorded_route_id'] = Variable<String>(recordedRouteId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRouteEventsCompanion(')
          ..write('recordedRouteId: $recordedRouteId, ')
          ..write('seq: $seq, ')
          ..write('ownerId: $ownerId, ')
          ..write('eventType: $eventType, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$GpsLocalDatabase extends GeneratedDatabase {
  _$GpsLocalDatabase(QueryExecutor e) : super(e);
  $GpsLocalDatabaseManager get managers => $GpsLocalDatabaseManager(this);
  late final $LocalRecordedRoutesTable localRecordedRoutes =
      $LocalRecordedRoutesTable(this);
  late final $LocalRoutePointsTable localRoutePoints =
      $LocalRoutePointsTable(this);
  late final $LocalWaypointsTable localWaypoints = $LocalWaypointsTable(this);
  late final $LocalRouteEventsTable localRouteEvents =
      $LocalRouteEventsTable(this);
  late final Index localRecordedRoutesOwnerIdx = Index(
      'local_recorded_routes_owner_idx',
      'CREATE INDEX local_recorded_routes_owner_idx ON local_recorded_routes (owner_id)');
  late final Index localRecordedRoutesOneActivePerOwner = Index(
      'local_recorded_routes_one_active_per_owner',
      'CREATE UNIQUE INDEX local_recorded_routes_one_active_per_owner ON local_recorded_routes (owner_id) WHERE status IN (\'recording\', \'paused\')');
  late final Index localWaypointsRouteIdx = Index('local_waypoints_route_idx',
      'CREATE INDEX local_waypoints_route_idx ON local_waypoints (recorded_route_id)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        localRecordedRoutes,
        localRoutePoints,
        localWaypoints,
        localRouteEvents,
        localRecordedRoutesOwnerIdx,
        localRecordedRoutesOneActivePerOwner,
        localWaypointsRouteIdx
      ];
}

typedef $$LocalRecordedRoutesTableCreateCompanionBuilder
    = LocalRecordedRoutesCompanion Function({
  required String id,
  required String ownerId,
  Value<String?> tripId,
  Value<String?> title,
  Value<String> transportMode,
  Value<String> status,
  Value<String> visibility,
  required DateTime startedAt,
  Value<DateTime?> endedAt,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<String> syncStatus,
  Value<int?> lastSyncedPointSeq,
  Value<int?> lastSyncedEventSeq,
  Value<DateTime?> lastSyncAttemptAt,
  Value<String?> lastSyncError,
  Value<int> rowid,
});
typedef $$LocalRecordedRoutesTableUpdateCompanionBuilder
    = LocalRecordedRoutesCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String?> tripId,
  Value<String?> title,
  Value<String> transportMode,
  Value<String> status,
  Value<String> visibility,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> syncStatus,
  Value<int?> lastSyncedPointSeq,
  Value<int?> lastSyncedEventSeq,
  Value<DateTime?> lastSyncAttemptAt,
  Value<String?> lastSyncError,
  Value<int> rowid,
});

class $$LocalRecordedRoutesTableFilterComposer
    extends Composer<_$GpsLocalDatabase, $LocalRecordedRoutesTable> {
  $$LocalRecordedRoutesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tripId => $composableBuilder(
      column: $table.tripId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transportMode => $composableBuilder(
      column: $table.transportMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get visibility => $composableBuilder(
      column: $table.visibility, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedPointSeq => $composableBuilder(
      column: $table.lastSyncedPointSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedEventSeq => $composableBuilder(
      column: $table.lastSyncedEventSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSyncAttemptAt => $composableBuilder(
      column: $table.lastSyncAttemptAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastSyncError => $composableBuilder(
      column: $table.lastSyncError, builder: (column) => ColumnFilters(column));
}

class $$LocalRecordedRoutesTableOrderingComposer
    extends Composer<_$GpsLocalDatabase, $LocalRecordedRoutesTable> {
  $$LocalRecordedRoutesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tripId => $composableBuilder(
      column: $table.tripId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transportMode => $composableBuilder(
      column: $table.transportMode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get visibility => $composableBuilder(
      column: $table.visibility, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedPointSeq => $composableBuilder(
      column: $table.lastSyncedPointSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedEventSeq => $composableBuilder(
      column: $table.lastSyncedEventSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSyncAttemptAt => $composableBuilder(
      column: $table.lastSyncAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastSyncError => $composableBuilder(
      column: $table.lastSyncError,
      builder: (column) => ColumnOrderings(column));
}

class $$LocalRecordedRoutesTableAnnotationComposer
    extends Composer<_$GpsLocalDatabase, $LocalRecordedRoutesTable> {
  $$LocalRecordedRoutesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get tripId =>
      $composableBuilder(column: $table.tripId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get transportMode => $composableBuilder(
      column: $table.transportMode, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get visibility => $composableBuilder(
      column: $table.visibility, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedPointSeq => $composableBuilder(
      column: $table.lastSyncedPointSeq, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedEventSeq => $composableBuilder(
      column: $table.lastSyncedEventSeq, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAttemptAt => $composableBuilder(
      column: $table.lastSyncAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get lastSyncError => $composableBuilder(
      column: $table.lastSyncError, builder: (column) => column);
}

class $$LocalRecordedRoutesTableTableManager extends RootTableManager<
    _$GpsLocalDatabase,
    $LocalRecordedRoutesTable,
    LocalRecordedRoute,
    $$LocalRecordedRoutesTableFilterComposer,
    $$LocalRecordedRoutesTableOrderingComposer,
    $$LocalRecordedRoutesTableAnnotationComposer,
    $$LocalRecordedRoutesTableCreateCompanionBuilder,
    $$LocalRecordedRoutesTableUpdateCompanionBuilder,
    (
      LocalRecordedRoute,
      BaseReferences<_$GpsLocalDatabase, $LocalRecordedRoutesTable,
          LocalRecordedRoute>
    ),
    LocalRecordedRoute,
    PrefetchHooks Function()> {
  $$LocalRecordedRoutesTableTableManager(
      _$GpsLocalDatabase db, $LocalRecordedRoutesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRecordedRoutesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRecordedRoutesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRecordedRoutesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String?> tripId = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String> transportMode = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> visibility = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<int?> lastSyncedPointSeq = const Value.absent(),
            Value<int?> lastSyncedEventSeq = const Value.absent(),
            Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
            Value<String?> lastSyncError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRecordedRoutesCompanion(
            id: id,
            ownerId: ownerId,
            tripId: tripId,
            title: title,
            transportMode: transportMode,
            status: status,
            visibility: visibility,
            startedAt: startedAt,
            endedAt: endedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            lastSyncedPointSeq: lastSyncedPointSeq,
            lastSyncedEventSeq: lastSyncedEventSeq,
            lastSyncAttemptAt: lastSyncAttemptAt,
            lastSyncError: lastSyncError,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String ownerId,
            Value<String?> tripId = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String> transportMode = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> visibility = const Value.absent(),
            required DateTime startedAt,
            Value<DateTime?> endedAt = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<String> syncStatus = const Value.absent(),
            Value<int?> lastSyncedPointSeq = const Value.absent(),
            Value<int?> lastSyncedEventSeq = const Value.absent(),
            Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
            Value<String?> lastSyncError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRecordedRoutesCompanion.insert(
            id: id,
            ownerId: ownerId,
            tripId: tripId,
            title: title,
            transportMode: transportMode,
            status: status,
            visibility: visibility,
            startedAt: startedAt,
            endedAt: endedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            lastSyncedPointSeq: lastSyncedPointSeq,
            lastSyncedEventSeq: lastSyncedEventSeq,
            lastSyncAttemptAt: lastSyncAttemptAt,
            lastSyncError: lastSyncError,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalRecordedRoutesTable, LocalRecordedRoute>(
                        table),
                    BaseReferences<
                        _$GpsLocalDatabase,
                        $LocalRecordedRoutesTable,
                        LocalRecordedRoute>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalRecordedRoutesTableProcessedTableManager = ProcessedTableManager<
    _$GpsLocalDatabase,
    $LocalRecordedRoutesTable,
    LocalRecordedRoute,
    $$LocalRecordedRoutesTableFilterComposer,
    $$LocalRecordedRoutesTableOrderingComposer,
    $$LocalRecordedRoutesTableAnnotationComposer,
    $$LocalRecordedRoutesTableCreateCompanionBuilder,
    $$LocalRecordedRoutesTableUpdateCompanionBuilder,
    (
      LocalRecordedRoute,
      BaseReferences<_$GpsLocalDatabase, $LocalRecordedRoutesTable,
          LocalRecordedRoute>
    ),
    LocalRecordedRoute,
    PrefetchHooks Function()>;
typedef $$LocalRoutePointsTableCreateCompanionBuilder
    = LocalRoutePointsCompanion Function({
  required String recordedRouteId,
  required int seq,
  required String ownerId,
  required double latitude,
  required double longitude,
  Value<double?> altitude,
  Value<double?> horizontalAccuracy,
  Value<double?> verticalAccuracy,
  Value<double?> speed,
  Value<double?> speedAccuracy,
  Value<double?> heading,
  Value<double?> headingAccuracy,
  required DateTime recordedAt,
  Value<String?> provider,
  Value<int> rowid,
});
typedef $$LocalRoutePointsTableUpdateCompanionBuilder
    = LocalRoutePointsCompanion Function({
  Value<String> recordedRouteId,
  Value<int> seq,
  Value<String> ownerId,
  Value<double> latitude,
  Value<double> longitude,
  Value<double?> altitude,
  Value<double?> horizontalAccuracy,
  Value<double?> verticalAccuracy,
  Value<double?> speed,
  Value<double?> speedAccuracy,
  Value<double?> heading,
  Value<double?> headingAccuracy,
  Value<DateTime> recordedAt,
  Value<String?> provider,
  Value<int> rowid,
});

class $$LocalRoutePointsTableFilterComposer
    extends Composer<_$GpsLocalDatabase, $LocalRoutePointsTable> {
  $$LocalRoutePointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get altitude => $composableBuilder(
      column: $table.altitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get horizontalAccuracy => $composableBuilder(
      column: $table.horizontalAccuracy,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get verticalAccuracy => $composableBuilder(
      column: $table.verticalAccuracy,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get speed => $composableBuilder(
      column: $table.speed, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get speedAccuracy => $composableBuilder(
      column: $table.speedAccuracy, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get heading => $composableBuilder(
      column: $table.heading, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get headingAccuracy => $composableBuilder(
      column: $table.headingAccuracy,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));
}

class $$LocalRoutePointsTableOrderingComposer
    extends Composer<_$GpsLocalDatabase, $LocalRoutePointsTable> {
  $$LocalRoutePointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get altitude => $composableBuilder(
      column: $table.altitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get horizontalAccuracy => $composableBuilder(
      column: $table.horizontalAccuracy,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get verticalAccuracy => $composableBuilder(
      column: $table.verticalAccuracy,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get speed => $composableBuilder(
      column: $table.speed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get speedAccuracy => $composableBuilder(
      column: $table.speedAccuracy,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get heading => $composableBuilder(
      column: $table.heading, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get headingAccuracy => $composableBuilder(
      column: $table.headingAccuracy,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));
}

class $$LocalRoutePointsTableAnnotationComposer
    extends Composer<_$GpsLocalDatabase, $LocalRoutePointsTable> {
  $$LocalRoutePointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get altitude =>
      $composableBuilder(column: $table.altitude, builder: (column) => column);

  GeneratedColumn<double> get horizontalAccuracy => $composableBuilder(
      column: $table.horizontalAccuracy, builder: (column) => column);

  GeneratedColumn<double> get verticalAccuracy => $composableBuilder(
      column: $table.verticalAccuracy, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<double> get speedAccuracy => $composableBuilder(
      column: $table.speedAccuracy, builder: (column) => column);

  GeneratedColumn<double> get heading =>
      $composableBuilder(column: $table.heading, builder: (column) => column);

  GeneratedColumn<double> get headingAccuracy => $composableBuilder(
      column: $table.headingAccuracy, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);
}

class $$LocalRoutePointsTableTableManager extends RootTableManager<
    _$GpsLocalDatabase,
    $LocalRoutePointsTable,
    LocalRoutePoint,
    $$LocalRoutePointsTableFilterComposer,
    $$LocalRoutePointsTableOrderingComposer,
    $$LocalRoutePointsTableAnnotationComposer,
    $$LocalRoutePointsTableCreateCompanionBuilder,
    $$LocalRoutePointsTableUpdateCompanionBuilder,
    (
      LocalRoutePoint,
      BaseReferences<_$GpsLocalDatabase, $LocalRoutePointsTable,
          LocalRoutePoint>
    ),
    LocalRoutePoint,
    PrefetchHooks Function()> {
  $$LocalRoutePointsTableTableManager(
      _$GpsLocalDatabase db, $LocalRoutePointsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRoutePointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRoutePointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRoutePointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> recordedRouteId = const Value.absent(),
            Value<int> seq = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<double?> altitude = const Value.absent(),
            Value<double?> horizontalAccuracy = const Value.absent(),
            Value<double?> verticalAccuracy = const Value.absent(),
            Value<double?> speed = const Value.absent(),
            Value<double?> speedAccuracy = const Value.absent(),
            Value<double?> heading = const Value.absent(),
            Value<double?> headingAccuracy = const Value.absent(),
            Value<DateTime> recordedAt = const Value.absent(),
            Value<String?> provider = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRoutePointsCompanion(
            recordedRouteId: recordedRouteId,
            seq: seq,
            ownerId: ownerId,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            heading: heading,
            headingAccuracy: headingAccuracy,
            recordedAt: recordedAt,
            provider: provider,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String recordedRouteId,
            required int seq,
            required String ownerId,
            required double latitude,
            required double longitude,
            Value<double?> altitude = const Value.absent(),
            Value<double?> horizontalAccuracy = const Value.absent(),
            Value<double?> verticalAccuracy = const Value.absent(),
            Value<double?> speed = const Value.absent(),
            Value<double?> speedAccuracy = const Value.absent(),
            Value<double?> heading = const Value.absent(),
            Value<double?> headingAccuracy = const Value.absent(),
            required DateTime recordedAt,
            Value<String?> provider = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRoutePointsCompanion.insert(
            recordedRouteId: recordedRouteId,
            seq: seq,
            ownerId: ownerId,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            heading: heading,
            headingAccuracy: headingAccuracy,
            recordedAt: recordedAt,
            provider: provider,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalRoutePointsTable, LocalRoutePoint>(table),
                    BaseReferences<_$GpsLocalDatabase, $LocalRoutePointsTable,
                        LocalRoutePoint>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalRoutePointsTableProcessedTableManager = ProcessedTableManager<
    _$GpsLocalDatabase,
    $LocalRoutePointsTable,
    LocalRoutePoint,
    $$LocalRoutePointsTableFilterComposer,
    $$LocalRoutePointsTableOrderingComposer,
    $$LocalRoutePointsTableAnnotationComposer,
    $$LocalRoutePointsTableCreateCompanionBuilder,
    $$LocalRoutePointsTableUpdateCompanionBuilder,
    (
      LocalRoutePoint,
      BaseReferences<_$GpsLocalDatabase, $LocalRoutePointsTable,
          LocalRoutePoint>
    ),
    LocalRoutePoint,
    PrefetchHooks Function()>;
typedef $$LocalWaypointsTableCreateCompanionBuilder = LocalWaypointsCompanion
    Function({
  required String id,
  required String recordedRouteId,
  required String ownerId,
  required String waypointType,
  Value<String?> title,
  Value<String?> note,
  required double latitude,
  required double longitude,
  Value<double?> altitude,
  required DateTime recordedAt,
  Value<String?> photoRef,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<String> syncStatus,
  Value<int> rowid,
});
typedef $$LocalWaypointsTableUpdateCompanionBuilder = LocalWaypointsCompanion
    Function({
  Value<String> id,
  Value<String> recordedRouteId,
  Value<String> ownerId,
  Value<String> waypointType,
  Value<String?> title,
  Value<String?> note,
  Value<double> latitude,
  Value<double> longitude,
  Value<double?> altitude,
  Value<DateTime> recordedAt,
  Value<String?> photoRef,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> syncStatus,
  Value<int> rowid,
});

class $$LocalWaypointsTableFilterComposer
    extends Composer<_$GpsLocalDatabase, $LocalWaypointsTable> {
  $$LocalWaypointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get waypointType => $composableBuilder(
      column: $table.waypointType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get altitude => $composableBuilder(
      column: $table.altitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get photoRef => $composableBuilder(
      column: $table.photoRef, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));
}

class $$LocalWaypointsTableOrderingComposer
    extends Composer<_$GpsLocalDatabase, $LocalWaypointsTable> {
  $$LocalWaypointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get waypointType => $composableBuilder(
      column: $table.waypointType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get altitude => $composableBuilder(
      column: $table.altitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get photoRef => $composableBuilder(
      column: $table.photoRef, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
}

class $$LocalWaypointsTableAnnotationComposer
    extends Composer<_$GpsLocalDatabase, $LocalWaypointsTable> {
  $$LocalWaypointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get waypointType => $composableBuilder(
      column: $table.waypointType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get altitude =>
      $composableBuilder(column: $table.altitude, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => column);

  GeneratedColumn<String> get photoRef =>
      $composableBuilder(column: $table.photoRef, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);
}

class $$LocalWaypointsTableTableManager extends RootTableManager<
    _$GpsLocalDatabase,
    $LocalWaypointsTable,
    LocalWaypoint,
    $$LocalWaypointsTableFilterComposer,
    $$LocalWaypointsTableOrderingComposer,
    $$LocalWaypointsTableAnnotationComposer,
    $$LocalWaypointsTableCreateCompanionBuilder,
    $$LocalWaypointsTableUpdateCompanionBuilder,
    (
      LocalWaypoint,
      BaseReferences<_$GpsLocalDatabase, $LocalWaypointsTable, LocalWaypoint>
    ),
    LocalWaypoint,
    PrefetchHooks Function()> {
  $$LocalWaypointsTableTableManager(
      _$GpsLocalDatabase db, $LocalWaypointsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalWaypointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalWaypointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalWaypointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> recordedRouteId = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String> waypointType = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<double?> altitude = const Value.absent(),
            Value<DateTime> recordedAt = const Value.absent(),
            Value<String?> photoRef = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalWaypointsCompanion(
            id: id,
            recordedRouteId: recordedRouteId,
            ownerId: ownerId,
            waypointType: waypointType,
            title: title,
            note: note,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            recordedAt: recordedAt,
            photoRef: photoRef,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String recordedRouteId,
            required String ownerId,
            required String waypointType,
            Value<String?> title = const Value.absent(),
            Value<String?> note = const Value.absent(),
            required double latitude,
            required double longitude,
            Value<double?> altitude = const Value.absent(),
            required DateTime recordedAt,
            Value<String?> photoRef = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<String> syncStatus = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalWaypointsCompanion.insert(
            id: id,
            recordedRouteId: recordedRouteId,
            ownerId: ownerId,
            waypointType: waypointType,
            title: title,
            note: note,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            recordedAt: recordedAt,
            photoRef: photoRef,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalWaypointsTable, LocalWaypoint>(table),
                    BaseReferences<_$GpsLocalDatabase, $LocalWaypointsTable,
                        LocalWaypoint>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalWaypointsTableProcessedTableManager = ProcessedTableManager<
    _$GpsLocalDatabase,
    $LocalWaypointsTable,
    LocalWaypoint,
    $$LocalWaypointsTableFilterComposer,
    $$LocalWaypointsTableOrderingComposer,
    $$LocalWaypointsTableAnnotationComposer,
    $$LocalWaypointsTableCreateCompanionBuilder,
    $$LocalWaypointsTableUpdateCompanionBuilder,
    (
      LocalWaypoint,
      BaseReferences<_$GpsLocalDatabase, $LocalWaypointsTable, LocalWaypoint>
    ),
    LocalWaypoint,
    PrefetchHooks Function()>;
typedef $$LocalRouteEventsTableCreateCompanionBuilder
    = LocalRouteEventsCompanion Function({
  required String recordedRouteId,
  required int seq,
  required String ownerId,
  required String eventType,
  required DateTime occurredAt,
  Value<int> rowid,
});
typedef $$LocalRouteEventsTableUpdateCompanionBuilder
    = LocalRouteEventsCompanion Function({
  Value<String> recordedRouteId,
  Value<int> seq,
  Value<String> ownerId,
  Value<String> eventType,
  Value<DateTime> occurredAt,
  Value<int> rowid,
});

class $$LocalRouteEventsTableFilterComposer
    extends Composer<_$GpsLocalDatabase, $LocalRouteEventsTable> {
  $$LocalRouteEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get eventType => $composableBuilder(
      column: $table.eventType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnFilters(column));
}

class $$LocalRouteEventsTableOrderingComposer
    extends Composer<_$GpsLocalDatabase, $LocalRouteEventsTable> {
  $$LocalRouteEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get eventType => $composableBuilder(
      column: $table.eventType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalRouteEventsTableAnnotationComposer
    extends Composer<_$GpsLocalDatabase, $LocalRouteEventsTable> {
  $$LocalRouteEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordedRouteId => $composableBuilder(
      column: $table.recordedRouteId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => column);
}

class $$LocalRouteEventsTableTableManager extends RootTableManager<
    _$GpsLocalDatabase,
    $LocalRouteEventsTable,
    LocalRouteEvent,
    $$LocalRouteEventsTableFilterComposer,
    $$LocalRouteEventsTableOrderingComposer,
    $$LocalRouteEventsTableAnnotationComposer,
    $$LocalRouteEventsTableCreateCompanionBuilder,
    $$LocalRouteEventsTableUpdateCompanionBuilder,
    (
      LocalRouteEvent,
      BaseReferences<_$GpsLocalDatabase, $LocalRouteEventsTable,
          LocalRouteEvent>
    ),
    LocalRouteEvent,
    PrefetchHooks Function()> {
  $$LocalRouteEventsTableTableManager(
      _$GpsLocalDatabase db, $LocalRouteEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRouteEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRouteEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRouteEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> recordedRouteId = const Value.absent(),
            Value<int> seq = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String> eventType = const Value.absent(),
            Value<DateTime> occurredAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRouteEventsCompanion(
            recordedRouteId: recordedRouteId,
            seq: seq,
            ownerId: ownerId,
            eventType: eventType,
            occurredAt: occurredAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String recordedRouteId,
            required int seq,
            required String ownerId,
            required String eventType,
            required DateTime occurredAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRouteEventsCompanion.insert(
            recordedRouteId: recordedRouteId,
            seq: seq,
            ownerId: ownerId,
            eventType: eventType,
            occurredAt: occurredAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalRouteEventsTable, LocalRouteEvent>(table),
                    BaseReferences<_$GpsLocalDatabase, $LocalRouteEventsTable,
                        LocalRouteEvent>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalRouteEventsTableProcessedTableManager = ProcessedTableManager<
    _$GpsLocalDatabase,
    $LocalRouteEventsTable,
    LocalRouteEvent,
    $$LocalRouteEventsTableFilterComposer,
    $$LocalRouteEventsTableOrderingComposer,
    $$LocalRouteEventsTableAnnotationComposer,
    $$LocalRouteEventsTableCreateCompanionBuilder,
    $$LocalRouteEventsTableUpdateCompanionBuilder,
    (
      LocalRouteEvent,
      BaseReferences<_$GpsLocalDatabase, $LocalRouteEventsTable,
          LocalRouteEvent>
    ),
    LocalRouteEvent,
    PrefetchHooks Function()>;

class $GpsLocalDatabaseManager {
  final _$GpsLocalDatabase _db;
  $GpsLocalDatabaseManager(this._db);
  $$LocalRecordedRoutesTableTableManager get localRecordedRoutes =>
      $$LocalRecordedRoutesTableTableManager(_db, _db.localRecordedRoutes);
  $$LocalRoutePointsTableTableManager get localRoutePoints =>
      $$LocalRoutePointsTableTableManager(_db, _db.localRoutePoints);
  $$LocalWaypointsTableTableManager get localWaypoints =>
      $$LocalWaypointsTableTableManager(_db, _db.localWaypoints);
  $$LocalRouteEventsTableTableManager get localRouteEvents =>
      $$LocalRouteEventsTableTableManager(_db, _db.localRouteEvents);
}
