import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/providers/network_provider.dart';
import '../../../providers/chat_provider.dart';
import '../local/chat_local_database.dart';
import '../local/chat_local_database_provider.dart';
import '../local/chat_sync_mapping.dart';
import '../local/conversation_key.dart';
import 'chat_server_message_mapper.dart';

/// UI-facing state for one open conversation. [messages] always comes
/// from the local cache (oldest-first) — this is the only thing the UI
/// renders as content; everything else here is transient sync metadata.
class ChatConversationState {
  const ChatConversationState({
    required this.messages,
    required this.isLoadingOlder,
    required this.hasMore,
    required this.isOffline,
    this.syncError,
  });

  factory ChatConversationState.initial() => const ChatConversationState(
        messages: [],
        isLoadingOlder: false,
        hasMore: true,
        isOffline: false,
      );

  final List<LocalMessage> messages;
  final bool isLoadingOlder;
  final bool hasMore;
  final bool isOffline;

  /// Non-blocking: a background sync step failed, but cached messages
  /// (if any) stay on screen regardless. Never a raw exception message.
  final String? syncError;

  static const _unset = Object();

  ChatConversationState copyWith({
    List<LocalMessage>? messages,
    bool? isLoadingOlder,
    bool? hasMore,
    bool? isOffline,
    Object? syncError = _unset,
  }) {
    return ChatConversationState(
      messages: messages ?? this.messages,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      hasMore: hasMore ?? this.hasMore,
      isOffline: isOffline ?? this.isOffline,
      syncError:
          identical(syncError, _unset) ? this.syncError : syncError as String?,
    );
  }
}

/// Owns everything for one open 1:1 conversation: cache-first display,
/// the initial server history page, older-page pagination, reconnect
/// catch-up, and forwarding the existing realtime stream into the local
/// cache. The local Drift cache is the single source of truth [state]'s
/// `messages` is built from — nothing here ever hands a raw Supabase row
/// straight to the UI.
///
/// Not a Riverpod [AsyncNotifier] — this deliberately mirrors the
/// already-proven pattern in this exact module
/// ([mergeConversationStreams]: a manually-managed broadcast
/// [StreamController] fed by multiple async sources) rather than the
/// class-based family-notifier API, whose argument-passing shape isn't
/// used anywhere else in this codebase on this Riverpod version.
class ChatConversationController {
  ChatConversationController({
    required Ref ref,
    required String friendId,
    required ChatLocalDatabase db,
  })  : _ref = ref,
        _friendId = friendId,
        _db = db {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      _emit((s) => s.copyWith(hasMore: false));
      return;
    }
    _me = me;
    _conversationKey = conversationKeyFor(me, friendId);
    _ready = true;

    // ref.listen must be called synchronously during setup (not after an
    // await), so both subscriptions are wired here before any async work
    // starts.
    _subscribeRealtime();
    _subscribeConnectivity();

    unawaited(_loadInitial());
  }

  static const _pageSize = 50;
  static const _catchUpPageLimit = 200;
  static const _maxCatchUpPagesPerSync = 20;
  static final DateTime _epoch = DateTime.utc(1970);

  final Ref _ref;
  final String _friendId;
  final ChatLocalDatabase _db;

  bool _ready = false;
  late final String _me;
  late final String _conversationKey;
  int _limit = _pageSize;
  StreamSubscription<List<LocalMessage>>? _watchSub;
  ProviderSubscription<AsyncValue<List<Map<String, dynamic>>>>? _realtimeSub;
  ProviderSubscription<AsyncValue<NetworkStatus>>? _connectivitySub;

  final _stateController = StreamController<ChatConversationState>.broadcast();
  ChatConversationState _state = ChatConversationState.initial();

  /// UI watches this (via [chatConversationStateProvider]) as the sole
  /// source of conversation content + sync metadata.
  Stream<ChatConversationState> get stateStream => _stateController.stream;

  void dispose() {
    _watchSub?.cancel();
    _realtimeSub?.close();
    _connectivitySub?.close();
    _stateController.close();
  }

  void _emit(ChatConversationState Function(ChatConversationState) update) {
    _state = update(_state);
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  // -------------------------------------------------------------------
  // Initial load: cache-first, then server history, then catch-up
  // -------------------------------------------------------------------

  Future<void> _loadInitial() async {
    if (!_ready) return;

    final initialRows = await _db.getRecentMessages(
      accountUserId: _me,
      conversationKey: _conversationKey,
      limit: _limit,
    );
    _emit((s) => s.copyWith(
          messages: initialRows,
          isOffline: !_ref.read(isOnlineProvider),
        ));

    _subscribeWatch();

    await _runInitialServerSync();
  }

  void _subscribeWatch() {
    unawaited(_watchSub?.cancel());
    _watchSub = _db
        .watchRecentMessages(
          accountUserId: _me,
          conversationKey: _conversationKey,
          limit: _limit,
        )
        .listen((rows) => _emit((s) => s.copyWith(messages: rows)));
  }

  // -------------------------------------------------------------------
  // Realtime forwarding (reuses the existing two-stream chatStreamProvider
  // — no Supabase realtime architecture change here)
  // -------------------------------------------------------------------

  void _subscribeRealtime() {
    _realtimeSub = _ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      chatStreamProvider(_friendId),
      (previous, next) {
        final rows = next.value;
        if (rows == null || rows.isEmpty) return;
        unawaited(_applyRealtimeRows(rows));
      },
    );
  }

  Future<void> _applyRealtimeRows(List<Map<String, dynamic>> rows) async {
    for (final raw in rows) {
      final row = ChatServerMessageMapper.fromRealtimeRow(raw);
      await applyServerRowToCache(
        db: _db,
        row: row,
        accountUserId: _me,
        conversationKey: _conversationKey,
      );
    }
  }

  // -------------------------------------------------------------------
  // Connectivity: reflect offline state, trigger catch-up on reconnect
  // -------------------------------------------------------------------

  void _subscribeConnectivity() {
    _connectivitySub = _ref.listen<AsyncValue<NetworkStatus>>(
      networkStatusProvider,
      (previous, next) {
        final prevStatus = previous?.value;
        final nextStatus = next.value;
        _emit((s) => s.copyWith(isOffline: nextStatus != NetworkStatus.online));
        if (prevStatus == NetworkStatus.offline &&
            nextStatus == NetworkStatus.online) {
          unawaited(_runCatchUp());
        }
      },
    );
  }

  // -------------------------------------------------------------------
  // Server sync
  // -------------------------------------------------------------------

  Future<void> _runInitialServerSync() async {
    if (!_ref.read(isOnlineProvider)) return;
    try {
      await _fetchInitialHistoryPage();
    } catch (_) {
      _emit((s) => s.copyWith(syncError: 'Не вдалося оновити історію.'));
    }
    try {
      await _runCatchUp();
    } catch (_) {
      _emit((s) => s.copyWith(
          syncError: 'Не вдалося синхронізувати нові повідомлення.'));
    }
  }

  Future<void> _fetchInitialHistoryPage() async {
    final response = await Supabase.instance.client.rpc(
      'travel_conversation_messages',
      params: {
        'p_other_user_id': _friendId,
        'p_limit': _pageSize + 1,
      },
    );
    final rows = (response as List).cast<Map<String, dynamic>>();
    final hasMoreFromServer = rows.length > _pageSize;
    final pageRows = hasMoreFromServer ? rows.sublist(0, _pageSize) : rows;

    for (final json in pageRows) {
      final row = ChatServerMessageMapper.fromRpcRow(json);
      await applyServerRowToCache(
        db: _db,
        row: row,
        accountUserId: _me,
        conversationKey: _conversationKey,
      );
    }
    await _db.cleanupConversation(
      accountUserId: _me,
      conversationKey: _conversationKey,
    );

    _emit((s) => s.copyWith(hasMore: hasMoreFromServer, syncError: null));
  }

  /// Reconnect/resume catch-up, looping through pages until the server
  /// signals there's nothing more.
  ///
  /// Cursor bootstrap: when there is no stored cursor yet (very first
  /// sync for this account+conversation), this deliberately starts from
  /// [_epoch] rather than "now" or the initial history page's newest
  /// timestamp. The history RPC never returns hidden-for-me rows at all,
  /// so there is no signal in its response that could safely anchor a
  /// cursor around a hide event that happened around the same time — any
  /// cursor derived only from history risks silently missing a
  /// concurrent hide. Starting from epoch guarantees every change this
  /// conversation has ever had (including any earlier hides) is swept at
  /// least once; the extra page(s) this costs are cheap and idempotent
  /// at this app's message volume, and only happen once per
  /// account+conversation (later syncs resume from the real cursor).
  Future<void> _runCatchUp() async {
    if (!_ref.read(isOnlineProvider)) return;
    final client = Supabase.instance.client;
    final cursor = await _db.getSyncCursor(
      accountUserId: _me,
      conversationKey: _conversationKey,
    );
    var sinceAt = cursor.changeAt ?? _epoch;
    var sinceId = cursor.changeId;

    for (var page = 0; page < _maxCatchUpPagesPerSync; page++) {
      final response = await client.rpc(
        'travel_conversation_catchup',
        params: {
          'p_other_user_id': _friendId,
          'p_since_change_at': sinceAt.toIso8601String(),
          'p_since_change_id': sinceId,
          'p_limit': _catchUpPageLimit,
        },
      );
      final rows = (response as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) break;

      for (final json in rows) {
        final row = ChatServerMessageMapper.fromRpcRow(json);
        await applyServerRowToCache(
          db: _db,
          row: row,
          accountUserId: _me,
          conversationKey: _conversationKey,
        );
      }

      final last = rows.last;
      final lastChangeAt = ChatServerMessageMapper.parseChangeAt(last);
      final lastChangeId = last['id'] as String;

      if (lastChangeAt == sinceAt && lastChangeId == sinceId) {
        // Cursor did not advance — stop rather than loop forever. No
        // message content in this diagnostic, only identifiers/times.
        debugPrint(
          'chat catchup: cursor stagnant for conversation $_conversationKey '
          '(changeAt=$lastChangeAt, changeId=$lastChangeId) — stopping sync.',
        );
        break;
      }

      sinceAt = lastChangeAt;
      sinceId = lastChangeId;
      await _db.setSyncCursor(
        accountUserId: _me,
        conversationKey: _conversationKey,
        changeAt: sinceAt,
        changeId: sinceId,
      );

      if (rows.length < _catchUpPageLimit) break;
    }

    _emit((s) => s.copyWith(syncError: null));
  }

  /// Re-runs the initial history + catch-up sync. Intended for a manual
  /// retry affordance when the cache is empty and the initial sync
  /// failed (e.g. the very first time a conversation is opened, offline).
  Future<void> retry() async {
    if (!_ready) return;
    await _runInitialServerSync();
  }

  // -------------------------------------------------------------------
  // Scroll-up pagination
  // -------------------------------------------------------------------

  Future<void> loadOlder() async {
    if (!_ready) return;
    final current = _state;
    if (current.isLoadingOlder ||
        !current.hasMore ||
        current.messages.isEmpty) {
      return;
    }

    _emit((s) => s.copyWith(isLoadingOlder: true, syncError: null));
    final oldest = current.messages.first;

    try {
      final moreLocal = await _db.getOlderMessages(
        accountUserId: _me,
        conversationKey: _conversationKey,
        beforeCreatedAt: oldest.createdAt,
        beforeId: oldest.id,
        limit: 1,
      );

      if (moreLocal.isNotEmpty) {
        _limit += _pageSize;
        _subscribeWatch();
        _emit((s) => s.copyWith(isLoadingOlder: false));
        return;
      }

      if (!_ref.read(isOnlineProvider)) {
        _emit((s) => s.copyWith(isLoadingOlder: false));
        return;
      }

      final response = await Supabase.instance.client.rpc(
        'travel_conversation_messages',
        params: {
          'p_other_user_id': _friendId,
          'p_limit': _pageSize + 1,
          'p_before_created_at': oldest.createdAt.toIso8601String(),
          'p_before_id': oldest.id,
        },
      );
      final rows = (response as List).cast<Map<String, dynamic>>();
      final hasMoreFromServer = rows.length > _pageSize;
      final pageRows = hasMoreFromServer ? rows.sublist(0, _pageSize) : rows;

      for (final json in pageRows) {
        final row = ChatServerMessageMapper.fromRpcRow(json);
        await applyServerRowToCache(
          db: _db,
          row: row,
          accountUserId: _me,
          conversationKey: _conversationKey,
        );
      }
      if (pageRows.isNotEmpty) {
        _limit += _pageSize;
        _subscribeWatch();
      }
      _emit(
          (s) => s.copyWith(isLoadingOlder: false, hasMore: hasMoreFromServer));
    } catch (_) {
      _emit((s) => s.copyWith(
            isLoadingOlder: false,
            syncError: 'Не вдалося завантажити історію.',
          ));
    }
  }
}

final chatConversationProvider = Provider.autoDispose
    .family<ChatConversationController, String>((ref, friendId) {
  final db = ref.watch(chatLocalDatabaseProvider);
  final controller =
      ChatConversationController(ref: ref, friendId: friendId, db: db);
  ref.onDispose(controller.dispose);
  return controller;
});

/// UI-facing reactive state for one conversation. Mirrors the pattern
/// already used by [chatStreamProvider] in this module: a plain
/// [StreamProvider.family] wrapping a manually-managed stream.
final chatConversationStateProvider = StreamProvider.autoDispose
    .family<ChatConversationState, String>((ref, friendId) {
  return ref.watch(chatConversationProvider(friendId)).stateStream;
});
