import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notification_model.dart';
import '../providers/notifications_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сповіщення'),
        actions: [
          TextButton(
            onPressed: unreadCount == 0
                ? null
                : () =>
                    ref.read(notificationsRepositoryProvider).markAllAsRead(),
            child: const Text('Прочитати всі'),
          ),
        ],
      ),
      body: notifications.when(
        data: (items) => items.isEmpty
            ? const _EmptyNotifications()
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _NotificationTile(
                    notification: items[index],
                    onTap: () {
                      if (!items[index].isRead) {
                        ref
                            .read(notificationsRepositoryProvider)
                            .markAsRead(items[index].id);
                      }
                    },
                  ),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Не вдалося завантажити сповіщення: $error'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(notificationsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Спробувати ще раз'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        tileColor: notification.isRead
            ? null
            : colorScheme.primaryContainer.withValues(alpha: 0.35),
        leading: Icon(
          notification.isRead
              ? Icons.notifications_none
              : Icons.notifications_active,
          color: notification.isRead ? null : colorScheme.primary,
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight:
                notification.isRead ? FontWeight.normal : FontWeight.w700,
          ),
        ),
        subtitle: Text(notification.message),
        trailing: Text(_formatDate(notification.createdAt)),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    if (now.difference(local).inDays == 0) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}';
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 56),
          SizedBox(height: 12),
          Text('Нових сповіщень поки немає'),
        ],
      ),
    );
  }
}
