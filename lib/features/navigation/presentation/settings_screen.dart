import 'package:flutter/material.dart';

import '../../../controllers/profile_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: profileController,
        builder: (context, _) => SettingsPage(
          offlineMode: profileController.isOfflineMode,
          onOfflineChanged: profileController.setOfflineMode,
          onLogout: profileController.logout,
        ),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.offlineMode,
    required this.onOfflineChanged,
    required this.onLogout,
    super.key,
  });

  final bool offlineMode;
  final ValueChanged<bool> onOfflineChanged;
  final VoidCallback onLogout;

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
