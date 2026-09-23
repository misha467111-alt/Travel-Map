import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/profile_controller.dart';
import '../../chat/local/chat_local_database_provider.dart';
import '../../gps/local/gps_local_database_provider.dart';
import '../../gps/presentation/gps_recording_debug_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: profileController,
        builder: (context, _) => SettingsPage(
          offlineMode: profileController.isOfflineMode,
          onOfflineChanged: profileController.setOfflineMode,
          onLogout: () => _logout(context, ref),
          // C4 — release users must never reach the GPS debug surface;
          // `SettingsPage` already hides the whole "РОЗРОБКА" section
          // whenever this is null, so gating it here at the source is
          // the entire fix.
          onOpenGpsDebug: kDebugMode
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const GpsRecordingDebugScreen()),
                  )
              : null,
        ),
      );

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final blockingRouteId = await blockingActiveRecordingId(ref);
    if (blockingRouteId != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Завершіть або скасуйте активний GPS-запис перед виходом з акаунту.',
          ),
        ));
      }
      return;
    }
    await clearChatCacheOnLogout(ref);
    await profileController.logout();
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.offlineMode,
    required this.onOfflineChanged,
    required this.onLogout,
    this.onOpenGpsDebug,
    super.key,
  });

  final bool offlineMode;
  final ValueChanged<bool> onOfflineChanged;
  final VoidCallback onLogout;

  /// GPS-3's minimal developer/test surface entry point. Nullable both so
  /// existing tests constructing SettingsPage directly (without this
  /// callback) keep working unchanged, and so the real [SettingsScreen]
  /// (C4) can pass `null` in release builds — the whole "РОЗРОБКА"
  /// section below renders only when this is non-null, so a release
  /// build shows no debug entry and no empty development section.
  final VoidCallback? onOpenGpsDebug;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text(
            'Налаштування',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          child: ListView(
            key: const Key('settings_scroll'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              SettingsSection(
                title: 'ДАНІ ТА ОФЛАЙН',
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('settings_offline_toggle'),
                    value: offlineMode,
                    onChanged: onOfflineChanged,
                    secondary: const Icon(Icons.offline_bolt_outlined,
                        color: Color(0xFFD4A017)),
                    title: const Text('Офлайн-режим'),
                    subtitle: const Text(
                      'Використовувати збережені локації та маршрути без мережі',
                    ),
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ],
              ),
              const SettingsSection(
                title: 'ПРО ЗАСТОСУНОК',
                children: [
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity(vertical: -3),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                    leading: Icon(Icons.verified_user_outlined),
                    title: Text('Модерація локацій'),
                    subtitle: Text(
                      'Нові локації проходять перевірку перед публікацією.',
                    ),
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity(vertical: -3),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                    leading: Icon(Icons.explore_outlined),
                    title: Text('Travel'),
                    subtitle: Text('Версія 1.0.0'),
                  ),
                ],
              ),
              if (onOpenGpsDebug != null)
                SettingsSection(
                  title: 'РОЗРОБКА',
                  children: [
                    ListTile(
                      key: const Key('settings_gps_debug'),
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -3),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      leading: const Icon(Icons.gps_fixed),
                      title: const Text('GPS запис (debug)'),
                      subtitle: const Text('Тестовий екран для GPS-3.'),
                      onTap: onOpenGpsDebug,
                    ),
                  ],
                ),
              SettingsSection(
                title: 'ОБЛІКОВИЙ ЗАПИС',
                children: [
                  ListTile(
                    key: const Key('settings_logout'),
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text('Вийти'),
                    textColor: Colors.redAccent,
                    onTap: onLogout,
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 1, 2, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .9,
                  ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: Colors.white10),
              ),
            ),
            child: Column(
              children: children.indexed
                  .expand((entry) => [
                        if (entry.$1 > 0) const Divider(indent: 42),
                        IconTheme(
                          data: const IconThemeData(size: 20),
                          child: DefaultTextStyle.merge(
                            style: const TextStyle(height: 1.15),
                            child: entry.$2,
                          ),
                        ),
                      ])
                  .toList(growable: false),
            ),
          ),
        ]),
      );
}
