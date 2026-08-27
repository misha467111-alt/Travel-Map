import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/notification_model.dart';

part 'notifications_provider.g.dart';

class NotificationsRepository {
  const NotificationsRepository(this._supabase);

  final SupabaseClient _supabase;

  String get _userId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Користувач не авторизований.');
    return id;
  }

  Stream<List<NotificationModel>> watchNotifications() {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', _userId)
        .order('created_at', ascending: false)
        .limit(100)
        .map(
          (rows) => rows
              .map((row) => NotificationModel.fromMap(row))
              .toList(growable: false),
        );
  }

  Future<void> markAsRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId)
        .eq('user_id', _userId);
  }

  Future<void> markAllAsRead() async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', _userId)
        .eq('is_read', false);
  }
}

@riverpod
NotificationsRepository notificationsRepository(Ref ref) {
  return NotificationsRepository(Supabase.instance.client);
}

@riverpod
Stream<List<NotificationModel>> notifications(Ref ref) {
  return ref.watch(notificationsRepositoryProvider).watchNotifications();
}

@riverpod
int unreadNotificationsCount(Ref ref) {
  return ref
          .watch(notificationsProvider)
          .value
          ?.where((notification) => !notification.isRead)
          .length ??
      0;
}
