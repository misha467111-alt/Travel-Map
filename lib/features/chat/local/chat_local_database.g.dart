// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_local_database.dart';

// ignore_for_file: type=lint
class $LocalMessagesTable extends LocalMessages
    with TableInfo<$LocalMessagesTable, LocalMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountUserIdMeta =
      const VerificationMeta('accountUserId');
  @override
  late final GeneratedColumn<String> accountUserId = GeneratedColumn<String>(
      'account_user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationKeyMeta =
      const VerificationMeta('conversationKey');
  @override
  late final GeneratedColumn<String> conversationKey = GeneratedColumn<String>(
      'conversation_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _receiverIdMeta =
      const VerificationMeta('receiverId');
  @override
  late final GeneratedColumn<String> receiverId = GeneratedColumn<String>(
      'receiver_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, true,
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
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        accountUserId,
        conversationKey,
        senderId,
        receiverId,
        body,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_messages';
  @override
  VerificationContext validateIntegrity(Insertable<LocalMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_user_id')) {
      context.handle(
          _accountUserIdMeta,
          accountUserId.isAcceptableOrUnknown(
              data['account_user_id']!, _accountUserIdMeta));
    } else if (isInserting) {
      context.missing(_accountUserIdMeta);
    }
    if (data.containsKey('conversation_key')) {
      context.handle(
          _conversationKeyMeta,
          conversationKey.isAcceptableOrUnknown(
              data['conversation_key']!, _conversationKeyMeta));
    } else if (isInserting) {
      context.missing(_conversationKeyMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('receiver_id')) {
      context.handle(
          _receiverIdMeta,
          receiverId.isAcceptableOrUnknown(
              data['receiver_id']!, _receiverIdMeta));
    } else if (isInserting) {
      context.missing(_receiverIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
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
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountUserId, id};
  @override
  LocalMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      accountUserId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}account_user_id'])!,
      conversationKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_key'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_id'])!,
      receiverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}receiver_id'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $LocalMessagesTable createAlias(String alias) {
    return $LocalMessagesTable(attachedDatabase, alias);
  }
}

class LocalMessage extends DataClass implements Insertable<LocalMessage> {
  final String id;
  final String accountUserId;
  final String conversationKey;
  final String senderId;
  final String receiverId;
  final String? body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalMessage(
      {required this.id,
      required this.accountUserId,
      required this.conversationKey,
      required this.senderId,
      required this.receiverId,
      this.body,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['account_user_id'] = Variable<String>(accountUserId);
    map['conversation_key'] = Variable<String>(conversationKey);
    map['sender_id'] = Variable<String>(senderId);
    map['receiver_id'] = Variable<String>(receiverId);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalMessagesCompanion toCompanion(bool nullToAbsent) {
    return LocalMessagesCompanion(
      id: Value(id),
      accountUserId: Value(accountUserId),
      conversationKey: Value(conversationKey),
      senderId: Value(senderId),
      receiverId: Value(receiverId),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMessage(
      id: serializer.fromJson<String>(json['id']),
      accountUserId: serializer.fromJson<String>(json['accountUserId']),
      conversationKey: serializer.fromJson<String>(json['conversationKey']),
      senderId: serializer.fromJson<String>(json['senderId']),
      receiverId: serializer.fromJson<String>(json['receiverId']),
      body: serializer.fromJson<String?>(json['body']),
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
      'accountUserId': serializer.toJson<String>(accountUserId),
      'conversationKey': serializer.toJson<String>(conversationKey),
      'senderId': serializer.toJson<String>(senderId),
      'receiverId': serializer.toJson<String>(receiverId),
      'body': serializer.toJson<String?>(body),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalMessage copyWith(
          {String? id,
          String? accountUserId,
          String? conversationKey,
          String? senderId,
          String? receiverId,
          Value<String?> body = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      LocalMessage(
        id: id ?? this.id,
        accountUserId: accountUserId ?? this.accountUserId,
        conversationKey: conversationKey ?? this.conversationKey,
        senderId: senderId ?? this.senderId,
        receiverId: receiverId ?? this.receiverId,
        body: body.present ? body.value : this.body,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  LocalMessage copyWithCompanion(LocalMessagesCompanion data) {
    return LocalMessage(
      id: data.id.present ? data.id.value : this.id,
      accountUserId: data.accountUserId.present
          ? data.accountUserId.value
          : this.accountUserId,
      conversationKey: data.conversationKey.present
          ? data.conversationKey.value
          : this.conversationKey,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      receiverId:
          data.receiverId.present ? data.receiverId.value : this.receiverId,
      body: data.body.present ? data.body.value : this.body,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessage(')
          ..write('id: $id, ')
          ..write('accountUserId: $accountUserId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('senderId: $senderId, ')
          ..write('receiverId: $receiverId, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, accountUserId, conversationKey, senderId,
      receiverId, body, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMessage &&
          other.id == this.id &&
          other.accountUserId == this.accountUserId &&
          other.conversationKey == this.conversationKey &&
          other.senderId == this.senderId &&
          other.receiverId == this.receiverId &&
          other.body == this.body &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalMessagesCompanion extends UpdateCompanion<LocalMessage> {
  final Value<String> id;
  final Value<String> accountUserId;
  final Value<String> conversationKey;
  final Value<String> senderId;
  final Value<String> receiverId;
  final Value<String?> body;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalMessagesCompanion({
    this.id = const Value.absent(),
    this.accountUserId = const Value.absent(),
    this.conversationKey = const Value.absent(),
    this.senderId = const Value.absent(),
    this.receiverId = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMessagesCompanion.insert({
    required String id,
    required String accountUserId,
    required String conversationKey,
    required String senderId,
    required String receiverId,
    this.body = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        accountUserId = Value(accountUserId),
        conversationKey = Value(conversationKey),
        senderId = Value(senderId),
        receiverId = Value(receiverId),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<LocalMessage> custom({
    Expression<String>? id,
    Expression<String>? accountUserId,
    Expression<String>? conversationKey,
    Expression<String>? senderId,
    Expression<String>? receiverId,
    Expression<String>? body,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountUserId != null) 'account_user_id': accountUserId,
      if (conversationKey != null) 'conversation_key': conversationKey,
      if (senderId != null) 'sender_id': senderId,
      if (receiverId != null) 'receiver_id': receiverId,
      if (body != null) 'body': body,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? accountUserId,
      Value<String>? conversationKey,
      Value<String>? senderId,
      Value<String>? receiverId,
      Value<String?>? body,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return LocalMessagesCompanion(
      id: id ?? this.id,
      accountUserId: accountUserId ?? this.accountUserId,
      conversationKey: conversationKey ?? this.conversationKey,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      body: body ?? this.body,
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
    if (accountUserId.present) {
      map['account_user_id'] = Variable<String>(accountUserId.value);
    }
    if (conversationKey.present) {
      map['conversation_key'] = Variable<String>(conversationKey.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (receiverId.present) {
      map['receiver_id'] = Variable<String>(receiverId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
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
    return (StringBuffer('LocalMessagesCompanion(')
          ..write('id: $id, ')
          ..write('accountUserId: $accountUserId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('senderId: $senderId, ')
          ..write('receiverId: $receiverId, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatSyncStateTable extends ChatSyncState
    with TableInfo<$ChatSyncStateTable, ChatSyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountUserIdMeta =
      const VerificationMeta('accountUserId');
  @override
  late final GeneratedColumn<String> accountUserId = GeneratedColumn<String>(
      'account_user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationKeyMeta =
      const VerificationMeta('conversationKey');
  @override
  late final GeneratedColumn<String> conversationKey = GeneratedColumn<String>(
      'conversation_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastChangeAtMeta =
      const VerificationMeta('lastChangeAt');
  @override
  late final GeneratedColumn<DateTime> lastChangeAt = GeneratedColumn<DateTime>(
      'last_change_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastChangeIdMeta =
      const VerificationMeta('lastChangeId');
  @override
  late final GeneratedColumn<String> lastChangeId = GeneratedColumn<String>(
      'last_change_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [accountUserId, conversationKey, lastChangeAt, lastChangeId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sync_state';
  @override
  VerificationContext validateIntegrity(Insertable<ChatSyncStateData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_user_id')) {
      context.handle(
          _accountUserIdMeta,
          accountUserId.isAcceptableOrUnknown(
              data['account_user_id']!, _accountUserIdMeta));
    } else if (isInserting) {
      context.missing(_accountUserIdMeta);
    }
    if (data.containsKey('conversation_key')) {
      context.handle(
          _conversationKeyMeta,
          conversationKey.isAcceptableOrUnknown(
              data['conversation_key']!, _conversationKeyMeta));
    } else if (isInserting) {
      context.missing(_conversationKeyMeta);
    }
    if (data.containsKey('last_change_at')) {
      context.handle(
          _lastChangeAtMeta,
          lastChangeAt.isAcceptableOrUnknown(
              data['last_change_at']!, _lastChangeAtMeta));
    }
    if (data.containsKey('last_change_id')) {
      context.handle(
          _lastChangeIdMeta,
          lastChangeId.isAcceptableOrUnknown(
              data['last_change_id']!, _lastChangeIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountUserId, conversationKey};
  @override
  ChatSyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSyncStateData(
      accountUserId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}account_user_id'])!,
      conversationKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_key'])!,
      lastChangeAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_change_at']),
      lastChangeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_change_id']),
    );
  }

  @override
  $ChatSyncStateTable createAlias(String alias) {
    return $ChatSyncStateTable(attachedDatabase, alias);
  }
}

class ChatSyncStateData extends DataClass
    implements Insertable<ChatSyncStateData> {
  final String accountUserId;
  final String conversationKey;
  final DateTime? lastChangeAt;
  final String? lastChangeId;
  const ChatSyncStateData(
      {required this.accountUserId,
      required this.conversationKey,
      this.lastChangeAt,
      this.lastChangeId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_user_id'] = Variable<String>(accountUserId);
    map['conversation_key'] = Variable<String>(conversationKey);
    if (!nullToAbsent || lastChangeAt != null) {
      map['last_change_at'] = Variable<DateTime>(lastChangeAt);
    }
    if (!nullToAbsent || lastChangeId != null) {
      map['last_change_id'] = Variable<String>(lastChangeId);
    }
    return map;
  }

  ChatSyncStateCompanion toCompanion(bool nullToAbsent) {
    return ChatSyncStateCompanion(
      accountUserId: Value(accountUserId),
      conversationKey: Value(conversationKey),
      lastChangeAt: lastChangeAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChangeAt),
      lastChangeId: lastChangeId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChangeId),
    );
  }

  factory ChatSyncStateData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSyncStateData(
      accountUserId: serializer.fromJson<String>(json['accountUserId']),
      conversationKey: serializer.fromJson<String>(json['conversationKey']),
      lastChangeAt: serializer.fromJson<DateTime?>(json['lastChangeAt']),
      lastChangeId: serializer.fromJson<String?>(json['lastChangeId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountUserId': serializer.toJson<String>(accountUserId),
      'conversationKey': serializer.toJson<String>(conversationKey),
      'lastChangeAt': serializer.toJson<DateTime?>(lastChangeAt),
      'lastChangeId': serializer.toJson<String?>(lastChangeId),
    };
  }

  ChatSyncStateData copyWith(
          {String? accountUserId,
          String? conversationKey,
          Value<DateTime?> lastChangeAt = const Value.absent(),
          Value<String?> lastChangeId = const Value.absent()}) =>
      ChatSyncStateData(
        accountUserId: accountUserId ?? this.accountUserId,
        conversationKey: conversationKey ?? this.conversationKey,
        lastChangeAt:
            lastChangeAt.present ? lastChangeAt.value : this.lastChangeAt,
        lastChangeId:
            lastChangeId.present ? lastChangeId.value : this.lastChangeId,
      );
  ChatSyncStateData copyWithCompanion(ChatSyncStateCompanion data) {
    return ChatSyncStateData(
      accountUserId: data.accountUserId.present
          ? data.accountUserId.value
          : this.accountUserId,
      conversationKey: data.conversationKey.present
          ? data.conversationKey.value
          : this.conversationKey,
      lastChangeAt: data.lastChangeAt.present
          ? data.lastChangeAt.value
          : this.lastChangeAt,
      lastChangeId: data.lastChangeId.present
          ? data.lastChangeId.value
          : this.lastChangeId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSyncStateData(')
          ..write('accountUserId: $accountUserId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('lastChangeAt: $lastChangeAt, ')
          ..write('lastChangeId: $lastChangeId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountUserId, conversationKey, lastChangeAt, lastChangeId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSyncStateData &&
          other.accountUserId == this.accountUserId &&
          other.conversationKey == this.conversationKey &&
          other.lastChangeAt == this.lastChangeAt &&
          other.lastChangeId == this.lastChangeId);
}

class ChatSyncStateCompanion extends UpdateCompanion<ChatSyncStateData> {
  final Value<String> accountUserId;
  final Value<String> conversationKey;
  final Value<DateTime?> lastChangeAt;
  final Value<String?> lastChangeId;
  final Value<int> rowid;
  const ChatSyncStateCompanion({
    this.accountUserId = const Value.absent(),
    this.conversationKey = const Value.absent(),
    this.lastChangeAt = const Value.absent(),
    this.lastChangeId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatSyncStateCompanion.insert({
    required String accountUserId,
    required String conversationKey,
    this.lastChangeAt = const Value.absent(),
    this.lastChangeId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : accountUserId = Value(accountUserId),
        conversationKey = Value(conversationKey);
  static Insertable<ChatSyncStateData> custom({
    Expression<String>? accountUserId,
    Expression<String>? conversationKey,
    Expression<DateTime>? lastChangeAt,
    Expression<String>? lastChangeId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountUserId != null) 'account_user_id': accountUserId,
      if (conversationKey != null) 'conversation_key': conversationKey,
      if (lastChangeAt != null) 'last_change_at': lastChangeAt,
      if (lastChangeId != null) 'last_change_id': lastChangeId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatSyncStateCompanion copyWith(
      {Value<String>? accountUserId,
      Value<String>? conversationKey,
      Value<DateTime?>? lastChangeAt,
      Value<String?>? lastChangeId,
      Value<int>? rowid}) {
    return ChatSyncStateCompanion(
      accountUserId: accountUserId ?? this.accountUserId,
      conversationKey: conversationKey ?? this.conversationKey,
      lastChangeAt: lastChangeAt ?? this.lastChangeAt,
      lastChangeId: lastChangeId ?? this.lastChangeId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountUserId.present) {
      map['account_user_id'] = Variable<String>(accountUserId.value);
    }
    if (conversationKey.present) {
      map['conversation_key'] = Variable<String>(conversationKey.value);
    }
    if (lastChangeAt.present) {
      map['last_change_at'] = Variable<DateTime>(lastChangeAt.value);
    }
    if (lastChangeId.present) {
      map['last_change_id'] = Variable<String>(lastChangeId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSyncStateCompanion(')
          ..write('accountUserId: $accountUserId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('lastChangeAt: $lastChangeAt, ')
          ..write('lastChangeId: $lastChangeId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChatLocalDatabase extends GeneratedDatabase {
  _$ChatLocalDatabase(QueryExecutor e) : super(e);
  $ChatLocalDatabaseManager get managers => $ChatLocalDatabaseManager(this);
  late final $LocalMessagesTable localMessages = $LocalMessagesTable(this);
  late final $ChatSyncStateTable chatSyncState = $ChatSyncStateTable(this);
  late final Index localMessagesConversationIdx = Index(
      'local_messages_conversation_idx',
      'CREATE INDEX local_messages_conversation_idx ON local_messages (account_user_id, conversation_key, created_at, id)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [localMessages, chatSyncState, localMessagesConversationIdx];
}

typedef $$LocalMessagesTableCreateCompanionBuilder = LocalMessagesCompanion
    Function({
  required String id,
  required String accountUserId,
  required String conversationKey,
  required String senderId,
  required String receiverId,
  Value<String?> body,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$LocalMessagesTableUpdateCompanionBuilder = LocalMessagesCompanion
    Function({
  Value<String> id,
  Value<String> accountUserId,
  Value<String> conversationKey,
  Value<String> senderId,
  Value<String> receiverId,
  Value<String?> body,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$LocalMessagesTableFilterComposer
    extends Composer<_$ChatLocalDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountUserId => $composableBuilder(
      column: $table.accountUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationKey => $composableBuilder(
      column: $table.conversationKey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get receiverId => $composableBuilder(
      column: $table.receiverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalMessagesTableOrderingComposer
    extends Composer<_$ChatLocalDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountUserId => $composableBuilder(
      column: $table.accountUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationKey => $composableBuilder(
      column: $table.conversationKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get receiverId => $composableBuilder(
      column: $table.receiverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalMessagesTableAnnotationComposer
    extends Composer<_$ChatLocalDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountUserId => $composableBuilder(
      column: $table.accountUserId, builder: (column) => column);

  GeneratedColumn<String> get conversationKey => $composableBuilder(
      column: $table.conversationKey, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get receiverId => $composableBuilder(
      column: $table.receiverId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalMessagesTableTableManager extends RootTableManager<
    _$ChatLocalDatabase,
    $LocalMessagesTable,
    LocalMessage,
    $$LocalMessagesTableFilterComposer,
    $$LocalMessagesTableOrderingComposer,
    $$LocalMessagesTableAnnotationComposer,
    $$LocalMessagesTableCreateCompanionBuilder,
    $$LocalMessagesTableUpdateCompanionBuilder,
    (
      LocalMessage,
      BaseReferences<_$ChatLocalDatabase, $LocalMessagesTable, LocalMessage>
    ),
    LocalMessage,
    PrefetchHooks Function()> {
  $$LocalMessagesTableTableManager(
      _$ChatLocalDatabase db, $LocalMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> accountUserId = const Value.absent(),
            Value<String> conversationKey = const Value.absent(),
            Value<String> senderId = const Value.absent(),
            Value<String> receiverId = const Value.absent(),
            Value<String?> body = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalMessagesCompanion(
            id: id,
            accountUserId: accountUserId,
            conversationKey: conversationKey,
            senderId: senderId,
            receiverId: receiverId,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String accountUserId,
            required String conversationKey,
            required String senderId,
            required String receiverId,
            Value<String?> body = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalMessagesCompanion.insert(
            id: id,
            accountUserId: accountUserId,
            conversationKey: conversationKey,
            senderId: senderId,
            receiverId: receiverId,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalMessagesTable, LocalMessage>(table),
                    BaseReferences<_$ChatLocalDatabase, $LocalMessagesTable,
                        LocalMessage>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalMessagesTableProcessedTableManager = ProcessedTableManager<
    _$ChatLocalDatabase,
    $LocalMessagesTable,
    LocalMessage,
    $$LocalMessagesTableFilterComposer,
    $$LocalMessagesTableOrderingComposer,
    $$LocalMessagesTableAnnotationComposer,
    $$LocalMessagesTableCreateCompanionBuilder,
    $$LocalMessagesTableUpdateCompanionBuilder,
    (
      LocalMessage,
      BaseReferences<_$ChatLocalDatabase, $LocalMessagesTable, LocalMessage>
    ),
    LocalMessage,
    PrefetchHooks Function()>;
typedef $$ChatSyncStateTableCreateCompanionBuilder = ChatSyncStateCompanion
    Function({
  required String accountUserId,
  required String conversationKey,
  Value<DateTime?> lastChangeAt,
  Value<String?> lastChangeId,
  Value<int> rowid,
});
typedef $$ChatSyncStateTableUpdateCompanionBuilder = ChatSyncStateCompanion
    Function({
  Value<String> accountUserId,
  Value<String> conversationKey,
  Value<DateTime?> lastChangeAt,
  Value<String?> lastChangeId,
  Value<int> rowid,
});

class $$ChatSyncStateTableFilterComposer
    extends Composer<_$ChatLocalDatabase, $ChatSyncStateTable> {
  $$ChatSyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountUserId => $composableBuilder(
      column: $table.accountUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationKey => $composableBuilder(
      column: $table.conversationKey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastChangeAt => $composableBuilder(
      column: $table.lastChangeAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastChangeId => $composableBuilder(
      column: $table.lastChangeId, builder: (column) => ColumnFilters(column));
}

class $$ChatSyncStateTableOrderingComposer
    extends Composer<_$ChatLocalDatabase, $ChatSyncStateTable> {
  $$ChatSyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountUserId => $composableBuilder(
      column: $table.accountUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationKey => $composableBuilder(
      column: $table.conversationKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastChangeAt => $composableBuilder(
      column: $table.lastChangeAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastChangeId => $composableBuilder(
      column: $table.lastChangeId,
      builder: (column) => ColumnOrderings(column));
}

class $$ChatSyncStateTableAnnotationComposer
    extends Composer<_$ChatLocalDatabase, $ChatSyncStateTable> {
  $$ChatSyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountUserId => $composableBuilder(
      column: $table.accountUserId, builder: (column) => column);

  GeneratedColumn<String> get conversationKey => $composableBuilder(
      column: $table.conversationKey, builder: (column) => column);

  GeneratedColumn<DateTime> get lastChangeAt => $composableBuilder(
      column: $table.lastChangeAt, builder: (column) => column);

  GeneratedColumn<String> get lastChangeId => $composableBuilder(
      column: $table.lastChangeId, builder: (column) => column);
}

class $$ChatSyncStateTableTableManager extends RootTableManager<
    _$ChatLocalDatabase,
    $ChatSyncStateTable,
    ChatSyncStateData,
    $$ChatSyncStateTableFilterComposer,
    $$ChatSyncStateTableOrderingComposer,
    $$ChatSyncStateTableAnnotationComposer,
    $$ChatSyncStateTableCreateCompanionBuilder,
    $$ChatSyncStateTableUpdateCompanionBuilder,
    (
      ChatSyncStateData,
      BaseReferences<_$ChatLocalDatabase, $ChatSyncStateTable,
          ChatSyncStateData>
    ),
    ChatSyncStateData,
    PrefetchHooks Function()> {
  $$ChatSyncStateTableTableManager(
      _$ChatLocalDatabase db, $ChatSyncStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> accountUserId = const Value.absent(),
            Value<String> conversationKey = const Value.absent(),
            Value<DateTime?> lastChangeAt = const Value.absent(),
            Value<String?> lastChangeId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatSyncStateCompanion(
            accountUserId: accountUserId,
            conversationKey: conversationKey,
            lastChangeAt: lastChangeAt,
            lastChangeId: lastChangeId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String accountUserId,
            required String conversationKey,
            Value<DateTime?> lastChangeAt = const Value.absent(),
            Value<String?> lastChangeId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatSyncStateCompanion.insert(
            accountUserId: accountUserId,
            conversationKey: conversationKey,
            lastChangeAt: lastChangeAt,
            lastChangeId: lastChangeId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ChatSyncStateTable, ChatSyncStateData>(table),
                    BaseReferences<_$ChatLocalDatabase, $ChatSyncStateTable,
                        ChatSyncStateData>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatSyncStateTableProcessedTableManager = ProcessedTableManager<
    _$ChatLocalDatabase,
    $ChatSyncStateTable,
    ChatSyncStateData,
    $$ChatSyncStateTableFilterComposer,
    $$ChatSyncStateTableOrderingComposer,
    $$ChatSyncStateTableAnnotationComposer,
    $$ChatSyncStateTableCreateCompanionBuilder,
    $$ChatSyncStateTableUpdateCompanionBuilder,
    (
      ChatSyncStateData,
      BaseReferences<_$ChatLocalDatabase, $ChatSyncStateTable,
          ChatSyncStateData>
    ),
    ChatSyncStateData,
    PrefetchHooks Function()>;

class $ChatLocalDatabaseManager {
  final _$ChatLocalDatabase _db;
  $ChatLocalDatabaseManager(this._db);
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db, _db.localMessages);
  $$ChatSyncStateTableTableManager get chatSyncState =>
      $$ChatSyncStateTableTableManager(_db, _db.chatSyncState);
}
